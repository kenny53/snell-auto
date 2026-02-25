#!/bin/sh
# OpenWrt IPv4-only GeoIP(CN) 分流管理脚本
set -eu

CONFIG_FILE="/etc/geoip-cn-split.conf"
NFT_SET_FILE="/usr/share/nftables.d/table-pre/10-geoip-cn-set.nft"
NFT_MARK_FILE="/usr/share/nftables.d/chain-pre/mangle_prerouting/10-geoip-cn-mark.nft"
UPDATE_SCRIPT="/usr/bin/update-geoip-cn.sh"
ENSURE_SCRIPT="/usr/bin/geoip-policy-ensure.sh"
HOTPLUG_FILE="/etc/hotplug.d/iface/99-geoip-cn-recover"
CRON_FILE="/etc/crontabs/root"

init_config() {
  [ -f "$CONFIG_FILE" ] && return 0
  cat > "$CONFIG_FILE" <<'CFG'
WAN_IF="wan"
LAN_DEV="br-lan"
BYPASS_GW4="10.8.8.3"
MARK_HEX="0x66"
MARK_MASK="0xff"
TABLE_ID="100"
CFG
}

load_config() {
  init_config
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
}

save_config() {
  cat > "$CONFIG_FILE" <<CFG
WAN_IF="$WAN_IF"
LAN_DEV="$LAN_DEV"
BYPASS_GW4="$BYPASS_GW4"
MARK_HEX="$MARK_HEX"
MARK_MASK="$MARK_MASK"
TABLE_ID="$TABLE_ID"
CFG
}

install_deps() {
  if command -v apk >/dev/null 2>&1; then
    apk update
    apk add curl ca-certificates coreutils
  elif command -v opkg >/dev/null 2>&1; then
    opkg update
    opkg install curl ca-bundle coreutils-flock
  else
    echo "错误: 未找到 apk 或 opkg 包管理器" >&2
    return 1
  fi
}

write_nft_files() {
  mkdir -p /usr/share/nftables.d/table-pre
  mkdir -p /usr/share/nftables.d/chain-pre/mangle_prerouting

  cat > "$NFT_SET_FILE" <<'NFT'
set geoip_cn4 {
    type ipv4_addr
    flags interval
}
NFT

  cat > "$NFT_MARK_FILE" <<NFT
fib daddr type local return
ip daddr @geoip_cn4 return
ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16 } return

meta mark set ${MARK_HEX}
ct mark set mark
NFT
}

write_update_script() {
  cat > "$UPDATE_SCRIPT" <<'SH'
#!/bin/sh
set -e
URL="https://raw.githubusercontent.com/Loyalsoldier/geoip/release/text/cn.txt"
TMP="/tmp/geoip_cn.txt"
TMP4="/tmp/geoip_cn4.txt"

curl -fsSL "$URL" -o "$TMP"
grep -E '^[0-9]+\.' "$TMP" > "$TMP4" || true

{
  echo "flush set inet fw4 geoip_cn4"
  if [ -s "$TMP4" ]; then
    printf "add element inet fw4 geoip_cn4 { "
    paste -sd, "$TMP4"
    echo " }"
  fi
} | nft -f -
SH
  chmod +x "$UPDATE_SCRIPT"
}

write_ensure_script() {
  cat > "$ENSURE_SCRIPT" <<SH
#!/bin/sh
set -eu
MARK_HEX="${MARK_HEX}"
MARK_MASK="${MARK_MASK}"
TABLE_ID="${TABLE_ID}"
BYPASS_GW4="${BYPASS_GW4}"
BYPASS_DEV4="${LAN_DEV}"

ip -4 rule show | grep -q "fwmark \${MARK_HEX}/\${MARK_MASK}.*lookup \${TABLE_ID}" || \
  ip -4 rule add pref 10000 fwmark \${MARK_HEX}/\${MARK_MASK} table \${TABLE_ID}

ip -4 route replace default via "\${BYPASS_GW4}" dev "\${BYPASS_DEV4}" table "\${TABLE_ID}"

if ! nft list chain inet fw4 mangle_prerouting 2>/dev/null | grep -q "meta mark set \${MARK_HEX}"; then
  fw4 reload
fi

logger -t geoip-cn "policy ensured: gw=\${BYPASS_GW4}, mark=\${MARK_HEX}, table=\${TABLE_ID}"
SH
  chmod +x "$ENSURE_SCRIPT"
}

