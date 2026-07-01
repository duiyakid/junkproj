#!/bin/bash
# install_junk.sh - 一键安装 junk 回收站工具（全局可用）

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Junk 回收站工具 - 全局安装脚本   ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 检查是否以 root 运行
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}错误：请使用 sudo 运行此脚本${NC}"
    echo "用法：sudo ./install_junk.sh"
    exit 1
fi

# ============ 1. 创建 /trash ============
echo -e "${GREEN}[1/5] 创建 /trash 目录...${NC}"
mkdir -p /trash
chown root:root /trash
chmod 700 /trash
echo -e "${GREEN}  ✅ /trash 创建完成 (700)${NC}"

# ============ 2. 创建 delInfo ============
echo -e "${GREEN}[2/5] 创建 /trash/delInfo...${NC}"
touch /trash/delInfo
chown root:root /trash/delInfo
chmod 600 /trash/delInfo
echo -e "${GREEN}  ✅ /trash/delInfo 创建完成 (600)${NC}"

# ============ 3. 安装 junk ============
echo -e "${GREEN}[3/5] 安装 junk 到 /usr/local/bin/...${NC}"
if [ ! -f "./junk" ]; then
    echo -e "${RED}  ❌ 错误：找不到 junk 脚本${NC}"
    echo "  请确保 install_junk.sh 和 junk 在同一目录"
    exit 1
fi

cp ./junk /usr/local/bin/junk
chown root:root /usr/local/bin/junk
chmod 755 /usr/local/bin/junk
echo -e "${GREEN}  ✅ 已安装到 /usr/local/bin/junk${NC}"

# ============ 4. 配置全局免密 sudo ============
echo -e "${GREEN}[4/5] 配置全局免密 sudo...${NC}"

SUDOERS_FILE="/etc/sudoers.d/junk"
echo "# Junk 回收站工具 - 全局免密执行" > "$SUDOERS_FILE"
echo "ALL ALL=(root) NOPASSWD: /usr/local/bin/junk" >> "$SUDOERS_FILE"
chmod 440 "$SUDOERS_FILE"

echo -e "${GREEN}  ✅ 所有用户可免密执行 junk${NC}"

# ============ 5. 验证 ============
echo -e "${GREEN}[5/5] 验证安装...${NC}"

if [ -f "/usr/local/bin/junk" ]; then
    echo -e "${GREEN}  ✅ junk 命令已安装${NC}"
else
    echo -e "${RED}  ❌ junk 安装失败${NC}"
    exit 1
fi

if [ -d "/trash" ]; then
    echo -e "${GREEN}  ✅ /trash 目录存在${NC}"
fi

if [ -f "/trash/delInfo" ]; then
    echo -e "${GREEN}  ✅ /trash/delInfo 存在${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  安装完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}所有用户现在可以直接使用 junk 命令：${NC}"
echo ""
echo "  junk <文件>         # 删除文件到回收站"
echo "  junk -r <目录>      # 递归删除目录"
echo "  junk -f <文件>      # 强制删除（不进回收站）"
echo "  junk -s             # 查看回收站"
echo "  junk -R <文件>      # 恢复文件"
echo "  junk -d             # 清空回收站"
echo ""
echo -e "${GREEN}示例：${NC}"
echo "  user1@host:~$ junk file.txt"
echo "  user2@host:~$ junk -s"
echo "  user3@host:~$ junk -R file.txt"
echo ""
echo -e "${GREEN}所有用户都已配置免密 sudo，无需输入密码！${NC}"
