#!/bin/bash

set -e

# 检测系统架构
arch=$(uname -m)
case "$arch" in
    x86_64)
        snell_url="https://dl.nssurge.com/snell/snell-server-v4.1.1-linux-amd64.zip"
        ;;
    i386)
        snell_url="https://dl.nssurge.com/snell/snell-server-v4.1.1-linux-i386.zip"
        ;;
    aarch64)
        snell_url="https://dl.nssurge.com/snell/snell-server-v4.1.1-linux-aarch64.zip"
        ;;
    armv7l)
        snell_url="https://dl.nssurge.com/snell/snell-server-v4.1.1-linux-armv7l.zip"
        ;;
    *)
        echo "Unsupported architecture: $arch. Only x86_64, i386, aarch64, and armv7l are supported."
        exit 1
        ;;
esac

# 更新系统
echo "Updating system..."
sudo apt update -y
sudo apt upgrade -y

# 安装必要的软件包
echo "Installing necessary packages..."
sudo apt install -y wget unzip

# 配置 TCP BBR
echo "Configuring TCP BBR..."
echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 下载并安装最新版本的 Snell 服务器，直接覆盖
echo "Downloading Snell server from: $snell_url..."
wget -q "$snell_url" -O snell-server.zip
unzip -o -q snell-server.zip -d /usr/local/bin  # 使用 -o 选项直接覆盖
chmod +x /usr/local/bin/snell-server
rm snell-server.zip

# 创建 systemd 服务文件
echo "Creating systemd service file for Snell..."
sudo bash -c 'cat << EOF > /etc/systemd/system/snell.service
[Unit]
Description=Snell Server
After=network.target

[Service]
ExecStart=/usr/local/bin/snell-server -c /etc/snell-server.conf
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF'

# 启动 Snell 服务
echo "Reloading systemd configuration and starting Snell service..."
sudo systemctl daemon-reload
sudo systemctl enable snell
sudo systemctl start snell

# 读取并显示本机IPv4地址
ipv4_address=$(curl -4 -s ip.sb)
echo "IPv4 Address: $ipv4_address"

# 更新 /etc/snell-server.conf 文件内容
sudo sed -i "s/0.0.0.0/$ipv4_address/g" /etc/snell-server.conf

# 显示 /etc/snell-server.conf 文件内容
echo -e "\033[31m\033[1mShowing updated /etc/snell-server.conf contents:\033[0m"
cat /etc/snell-server.conf

# 清理无用的包
echo "Cleaning up unused packages..."
sudo apt autoremove -y > /dev/null 2>&1

echo "All installations and configurations are complete!"
