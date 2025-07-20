#!/bin/bash
set -e

# 必需依赖包列表
DEPS=(wget gpg lsb-release)

# 检查并安装依赖
for pkg in "${DEPS[@]}"; do
  if ! dpkg -s "$pkg" &>/dev/null; then
    echo "缺少依赖: $pkg，正在安装..."
    apt update
    apt install -y "$pkg"
  fi
done

# 检查是否为root用户
if [ "$(id -u)" -ne 0 ]; then
  echo "请以 root 用户或使用 sudo 执行此脚本。"
  exit 1
fi

# 检查和创建keyrings目录
KEYRING_DIR="/etc/apt/keyrings"
KEYRING_FILE="$KEYRING_DIR/xanmod-archive-keyring.gpg"
[ -d "$KEYRING_DIR" ] || mkdir -p "$KEYRING_DIR"

# 导入 XanMod PGP 公钥
echo "正在导入 XanMod 公钥..."
wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor -o "$KEYRING_FILE"

# 获取发行版codename
CODENAME=$(lsb_release -sc)

# 检查是否支持当前codename
if ! echo "bookworm trixie sid noble oracular plucky questing faye wilma xia" | grep -qw "$CODENAME"; then
  echo "当前系统 codename ($CODENAME) 不在官方支持列表中。请确认兼容性后继续。"
  exit 1
fi

# 添加XanMod软件源
REPO_LINE="deb [signed-by=$KEYRING_FILE] http://deb.xanmod.org $CODENAME main"
echo "$REPO_LINE" | tee /etc/apt/sources.list.d/xanmod-release.list

# 更新软件包并安装xanmod内核
apt update
apt install -y linux-xanmod-x64v3

echo "XanMod 内核安装完成，系统即将自动重启以启用新内核！"
sleep 3
reboot
