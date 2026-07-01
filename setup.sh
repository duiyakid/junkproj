sudo mkdir -p /trash
sudo chmod 1777 /trash          # 粘滞位，所有用户可读写但不能删别人的
sudo touch /trash/delInfo
sudo chmod 666 /trash/delInfo   # 所有用户可读写
