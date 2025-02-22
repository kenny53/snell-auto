#!/bin/bash

set -e

echo "📌 1. 更新系统..."
apt update && apt upgrade -y

echo "📌 2. 启用 BBR 加速..."
echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf
sysctl -p

echo "📌 3. 安装必要的软件 (vim、mtr)..."
apt install -y vim mtr curl wget

echo "📌 4. 创建 Shadowsocks-Rust 安装目录..."
INSTALL_DIR="/usr/local/etc/shadowsocks-rust"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo "📌 5. 获取 Shadowsocks-Rust 最新版本..."
LATEST_URL=$(curl -s https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest | grep 'browser_download_url' | grep 'x86_64-unknown-linux-gnu.tar.xz' | cut -d '"' -f 4)

if [[ -z "$LATEST_URL" ]]; then
    echo "❌ 无法获取 Shadowsocks-Rust 最新版下载链接，请检查 GitHub 访问或 API 是否正常。"
    exit 1
fi

echo "✅ 最新版下载地址: $LATEST_URL"
wget -q --show-progress "$LATEST_URL" -O ss-rust.tar.xz

echo "📌 6. 解压 Shadowsocks-Rust..."
tar -xvf ss-rust.tar.xz --strip-components=1
rm -f ss-rust.tar.xz

echo "📌 7. 生成 Shadowsocks-2022 的安全密码..."
PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)

echo "📌 8. 生成随机端口号 (1024 ~ 65535)..."
SERVER_PORT=$((RANDOM % 64512 + 1024))

echo "📌 9. 获取服务器公网 IP..."
SERVER_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || curl -s https://api64.ipify.org)

echo "📌 10. 创建 Shadowsocks 配置文件..."
cat <<EOF > "$INSTALL_DIR/config.json"
{
    "server": "0.0.0.0",
    "server_port": $SERVER_PORT,
    "method": "2022-blake3-aes-256-gcm",
    "password": "$PASSWORD"
}
EOF

echo "✅ Shadowsocks 配置文件已创建!"

echo "📌 11. 创建 Systemd 服务..."
cat <<EOF > /etc/systemd/system/shadowsocks-rust.service
[Unit]
Description=Shadowsocks Rust 代理服务
After=network.target

[Service]
ExecStart=$INSTALL_DIR/ssserver -c $INSTALL_DIR/config.json
Restart=always
User=nobody
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

echo "✅ Systemd 服务文件已创建!"

echo "📌 12. 启动 Shadowsocks 服务并设为开机自启..."
systemctl daemon-reload
systemctl enable --now shadowsocks-rust

echo "🎉 Shadowsocks-Rust 安装完成并成功运行！"
echo "📢 你可以使用 'systemctl status shadowsocks-rust' 检查状态"

echo "🔥 Shadowsocks 配置信息如下:"
echo "=================================="
echo "🌍 服务器 IP 地址: $SERVER_IP"
echo "🔌 服务器端口号  : $SERVER_PORT"
echo "🔐 加密方式      : 2022-blake3-aes-256-gcm"
echo "🔑 密码          : $PASSWORD"
echo "=================================="
echo "📢 请使用上述信息配置你的 Shadowsocks 客户端!"
