#!/bin/bash

# 检查是否为 root 用户（EUID 为有效用户 ID）
if [ "$EUID" -ne 0 ]; then
    # 如果不是 root，则使用 sudo 重新执行当前脚本
    # exec 会替换当前进程，不需要退出
    exec sudo "$0" "$@"
    exit $?  # 如果 exec 失败才执行到这里
fi

# 定义锁文件路径和超时时间
LOCK_FILE="/var/lock/recycle.lock"
TIMEOUT=3

# 设置信号捕获，当脚本退出时自动删除锁文件
# EXIT: 正常退出, INT: Ctrl+C, TERM: 终止信号, TSTP: Ctrl+Z
trap 'rm -f "$LOCK_FILE"; exit' EXIT INT TERM TSTP

# 创建文件描述符 200 并打开锁文件
exec 200>"$LOCK_FILE"
# 尝试获取文件锁，最多等待 TIMEOUT 秒
if ! flock -w $TIMEOUT 200; then
    echo "错误: 回收站正忙" >&2
    exit 1
fi

# 将当前进程 PID 写入锁文件（用于调试）
echo $$ > "$LOCK_FILE"

# 检查是否提供了参数
if [ $# -eq 0 ]
then
	echo "错误：需要至少一个参数"
	exit 1
fi

# ===== 初始化变量和目录检查 =====

# -r 标志：是否递归删除目录
flag_r=false
# 回收站目录路径
trash="/trash"
# 删除信息记录文件（格式：目标名称|原始路径）
delInfo="/trash/delInfo"
# 操作模式：default(普通删除), f(强制删除), R(恢复), s(查看), d(清空)
mode="default"

# 检查回收站目录是否存在
if [ ! -e "$trash" ]; then
    echo "错误：/trash 目录不存在，请联系管理员创建"
    exit 1
fi

# 检查删除信息文件是否存在
if [ ! -e "$delInfo" ]; then
    echo "错误：/trash/delInfo 文件不存在，请联系管理员创建"
    exit 1
fi

# ===== 工具函数 =====

# 检查文件所有者函数
# 参数：$1 - 要检查的文件路径
# 返回值：
#   0 - 文件属于当前用户
#   1 - 文件不存在
#   2 - 文件属于其他用户（权限不足）
check_owner() {
	local file="$1"

	# 检查文件是否存在（包括符号链接）
	if [ ! -e "$file" ] && [ ! -L "$file" ]; then
        return 1
    fi
    
    # 获取实际操作用户（SUDO_USER 是使用 sudo 时的原始用户）
    local current_user="${SUDO_USER:-$(whoami)}"
    # 获取文件的所有者
    local file_owner=$(stat -c '%U' "$file" 2>/dev/null)
    
    # 检查文件所有者是否匹配
    if [ "$file_owner" != "$current_user" ]; then
        return 2
    fi

    return 0
}

# ===== 模式 1: 默认删除模式（移到回收站） =====
default_mode(){
	# 遍历所有传入的文件参数
	for file in "$@"
	do
		# 检查文件所有权
		check_owner "$file"
		local code=$?
		# 根据返回值进行不同处理
		case ${code} in
		0) 
			# 权限正常，继续执行
			;;
		1)
			echo "错误：文件不存在：${file}" >&2
			continue  # 跳过这个文件，处理下一个
			;;
		2)
			echo "错误：权限不足：${file}" >&2
			continue
			;;
		*)
			echo "错误：未知错误($code)" >&2
			continue
			;;
		esac

		# 检查是否为目录且未使用 -r 标志
		if [ -d "$file" ] && [ "$flag_r" != "true" ]
		then
            echo "错误：默认无法删除目录，请尝试使用-r" >&2
            continue
        fi

		# 获取文件名和绝对路径
		local src_name="$(basename "${file}")"
		local src_path="$(realpath -s "${file}")"
		local target_name="${src_name}"
		local target_path="${trash}/${src_name}"
		
		# 如果回收站中已存在同名文件，添加时间戳避免覆盖
        while [ -e "$target_path" ]
		do
			target_name="${src_name}_$(date +%s)"  # 添加 Unix 时间戳
            target_path="${trash}/${target_name}"
        done

        # 移动文件到回收站
        if mv "$file" "$target_path"
		then
            # 记录删除信息到 delInfo 文件
            echo "${target_name}|${src_path}" >> "${delInfo}"
        else
            echo "错误: 删除文件失败: ${file}" >&2
        fi
	done
}

