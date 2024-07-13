#!/bin/bash

# 检测并安装sudo
if ! dpkg -s sudo > /dev/null 2>&1; then
    echo "sudo is not installed. Installing sudo..."
    apt update -y > /dev/null 2>&1
    apt install sudo -y > /dev/null 2>&1
else
    echo "sudo is already installed."
fi

# 检测并安装mtr
if ! dpkg -s mtr > /dev/null 2>&1; then
    echo "mtr is not installed. Installing mtr..."
    sudo apt update -y > /dev/null 2>&1
    sudo apt install mtr -y > /dev/null 2>&1
else
    echo "mtr is already installed."
fi

# 配置iperf3安装选项
echo "iperf3 iperf3/start_daemon boolean false" | sudo debconf-set-selections

# 检测并安装iperf3
if ! dpkg -s iperf3 > /dev/null 2>&1; then
    echo "iperf3 is not installed. Installing iperf3..."
    sudo apt update -y > /dev/null 2>&1
    sudo apt install iperf3 -y > /dev/null 2>&1
else
    echo "iperf3 is already installed."
fi

# 检测并安装dnsutils
if ! dpkg -s dnsutils > /dev/null 2>&1; then
    echo "dnsutils is not installed. Installing dnsutils..."
    sudo apt update -y > /dev/null 2>&1
    sudo apt install dnsutils -y > /dev/null 2>&1
else
    echo "dnsutils is already installed."
fi

# 检测并安装net-tools
if ! dpkg -s net-tools > /dev/null 2>&1; then
    echo "net-tools is not installed. Installing net-tools..."
    sudo apt update -y > /dev/null 2>&1
    sudo apt install net-tools -y > /dev/null 2>&1
else
    echo "net-tools is already installed."
fi

# 安装curl
if ! dpkg -s curl > /dev/null 2>&1; then
    echo "curl is not installed. Installing curl..."
    sudo apt update -y > /dev/null 2>&1
    sudo apt install curl -y > /dev/null 2>&1
else
    echo "curl is already installed."
fi

# 检测并安装vnstat
if ! dpkg -s vnstat > /dev/null 2>&1; then
    echo "vnstat is not installed. Installing vnstat..."
    sudo apt update -y > /dev/null 2>&1
    sudo apt install vnstat -y > /dev/null 2>&1
else
    echo "vnstat is already installed."
fi

# 更新软件包列表
echo "Updating package list..."
sudo apt update -y > /dev/null 2>&1

# 配置TCP BBR
if [ -f /etc/sysctl.conf ]; then
    echo "Configuring TCP BBR..."
    echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf > /dev/null
    echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf > /dev/null
    sudo sysctl -p
else
    echo "/etc/sysctl.conf does not exist. Skipping TCP BBR configuration."
fi

# 安装Vim
if ! dpkg -s vim > /dev/null 2>&1; then
    echo "vim is not installed. Installing vim..."
    sudo apt install vim -y > /dev/null 2>&1
else
    echo "vim is already installed."
fi

# 安装unzip
if ! dpkg -s unzip > /dev/null 2>&1; then
    echo "unzip is not installed. Installing unzip..."
    sudo apt install unzip -y > /dev/null 2>&1
else
    echo "unzip is already installed."
fi

# 检测是否已安装Snell服务器
if command -v snell-server > /dev/null 2>&1; then
    # 读取并显示本机IPv4地址
    ipv4_address=$(curl -4 ip.sb)
    echo "Snell server is already installed. Updating /etc/snell-server.conf with local IPv4 address ($ipv4_address)..."
    
    # 更新 /etc/snell-server.conf 文件内容
    sudo sed -i "s/0.0.0.0/$ipv4_address/g" /etc/snell-server.conf

    # 显示 /etc/snell-server.conf 文件内容
    echo -e "\033[31m\033[1mShowing updated /etc/snell-server.conf contents:\033[0m"
    cat /etc/snell-server.conf
    
    exit 0
fi

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

# 读取并显示本机IPv4地址
ipv4_address=$(curl -4 ip.sb)
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
