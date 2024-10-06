#!/bin/bash

# 定义最新的 Snell 版本信息
latest_version="v4.1.1"
latest_x86_url="https://dl.nssurge.com/snell/snell-server-v4.1.1-linux-amd64.zip"
latest_arm_url="https://dl.nssurge.com/snell/snell-server-v4.1.1-linux-armv7l.zip"

# 获取已安装的 Snell 服务器版本
installed_version=""
if command -v snell-server > /dev/null 2>&1; then
    installed_version=$(snell-server -v | grep -oP "v[0-9]+\.[0-9]+\.[0-9]+")
fi

# 检测当前架构
arch=$(uname -m)
if [ "$arch" = "x86_64" ]; then
    snell_url=$latest_x86_url
elif [[ "$arch" == arm* ]]; then
    snell_url=$latest_arm_url
else
    echo "Unsupported architecture: $arch"
    exit 1
fi

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
echo "Clearing and configuring /etc/sysctl.conf for TCP BBR..."
sudo truncate -s 0 /etc/sysctl.conf
echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf > /dev/null
echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf > /dev/null
sudo sysctl -p > /dev/null

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

# 下载并安装最新版本
if [ "$installed_version" = "$latest_version" ]; then
    echo "Snell server is up-to-date (version: $installed_version)."
else
    echo "Newer Snell server version available (version: $latest_version). Updating..."

    # 停止现有的 Snell 服务
    if systemctl is-active --quiet snell; then
        echo "Stopping existing Snell server..."
        sudo systemctl stop snell
    fi

    # 删除现有的 Snell 服务器二进制文件
    if [ -f /usr/local/bin/snell-server ]; then
        echo "Removing old Snell server binary..."
        sudo rm -f /usr/local/bin/snell-server
    fi

    # 下载并安装最新版本
    echo "Downloading Snell server version: $latest_version for architecture: $arch..."
    wget $snell_url
    unzip snell-server-$latest_version-linux-*.zip -d /usr/local/bin
    yes | /usr/local/bin/snell-server --wizard -c /etc/snell-server.conf
fi

# 重新加载systemd配置并启动新版本Snell服务
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
