#!/bin/sh

# Exit on absolute errors, but allow menu loops to handle user choices safely
set -e

# --- Configuration ---
VERSION="1.1"
WORKDIR="/opt/bluefalcon-openwrt-utility"
CONFIG_FILE="$WORKDIR/.env"
LOG_FILE="$WORKDIR/setup.log"

# --- UI Color Codes ---
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
NC="\033[0m"

# --- Utility Functions ---
log_info() { 
    echo -e "${GREEN}[INFO] $1${NC}"
    [ -d "$WORKDIR" ] && echo "[INFO] $(date) - $1" >> "$LOG_FILE"
}
log_warn() { 
    echo -e "${YELLOW}[WARN] $1${NC}"
    [ -d "$WORKDIR" ] && echo "[WARN] $(date) - $1" >> "$LOG_FILE"
}
log_err() { 
    echo -e "${RED}[ERROR] $1${NC}"
    [ -d "$WORKDIR" ] && echo "[ERROR] $(date) - $1" >> "$LOG_FILE"
}

check_internet() {
    if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log_err "No internet connection detected."
        return 1
    fi
}

# --- Background Task Spinner ---
run_with_spinner() {
    local msg="$1"
    shift
    echo -n -e "${YELLOW}- ${msg}...${NC} "
    "$@" >> "$LOG_FILE" 2>&1 &
    local pid=$!
    local delay=0.15
    local spinstr='|/-\'
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf "[%c]" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b"
    done
    wait $pid
    local status=$?
    if [ $status -eq 0 ]; then
        echo -e "${GREEN}Done${NC}"
    else
        echo -e "${RED}Failed${NC}"
    fi
    return $status
}

# --- Submenu 0 Rule Return ---
prompt_return() {
    while true; do
        echo ""
        read -p "Enter 0 to Return: " sub_opt
        if [ "$sub_opt" = "0" ]; then break; fi
    done
}

# --- Graceful Exit Trap ---
cleanup_and_exit() {
    echo -e "${NC}\n${YELLOW}[WARN] Process interrupted. Cleaning up...${NC}"
    kill $(jobs -p) 2>/dev/null || true
    rm -f "$WORKDIR/passwall2.zip" "$WORKDIR/luci-app-passwall2.apk" "$WORKDIR/luci-app-passwall2.ipk"
    rm -rf "$WORKDIR/pkg"
    echo -e "${NC}"
    exit 1
}
trap cleanup_and_exit INT TERM

cleanup_temp() {
    rm -f "$WORKDIR/passwall2.zip" "$WORKDIR/luci-app-passwall2.apk" "$WORKDIR/luci-app-passwall2.ipk"
    rm -rf "$WORKDIR/pkg"
}
trap cleanup_temp EXIT

# --- Pre-Flight Checks ---
pre_flight_checks() {
    if [ "$(id -u)" -ne 0 ]; then
        log_err "This script requires root privileges."
        exit 1
    fi
    check_internet || exit 1
    if [ -f "/var/lock/opkg.lock" ] || [ -f "/lib/apk/db/lock" ]; then
        log_err "Package manager is currently locked by another process."
        exit 1
    fi
}

