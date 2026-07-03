#!/bin/bash

# set -e: 任何命令执行失败（返回非0）时，脚本立即退出
# 防止在错误状态下继续执行，造成系统配置损坏
set -e

# 用于美化输出信息，增强可读性
RED='\033[0;31m'      # 红色 - 用于错误信息
GREEN='\033[0;32m'    # 绿色 - 用于成功信息
YELLOW='\033[1;33m'   # 黄色 - 用于提示信息
NC='\033[0m'           # No Color - 重置颜色到默认

# 权限检查：必须以 root 身份运行
# EUID: 有效用户ID，0 表示 root
if [ "$EUID" -ne 0 ]
then 
    # -e: 启用转义字符解析（使颜色代码生效）
    echo -e "${RED}错误：请使用 sudo 运行此脚本${NC}"
    echo "用法：sudo bash ./setup.sh"
    exit 1
fi

# 步骤 1：创建回收站目录 
echo -e "${GREEN}[1/5] 创建 /trash 目录...${NC}"

# mkdir -p: 递归创建目录，如果父目录不存在也会创建
# 如果目录已存在也不会报错
mkdir -p /trash

# 设置目录所有权为 root
# root:root 表示所有者和组都是 root
chown root:root /trash

# 设置目录权限为 700
# 7(所有着:rwx) 0(组:---) 0(其他人:---)
# 只有 root 可以读写执行，其他用户完全无法访问
chmod 700 /trash

echo -e "${GREEN}/trash 创建完成 (700)${NC}"

# 步骤 2：创建删除信息记录文件
echo -e "${GREEN}[2/5] 创建 /trash/delInfo...${NC}"

# touch: 创建空文件，如果文件已存在则更新其访问/修改时间
# 该文件用于记录：回收站文件名|原始路径
touch /trash/delInfo

# 设置文件所有权
chown root:root /trash/delInfo

# 设置文件权限为 600
# 6(所有着:rw-) 0(组:---) 0(其他人:---)
# 只有 root 可以读写，其他用户无法查看
chmod 600 /trash/delInfo

echo -e "${GREEN}/trash/delInfo 创建完成 (600)${NC}"

# 步骤 3：安装 junk 主脚本
echo -e "${GREEN}[3/5] 安装 junk 到 /usr/local/bin/...${NC}"

# 检查当前目录是否存在 junk 脚本
# -f: 检查文件是否存在且为普通文件（不是目录）
if [ ! -f "./junk" ]
then
    echo -e "${RED}错误：找不到 junk 脚本${NC}"
    echo "请确保 setup.sh 和 junk 在同一目录"
    exit 1
fi

# 复制 junk 脚本到系统可执行目录
# /usr/local/bin/ 通常在 $PATH 中，所有用户都可以直接使用
cp ./junk /usr/local/bin/junk

# 设置脚本所有权
chown root:root /usr/local/bin/junk

# 设置权限为 755
# 7(所有着:rwx) 5(组:r-x) 5(其他人:r-x)
# 所有用户都可以读取和执行，只有 root 可以修改
chmod 755 /usr/local/bin/junk

echo -e "${GREEN}已安装到 /usr/local/bin/junk${NC}"

# 步骤 4：配置 sudo 免密权限
echo -e "${GREEN}[4/5] 配置全局免密 sudo...${NC}"

# sudoers 配置文件的路径
# /etc/sudoers.d/ 目录下的文件会被 sudo 主配置文件包含
# 文件名可以自定义，这里叫 junk
SUDOERS_FILE="/etc/sudoers.d/junk"

# 写入 sudoers 配置内容
# >：覆盖写入（创建新文件）
echo "# junk 回收站工具 - 全局免密执行" > "$SUDOERS_FILE"

# >>：追加写入（在文件末尾添加）
# 语法：ALL ALL=(root) NOPASSWD: /usr/local/bin/junk
# 第一个 ALL: 所有主机
# 第二个 ALL: 所有用户
# (root): 以 root 身份运行
# NOPASSWD: 不需要输入密码
# /usr/local/bin/junk: 只对 junk 命令免密
echo "ALL ALL=(root) NOPASSWD: /usr/local/bin/junk" >> "$SUDOERS_FILE"

# 设置 sudoers 文件的正确权限
# 440: 只有所有者和组可以读，防止未授权修改
# 如果权限不对，sudo 会拒绝读取该文件
chmod 440 "$SUDOERS_FILE"

echo -e "${GREEN}免密设置完成${NC}"

# 步骤 5：验证安装结果 
echo -e "${GREEN}[5/5] 验证安装...${NC}"

# 逐个检查关键组件是否安装成功
# 使用独立的 if 语句，确保所有检查都能执行（不用 elif）

# 检查 junk 命令是否存在
if [ -f "/usr/local/bin/junk" ]
then
    echo -e "${GREEN}junk 命令已安装${NC}"
else
    echo -e "${RED}junk 安装失败${NC}"
    exit 1
fi

# 检查回收站目录是否存在
if [ ! -d "/trash" ]
then
    echo -e "${RED}错误：/trash 目录不存在！${NC}"
fi
# 检查删除记录文件是否存在
if [ ! -f "/trash/delInfo" ]
then
    echo -e "${RED}错误：/trash/delInfo 不存在！${NC}"
fi

# 显示安装完成信息
echo ""
echo -e "${GREEN}  安装完成！${NC}"
echo ""

# 使用黄色显示使用说明
echo -e "${YELLOW}所有用户现在可以直接使用 junk 命令：${NC}"
echo ""

# 显示各个命令的用法
echo "  junk <文件>         # 删除文件到回收站"
echo "  junk -r <目录>      # 递归删除目录（配合主命令使用）"
echo "  junk -f <文件>      # 强制删除（不进回收站，直接永久删除）"
echo "  junk -s             # 查看回收站内容（显示所有已删除文件）"
echo "  junk -R <文件>      # 恢复文件（从回收站还原到原位置）"
echo "  junk -d             # 清空回收站（永久删除所有文件）"
echo ""

# 显示使用示例
echo -e "${GREEN}示例：${NC}"
echo "  user1@host:~$ junk file.txt          # 删除文件"
echo "  user2@host:~$ junk -s                # 查看回收站"
echo "  user3@host:~$ junk -R file.txt       # 恢复文件"
echo ""