# ===== 模式 2: 强制删除模式（永久删除） =====
f_mode(){
	for file in "$@"
	do
		# 权限检查（与 default_mode 类似）
		check_owner "$file"
		local code=$?
		case ${code} in
		0) 
			;;
		1)
			echo "错误：文件不存在：${file}" >&2
			continue
			;;
		2)
			echo "错误：权限不足：${file}" >&2
			continue
			;;
		*)
			echo "错误：未知错误($code)" >&2
			continue
			;;
		esac

		# 目录需要 -r 标志
		if [ -d "$file" ] && [ "$flag_r" != "true" ]
		then
            echo "错误：默认无法删除目录，请尝试使用-r" >&2
            continue
        fi

		# 获取绝对路径
		local src_path="$(realpath -s "${file}")"

		# 使用 rm -rf 永久删除文件
		if ! rm -rf "${src_path}"
		then
			echo "错误: 删除文件失败: ${file}" >&2
		fi
	done
}

# ===== 模式 3: 恢复模式（从回收站恢复文件） =====
R_mode(){
	# 保存并修改列数为 1，用于 select 菜单显示
	OLD_COLUMNS="${COLUMNS}"
	COLUMNS=1
	
	for file in "$@"
	do
		# 获取文件名（用户可能只输入部分名称）
		local src_name="$(basename "${file}")"
		local target_name="${src_name}"
		local filtered_result=()

		# 从 delInfo 中查找匹配的文件（使用 awk 进行前缀匹配）
		mapfile -t all_result < <(
		awk -F'|' -v target="${target_name}" 'index($1, target) == 1' "$delInfo" | tac )

		# 过滤：只保留属于当前用户的文件
		for item in "${all_result[@]}"; do
			IFS='|' read -r target_name ori_path <<< "$item"
			if check_owner "$trash/$target_name"
			then
				filtered_result+=("$item")
			fi
		done
		
		# 使用过滤后的结果
		local result=("${filtered_result[@]}")

		# 如果没有匹配的文件
		if [ ${#result[@]} -eq 0 ]
		then
        	echo "错误: /trash 没有匹配文件: ${src_name}"
        	continue
    	fi

		# 准备显示数据
		local display=()
		local -a temp_data=()
		local max_size=0 max_name=0

		# 遍历每个匹配的文件，收集显示信息
		for dis in "${result[@]}"
		do
			IFS='|' read -r target_name ori_path <<< "${dis}"
			local del_time="未知时间"
			local file_size="未知大小"
			local type_char="?"  # 文件类型字符（d目录, -文件, l链接等）
			
			# 如果文件在回收站中存在
			if [ -e "$trash/$target_name" ] || [ -L "$trash/$target_name" ]
			then
				# 获取删除时间
				del_time="$(stat -c '%z' "$trash/$target_name" 2>/dev/null | cut -d'.' -f1)"
				del_time="${del_time:-未知时间}"
				# 获取文件大小
				file_size="$(du -sh "$trash/$target_name" 2>/dev/null | cut -f1)"
				# 获取文件类型第一个字符
				type_char=$(ls -ld "$trash/$target_name" 2>/dev/null | cut -c1)
			fi
			
			# 用管道符分隔的临时数据
			temp_data+=("${del_time}|${type_char}|${file_size}|${target_name}|${ori_path}")
			
			# 计算列宽用于对齐
			local size_len=$(echo -n "$file_size" | wc -c)
			local name_len=$(echo -n "$target_name" | wc -c)
			
			[ $size_len -gt $max_size ] && max_size=$((size_len + 1))
			[ $name_len -gt $max_name ] && max_name=$((name_len + 1))
		done
		
		echo "总计 ${#result[@]}"

		# 格式化显示数据（使用 printf 对齐）
		for data in "${temp_data[@]}"
		do
			IFS='|' read -r del_time type_char file_size target_name ori_path <<< "$data"
			display+=("$del_time  $type_char  $(printf "%-${max_size}s %-${max_name}s %s" "$file_size" "$target_name" "$ori_path")")
		done

		# 使用 select 创建交互式菜单
		PS3="选择恢复版本(编号): "
		select item in "${display[@]}" "取消"
		do
			if [ "$item" == "取消" ]
			then
				break
			elif [ -n "$item" ]
			then
				# 获取选择的文件信息
				local index=$((REPLY - 1))
				IFS='|' read -r target_name ori_path <<< "${result[$index]}"

				# 检查原始路径是否存在
				check_owner "${ori_path}"
				local code=$?
				case ${code} in
				0) 
					# 目标已存在，询问是否覆盖
					echo "警告: 目标文件已存在: ${ori_path}"
					read -p "是否覆盖？(y/n): " confirm
					if [[ "$confirm" != "y" && "$confirm" != "Y" ]]
					then
						echo "操作已取消"
						continue
					fi
					;;
				1)
					# 目标不存在，可以恢复
					;;
				2)
					echo "错误：目标文件已存在，且权限不足: ${ori_path}" >&2
					continue
					;;
				*)
					echo "错误：未知错误($code)" >&2
					continue
					;;
				esac
				
				# 执行恢复操作（移动文件回原路径）
				if mv "$trash/$target_name" "$ori_path"
				then
					# 从 delInfo 中删除对应记录
					sudo sed -i "\;${target_name}|${ori_path};d" "$delInfo"
				else
					echo "错误: 未知错误($?), 恢复失败: ${ori_path}"
				fi
				break
			else
				echo "无效输入，请重新选择"
			fi
		done
    done
	# 恢复列数设置
	COLUMNS=$OLD_COLUMNS
}