# --- System Initialization ---
detect_system() {
    mkdir -p "$WORKDIR"
    if [ ! -f "$LOG_FILE" ]; then
        echo "=== BlueFalcon OpenWrt Utility System Log ===" > "$LOG_FILE"
    fi

    if command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
        EXT="apk"
        DEPS_CORE="unzip dnsmasq-full ipset iptables-nft kmod-nft-tproxy kmod-nft-socket"
        DEPS_STATUS="unzip ipset iptables-nft kmod-nft-tproxy kmod-nft-socket"
        OPENVPN_PKGS="openvpn-openssl luci-app-openvpn"
    elif command -v opkg >/dev/null 2>&1; then
        PKG_MANAGER="opkg"
        EXT="ipk"
        DEPS_CORE="unzip dnsmasq-full ipset iptables kmod-nft-tproxy kmod-nft-socket"
        DEPS_STATUS="unzip ipset iptables kmod-nft-tproxy kmod-nft-socket"
        OPENVPN_PKGS="openvpn-openssl luci-app-openvpn"
    else
        log_err "No supported package manager found (apk or opkg)."
        exit 1
    fi

    if [ -f /etc/os-release ]; then
        SYS_ARCH=$(grep '^OPENWRT_ARCH=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr -d "'")
    fi
    [ -z "$SYS_ARCH" ] && SYS_ARCH="UNKNOWN_ARCH"
}

load_env() {
    if [ -f "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE"
    fi
}

save_env() {
    cat << EOF > "$CONFIG_FILE"
ZIP_URL="$ZIP_URL"
APK_URL="$APK_URL"
EOF
}

is_installed() {
    if [ "$PKG_MANAGER" = "apk" ]; then
        apk info -e "$1" >/dev/null 2>&1
    else
        opkg list-installed 2>/dev/null | grep -q "^$1\b"
    fi
}

check_dnsmasq_full() {
    if ! is_installed "dnsmasq-full"; then
        log_err "dnsmasq-full is missing. Please run Option 1 first."
        return 1
    fi
    return 0
}

# --- Core Modules ---

# [Option 1] Requirements
install_dependencies() {
    echo -e "\n--- Install Core Requirements ---"
    check_internet || return 1

    run_with_spinner "Updating system package repositories" $PKG_MANAGER update

    if is_installed "dnsmasq"; then
        if [ "$PKG_MANAGER" = "apk" ]; then
            run_with_spinner "Removing standard dnsmasq" apk del dnsmasq
        else
            run_with_spinner "Removing standard dnsmasq" opkg remove dnsmasq
        fi
    fi

    for pkg in $DEPS_CORE; do
        if ! is_installed "$pkg"; then
            if [ "$PKG_MANAGER" = "apk" ]; then
                run_with_spinner "Installing $pkg" apk add "$pkg"
            else
                run_with_spinner "Installing $pkg" opkg install "$pkg"
            fi
        else
            echo -e "${GREEN}- $pkg is already installed${NC}"
        fi
    done

    log_info "Requirements successfully verified and installed!"
    prompt_return
}

# [Option 2] PassWall 2 Engine
install_passwall2() {
    check_dnsmasq_full || return 1

    echo -e "\n--- Configure Download Links ---"
    echo -e "${YELLOW}[SYSTEM AUTO-DETECT]${NC}"
    echo -e "Package Manager : ${GREEN}${PKG_MANAGER}${NC}"
    echo -e "Architecture    : ${GREEN}${SYS_ARCH}${NC}"
    echo ""
    
    echo -e "1. GUI App Link (Look for: ${YELLOW}luci-app-passwall2*.${EXT}${NC})"
    read -p "[Current: ${APK_URL:-None}]: " INPUT_APK
    
    echo -e "2. Core Packages Link (Look for: ${YELLOW}passwall_packages_${EXT}_${SYS_ARCH}.zip${NC})"
    read -p "[Current: ${ZIP_URL:-None}]: " INPUT_ZIP
    
    [ -n "$INPUT_APK" ] && APK_URL="$INPUT_APK"
    [ -n "$INPUT_ZIP" ] && ZIP_URL="$INPUT_ZIP"
    
    if [ -n "$APK_URL" ] && ! echo "$APK_URL" | grep -q "^http"; then
        log_warn "GUI URL does not start with http/https."
    fi

    save_env

    if [ -z "$ZIP_URL" ] || [ -z "$APK_URL" ]; then
        log_err "Download URLs are missing."
        prompt_return
        return 1
    fi

    check_internet || return 1
    echo -e "\n--- Install PassWall 2 ---"
    
    run_with_spinner "Downloading PassWall packages (ZIP)" wget -O "$WORKDIR/passwall2.zip" "$ZIP_URL" || return 1
    
    rm -rf "$WORKDIR/pkg" && mkdir -p "$WORKDIR/pkg"
    run_with_spinner "Extracting payload files" unzip -o "$WORKDIR/passwall2.zip" -d "$WORKDIR/pkg"
    
    cd "$WORKDIR/pkg"
    local APK_FILES=$(find . -name "*.apk" -o -name "*.ipk")
    if [ -z "$APK_FILES" ]; then
        log_err "No valid package files found inside the archive!"
        cd "$WORKDIR"
        prompt_return
        return 1
    fi

    if [ "$PKG_MANAGER" = "apk" ]; then
        run_with_spinner "Installing local dependencies" apk add --allow-untrusted $APK_FILES
    else
        run_with_spinner "Installing local dependencies" opkg install $APK_FILES
    fi
    cd "$WORKDIR"

    run_with_spinner "Downloading luci-app-passwall2" wget -O "$WORKDIR/luci-app-passwall2.${EXT}" "$APK_URL" || return 1

    if [ "$PKG_MANAGER" = "apk" ]; then
        run_with_spinner "Installing luci-app-passwall2" apk add --allow-untrusted "$WORKDIR/luci-app-passwall2.apk"
    else
        run_with_spinner "Installing luci-app-passwall2" opkg install "$WORKDIR/luci-app-passwall2.ipk"
    fi

    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}      PASSWALL 2 INSTALLATION COMPLETE  ${NC}"
    echo -e "${GREEN}========================================${NC}"
    prompt_return
}

# [Option 3] OpenVPN Installer & Configurator
install_openvpn() {
    check_dnsmasq_full || return 1
    check_internet || return 1

    echo -e "\n--- Install and Configure OpenVPN ---"
    echo -e "${YELLOW}[ATTENTION: PREVENT CONNECTION LOSS]${NC}"
    echo -e "Network services will reload during this process. Disconnect from"
    echo -e "all other networks now to prevent SSH session drops."
    echo ""
    read -p "Press [Enter] when ready..." dummy

    for pkg in $OPENVPN_PKGS; do
        if ! is_installed "$pkg"; then
            if [ "$PKG_MANAGER" = "apk" ]; then
                run_with_spinner "Installing $pkg" apk add "$pkg"
            else
                run_with_spinner "Installing $pkg" opkg install "$pkg"
            fi
        else
            echo -e "${GREEN}- $pkg is already installed${NC}"
        fi
    done

    # Idempotent Firewall Config
    if ! uci -q get firewall.wan.device | grep -q "tun+"; then
        run_with_spinner "Configuring Firewall for tun+ interfaces" uci add_list firewall.wan.device="tun+"
        uci commit firewall >> "$LOG_FILE" 2>&1
    else
        echo -e "${GREEN}- Firewall rules already configured${NC}"
    fi

    run_with_spinner "Configuring Secure DNS Routing" uci set network.wan.peerdns='0'
    uci commit network >> "$LOG_FILE" 2>&1

    uci -q delete dhcp.@dnsmasq[0].server || true
    uci add_list dhcp.@dnsmasq[0].server='1.1.1.1'
    uci add_list dhcp.@dnsmasq[0].server='8.8.8.8'
    uci commit dhcp >> "$LOG_FILE" 2>&1

    run_with_spinner "Reloading Network Services" /etc/init.d/network reload
    run_with_spinner "Reloading Firewall" /etc/init.d/firewall reload
    run_with_spinner "Reloading DNS" /etc/init.d/dnsmasq reload

    run_with_spinner "Starting OpenVPN service" /etc/init.d/openvpn enable
    /etc/init.d/openvpn start >> "$LOG_FILE" 2>&1

    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}        OPENVPN INSTALLATION COMPLETE    ${NC}"
    echo -e "${GREEN}========================================${NC}"
    log_info "Proceed to LuCI > VPN > OpenVPN to import your .ovpn profile."
    prompt_return
}

