#!/bin/sh

# ============================================
# OpenWrt 25.12 chnroute 分流管理脚本
# Surge Gateway VM: 10.8.8.3
# ============================================

set -u

# ─── 全局配置 ───
GW_SURGE="10.8.8.3"
TABLE_CHINA=100
TABLE_FOREIGN=200
MARK_CHINA="0x10"
MARK_FOREIGN="0x20"
RULE_PRIO_CHINA=100
RULE_PRIO_FOREIGN=200
NFT_TABLE="inet fw4"
CHAIN_ENTRY="mangle_prerouting"
CHAIN_MARK="chnroute_mark"
SET_CHN="chnroute4"
SET_SURGE_MACS="surge_macs"
SET_DOH="doh_direct4"
DOH_IPS="1.1.1.1, 76.76.2.0"
CHNROUTE_URL="https://cdn.jsdelivr.net/gh/misakaio/chnroutes2@master/chnroutes.txt"
CHNROUTE_FILE="/etc/chnroute.txt"

# ─── 颜色 ───
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── 工具函数 ───
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

info() {
    printf "${GREEN}✓${RESET} %s\n" "$*"
}

warn() {
    printf "${YELLOW}!${RESET} %s\n" "$*"
}

fail() {
    printf "${RED}✗${RESET} %s\n" "$*"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        fail "缺少命令: $1"
        return 1
    }
}

download() {
    url="$1"
    out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 15 --retry 3 "$url" -o "$out"
        return $?
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -q -T 15 -O "$out" "$url"
        return $?
    fi
    if command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q -T 15 -O "$out" "$url"
        return $?
    fi
    fail "curl/wget/uclient-fetch 都不可用"
    return 127
}

is_running() {
    nft list chain $NFT_TABLE "$CHAIN_MARK" >/dev/null 2>&1
}

# ─── 分流核心函数 ───
ensure_base_chain() {
    nft list chain $NFT_TABLE "$CHAIN_ENTRY" >/dev/null 2>&1 || {
        fail "未找到 $NFT_TABLE $CHAIN_ENTRY (fw4 未就绪?)"
        return 1
    }
}

ensure_set() {
    name="$1"
    type="$2"
    extra="$3"
    if nft list set $NFT_TABLE "$name" >/dev/null 2>&1; then
        nft flush set $NFT_TABLE "$name"
    else
        nft add set $NFT_TABLE "$name" "{ type $type; $extra }"
    fi
}

load_chnroute_set() {
    file="$1"
    [ -s "$file" ] || {
        warn "$file 不存在或为空"
        return 1
    }

    tmp_file="$(mktemp)" || return 1
    {
        echo "flush set $NFT_TABLE $SET_CHN"
        echo "add element $NFT_TABLE $SET_CHN {"
        sed -n '/^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+\(\/[0-9]\+\)\{0,1\}$/p' "$file" | sed 's/$/,/'
        echo "}"
    } >"$tmp_file"

    if ! nft -f "$tmp_file"; then
        rm -f "$tmp_file"
        fail "导入 chnroute 集合失败"
        return 1
    fi
    rm -f "$tmp_file"
    return 0
}

setup_rules() {
    nft delete rule $NFT_TABLE "$CHAIN_ENTRY" comment "chnroute_jump" 2>/dev/null
    nft delete chain $NFT_TABLE "$CHAIN_MARK" 2>/dev/null

    nft add chain $NFT_TABLE "$CHAIN_MARK"
    nft insert rule $NFT_TABLE "$CHAIN_ENTRY" jump "$CHAIN_MARK" comment "chnroute_jump"

    nft add rule $NFT_TABLE "$CHAIN_MARK" meta nfproto != ipv4 return
    nft add rule $NFT_TABLE "$CHAIN_MARK" iifname "lo" return
    nft add rule $NFT_TABLE "$CHAIN_MARK" ct direction reply return
    nft add rule $NFT_TABLE "$CHAIN_MARK" meta mark != 0x0 return

    nft add rule $NFT_TABLE "$CHAIN_MARK" ether saddr @"$SET_SURGE_MACS" return
    nft add rule $NFT_TABLE "$CHAIN_MARK" ip saddr "$GW_SURGE" return
    nft add rule $NFT_TABLE "$CHAIN_MARK" ip daddr "$GW_SURGE" return

    nft add rule $NFT_TABLE "$CHAIN_MARK" ip daddr { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/3 } return

    nft add rule $NFT_TABLE "$CHAIN_MARK" ip daddr @"$SET_DOH" meta mark set "$MARK_CHINA" return
    nft add rule $NFT_TABLE "$CHAIN_MARK" ip daddr @"$SET_CHN" meta mark set "$MARK_CHINA" return
    nft add rule $NFT_TABLE "$CHAIN_MARK" meta mark set "$MARK_FOREIGN"
}

