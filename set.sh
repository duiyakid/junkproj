# 1. 创建 /trash 目录
sudo mkdir -p /trash

# 2. 设置权限（只有 root 可访问）
sudo chown root:root /trash
sudo chmod 700 /trash

# 3. 创建 delInfo
sudo touch /trash/delInfo
sudo chown root:root /trash/delInfo
sudo chmod 600 /trash/delInfo

# 4. 安装 junk（SetUID）
sudo cp junk /usr/local/bin/
sudo chown root:root /usr/local/bin/junk
sudo chmod 4755 /usr/local/bin/junk

# 5. 测试
user1@host:~$ junk file.txt  # 应该成功
user1@host:~$ junk -s        # 应该显示文件
