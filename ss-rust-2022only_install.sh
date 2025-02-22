#!/bin/bash

set -e

echo "1. 更新并升级系统..."
apt update && apt upgrade -y

echo "2. 启用 BBR 网络优化..."
echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf
sysctl -p

echo "3. 安装 vim 和 mtr..."
apt install -y vim mtr

echo "4. 创建 Shadowsocks-rust 目录..."
INSTALL_DIR="/usr/local/etc/shadowsocks-rust"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo "5. 获取 Shadowsocks-rust 最新版本..."
LATEST_URL=$(curl -sL https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest | grep 'browser_download_url' | grep 'x86_64-unknown-linux-gnu.tar.xz' | cut -d '"' -f 4)

if [[ -z "$LATEST_URL" ]]; then
    echo "❌ 无法获取 Shadowsocks-rust 最新版下载链接，请检查 GitHub 访问或 API 是否正常。"
    exit 1
fi

echo "✅ 下载地址：$LATEST_URL"
wget -q --show-progress "$LATEST_URL" -O ss-rust.tar.xz

echo "6. 解压 Shadowsocks-rust..."
tar -xvf ss-rust.tar.xz --strip-components=1
rm -f ss-rust.tar.xz

echo "7. 生成 Shadowsocks-2022 加密密钥..."
PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)

echo "🛠 生成随机端口号 (1024-65535)..."
SERVER_PORT=$((RANDOM % 64512 + 1024))

echo "8. 创建 Shadowsocks 配置文件..."
cat <<EOF > "$INSTALL_DIR/config.json"
{
    "server": "0.0.0.0",
    "server_port": $SERVER_PORT,
    "method": "2022-blake3-aes-256-gcm",
    "password": "$PASSWORD"
}
EOF

echo "✅ 配置文件创建成功！"
echo "📌 服务器监听地址: 0.0.0.0"
echo "📌 服务器端口号: $SERVER_PORT"
echo "📌 加密方式: 2022-blake3-aes-256-gcm"
echo "📌 密码: $PASSWORD"

echo "9. 创建 systemd 服务..."
cat <<EOF > /etc/systemd/system/shadowsocks-rust.service
[Unit]
Description=Shadowsocks Rust Service
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

echo "✅ systemd 服务文件创建成功！"

echo "10. 启动并设置 Shadowsocks-rust 开机自启..."
systemctl daemon-reload
systemctl enable --now shadowsocks-rust

echo "🎉 安装完成！Shadowsocks-rust 已启动并设置为开机自启"
echo "📢 使用 systemctl status shadowsocks-rust 检查状态"
echo "🔥 Shadowsocks-rust 运行状态:"
systemctl status shadowsocks-rust --no-pager -l