setup_policy_routing() {
    wan_gw="$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}')"

    ip rule del fwmark "$MARK_CHINA" table "$TABLE_CHINA" priority "$RULE_PRIO_CHINA" 2>/dev/null
    ip rule del fwmark "$MARK_FOREIGN" table "$TABLE_FOREIGN" priority "$RULE_PRIO_FOREIGN" 2>/dev/null

    ip rule add fwmark "$MARK_CHINA" table "$TABLE_CHINA" priority "$RULE_PRIO_CHINA"
    ip rule add fwmark "$MARK_FOREIGN" table "$TABLE_FOREIGN" priority "$RULE_PRIO_FOREIGN"

    if [ -n "$wan_gw" ]; then
        ip route replace default via "$wan_gw" table "$TABLE_CHINA"
    fi

    gw_dev="$(ip route get "$GW_SURGE" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')"
    gw_via="$(ip route get "$GW_SURGE" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via") {print $(i+1); exit}}')"

    if [ -z "$gw_dev" ]; then
        fail "无法解析 Surge 网关接口 ($GW_SURGE)"
        return 1
    fi

    if [ -n "$gw_via" ]; then
        ip route replace default via "$gw_via" dev "$gw_dev" table "$TABLE_FOREIGN"
    else
        ip route replace default via "$GW_SURGE" dev "$gw_dev" table "$TABLE_FOREIGN"
    fi

    ip route flush cache

    info "中国 IP -> 主路由 ($wan_gw)"
    if [ -n "$gw_via" ]; then
        info "其他 IP -> Surge ($GW_SURGE, via $gw_via dev $gw_dev)"
    else
        info "其他 IP -> Surge ($GW_SURGE dev $gw_dev)"
    fi
    return 0
}

# ─── 菜单动作 ───

do_start() {
    printf "\n${CYAN}═══ 启动 chnroute 分流 ═══${RESET}\n\n"

    if is_running; then
        warn "分流已在运行中，将先停止再启动"
        do_stop
        echo ""
    fi

    require_cmd nft || return 1
    require_cmd ip  || return 1
    ensure_base_chain || return 1

    printf "${BOLD}[1/4]${RESET} 准备 nftables 资源...\n"
    ensure_set "$SET_SURGE_MACS" "ether_addr" ""
    nft add element $NFT_TABLE "$SET_SURGE_MACS" { 50:65:f3:30:fc:74, 1e:4a:32:c0:6a:76, 52:65:f3:03:bb:64, 8c:1f:64:47:22:66 }

    ensure_set "$SET_CHN" "ipv4_addr" "flags interval; auto-merge;"
    ensure_set "$SET_DOH" "ipv4_addr" "flags interval; auto-merge;"
    nft add element $NFT_TABLE "$SET_DOH" { $DOH_IPS }

    printf "${BOLD}[2/4]${RESET} 加载 IP 列表...\n"
    load_chnroute_set "$CHNROUTE_FILE" || true

    printf "${BOLD}[3/4]${RESET} 写入分流规则...\n"
    setup_rules

    printf "${BOLD}[4/4]${RESET} 配置策略路由...\n"
    setup_policy_routing

    echo ""
    info "启动完成"
}