# [Option 4] Diagnostic Status
check_status() {
    echo -e "\n--- Installation Status ---"
    
    if is_installed "dnsmasq-full"; then
        echo -e "- dnsmasq-full: [${GREEN}Installed${NC}]"
    elif is_installed "dnsmasq"; then
        echo -e "- dnsmasq: [${RED}Incorrect (Run Option 1)${NC}]"
    else
        echo -e "- dnsmasq-full: [${RED}Missing${NC}]"
    fi

    for pkg in $DEPS_STATUS; do
        if is_installed "$pkg"; then
            echo -e "- $pkg: [${GREEN}Installed${NC}]"
        else
            echo -e "- $pkg: [${RED}Missing${NC}]"
        fi
    done

    echo -e "\n--- OpenVPN Status ---"
    for pkg in $OPENVPN_PKGS; do
        if is_installed "$pkg"; then
            echo -e "- $pkg: [${GREEN}Installed${NC}]"
        else
            echo -e "- $pkg: [${RED}Missing${NC}]"
        fi
    done

    echo -e "\n--- PassWall Status ---"
    if is_installed "luci-app-passwall2"; then
        echo -e "- luci-app-passwall2: [${GREEN}Installed${NC}]"
    else
        echo -e "- luci-app-passwall2: [${RED}Missing${NC}]"
    fi
    
    prompt_return
}

# --- Main Execution ---
pre_flight_checks
detect_system
load_env

while true; do
    clear
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}       🦅 BLUEFALCON OPENWRT UTILITY      ${NC}"
    echo -e "${YELLOW}                Version ${VERSION}              ${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo -e " 1) Install Core Requirements"
    echo -e " 2) Install PassWall 2"
    echo -e " 3) Install OpenVPN"
    echo -e " 4) Installation Status"
    echo -e " 0) Exit"
    echo -e "${YELLOW}========================================${NC}"
    read -p "Select an option [0-4]: " OPTION

    if ! echo "$OPTION" | grep -Eq '^[0-4]$'; then
        log_err "Invalid input. Please enter a number between 0 and 4."
        sleep 2
        continue
    fi

    case "$OPTION" in
        1) install_dependencies ;;
        2) install_passwall2 ;;
        3) install_openvpn ;;
        4) check_status ;;
        0) echo -e "\n${GREEN}[INFO] Exiting console. Goodbye!${NC}"; exit 0 ;;
    esac
done
