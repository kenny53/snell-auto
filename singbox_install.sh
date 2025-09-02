#!/usr/bin/env bash
set -euo pipefail

# === Basic ===
REPO="SagerNet/sing-box"
BIN_DIR="/usr/local/bin"
ETC_DIR="/etc/sing-box"
SERVICE_FILE="/etc/systemd/system/sing-box.service"
SB_USER="sing-box"

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo)"; exit 1
fi

command -v curl >/dev/null || { apt-get update && apt-get install -y curl; }
command -v tar  >/dev/null || { apt-get update && apt-get install -y tar; }
command -v sed  >/dev/null || { apt-get update && apt-get install -y sed; }
command -v sha256sum >/dev/null || { apt-get update && apt-get install -y coreutils; }
command -v setcap >/dev/null || { apt-get update && apt-get install -y libcap2-bin; }

# === Arch map (Debian x86 家族优先) ===
DEB_ARCH=$(dpkg --print-architecture)
case "$DEB_ARCH" in
  amd64)  SB_PLAT="linux-amd64" ;;
  i386)   SB_PLAT="linux-386"   ;;
  # 兼容其他：如需可自行删掉
  arm64)  SB_PLAT="linux-arm64" ;;
  armhf)  SB_PLAT="linux-armv7" ;;
  riscv64) SB_PLAT="linux-riscv64" ;;
  *)
    echo "Unsupported architecture: $DEB_ARCH"; exit 2
  ;;
esac

echo "[*] Detecting latest release from GitHub..."
LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
  | sed -n 's/  *\"tag_name\": *\"\(v\{0,1\}[0-9][^"]*\)\".*/\1/p' | head -n1)
[[ -n "${LATEST_TAG:-}" ]] || { echo "Failed to get latest tag"; exit 3; }

VER="${LATEST_TAG#v}"
ASSET="sing-box-${VER}-${SB_PLAT}.tar.gz"
CHECKSUM_FILE="sing-box-${VER}-checksums.txt"
BASE_URL="https://github.com/${REPO}/releases/download/${LATEST_TAG}"

echo "[*] Latest: ${LATEST_TAG}  asset=${ASSET}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

echo "[*] Downloading asset & checksums..."
curl -fL --retry 3 -o "${ASSET}"        "${BASE_URL}/${ASSET}"
curl -fL --retry 3 -o "${CHECKSUM_FILE}" "${BASE_URL}/${CHECKSUM_FILE}"

echo "[*] Verifying sha256..."
grep " ${ASSET}$" "${CHECKSUM_FILE}" | sha256sum -c -

echo "[*] Extracting..."
tar -xzf "${ASSET}"
EXTRACT_DIR="sing-box-${VER}-${SB_PLAT}"
[[ -x "${EXTRACT_DIR}/sing-box" ]] || { echo "Binary not found after extract"; exit 4; }

echo "[*] Installing binary -> ${BIN_DIR}/sing-box"
install -m 0755 "${EXTRACT_DIR}/sing-box" "${BIN_DIR}/sing-box"

# 创建最小运行环境（不写 config.json）
echo "[*] Preparing user & dirs..."
if ! id -u "${SB_USER}" >/dev/null 2>&1; then
  useradd -r -s /usr/sbin/nologin -M "${SB_USER}"
fi
mkdir -p "${ETC_DIR}"
chown -R "${SB_USER}:${SB_USER}" "${ETC_DIR}"
chmod 0755 "${ETC_DIR}"

# 赋予必要能力：TUN / 低端口
echo "[*] Setting capabilities..."
setcap 'cap_net_admin,cap_net_bind_service=+ep' "${BIN_DIR}/sing-box" || true

# 写入 systemd（仅在存在配置文件时才启动）
echo "[*] Writing systemd service -> ${SERVICE_FILE}"
cat > "${SERVICE_FILE}" <<SYSTEMD
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
echo "Binary:  $(command -v sing-box)"
echo "Config dir: ${ETC_DIR}"
echo "Service: systemctl start sing-box    # 仅当你放好 ${ETC_DIR}/config.json 后才会启动"