do_stop() {
    printf "\n${CYAN}═══ 停止 chnroute 分流 ═══${RESET}\n\n"

    printf "${BOLD}[1/3]${RESET} 清理策略路由...\n"
    ip rule del fwmark "$MARK_CHINA" table "$TABLE_CHINA" priority "$RULE_PRIO_CHINA" 2>/dev/null
    ip rule del fwmark "$MARK_FOREIGN" table "$TABLE_FOREIGN" priority "$RULE_PRIO_FOREIGN" 2>/dev/null
    ip route flush table "$TABLE_CHINA" 2>/dev/null
    ip route flush table "$TABLE_FOREIGN" 2>/dev/null

    printf "${BOLD}[2/3]${RESET} 清理 nftables 规则...\n"
    nft delete rule $NFT_TABLE "$CHAIN_ENTRY" comment "chnroute_jump" 2>/dev/null
    nft delete chain $NFT_TABLE "$CHAIN_MARK" 2>/dev/null
    nft delete set $NFT_TABLE "$SET_CHN" 2>/dev/null
    nft delete set $NFT_TABLE "$SET_SURGE_MACS" 2>/dev/null
    nft delete set $NFT_TABLE "$SET_DOH" 2>/dev/null

    printf "${BOLD}[3/3]${RESET} 刷新路由缓存...\n"
    ip route flush cache

    info "已停止"
}

do_refresh() {
    printf "\n${CYAN}═══ 刷新策略路由 ═══${RESET}\n\n"

    if ! is_running; then
        fail "分流未运行，请先启动"
        return 1
    fi

    require_cmd ip || return 1
    setup_policy_routing
    echo ""
    info "刷新完成"
}

do_update() {
    printf "\n${CYAN}═══ 更新中国 IP 列表 ═══${RESET}\n\n"

    TMP_FILE="/tmp/chnroute_tmp.txt"

    printf "下载中...\n"
    if ! download "$CHNROUTE_URL" "$TMP_FILE"; then
        fail "下载失败"
        rm -f "$TMP_FILE"
        return 1
    fi

    sed '/^#/d;/^$/d' "$TMP_FILE" | sed -n '/^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+\(\/[0-9]\+\)\{0,1\}$/p' > "${TMP_FILE}.clean"

    if [ ! -s "${TMP_FILE}.clean" ]; then
        fail "下载内容为空或格式异常"
        rm -f "$TMP_FILE" "${TMP_FILE}.clean"
        return 1
    fi

    mv "${TMP_FILE}.clean" "$CHNROUTE_FILE"
    rm -f "$TMP_FILE"

    count="$(wc -l < "$CHNROUTE_FILE")"
    info "下载完成: $count 条记录"

    # 若服务运行中，热加载
    if is_running; then
        printf "检测到服务运行中，重新加载...\n"
        load_chnroute_set "$CHNROUTE_FILE" && info "热加载完成" || warn "热加载失败，保留现有规则"
    fi
}

do_status() {
    printf "\n${CYAN}═══ chnroute 状态 ═══${RESET}\n\n"

    printf "${BOLD}--- IP 列表 ---${RESET}\n"
    if [ -f "$CHNROUTE_FILE" ]; then
        echo "  文件: $CHNROUTE_FILE"
        echo "  条目: $(wc -l < "$CHNROUTE_FILE") 条"
        echo "  更新: $(ls -l "$CHNROUTE_FILE" | awk '{print $6, $7, $8}')"
    else
        echo "  文件不存在"
    fi
    echo ""

    printf "${BOLD}--- 服务状态 ---${RESET}\n"
    if is_running; then
        printf "  状态: ${GREEN}运行中${RESET}\n"
    else
        printf "  状态: ${RED}未运行${RESET}\n"
    fi
    echo ""

    printf "${BOLD}--- 跳转规则 ---${RESET}\n"
    nft list chain $NFT_TABLE "$CHAIN_ENTRY" 2>/dev/null | grep -E "chnroute_jump|jump $CHAIN_MARK" | sed 's/^/  /' || echo "  未找到跳转"
    echo ""

    printf "${BOLD}--- 分流规则链 ---${RESET}\n"
    nft list chain $NFT_TABLE "$CHAIN_MARK" 2>/dev/null | grep -v '^table\|^}$' | sed 's/^/  /' || echo "  未创建"
    echo ""

    printf "${BOLD}--- DoH 直连白名单 ---${RESET}\n"
    nft list set $NFT_TABLE "$SET_DOH" 2>/dev/null | grep -E "elements|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | sed 's/^/  /' || echo "  空"
    echo ""

    printf "${BOLD}--- 策略路由规则 ---${RESET}\n"
    ip rule show | grep -E "fwmark 0x(10|20)" | sed 's/^/  /' || echo "  无"
    echo ""

    printf "${BOLD}--- 路由表 100 (中国) ---${RESET}\n"
    ip route show table 100 2>/dev/null | sed 's/^/  /' || echo "  空"
    printf "${BOLD}--- 路由表 200 (国外) ---${RESET}\n"
    ip route show table 200 2>/dev/null | sed 's/^/  /' || echo "  空"
    echo ""

    printf "${BOLD}--- 开机自启 ---${RESET}\n"
    if [ -f /etc/init.d/chnroute ]; then
        if ls /etc/rc.d/S*chnroute >/dev/null 2>&1; then
            printf "  ${GREEN}已启用${RESET}\n"
        else
            printf "  ${YELLOW}已安装但未启用${RESET}\n"
        fi
    else
        echo "  未安装"
    fi

    printf "${BOLD}--- PPPoE 重拨保护 ---${RESET}\n"
    if [ -f /etc/hotplug.d/iface/99-chnroute ]; then
        printf "  ${GREEN}已安装${RESET}\n"
    else
        printf "  ${RED}未安装${RESET}\n"
    fi
    echo ""
}