write_hotplug() {
  cat > "$HOTPLUG_FILE" <<SH
#!/bin/sh
[ "\$ACTION" = "ifup" ] || [ "\$ACTION" = "ifupdate" ] || exit 0
[ "\$INTERFACE" = "${WAN_IF}" ] || exit 0

(
  flock -n 9 || exit 0
  ${ENSURE_SCRIPT}
) 9>/var/lock/geoip-cn-recover.lock
SH
  chmod +x "$HOTPLUG_FILE"
}

apply_uci_policy() {
  uci -q delete network.geoip_rule4
  uci set network.geoip_rule4='rule'
  uci set network.geoip_rule4.priority='10000'
  uci set network.geoip_rule4.mark="${MARK_HEX}/${MARK_MASK}"
  uci set network.geoip_rule4.lookup="${TABLE_ID}"

  uci -q delete network.geoip_route4
  uci set network.geoip_route4='route'
  uci set network.geoip_route4.interface='lan'
  uci set network.geoip_route4.target='0.0.0.0/0'
  uci set network.geoip_route4.gateway="${BYPASS_GW4}"
  uci set network.geoip_route4.table="${TABLE_ID}"

  uci commit network
}

ensure_boot_cron() {
  grep -q 'geoip-policy-ensure.sh' /etc/rc.local || \
    sed -i '/^exit 0/i /usr/bin/geoip-policy-ensure.sh \&' /etc/rc.local

  grep -q 'update-geoip-cn.sh' "$CRON_FILE" || \
    echo '0 4 * * * /usr/bin/update-geoip-cn.sh' >> "$CRON_FILE"
}

reload_services() {
  /etc/init.d/network restart
  /etc/init.d/firewall restart
  /etc/init.d/cron restart
}

setup_split() {
  load_config
  install_deps
  write_nft_files
  write_update_script
  write_ensure_script
  write_hotplug
  apply_uci_policy
  ensure_boot_cron
  reload_services
  "$UPDATE_SCRIPT"
  "$ENSURE_SCRIPT"
  echo "完成: GeoIP 分流已启用（IPv4 only）"
}

update_cnip() {
  [ -x "$UPDATE_SCRIPT" ] || { echo "未找到 $UPDATE_SCRIPT，请先执行选项1"; return 1; }
  "$UPDATE_SCRIPT"
  echo "完成: CNIP 已更新"
}

clear_rules() {
  rm -f "$NFT_SET_FILE" "$NFT_MARK_FILE" "$UPDATE_SCRIPT" "$ENSURE_SCRIPT" "$HOTPLUG_FILE"

  uci -q delete network.geoip_rule4
  uci -q delete network.geoip_route4
  uci commit network

  sed -i '\|/usr/bin/geoip-policy-ensure.sh|d' /etc/rc.local
  sed -i '\|/usr/bin/update-geoip-cn.sh|d' "$CRON_FILE" || true

  /etc/init.d/network restart
  /etc/init.d/firewall restart
  /etc/init.d/cron restart

  nft 'flush set inet fw4 geoip_cn4' 2>/dev/null || true
  echo "完成: 规则已清除"
}

custom_gateway() {
  load_config
  printf "当前非CN网关: %s\n请输入新网关IP: " "$BYPASS_GW4"
  read -r newgw
  [ -n "$newgw" ] || { echo "未输入，取消"; return 1; }
  BYPASS_GW4="$newgw"
  save_config

  apply_uci_policy
  write_ensure_script
  /etc/init.d/network restart
  "$ENSURE_SCRIPT"
  echo "完成: 非CN网关已改为 $BYPASS_GW4"
}

menu() {
  while true; do
    load_config
    echo ""
    echo "==== GeoIP CN 分流管理 (IPv4) ===="
    echo "当前配置: WAN=${WAN_IF} LAN_DEV=${LAN_DEV} 非CN网关=${BYPASS_GW4}"
    echo "1) GeoIP分流（初始化/重建）"
    echo "2) 更新CNIP"
    echo "3) 清除规则"
    echo "4) 自定义非CNIP网关"
    echo "0) 退出"
    printf "请选择: "
    read -r n

    case "$n" in
      1) setup_split ;;
      2) update_cnip ;;
      3) clear_rules ;;
      4) custom_gateway ;;
      0) exit 0 ;;
      *) echo "无效选项" ;;
    esac
  done
}

menu
