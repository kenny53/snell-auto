#!/bin/bash

set -e

# 设置安装目录和文件名
INSTALL_DIR="/usr/local/etc"
SNELL_ZIP_URL="https://dl.nssurge.com/snell/snell-server-v4.1.1-linux-amd64.zip"
SNELL_ZIP_FILE="$INSTALL_DIR/snell-server.zip"
SNELL_BINARY="$INSTALL_DIR/snell-server"
CONFIG_FILE="$INSTALL_DIR/snell-server.conf"
SERVICE_FILE="/etc/systemd/system/snell-server.service"

# 生成随机端口 (10000-60000)
RANDOM_PORT=$(shuf -i 10000-60000 -n 1)

# 生成随机密码 (32 字节 Base64)
RANDOM_PSK=$(openssl rand -base64 32)

# 获取服务器 IP 地址
SERVER_IP=$(curl -s ifconfig.me || echo "Unable to fetch IP")

# 更新系统并安装必要的软件包
apt update && apt install -y unzip wget curl

# 创建目录
mkdir -p "$INSTALL_DIR"

# 下载 Snell Server
echo "Downloading Snell Server..."
wget -O "$SNELL_ZIP_FILE" "$SNELL_ZIP_URL"

# 解压 Snell Server
echo "Extracting Snell Server..."
unzip -o "$SNELL_ZIP_FILE" -d "$INSTALL_DIR"
chmod +x "$SNELL_BINARY"

# 生成 Snell Server 配置文件
echo "Generating Snell Server config..."
cat > "$CONFIG_FILE" <<EOF
[snell-server]
listen = 0.0.0.0:$RANDOM_PORT
psk = $RANDOM_PSK
obfs = tls
EOF

# 创建 Snell Server systemd 服务
echo "Creating systemd service..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
ExecStart=$SNELL_BINARY -c $CONFIG_FILE
Restart=always
User=root
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

# 重新加载 systemd 配置
systemctl daemon-reload

# 启用并启动 Snell Server
systemctl enable snell-server
systemctl restart snell-server

# 输出连接信息
echo "==============================================="
echo " Snell Server Installation Completed!"
echo " Server IP    : $SERVER_IP"
echo " Snell Port   : $RANDOM_PORT"
echo " Snell PSK    : $RANDOM_PSK"
echo " Config file  : $CONFIG_FILE"
echo " To check status: systemctl status snell-server"
echo "==============================================="
