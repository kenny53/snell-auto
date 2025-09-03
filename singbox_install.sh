#!/usr/bin/env bash
set -euo pipefail

REPO="SagerNet/sing-box"
BIN_DIR="/usr/local/bin"
ETC_DIR="/etc/sing-box"
SERVICE_FILE="/etc/systemd/system/sing-box.service"
SB_USER="sing-box"

# 需要 curl、jq、tar、setcap
need() { command -v "$1" >/dev/null 2>&1 || { apt-get update && apt-get install -y "$2"; }; }
[[ $EUID -eq 0 ]] || { echo "Please run as root (sudo)"; exit 1; }
need curl curl
need jq jq
need tar tar
need setcap libcap2-bin
need sha256sum coreutils
need sed sed

# 映射 Debian 架构到 sing-box 资产关键字
DEB_ARCH=$(dpkg --print-architecture)
case "$DEB_ARCH" in
  amd64)   CANDS=("linux-amd64v3" "linux-amd64") ;;  # 优先 v3，有些版本才有
  i386)    CANDS=("linux-386") ;;
  arm64)   CANDS=("linux-arm64") ;;
  armhf)   CANDS=("linux-armv7") ;;
  riscv64) CANDS=("linux-riscv64") ;;
  *) echo "Unsupported architecture: $DEB_ARCH"; exit 2 ;;
esac

echo "[*] Fetching latest release metadata…"
API="https://api.github.com/repos/${REPO}/releases/latest"
# 如果被 GitHub API 限流，可设置 GH_TOKEN 环境变量提高配额
AUTH_HDR=()
[[ -n "${GH_TOKEN:-}" ]] && AUTH_HDR=(-H "Authorization: Bearer ${GH_TOKEN}")
JSON=$(curl -fsSL "${AUTH_HDR[@]}" "$API")

TAG=$(jq -r '.tag_name' <<<"$JSON")
[[ "$TAG" != "null" && -n "$TAG" ]] || { echo "Failed to get latest tag"; exit 3; }
echo "[*] Latest tag: $TAG"

# 在 assets 中按候选关键词寻找合适的 tar.gz 与 checksums.txt
ASSETS=$(jq -r '.assets[] | @base64' <<<"$JSON")

pick_asset() {
  local kw="$1"
  for row in $ASSETS; do
    row=$(echo "$row" | base64 -d)
    name=$(jq -r '.name' <<<"$row")
    url=$(jq -r '.browser_download_url' <<<"$row")
    if [[ "$name" == *"${kw}.tar.gz" ]]; then
      echo "$name|$url"
      return 0
    fi
  done
  return 1
}

ASSET_NAME=""
ASSET_URL=""
for kw in "${CANDS[@]}"; do
  if out=$(pick_asset "$kw"); then
    ASSET_NAME="${out%%|*}"
    ASSET_URL="${out##*|}"
    break
  fi
done

[[ -n "$ASSET_NAME" ]] || { echo "No matching tar.gz asset found for arch=${DEB_ARCH} (candidates: ${CANDS[*]})"; exit 4; }
echo "[*] Selected asset: $ASSET_NAME"

# 找 checksums 文件
CHECK_NAME=""
CHECK_URL=""
while read -r row; do
  row=$(echo "$row" | base64 -d)
  name=$(jq -r '.name' <<<"$row")
  url=$(jq -r '.browser_download_url' <<<"$row")
  if [[ "$name" == *checksums.txt ]]; then
    CHECK_NAME="$name"
    CHECK_URL="$url"
    break
  fi
done <<<"$ASSETS"

[[ -n "$CHECK_NAME" ]] || { echo "Checksums file not found in latest release"; exit 5; }

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

echo "[*] Downloading: $ASSET_NAME"
curl -fL --retry 3 -o "$ASSET_NAME" "$ASSET_URL"

echo "[*] Downloading: $CHECK_NAME"
curl -fL --retry 3 -o "$CHECK_NAME" "$CHECK_URL"

echo "[*] Verifying sha256..."
# checksums 里每行可能是 "SHA256  filename" 或 "hash  filename"
# 都用 grep 精确匹配文件名再校验
( grep -F " $ASSET_NAME" "$CHECK_NAME" || grep -F "  $ASSET_NAME" "$CHECK_NAME" ) | sha256sum -c -

echo "[*] Extracting..."
tar -xzf "$ASSET_NAME"
EXDIR=$(tar -tzf "$ASSET_NAME" | head -n1 | cut -d/ -f1)
[[ -x "$EXDIR/sing-box" ]] || { echo "sing-box binary not found after extraction"; exit 6; }

echo "[*] Installing binary -> ${BIN_DIR}/sing-box"
install -m 0755 "$EXDIR/sing-box" "${BIN_DIR}/sing-box"

# 创建用户/目录（不写 config.json）
if ! id -u "$SB_USER" >/dev/null 2>&1; then
  useradd -r -s /usr/sbin/nologin -M "$SB_USER"
fi
mkdir -p "$ETC_DIR"
chown -R "$SB_USER:$SB_USER" "$ETC_DIR"
chmod 0755 "$ETC_DIR"

# 赋权（TUN / 低端口）
setcap 'cap_net_admin,cap_net_bind_service=+ep' "${BIN_DIR}/sing-box" || true

echo "[*] Writing systemd service -> $SERVICE_FILE"
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

echo "[*] Installed:"
"${BIN_DIR}/sing-box" version || true

echo
echo "=== DONE ==="
echo "Binary:      $(command -v sing-box)"
echo "Config dir:  ${ETC_DIR}   # 请自行放置 config.json（如 TUN 全局配置）"
echo "Service:     systemctl start sing-box   # 仅在存在 config.json 时启动"