do_deploy() {
    printf "\n${CYAN}══════════════════════════════════════════${RESET}\n"
    printf "${CYAN}       一键部署 chnroute 分流${RESET}\n"
    printf "${CYAN}══════════════════════════════════════════${RESET}\n\n"

    SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || echo "$0")"

    # 1. 安装主脚本
    printf "${BOLD}[1/5]${RESET} 安装脚本到 /usr/bin/chnroute...\n"
    cp "$SCRIPT_PATH" /usr/bin/chnroute
    chmod +x /usr/bin/chnroute
    info "已安装: /usr/bin/chnroute"

    # 2. 创建 init.d 服务
    printf "${BOLD}[2/5]${RESET} 创建开机服务...\n"
    cat > /etc/init.d/chnroute << 'INITD'
#!/bin/sh /etc/rc.common

START=99
STOP=10
USE_PROCD=0

start() {
    echo "Starting chnroute..."
    sleep 2
    /usr/bin/chnroute start
}

stop() {
    echo "Stopping chnroute..."
    /usr/bin/chnroute stop
}

restart() {
    stop
    sleep 1
    start
}

status() {
    /usr/bin/chnroute status
}
INITD
    chmod +x /etc/init.d/chnroute
    /etc/init.d/chnroute enable
    info "已创建并启用开机自启"

    # 3. 创建 hotplug（PPPoE 重拨保护）
    printf "${BOLD}[3/5]${RESET} 安装 PPPoE 重拨保护...\n"
    mkdir -p /etc/hotplug.d/iface
    cat > /etc/hotplug.d/iface/99-chnroute << 'HOTPLUG'
#!/bin/sh

# PPPoE 重拨后自动刷新 chnroute 策略路由
[ "$ACTION" = "ifup" ] || exit 0
[ "$INTERFACE" = "wan" ] || exit 0

nft list chain inet fw4 chnroute_mark >/dev/null 2>&1 || exit 0

logger -t chnroute "检测到 WAN ($DEVICE) ifup，刷新策略路由..."
sleep 2
/usr/bin/chnroute refresh
HOTPLUG
    chmod +x /etc/hotplug.d/iface/99-chnroute
    info "已安装 hotplug 脚本"

    # 4. 定时更新
    printf "${BOLD}[4/5]${RESET} 配置定时更新...\n"
    grep -q "chnroute.*update" /etc/crontabs/root 2>/dev/null || {
        echo "0 3 * * 0 /usr/bin/chnroute update >> /var/log/chnroute.log 2>&1" >> /etc/crontabs/root
        /etc/init.d/cron restart
    }
    info "每周日 03:00 自动更新 IP 列表"

    # 5. 首次下载 + 启动
    printf "${BOLD}[5/5]${RESET} 首次下载 IP 列表并启动...\n\n"
    do_update
    echo ""
    do_start

    printf "\n${GREEN}══════════════════════════════════════════${RESET}\n"
    printf "${GREEN}              部署完成！${RESET}\n"
    printf "${GREEN}══════════════════════════════════════════${RESET}\n\n"
    printf "  ${BOLD}用法:${RESET}  chnroute              交互式菜单\n"
    printf "         chnroute start          启动分流\n"
    printf "         chnroute stop           停止分流\n"
    printf "         chnroute restart        重启分流\n"
    printf "         chnroute refresh        刷新路由 (PPPoE 重拨后)\n"
    printf "         chnroute update         更新 IP 列表\n"
    printf "         chnroute status         查看状态\n"
    printf "         chnroute uninstall      完全卸载\n\n"
    printf "  ${BOLD}配置:${RESET}  Surge Gateway: ${CYAN}$GW_SURGE${RESET}\n"
    printf "         中国 IP → 主路由直连\n"
    printf "         其他 IP → Surge 代理\n"
    printf "         DoH 白名单 → 强制直连\n\n"
}