# ===== 模式 4: 查看模式（浏览回收站内容） =====
s_mode(){
	OLD_COLUMNS="${COLUMNS}"
	COLUMNS=1
	
	local filtered_result=()

	# 读取 delInfo 并反转顺序（最近删除的在前）
	mapfile -t all_result < <(tac "$delInfo" )

	# 过滤：只保留当前用户的文件
	for item in "${all_result[@]}"
	do
		IFS='|' read -r target_name ori_path <<< "$item"
		if check_owner "$trash/$target_name"
		then
			filtered_result+=("$item")
		fi
	done
	
	local result=("${filtered_result[@]}")

	# 检查回收站是否为空
	if [ ${#result[@]} -eq 0 ]
	then
		echo "回收站为空"
		return 0
	fi

	# 收集和格式化显示数据（与 R_mode 类似）
	local display=()
	local -a temp_data=()
	local max_size=0 max_name=0

	for dis in "${result[@]}"
	do
		IFS='|' read -r target_name ori_path <<< "${dis}"
		local del_time="未知时间"
		local file_size="未知大小"
		local type_char="?"
		if [ -e "$trash/$target_name" ] || [ -L "$trash/$target_name" ]
		then
			del_time="$(stat -c '%z' "$trash/$target_name" 2>/dev/null | cut -d'.' -f1)"
			del_time="${del_time:-未知时间}"
			file_size="$(du -sh "$trash/$target_name" 2>/dev/null | cut -f1)"
			type_char=$(ls -ld "$trash/$target_name" 2>/dev/null | cut -c1)
		fi
		temp_data+=("${del_time}|${type_char}|${file_size}|${target_name}|${ori_path}")
		local size_len=$(echo -n "$file_size" | wc -c)
		local name_len=$(echo -n "$target_name" | wc -c)
		
		[ $size_len -gt $max_size ] && max_size=$((size_len + 1))
		[ $name_len -gt $max_name ] && max_name=$((name_len + 1))
	done
	
	echo "总计 ${#result[@]}"

	# 格式化显示
	for data in "${temp_data[@]}"
	do
		IFS='|' read -r del_time type_char file_size target_name ori_path <<< "$data"
		display+=("$del_time  $type_char  $(printf "%-${max_size}s %-${max_name}s %s" "$file_size" "$target_name"  "$ori_path")")
	done

	# 交互式选择文件查看内容
	PS3="选择文件(编号): "
	select item in "${display[@]}" "取消"
	do
		if [[ "$item" == "取消" ]]
		then
			break
		elif [[ -n "$item" ]]
		then
			local index=$((REPLY - 1))
			IFS='|' read -r target_name ori_path <<< "${result[$index]}"
			target_path="${trash}/${target_name}"

			# 根据文件类型显示内容
			if [ -d "${target_path}" ]
			then
				# 目录：显示文件列表
				if ! ls -la "${target_path}" | less
				then
					echo "错误: 无法显示文件内容: ${target_name}"
				fi
				continue
			else
				# 普通文件：使用 less 查看内容
				if ! less "$trash/$target_name"
				then
					echo "错误: 无法显示文件内容: ${target_name}"
				fi
				continue
			fi
		else
			echo "无效输入，请重新选择"
		fi
	done

	COLUMNS=$OLD_COLUMNS
}

# ===== 模式 5: 清空模式（永久删除回收站中自己的文件） =====
d_mode(){
	# 警告确认
	echo "警告: 这将永久删除回收站中您的所有文件！"
    read -p "确认清空？(y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "操作已取消"
        return 0
    fi

	# 获取所有记录
	mapfile -t all_result < <(tac "$delInfo" )

	local filtered_result=()

	# 过滤：只保留当前用户的文件
	for item in "${all_result[@]}"; do
		IFS='|' read -r target_name ori_path <<< "$item"
		if check_owner "$trash/$target_name"
		then
			filtered_result+=("$item")
		fi
	done
	
	local result=("${filtered_result[@]}")

	# 如果已经为空
	if [ ${#result[@]} -eq 0 ]
	then
	 	echo "回收站已为空"
        return 0
	fi

	# 逐个永久删除文件
	for dis in "${result[@]}"
	do
		IFS='|' read -r target_name ori_path <<< "${dis}"
		if rm -rf "$trash/$target_name"
			then
				# 从记录文件中删除
				sudo sed -i "\;${target_name}|${ori_path};d" "$delInfo"
			else
				echo "错误: 删除文件失败: ${target_name}"
				continue
			fi
	done
}

# ===== 参数解析 =====

# 使用 getopts 解析命令行选项
while getopts "frRsd" opt; do
    case $opt in
        f) 
            # -f: 强制永久删除模式
            if [ "$mode" != "default" ]; then
                echo "错误: -f, -R, -s, -d 参数不支持混用"
                exit 1
            fi
            mode="f" 
            ;;
        r) flag_r=true ;;  # -r: 递归标志（用于删除目录）
        R) 
            # -R: 恢复模式
            if [ "$mode" != "default" ]; then
                echo "错误: -f, -R, -s, -d 参数不支持混用"
                exit 1
            fi
            mode="R" 
            ;;
		s)
            # -s: 查看回收站模式
			if [ "$mode" != "default" ]; then
                echo "错误: -f, -R, -s,-d 参数不支持混用"
                exit 1
            fi
            mode="s" 
            ;;
		d)
            # -d: 清空回收站模式
			if [ "$mode" != "default" ]; then
                echo "错误: -f, -R, -s, -d 参数不支持混用"
                exit 1
            fi
            mode="d" 
            ;;
        *) 
            # 未知选项
            echo "未知的选项: -${opt}"
            exit 1
            ;;
    esac
done

# 移除已处理的选项，剩余为文件名参数
shift $((OPTIND - 1))

# ===== 根据模式执行对应函数 =====
case "$mode" in
    R) R_mode "$@" ;;      # 恢复文件
    f) f_mode "$@" ;;      # 强制删除
	s) s_mode ;;           # 查看回收站
	d) d_mode ;;           # 清空回收站
    default) default_mode "$@" ;;  # 默认删除（移入回收站）
esac