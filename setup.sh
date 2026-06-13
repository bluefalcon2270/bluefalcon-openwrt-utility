#!/bin/sh

set -e

# --- Configuration ---
VERSION="1.4"
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
    local delay=1
    local spinstr='|/-\'
    printf "\033[?25l"
    while [ "$(ps | awk '{print $1}' | grep "^$pid$")" ]; do
        local temp=${spinstr#?}
        printf " [%c] " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b"
    done
    printf "     \b\b\b\b\b"
    printf "\033[?25h"
}

check_internet() {
    if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log_err "No internet connection detected."
        return 1
    fi
}

cleanup() {
    printf "\033[?25h"
    rm -f "$WORKDIR/passwall2.zip" "$WORKDIR/luci-app-passwall2.apk" "$WORKDIR/luci-app-passwall2.ipk"
    rm -rf "$WORKDIR/pkg"
}
trap cleanup EXIT

# --- System Initialization ---
detect_system() {
    mkdir -p "$WORKDIR"
    [ ! -f "$LOG_FILE" ] && echo "=== BlueFalcon OpenWrt Utility System Log ===" > "$LOG_FILE"

    if command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
        EXT="apk"
        DEPS_CORE="unzip dnsmasq-full ipset iptables-nft kmod-nft-tproxy kmod-nft-socket"
        DEPS_STATUS="dnsmasq-full unzip ipset iptables-nft kmod-nft-tproxy kmod-nft-socket"
        OPENVPN_PKGS="openvpn-openssl luci-app-openvpn"
    elif command -v opkg >/dev/null 2>&1; then
        PKG_MANAGER="opkg"
        EXT="ipk"
        DEPS_CORE="unzip dnsmasq-full ipset iptables kmod-nft-tproxy kmod-nft-socket"
        DEPS_STATUS="dnsmasq-full unzip ipset iptables kmod-nft-tproxy kmod-nft-socket"
        OPENVPN_PKGS="openvpn-openssl luci-app-openvpn"
    else
        log_err "No supported package manager found."
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

check_dnsmasq_full() {
    local check_cmd=""
    [ "$PKG_MANAGER" = "apk" ] && check_cmd="apk info 2>/dev/null | grep -q" || check_cmd="opkg list-installed 2>/dev/null | grep -q"
    
    if ! eval "$check_cmd '^dnsmasq-full\b'"; then
        log_warn "Please run Option 1 (Install Core Requirements) first."
        return 1
    fi
    return 0
}

# --- Core Modules ---
install_dependencies() {
    clear
    echo -e "Install Core Requirements:"
    echo -e "--------------------------"
    check_internet || return 1
    
    printf "${GREEN}[INFO]${NC} Updating system package repositories..."
    if [ "$PKG_MANAGER" = "apk" ]; then
        apk update >> "$LOG_FILE" 2>&1 & spinner $!
        echo -e "\n${GREEN}[INFO]${NC} Removing standard dnsmasq..."
        apk del dnsmasq >> "$LOG_FILE" 2>&1 & spinner $!
        echo -e "\n${GREEN}[INFO]${NC} Installing core packages..."
        apk add $DEPS_CORE >> "$LOG_FILE" 2>&1 & spinner $!
    else
        opkg update >> "$LOG_FILE" 2>&1 & spinner $!
        echo -e "\n${GREEN}[INFO]${NC} Removing standard dnsmasq..."
        opkg remove dnsmasq >> "$LOG_FILE" 2>&1 & spinner $!
        echo -e "\n${GREEN}[INFO]${NC} Installing core packages..."
        opkg install $DEPS_CORE >> "$LOG_FILE" 2>&1 & spinner $!
    fi
    echo -e "\n\n${GREEN}[INFO] Core requirements successfully installed!${NC}"
    read -p "Press [Enter] to return..." dummy
}

install_passwall2() {
    check_dnsmasq_full || { read -p "Press [Enter] to return..." dummy; return 1; }
    clear
    
    echo -e "Install PassWall 2:"
    echo -e "- Configure Download Links"
    echo -e "--------------------------"
    echo -e "${YELLOW}[SYSTEM AUTO-DETECT]${NC}"
    echo -e "Package Manager : ${GREEN}${PKG_MANAGER}${NC}"
    echo -e "Architecture    : ${GREEN}${SYS_ARCH}${NC}"
    echo ""
    echo -e "Based on your system, please find these exact files on the GitHub Releases page:\n"
    
    echo -e "1. GUI App Link (Look for: ${YELLOW}luci-app-passwall2*.${EXT}${NC})"
    read -p "[Current: ${APK_URL:-None} / 0 to Return]: " INPUT_APK
    [ "$INPUT_APK" = "0" ] && return 0
    
    echo -e "2. Core Packages Link (Look for: ${YELLOW}passwall_packages_${EXT}_${SYS_ARCH}.zip${NC})"
    read -p "[Current: ${ZIP_URL:-None} / 0 to Return]: " INPUT_ZIP
    [ "$INPUT_ZIP" = "0" ] && return 0
    
    [ -n "$INPUT_APK" ] && APK_URL="$INPUT_APK"
    [ -n "$INPUT_ZIP" ] && ZIP_URL="$INPUT_ZIP"
    
    if [ -n "$APK_URL" ] && ! echo "$APK_URL" | grep -q "^http"; then
        log_warn "GUI URL does not start with http/https. It may be invalid."
    fi

    save_env

    if [ -z "$ZIP_URL" ] || [ -z "$APK_URL" ]; then
        log_err "Download URLs are missing. Cannot proceed."
        read -p "Press [Enter] to return..." dummy
        return 1
    fi

    check_internet || return 1
    
    echo -e "\n- Deploying Packages"
    echo -e "--------------------------"
    
    printf "${GREEN}[INFO]${NC} Downloading PassWall packages (ZIP file)..."
    wget -O "$WORKDIR/passwall2.zip" "$ZIP_URL" >> "$LOG_FILE" 2>&1 & spinner $!
    if [ ! -s "$WORKDIR/passwall2.zip" ]; then
        echo -e "\n${RED}[ERROR] Failed to download ZIP file. Check setup.log${NC}"
        read -p "Press [Enter] to return..." dummy
        return 1
    fi
    
    rm -rf "$WORKDIR/pkg" && mkdir -p "$WORKDIR/pkg"
    echo -e "\n${GREEN}[INFO]${NC} Extracting payload files..."
    unzip -o "$WORKDIR/passwall2.zip" -d "$WORKDIR/pkg" >> "$LOG_FILE" 2>&1 & spinner $!
    
    cd "$WORKDIR/pkg"
    local APK_FILES=$(find . -name "*.apk" -o -name "*.ipk")
    if [ -z "$APK_FILES" ]; then
        echo -e "\n${RED}[ERROR] No valid package files found inside the archive!${NC}"
        cd "$WORKDIR"
        read -p "Press [Enter] to return..." dummy
        return 1
    fi

    echo -e "\n${GREEN}[INFO]${NC} Installing local dependencies..."
    if [ "$PKG_MANAGER" = "apk" ]; then
        apk add --allow-untrusted $APK_FILES >> "$LOG_FILE" 2>&1 & spinner $!
    else
        opkg install $APK_FILES >> "$LOG_FILE" 2>&1 & spinner $!
    fi
    cd "$WORKDIR"

    echo -e "\n${GREEN}[INFO]${NC} Downloading luci-app-passwall2..."
    wget -O "$WORKDIR/luci-app-passwall2.${EXT}" "$APK_URL" >> "$LOG_FILE" 2>&1 & spinner $!
    if [ ! -s "$WORKDIR/luci-app-passwall2.${EXT}" ]; then
        echo -e "\n${RED}[ERROR] Failed to download GUI package. Check setup.log${NC}"
        read -p "Press [Enter] to return..." dummy
        return 1
    fi

    echo -e "\n${GREEN}[INFO]${NC} Installing luci-app-passwall2..."
    if [ "$PKG_MANAGER" = "apk" ]; then
        apk add --allow-untrusted "$WORKDIR/luci-app-passwall2.apk" >> "$LOG_FILE" 2>&1 & spinner $!
    else
        opkg install "$WORKDIR/luci-app-passwall2.ipk" >> "$LOG_FILE" 2>&1 & spinner $!
    fi

    echo -e "\n\n${GREEN}========================================${NC}"
    echo -e "${GREEN}      PASSWALL 2 INSTALLATION COMPLETE  ${NC}"
    echo -e "${GREEN}========================================${NC}"
    read -p "Press [Enter] to return..." dummy
}

install_openvpn() {
    check_dnsmasq_full || { read -p "Press [Enter] to return..." dummy; return 1; }
    check_internet || return 1
    clear

    echo -e "Install OpenVPN:"
    echo -e "--------------------------"
    echo -e "${YELLOW}[ATTENTION: PREVENT CONNECTION LOSS]${NC}"
    echo -e "Network services will reload during this process. If your PC is connected to"
    echo -e "another network (like Wi-Fi) alongside this OpenWrt router, your SSH session"
    echo -e "may drop when the routing table updates."
    echo -e "${YELLOW}Recommendation: Disconnect from all other networks now.${NC}"
    read -p "Press [Enter] when ready to continue (or 0 to Return)... " CONFIRM
    [ "$CONFIRM" = "0" ] && return 0

    printf "\n${GREEN}[INFO]${NC} Installing OpenVPN components..."
    if [ "$PKG_MANAGER" = "apk" ]; then
        apk add $OPENVPN_PKGS >> "$LOG_FILE" 2>&1 & spinner $!
    else
        opkg install $OPENVPN_PKGS >> "$LOG_FILE" 2>&1 & spinner $!
    fi

    echo -e "\n${GREEN}[INFO]${NC} Configuring Firewall and DNS Routing..."
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

    echo -e "${GREEN}[INFO]${NC} Reloading Core Services..."
    /etc/init.d/network reload >> "$LOG_FILE" 2>&1
    /etc/init.d/firewall reload >> "$LOG_FILE" 2>&1
    /etc/init.d/dnsmasq reload >> "$LOG_FILE" 2>&1

    echo -e "${GREEN}[INFO]${NC} Starting OpenVPN service..."
    /etc/init.d/openvpn enable >> "$LOG_FILE" 2>&1
    /etc/init.d/openvpn start >> "$LOG_FILE" 2>&1

    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}        OPENVPN INSTALLATION COMPLETE    ${NC}"
    echo -e "${GREEN}========================================${NC}"
    log_info "Proceed to LuCI > VPN > OpenVPN to import your .ovpn profile."
    read -p "Press [Enter] to return..." dummy
}

