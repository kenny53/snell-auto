#!/usr/bin/env bash
set -euo pipefail

REPO="SagerNet/sing-box"
BIN_DIR="/usr/local/bin"
ETC_DIR="/etc/sing-box"
SERVICE_FILE="/etc/systemd/system/sing-box.service"
SB_USER="sing-box"

[[ $EUID -eq 0 ]] || { echo "Please run as root (sudo)"; exit 1; }

# 依赖
apt-get update -y
apt-get install -y curl jq tar libcap2-bin

# 架构映射
DEB_ARCH=$(dpkg --print-architecture)
case "$DEB_ARCH" in
  amd64)   CANDS=("linux-amd64v3" "linux-amd64") ;;
  i386)    CANDS=("linux-386") ;;
  arm64)   CANDS=("linux-arm64") ;;
  armhf)   CANDS=("linux-armv7") ;;
  riscv64) CANDS=("linux-riscv64") ;;
  *) echo "Unsupported architecture: $DEB_ARCH"; exit 2 ;;
esac

# 获取 release 信息
API="https://api.github.com/repos/${REPO}/releases/latest"
JSON=$(curl -fsSL "$API")
TAG=$(jq -r '.tag_name' <<<"$JSON")
[[ -n "$TAG" && "$TAG" != "null" ]] || { echo "Failed to fetch release info"; exit 3; }

ASSETS=$(jq -r '.assets[] | @base64' <<<"$JSON")
ASSET_NAME=""; ASSET_URL=""
for kw in "${CANDS[@]}"; do
  for row in $ASSETS; do
    row=$(echo "$row" | base64 -d)
    name=$(jq -r '.name' <<<"$row")
    url=$(jq -r '.browser_download_url' <<<"$row")
    if [[ "$name" == *"${kw}.tar.gz" ]]; then
      ASSET_NAME="$name"; ASSET_URL="$url"; break 2
    fi
  done
done
[[ -n "$ASSET_URL" ]] || { echo "No matching asset found"; exit 4; }

echo "[*] Downloading $ASSET_NAME ($TAG)…"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"
curl -fL --retry 3 -o "$ASSET_NAME" "$ASSET_URL"

echo "[*] Extracting…"
tar -xzf "$ASSET_NAME"
EXDIR=$(tar -tzf "$ASSET_NAME" | head -n1 | cut -d/ -f1)
[[ -x "$EXDIR/sing-box" ]] || { echo "Binary not found"; exit 5; }

echo "[*] Installing binary -> ${BIN_DIR}/sing-box"
install -m 0755 "$EXDIR/sing-box" "$BIN_DIR/sing-box"

# 建用户和目录
if ! id -u "$SB_USER" >/dev/null 2>&1; then
  useradd -r -s /usr/sbin/nologin -M "$SB_USER"
fi
mkdir -p "$ETC_DIR"
chown -R "$SB_USER:$SB_USER" "$ETC_DIR"

# 授权
setcap 'cap_net_admin,cap_net_bind_service=+ep' "$BIN_DIR/sing-box" || true

# 写 systemd 服务
cat > "$SERVICE_FILE" <<SYSTEMD
[Unit]
Description=Sing-Box Service
After=network-online.target
Wants=network-online.target
ConditionPathExists=${ETC_DIR}/config.json

[Service]
User=${SB_USER}
Group=${SB_USER}
ExecStart=${BIN_DIR}/sing-box run -c ${ETC_DIR}/config.json
Restart=always
RestartSec=3
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload
systemctl enable sing-box >/dev/null 2>&1 || true

echo
echo "=== DONE ==="
echo "Installed version: $($BIN_DIR/sing-box version)"
echo "Config dir:  $ETC_DIR   (请自行放置 config.json)"
echo "Service:     systemctl start sing-box"
