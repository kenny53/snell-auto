#!/bin/bash
set -e

echo "=== Debian 12 全自动初始化脚本（含 Snell Server）==="

# 检查是否为 root
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ 请以 root 用户执行此脚本。"
  exit 1
fi

### Step 1: 设置时区 ###
echo "[1/6] 设置时区为 Asia/Hong_Kong"
timedatectl set-timezone Asia/Hong_Kong

### Step 2: 更新系统 ###
echo "[2/6] 更新系统并安装常用软件包"
apt update && apt upgrade -y
apt install -y curl wget vim git htop sudo lsof \
  net-tools unzip ca-certificates gnupg \
  bash-completion build-essential

### Step 3: 启用 BBR ###
echo "[3/6] 启用 TCP BBR 拥塞控制"
if ! grep -q "tcp_bbr" /etc/sysctl.conf; then
  cat <<EOF >> /etc/sysctl.conf

# 启用 BBR 拥塞控制
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
fi
sysctl -p || echo "⚠️ sysctl -p 执行失败，BBR 可能未正确应用，请手动检查"

### Step 4: 下载 Snell Server ###
echo "[4/6] 检测系统架构并下载 Snell Server"

ARCH=$(uname -m)
SNELL_URL=""
TARGET_DIR="/usr/local/etc"
mkdir -p "$TARGET_DIR"

case "$ARCH" in
  x86_64)
    SNELL_URL="https://dl.nssurge.com/snell/snell-server-v5.0.0-linux-amd64.zip"
    ;;
  i386|i686)
    SNELL_URL="https://dl.nssurge.com/snell/snell-server-v5.0.0-linux-i386.zip"
    ;;
  aarch64)
    SNELL_URL="https://dl.nssurge.com/snell/snell-server-v5.0.0-linux-aarch64.zip"
    ;;
  armv7l)
    SNELL_URL="https://dl.nssurge.com/snell/snell-server-v5.0.0-linux-armv7l.zip"
    ;;
  *)
    echo "❌ 不支持的架构: $ARCH"
    exit 1
    ;;
esac

cd "$TARGET_DIR"
wget -N "$SNELL_URL"
unzip -o snell-server-v5.0.0-*.zip
chmod +x snell-server

### Step 5: 自动生成配置文件 ###
echo "[5/6] 检查 Snell 配置文件是否存在..."

CONFIG_FILE="$TARGET_DIR/snell-server.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "未检测到 snell-server.conf，自动生成配置..."

  # 随机端口（1025–65535）
  SNELL_PORT=$(( RANDOM % 64511 + 1025 ))

  # 随机 32 字符 PSK
  SNELL_PSK=$(openssl rand -hex 16)

  cat <<EOF > "$CONFIG_FILE"
port = $SNELL_PORT
psk = $SNELL_PSK
EOF

  echo "✅ 已生成配置文件: $CONFIG_FILE"
else
  echo "已存在配置文件，跳过生成"
fi

### Step 6: 注册为 systemd 服务 ###
echo "[6/6] 注册 Snell Server 为 systemd 服务"

cat <<EOF > /etc/systemd/system/snell-server.service
[Unit]
Description=Snell Proxy Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$TARGET_DIR
ExecStart=$TARGET_DIR/snell-server -c $CONFIG_FILE
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable snell-server
systemctl restart snell-server

### 显示网络信息与 Snell 配置 ###
echo
echo "=== ✅ 初始化完成 ==="

IPV4=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127' | head -n1)
IPV6=$(ip -6 addr show scope global | grep -oP '(?<=inet6\s)[a-f0-9:]+(?=/)' | head -n1)

echo "IPv4 地址: $IPV4"
echo "IPv6 地址: $IPV6"

if [ -f "$CONFIG_FILE" ]; then
  echo
  echo "🔧 Snell 配置内容："
  grep -E '^port|^psk' "$CONFIG_FILE"
else
  echo "⚠️ 未找到 Snell 配置文件"
fi

echo
systemctl status snell-server --no-pager