check_status() {
    clear
    echo -e "Installation Status:\n--------------------------"
    local check_cmd=""
    [ "$PKG_MANAGER" = "apk" ] && check_cmd="apk info 2>/dev/null | grep -q" || check_cmd="opkg list-installed 2>/dev/null | grep -q"
    
    echo -e "--- Core Dependencies ---"
    for pkg in $DEPS_STATUS; do
        if eval "$check_cmd '^$pkg\b'"; then
            echo -e "$pkg: [${GREEN}Installed${NC}]"
        else
            echo -e "$pkg: [${RED}Missing${NC}]"
        fi
    done

    echo -e "\n--- OpenVPN Status ---"
    for pkg in $OPENVPN_PKGS; do
        if eval "$check_cmd '^$pkg\b'"; then
            echo -e "$pkg: [${GREEN}Installed${NC}]"
        else
            echo -e "$pkg: [${RED}Missing${NC}]"
        fi
    done

    echo -e "\n--- PassWall Status ---"
    if eval "$check_cmd '^luci-app-passwall2\b'"; then
        echo -e "luci-app-passwall2: [${GREEN}Installed${NC}]"
    else
        echo -e "luci-app-passwall2: [${RED}Missing${NC}]"
    fi
    
    echo ""
    read -p "Press [Enter] to return..." dummy
}

# --- Main Execution ---
detect_system
load_env

while true; do
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}      🦅 BLUEFALCON OPENWRT UTILITY      ${NC}"
    echo -e "${GREEN}              Version ${VERSION}               ${NC}"
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
        0) echo -e "\n${GREEN}[INFO] Exiting console. Goodbye!${NC}"; exit 0 ;;
        *) log_err "Invalid selection. Please input 0 to 4."; sleep 2 ;;
    esac
done
