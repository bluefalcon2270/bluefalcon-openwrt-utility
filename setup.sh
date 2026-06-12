#!/bin/sh

# Exit on absolute errors, but allow menu loops to handle user choices safely
set -e

# --- Configuration ---
VERSION="1.3"
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

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while ps | grep -v grep | grep -q $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

cleanup() {
    echo -e "${NC}"
    rm -f "$WORKDIR/passwall2.zip" "$WORKDIR/luci-app-passwall2.apk" "$WORKDIR/luci-app-passwall2.ipk"
    rm -rf "$WORKDIR/pkg"
    kill $(jobs -p) 2>/dev/null || true
}
trap cleanup EXIT INT TERM

check_preflight() {
    if [ "$(id -u)" -ne 0 ]; then
        log_err "Must run as root."
        exit 1
    fi
    if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log_err "No internet connection detected."
        exit 1
    fi
}

check_pkg_installed() {
    if [ "$PKG_MANAGER" = "apk" ]; then
        apk info 2>/dev/null | grep -q "^$1\b"
    else
        opkg list-installed 2>/dev/null | grep -q "^$1\b"
    fi
}

# --- System Initialization ---
detect_system() {
    mkdir -p "$WORKDIR"
    if [ ! -f "$LOG_FILE" ]; then
        echo "=== BlueFalcon OpenWrt Utility System Log ===" > "$LOG_FILE"
    fi

    # Detect Package Manager
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
        if [ -f /var/lock/opkg.lock ]; then
            log_err "opkg is locked. Please wait or remove /var/lock/opkg.lock."
            exit 1
        fi
    else
        log_err "No supported package manager found (apk or opkg)."
        exit 1
    fi

    # Detect System Architecture safely without breaking set -e
    if [ -f /etc/os-release ]; then
        SYS_ARCH=$(grep '^OPENWRT_ARCH=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr -d "'" || true)
    fi
    
    if [ -z "$SYS_ARCH" ]; then
        SYS_ARCH="UNKNOWN_ARCH"
    fi
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

# --- Core Modules ---

# [Option 1] Requirements
install_dependencies() {
    clear
    echo -e "\n--- Install Core Requirements ---"
    if check_pkg_installed "dnsmasq-full"; then
        log_warn "dnsmasq-full is already installed. Skipping to prevent conflicts."
        read -p "Press [Enter] to return..." dummy
        return 0
    fi

    echo -n " - Updating system repositories..."
    if [ "$PKG_MANAGER" = "apk" ]; then
        apk update >> "$LOG_FILE" 2>&1 & spinner $!
        echo -ne "\n - Removing standard dnsmasq..."
        apk del dnsmasq >> "$LOG_FILE" 2>&1 || true & spinner $!
        echo -ne "\n - Installing core packages..."
        apk add $DEPS_CORE >> "$LOG_FILE" 2>&1 & spinner $!
    else
        opkg update >> "$LOG_FILE" 2>&1 & spinner $!
        echo -ne "\n - Removing standard dnsmasq..."
        opkg remove dnsmasq >> "$LOG_FILE" 2>&1 || true & spinner $!
        echo -ne "\n - Installing core packages..."
        opkg install $DEPS_CORE >> "$LOG_FILE" 2>&1 || true & spinner $!
    fi
    
    echo ""
    log_info "Requirements successfully installed!"
    read -p "Press [Enter] to return..." dummy
}

# [Option 2] PassWall 2 Engine
install_passwall2() {
    clear
    if ! check_pkg_installed "dnsmasq-full"; then
        log_err "dnsmasq-full is missing. Run Option 1 first."
        read -p "Press [Enter] to return..." dummy
        return 1
    fi
    if check_pkg_installed "luci-app-passwall2"; then
        log_warn "PassWall 2 is already installed."
        read -p "Press [Enter] to return..." dummy
        return 0
    fi

    echo -e "\n--- Configure Download Links ---"
    echo -e "${YELLOW}Package Manager : ${GREEN}${PKG_MANAGER}${NC}"
    echo -e "${YELLOW}Architecture    : ${GREEN}${SYS_ARCH}${NC}\n"
    
    echo -e "1. GUI App Link (Look for: ${YELLOW}luci-app-passwall2*.${EXT}${NC})"
    read -p "[Current: ${APK_URL:-None}]: " INPUT_APK
    echo -e "2. Core Packages Link (Look for: ${YELLOW}passwall_packages_${EXT}_${SYS_ARCH}.zip${NC})"
    read -p "[Current: ${ZIP_URL:-None}]: " INPUT_ZIP
    
    [ -n "$INPUT_APK" ] && APK_URL="$INPUT_APK"
    [ -n "$INPUT_ZIP" ] && ZIP_URL="$INPUT_ZIP"
    save_env

    if [ -z "$ZIP_URL" ] || [ -z "$APK_URL" ]; then
        log_err "Missing URLs."
        read -p "Press [Enter] to return..." dummy
        return 1
    fi

    echo -e "\n--- Installing PassWall 2 ---"
    echo -n " - Downloading ZIP file..."
    wget -O "$WORKDIR/passwall2.zip" "$ZIP_URL" >> "$LOG_FILE" 2>&1 & spinner $!
    
    rm -rf "$WORKDIR/pkg" && mkdir -p "$WORKDIR/pkg"
    echo -ne "\n - Extracting payload..."
    unzip -o "$WORKDIR/passwall2.zip" -d "$WORKDIR/pkg" >> "$LOG_FILE" 2>&1 & spinner $!
    
    cd "$WORKDIR/pkg"
    local APK_FILES=$(find . -name "*.apk" -o -name "*.ipk")
    if [ -n "$APK_FILES" ]; then
        echo -ne "\n - Installing local dependencies..."
        if [ "$PKG_MANAGER" = "apk" ]; then
            apk add --allow-untrusted $APK_FILES >> "$LOG_FILE" 2>&1 & spinner $!
        else
            opkg install $APK_FILES >> "$LOG_FILE" 2>&1 || true & spinner $!
        fi
    fi
    cd "$WORKDIR"

    echo -ne "\n - Downloading GUI package..."
    wget -O "$WORKDIR/luci-app-passwall2.${EXT}" "$APK_URL" >> "$LOG_FILE" 2>&1 & spinner $!

    echo -ne "\n - Installing GUI package..."
    if [ "$PKG_MANAGER" = "apk" ]; then
        apk add --allow-untrusted "$WORKDIR/luci-app-passwall2.apk" >> "$LOG_FILE" 2>&1 & spinner $!
    else
        opkg install "$WORKDIR/luci-app-passwall2.ipk" >> "$LOG_FILE" 2>&1 || true & spinner $!
    fi

    echo -e "\n\n${GREEN}PASSWALL 2 INSTALLATION COMPLETE${NC}"
    read -p "Press [Enter] to return..." dummy
}

# [Option 3] OpenVPN Installer & Configurator
install_openvpn() {
    clear
    if ! check_pkg_installed "dnsmasq-full"; then
        log_err "dnsmasq-full is missing. Run Option 1 first."
        read -p "Press [Enter] to return..." dummy
        return 1
    fi
    if check_pkg_installed "luci-app-openvpn"; then
        log_warn "OpenVPN is already installed."
        read -p "Press [Enter] to return..." dummy
        return 0
    fi

    echo -e "\n--- Installing OpenVPN ---"
    echo -e "${YELLOW}Warning: Network services will reload. Disconnect other networks to avoid SSH drop.${NC}"
    read -p "Press [Enter] when ready..." dummy

    echo -n "\n - Installing OpenVPN components..."
    if [ "$PKG_MANAGER" = "apk" ]; then
        apk add $OPENVPN_PKGS >> "$LOG_FILE" 2>&1 & spinner $!
    else
        opkg install $OPENVPN_PKGS >> "$LOG_FILE" 2>&1 & spinner $!
    fi

    echo -ne "\n - Configuring Firewall & DNS..."
    (
        uci -q rename firewall.@zone[0]="lan" || true
        uci -q rename firewall.@zone[1]="wan" || true
        uci -q del_list firewall.wan.device="tun+" || true
        uci add_list firewall.wan.device="tun+"
        uci commit firewall
        uci set network.wan.peerdns='0'
        uci commit network
        uci -q delete dhcp.@dnsmasq[0].server || true
        uci add_list dhcp.@dnsmasq[0].server='1.1.1.1'
        uci add_list dhcp.@dnsmasq[0].server='8.8.8.8'
        uci commit dhcp
    ) >> "$LOG_FILE" 2>&1

    echo -ne "\n - Reloading Core Services..."
    ( /etc/init.d/network reload && /etc/init.d/firewall reload && /etc/init.d/dnsmasq reload ) >> "$LOG_FILE" 2>&1 & spinner $!

    echo -ne "\n - Starting OpenVPN service..."
    ( /etc/init.d/openvpn enable && /etc/init.d/openvpn start ) >> "$LOG_FILE" 2>&1 & spinner $!

    echo -e "\n\n${GREEN}OPENVPN INSTALLATION COMPLETE${NC}"
    read -p "Press [Enter] to return..." dummy
}

# [Option 4] Diagnostic Status
check_status() {
    clear
    echo -e "\n--- Installation Status ---"
    
    if check_pkg_installed "dnsmasq-full"; then
        echo -e "dnsmasq-full: [${GREEN}Installed${NC}]"
    elif check_pkg_installed "dnsmasq"; then
        echo -e "dnsmasq: [${RED}Incorrect (Run Option 1)${NC}]"
    else
        echo -e "dnsmasq-full: [${RED}Missing${NC}]"
    fi

    for pkg in $DEPS_STATUS $OPENVPN_PKGS "luci-app-passwall2"; do
        if check_pkg_installed "$pkg"; then
            echo -e "$pkg: [${GREEN}Installed${NC}]"
        else
            echo -e "$pkg: [${RED}Missing${NC}]"
        fi
    done
    
    echo ""
    read -p "Press [Enter] to return..." dummy
}

# --- Main Execution ---
check_preflight
detect_system
load_env

while true; do
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}       🦅 BLUEFALCON OPENWRT UTILITY    ${NC}"
    echo -e "${GREEN}                Version ${VERSION}      ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e " 1) Install Core Requirements"
    echo -e " 2) Install PassWall 2"
    echo -e " 3) Install OpenVPN"
    echo -e " 4) Installation Status"
    echo -e " 0) Exit"
    echo -e "${GREEN}========================================${NC}"
    read -p "Select an option [0-4]: " OPTION

    case "$OPTION" in
        1) install_dependencies ;;
        2) install_passwall2 ;;
        3) install_openvpn ;;
        4) check_status ;;
        0) log_info "Exiting console. Goodbye!"; exit 0 ;;
        *) 
            echo -e "${RED}[ERROR] Invalid input. Please enter a number 0-4.${NC}"
            sleep 2
            ;;
    esac
done
