#!/bin/bash

set -e  # 遇到错误时立即退出

# 颜色标注输出
GREEN="\e[32m"
RED="\e[31m"
RESET="\e[0m"

echo -e "${GREEN}📌 1. 更新系统...${RESET}"
apt update && apt upgrade -y

echo -e "${GREEN}📌 2. 启用 BBR 加速...${RESET}"
echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf
sysctl -p

echo -e "${GREEN}📌 3. 安装必要的软件...${RESET}"
apt install -y vim mtr curl wget jq

echo -e "${GREEN}📌 4. 创建 Shadowsocks-Rust 目录...${RESET}"
INSTALL_DIR="/usr/local/etc/shadowsocks-rust"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo -e "${GREEN}📌 5. 获取 Shadowsocks-Rust 最新版本...${RESET}"

# 使用 GitHub API 获取最新版本号
LATEST_VERSION=$(curl -s https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest | jq -r '.tag_name')

# 如果获取失败，尝试备用方案
if [[ -z "$LATEST_VERSION" || "$LATEST_VERSION" == "null" ]]; then
    echo -e "${RED}❌ 获取 Shadowsocks 版本失败，尝试备用方式...${RESET}"
    LATEST_VERSION=$(curl -s https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases | jq -r '.[0].tag_name')
fi

# 如果仍然失败，则退出
if [[ -z "$LATEST_VERSION" || "$LATEST_VERSION" == "null" ]]; then
    echo -e "${RED}❌ 无法获取 Shadowsocks-Rust 最新版本号，请检查 GitHub 访问或 API 是否受限。${RESET}"
    exit 1
fi

echo -e "✅  最新版本: $LATEST_VERSION"

# 构造下载链接
LATEST_URL="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${LATEST_VERSION}/shadowsocks-${LATEST_VERSION}-x86_64-unknown-linux-gnu.tar.xz"

echo -e "✅  下载链接: ${LATEST_URL}"
wget -q --show-progress "$LATEST_URL" -O ss-rust.tar.xz

echo -e "${GREEN}📌 6. 解压 Shadowsocks-Rust...${RESET}"
tar -xvf ss-rust.tar.xz --strip-components=1
rm -f ss-rust.tar.xz

echo -e "${GREEN}📌 7. 生成 Shadowsocks-2022 的安全密码...${RESET}"
PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)

echo -e "${GREEN}📌 8. 生成随机端口号 (1024 ~ 65535)...${RESET}"
SERVER_PORT=$((RANDOM % 64512 + 1024))

echo -e "${GREEN}📌 9. 获取服务器公网 IP...${RESET}"
SERVER_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || curl -s https://api64.ipify.org)

echo -e "${GREEN}📌 10. 创建 Shadowsocks 配置文件...${RESET}"
cat <<EOF > "$INSTALL_DIR/config.json"
{
    "server": "0.0.0.0",
    "server_port": $SERVER_PORT,
    "method": "2022-blake3-aes-256-gcm",
    "password": "$PASSWORD"
}
EOF

echo -e "✅ 配置文件已创建! 📄"

echo -e "${GREEN}📌 11. 创建 Systemd 服务...${RESET}"
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

echo -e "✅ Systemd 服务已创建! 🛠"

echo -e "${GREEN}📌 12. 启动 Shadowsocks 服务并设为开机自启...${RESET}"
systemctl daemon-reload
systemctl enable --now shadowsocks-rust

echo -e "🎉 Shadowsocks-Rust 成功安装并运行！ 🚀"
echo -e "📢 使用以下命令检查服务状态: ${GREEN}systemctl status shadowsocks-rust${RESET}"

echo -e "${GREEN}🔥 Shadowsocks 配置信息如下:${RESET}"
echo "=================================="
echo -e "🌍 服务器 IP 地址: ${GREEN}$SERVER_IP${RESET}"
echo -e "🔌 服务器端口号  : ${GREEN}$SERVER_PORT${RESET}"
echo -e "🔐 加密方式      : ${GREEN}2022-blake3-aes-256-gcm${RESET}"
echo -e "🔑 密码          : ${GREEN}$PASSWORD${RESET}"
echo "=================================="
echo "📢 请使用上述信息配置你的 Shadowsocks 客户端! ✅"
