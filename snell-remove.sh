#!/bin/bash
set -e

TARGET_DIR="/usr/local/etc"
SNELL_BIN="$TARGET_DIR/snell-server"
CONFIG_FILE="$TARGET_DIR/snell-server.conf"
SERVICE_FILE="/etc/systemd/system/snell-server.service"

echo "=== Snell Server 一键卸载脚本 ==="

# 1. 停止 systemd 服务
if systemctl is-active --quiet snell-server; then
  echo "停止 snell-server 服务..."
  systemctl stop snell-server
fi

# 2. 禁用 systemd 服务
if systemctl is-enabled --quiet snell-server; then
  echo "禁用 snell-server 开机自启..."
  systemctl disable snell-server
fi

# 3. 删除 systemd 服务文件
if [ -f "$SERVICE_FILE" ]; then
  echo "删除 systemd 服务文件..."
  rm -f "$SERVICE_FILE"
  systemctl daemon-reload
fi

# 4. 删除 Snell 目录及文件
if [ -f "$SNELL_BIN" ] || [ -f "$CONFIG_FILE" ]; then
  echo "删除 $TARGET_DIR 下 snell-server 相关文件..."
  rm -f "$SNELL_BIN" "$CONFIG_FILE"
  # 如你要整个目录都删掉且里面没别的内容，可用 rm -rf "$TARGET_DIR"
fi

echo "卸载完成。如需彻底删除目录可手动运行: rm -rf $TARGET_DIR"
