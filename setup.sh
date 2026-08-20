#!/bin/sh

# Exit on absolute errors, but allow menu loops to handle user choices safely
set -e

# --- Configuration ---
VERSION="1.5"
WORKDIR="/opt/bluefalcon-openwrt-utility"
CONFIG_FILE="$WORKDIR/.env"

# --- UI Color Codes ---
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
RESET="\033[0m"

# --- Utility Functions ---
check_internet() {
    if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] No internet connection detected. Please check your router's network settings.${RESET}"
        return 1
    fi
}

cleanup() {
    rm -f "$WORKDIR/passwall2.zip" "$WORKDIR/luci-app-passwall2.apk" "$WORKDIR/luci-app-passwall2.ipk"
    rm -rf "$WORKDIR/pkg"
}
trap cleanup EXIT

# --- System Initialization ---
detect_system() {
    mkdir -p "$WORKDIR"

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
    else
        echo -e "${RED}[ERROR] No supported package manager found (apk or opkg).${RESET}"
        exit 1
    fi

    # Detect System Architecture
    if [ -f /etc/os-release ]; then
        SYS_ARCH=$(grep '^OPENWRT_ARCH=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr -d "'")
    fi
    [ -z "$SYS_ARCH" ] && SYS_ARCH="UNKNOWN_ARCH"

    echo -e "${GREEN}[INFO] Detected package manager: $PKG_MANAGER${RESET}"
    echo -e "${GREEN}[INFO] Detected architecture: $SYS_ARCH${RESET}"
    sleep 2
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
    if [ "$PKG_MANAGER" = "apk" ]; then
        check_cmd="apk info 2>/dev/null | grep -q"
    else
        check_cmd="opkg list-installed 2>/dev/null | grep -q"
    fi

    if ! eval "$check_cmd '^dnsmasq-full\b'"; then
        echo -e "${RED}[ERROR] dnsmasq-full is missing. Please run Option 1 (Install Core Requirements) first.${RESET}"
        return 1
    fi
    return 0
}

# --- Core Modules ---

# [Option 1] Requirements
install_dependencies() {
    echo -e "\n--- Installing Core Requirements ---"
    check_internet || return 1

    echo -e "\n${CYAN}[INFO] Updating system package repositories...${RESET}"
    if [ "$PKG_MANAGER" = "apk" ]; then apk update; else opkg update; fi
    
    echo -e "\n${CYAN}[INFO] Removing standard dnsmasq to prevent conflicts...${RESET}"
    if [ "$PKG_MANAGER" = "apk" ]; then apk del dnsmasq || true; else opkg remove dnsmasq || true; fi
        
    echo -e "\n${CYAN}[INFO] Installing required core packages...${RESET}"
    if [ "$PKG_MANAGER" = "apk" ]; then apk add $DEPS_CORE; else opkg install $DEPS_CORE || true; fi

    echo -e "\n${GREEN}[INFO] Requirements successfully installed!${RESET}"
    read -p "Press [Enter] to return to the menu..." dummy
}

# [Option 2] PassWall 2 Engine
install_passwall2() {
    check_dnsmasq_full || return 1

    echo -e "\n--- Configure Download Links ---"
    echo -e "${CYAN}[SYSTEM AUTO-DETECT]${RESET}"
    echo -e "Package Manager : ${GREEN}${PKG_MANAGER}${RESET}"
    echo -e "Architecture    : ${GREEN}${SYS_ARCH}${RESET}"
    echo ""
    echo -e "Based on your system, please find these exact files on the GitHub Releases page:"
    echo ""
    
    echo -e "1. GUI App Link (Look for: ${YELLOW}luci-app-passwall2*.${EXT}${RESET})"
    read -p "[Current: ${APK_URL:-None}]: " INPUT_APK
    
    echo -e "2. Core Packages Link (Look for: ${YELLOW}passwall_packages_${EXT}_${SYS_ARCH}.zip${RESET})"
    read -p "[Current: ${ZIP_URL:-None}]: " INPUT_ZIP
    
    [ -n "$INPUT_APK" ] && APK_URL="$INPUT_APK"
    [ -n "$INPUT_ZIP" ] && ZIP_URL="$INPUT_ZIP"
    
    if [ -n "$APK_URL" ] && ! echo "$APK_URL" | grep -q "^http"; then
        echo -e "${YELLOW}[WARN] GUI URL does not start with http/https. It may be invalid.${RESET}"
    fi

    save_env

    if [ -z "$ZIP_URL" ] || [ -z "$APK_URL" ]; then
        echo -e "${RED}[ERROR] Download URLs are missing. Cannot proceed.${RESET}"
        read -p "Press [Enter] to return to the menu..." dummy
        return 1
    fi

    check_internet || return 1
    echo -e "\n--- Installing PassWall 2 ---"
    
    echo -e "\n${CYAN}[INFO] Downloading PassWall packages (ZIP file)...${RESET}"
    wget -O "$WORKDIR/passwall2.zip" "$ZIP_URL" || { read -p "Press [Enter] to return..." dummy; return 1; }
    
    rm -rf "$WORKDIR/pkg" && mkdir -p "$WORKDIR/pkg"
    echo -e "\n${CYAN}[INFO] Extracting payload files...${RESET}"
    unzip -o "$WORKDIR/passwall2.zip" -d "$WORKDIR/pkg"
    
    cd "$WORKDIR/pkg"
    local APK_FILES=$(find . -name "*.apk" -o -name "*.ipk")
    if [ -z "$APK_FILES" ]; then
        echo -e "${RED}[ERROR] No valid package files found inside the archive!${RESET}"
        cd "$WORKDIR"
        read -p "Press [Enter] to return to the menu..." dummy
        return 1
    fi

    echo -e "\n${CYAN}[INFO] Installing local dependencies...${RESET}"
    if [ "$PKG_MANAGER" = "apk" ]; then apk add --allow-untrusted $APK_FILES; else opkg install $APK_FILES || true; fi
    cd "$WORKDIR"

    echo -e "\n${CYAN}[INFO] Downloading luci-app-passwall2...${RESET}"
    wget -O "$WORKDIR/luci-app-passwall2.${EXT}" "$APK_URL" || { read -p "Press [Enter] to return..." dummy; return 1; }

    echo -e "\n${CYAN}[INFO] Installing luci-app-passwall2...${RESET}"
    if [ "$PKG_MANAGER" = "apk" ]; then apk add --allow-untrusted "$WORKDIR/luci-app-passwall2.apk"; else opkg install "$WORKDIR/luci-app-passwall2.ipk" || true; fi

    echo -e "\n${GREEN}========================================${RESET}"
    echo -e "${GREEN}      PASSWALL 2 INSTALLATION COMPLETE  ${RESET}"
    echo -e "${GREEN}========================================${RESET}"
    read -p "Press [Enter] to return to the menu..." dummy
}

# [Option 3] OpenVPN Installer & Configurator
install_openvpn() {
    check_dnsmasq_full || return 1
    check_internet || return 1

    echo -e "\n--- Installing and Configuring OpenVPN ---"
    
    echo -e "${YELLOW}[ATTENTION: PREVENT CONNECTION LOSS]${RESET}"
    echo -e "Network services will reload during this process. If your PC is connected to"
    echo -e "another network (like Wi-Fi) alongside this OpenWrt router, your SSH session"
    echo -e "may drop when the routing table updates."
    echo -e "${CYAN}Recommendation: Disconnect from all other networks now.${RESET}"
    read -p "Press [Enter] when ready to continue..." dummy

    echo -e "\n${CYAN}[INFO] Installing OpenVPN components...${RESET}"
    if [ "$PKG_MANAGER" = "apk" ]; then apk add $OPENVPN_PKGS; else opkg install $OPENVPN_PKGS; fi

    echo -e "\n${CYAN}[INFO] Configuring Firewall for tun+ interfaces...${RESET}"
    uci -q del_list firewall.wan.device="tun+" || true
    uci add_list firewall.wan.device="tun+"
    uci commit firewall

    echo -e "\n${CYAN}[INFO] Configuring Secure DNS Routing...${RESET}"
    uci set network.wan.peerdns='0'
    uci commit network

    echo -e "\n${CYAN}DNS Configuration${RESET}"
    echo -e "Would you like to override the system DNS with secure defaults (1.1.1.1 and 8.8.8.8)?"
    echo -e "Choose 'n' if you are using AdGuard Home, Pi-hole, or custom DNS."
    read -p "Override system DNS? (y/N): " OVERRIDE_DNS
    if [ "$OVERRIDE_DNS" = "y" ] || [ "$OVERRIDE_DNS" = "Y" ]; then
        echo -e "${GREEN}[INFO] Overriding DNS...${RESET}"
        uci -q delete dhcp.@dnsmasq[0].server || true
        uci add_list dhcp.@dnsmasq[0].server='1.1.1.1'
        uci add_list dhcp.@dnsmasq[0].server='8.8.8.8'
        uci commit dhcp
    else
        echo -e "${GREEN}[INFO] Skipping DNS override. Using existing configuration.${RESET}"
    fi

    echo -e "\n${CYAN}[INFO] Reloading Core Services (Network, Firewall, DNS)...${RESET}"
    /etc/init.d/network reload && /etc/init.d/firewall reload && /etc/init.d/dnsmasq reload

    echo -e "\n${CYAN}[INFO] Enabling and starting OpenVPN service...${RESET}"
    /etc/init.d/openvpn enable || true
    /etc/init.d/openvpn start || true

    echo -e "\n${GREEN}========================================${RESET}"
    echo -e "${GREEN}        OPENVPN INSTALLATION COMPLETE    ${RESET}"
    echo -e "${GREEN}========================================${RESET}"
    echo -e "${GREEN}[INFO] Proceed to LuCI > VPN > OpenVPN to import your .ovpn profile.${RESET}"
    read -p "Press [Enter] to return to the menu..." dummy
}

# [Option 4] Diagnostic Status
check_status() {
    echo -e "\n--- Installation Status ---"
    local check_cmd=""
    
    if [ "$PKG_MANAGER" = "apk" ]; then
        check_cmd="apk info 2>/dev/null | grep -q"
    else
        check_cmd="opkg list-installed 2>/dev/null | grep -q"
    fi

    # Check DNS Stack Explicitly
    if eval "$check_cmd '^dnsmasq-full\b'"; then
        echo -e "dnsmasq-full: [${GREEN}Installed${RESET}]"
    elif eval "$check_cmd '^dnsmasq\b'"; then
        echo -e "dnsmasq: [${RED}Incorrect (Run Option 1)${RESET}]"
    else
        echo -e "dnsmasq-full: [${RED}Missing${RESET}]"
    fi

    # Check Core Dependencies
    for pkg in $DEPS_STATUS; do
        if eval "$check_cmd '^$pkg\b'"; then
            echo -e "$pkg: [${GREEN}Installed${RESET}]"
        else
            echo -e "$pkg: [${RED}Missing${RESET}]"
        fi
    done

    # Check OpenVPN
    echo -e "\n--- OpenVPN Status ---"
    for pkg in $OPENVPN_PKGS; do
        if eval "$check_cmd '^$pkg\b'"; then
            echo -e "$pkg: [${GREEN}Installed${RESET}]"
        else
            echo -e "$pkg: [${RED}Missing${RESET}]"
        fi
    done

    # Check PassWall GUI
    echo -e "\n--- PassWall Status ---"
    if eval "$check_cmd '^luci-app-passwall2\b'"; then
        echo -e "luci-app-passwall2: [${GREEN}Installed${RESET}]"
    else
        echo -e "luci-app-passwall2: [${RED}Missing${RESET}]"
    fi
    
    echo ""
    read -p "Press [Enter] to return to the menu..." dummy
}

# --- Main Execution ---
detect_system
load_env

while true; do
    clear
    echo -e "${CYAN}========================================${RESET}"
    echo -e "${CYAN}        🦅 BLUEFALCON OPENWRT UTILITY       ${RESET}"
    echo -e "${CYAN}                Version ${VERSION}               ${RESET}"
    echo -e "${CYAN}========================================${RESET}"
    echo -e " 1) Install Core Requirements"
    echo -e " 2) Install PassWall 2"
    echo -e " 3) Install OpenVPN"
    echo -e " 4) Installation Status"
    echo -e " 0) Exit"
    echo -e "${CYAN}========================================${RESET}"
    read -p "Select an option [0-4]: " OPTION

    case "$OPTION" in
        1) install_dependencies ;;
        2) install_passwall2 || { echo -e "${RED}[ERROR] PassWall 2 installation sequence aborted.${RESET}"; read -p "Press [Enter] to return..." dummy; } ;;
        3) install_openvpn || { echo -e "${RED}[ERROR] OpenVPN installation sequence aborted.${RESET}"; read -p "Press [Enter] to return..." dummy; } ;;
        4) check_status ;;
        0) echo -e "\n${GREEN}[INFO] Exiting console. Goodbye!${RESET}"; exit 0 ;;
        *) echo -e "${RED}[ERROR] Invalid selection. Please input 0 to 4.${RESET}"; sleep 2 ;;
    esac
done