do_uninstall() {
    printf "\n${RED}═══ 卸载 chnroute ═══${RESET}\n\n"

    printf "确认卸载? (y/N): "
    read -r ans
    case "$ans" in
        y|Y) ;;
        *) echo "取消"; return ;;
    esac

    echo ""
    do_stop 2>/dev/null

    /etc/init.d/chnroute disable 2>/dev/null
    rm -f /etc/init.d/chnroute
    rm -f /etc/hotplug.d/iface/99-chnroute
    rm -f "$CHNROUTE_FILE"

    sed -i '/chnroute/d' /etc/crontabs/root 2>/dev/null
    /etc/init.d/cron restart 2>/dev/null

    echo ""
    info "卸载完成"
    warn "主脚本 /usr/bin/chnroute 保留，可重新部署"
    warn "如需彻底删除: rm -f /usr/bin/chnroute"
}

# ─── 菜单界面 ───
show_menu() {
    clear 2>/dev/null || true
    printf "${CYAN}╔══════════════════════════════════════════╗${RESET}\n"
    printf "${CYAN}║${RESET}     ${BOLD}OpenWrt chnroute 分流管理${RESET}             ${CYAN}║${RESET}\n"
    printf "${CYAN}║${RESET}     Surge Gateway: ${GREEN}%-22s${RESET}${CYAN}║${RESET}\n" "$GW_SURGE"
    printf "${CYAN}╠══════════════════════════════════════════╣${RESET}\n"

    # 动态状态指示
    if is_running; then
        printf "${CYAN}║${RESET}  状态: ${GREEN}● 运行中${RESET}                           ${CYAN}║${RESET}\n"
    else
        printf "${CYAN}║${RESET}  状态: ${RED}○ 未运行${RESET}                           ${CYAN}║${RESET}\n"
    fi

    printf "${CYAN}╠══════════════════════════════════════════╣${RESET}\n"
    printf "${CYAN}║${RESET}                                          ${CYAN}║${RESET}\n"
    printf "${CYAN}║${RESET}   ${BOLD}1)${RESET}  一键部署       ${BOLD}5)${RESET}  更新 IP 列表     ${CYAN}║${RESET}\n"
    printf "${CYAN}║${RESET}   ${BOLD}2)${RESET}  启动分流       ${BOLD}6)${RESET}  查看状态         ${CYAN}║${RESET}\n"
    printf "${CYAN}║${RESET}   ${BOLD}3)${RESET}  停止分流       ${BOLD}7)${RESET}  卸载             ${CYAN}║${RESET}\n"
    printf "${CYAN}║${RESET}   ${BOLD}4)${RESET}  刷新路由       ${BOLD}0)${RESET}  退出             ${CYAN}║${RESET}\n"
    printf "${CYAN}║${RESET}                                          ${CYAN}║${RESET}\n"
    printf "${CYAN}╚══════════════════════════════════════════╝${RESET}\n"
    printf "\n请选择 [0-7]: "
}

menu_loop() {
    while true; do
        show_menu
        read -r choice
        case "$choice" in
            1) do_deploy ;;
            2) do_start ;;
            3) do_stop ;;
            4) do_refresh ;;
            5) do_update ;;
            6) do_status ;;
            7) do_uninstall ;;
            0) printf "\n再见！\n"; exit 0 ;;
            *) warn "无效选择" ;;
        esac
        printf "\n按 Enter 返回菜单..."
        read -r _
    done
}

# ─── 命令行入口 ───
case "${1:-menu}" in
    start)     do_start ;;
    stop)      do_stop ;;
    restart)   do_stop; sleep 1; do_start ;;
    refresh)   do_refresh ;;
    update)    do_update ;;
    status)    do_status ;;
    deploy)    do_deploy ;;
    uninstall) do_uninstall ;;
    menu)      menu_loop ;;
    *)
        echo "用法: $0 {start|stop|restart|refresh|update|status|deploy|uninstall|menu}"
        exit 1
        ;;
esac
