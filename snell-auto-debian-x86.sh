#!/bin/bash

# 更新软件包列表并升级系统
echo "Updating package list and upgrading the system..."
sudo apt update -y && sudo apt upgrade -y

# 配置TCP BBR
echo "Configuring TCP BBR..."
echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 安装Vim
echo "Installing Vim..."
sudo apt install vim -y

# 安装unzip
echo "Installing unzip..."
sudo apt install unzip -y

# 下载并配置Snell服务器
echo "Downloading and configuring Snell server..."
wget https://dl.nssurge.com/snell/snell-server-v4.0.1-linux-amd64.zip
unzip snell-server-v4.0.1-linux-amd64.zip -d /usr/local/bin
yes | /usr/local/bin/snell-server --wizard -c /etc/snell-server.conf

# 创建Snell服务文件
echo "Creating Snell service file..."
sudo tee /lib/systemd/system/snell.service > /dev/null <<EOL
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
LimitNOFILE=32768
ExecStart=/usr/local/bin/snell-server -c /etc/snell-server.conf
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=snell-server

[Install]
WantedBy=multi-user.target
EOL

# 重新加载systemd配置并启动Snell服务
echo "Reloading systemd configuration and starting Snell service..."
sudo systemctl daemon-reload
sudo systemctl enable snell
sudo systemctl start snell

# 清理无用的包
echo "Cleaning up unused packages..."
sudo apt autoremove -y

echo "All installations and configurations are complete!"
