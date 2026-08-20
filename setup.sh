#!/bin/sh

# Exit on absolute errors, but allow menu loops to handle user choices safely
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
CYAN="\033[0;36m"
RESET="\033[0m"

# --- Utility Functions ---
log_info() { 
    echo -e "${GREEN}[INFO] $1${RESET}"
    [ -d "$WORKDIR" ] && echo "[INFO] $(date) - $1" >> "$LOG_FILE"
}
log_warn() { 
    echo -e "${YELLOW}[WARN] $1${RESET}"
    [ -d "$WORKDIR" ] && echo "[WARN] $(date) - $1" >> "$LOG_FILE"
}
log_err() { 
    echo -e "${RED}[ERROR] $1${RESET}"
    [ -d "$WORKDIR" ] && echo "[ERROR] $(date) - $1" >> "$LOG_FILE"
}

execute_step() {
    local msg="$1"
    local cmd="$2"
    echo -e "\n${CYAN}[INFO] ${msg}...${RESET}"
    echo "[INFO] $(date) - $msg" >> "$LOG_FILE"
    
    # Run command, save exit code to a temp file, and pipe all output to tee
    # This shows logs on the screen exactly like a normal installation while still saving to setup.log
    {
        eval "$cmd" 2>&1
        echo $? > "$WORKDIR/.step_exit"
    } | tee -a "$LOG_FILE"
    
    local exit_code=0
    if [ -f "$WORKDIR/.step_exit" ]; then
        exit_code=$(cat "$WORKDIR/.step_exit")
        rm -f "$WORKDIR/.step_exit"
    fi
    
    if [ $exit_code -eq 0 ]; then
        log_info "$msg... Done."
    else
        log_err "$msg... Failed! (Check setup.log for full details)"
    fi
    return $exit_code
}

check_internet() {
    if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log_err "No internet connection detected. Please check your router's network settings."
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
    else
        log_err "No supported package manager found (apk or opkg)."
        exit 1
    fi

    # Detect System Architecture
    if [ -f /etc/os-release ]; then
        SYS_ARCH=$(grep '^OPENWRT_ARCH=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr -d "'")
    fi
    [ -z "$SYS_ARCH" ] && SYS_ARCH="UNKNOWN_ARCH"

    log_info "Detected package manager: $PKG_MANAGER"
    log_info "Detected architecture: $SYS_ARCH"
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
        log_err "dnsmasq-full is missing. Please run Option 1 (Install Core Requirements) first."
        return 1
    fi
    return 0
}

view_logs() {
    echo -e "\n--- System Logs ($LOG_FILE) ---"
    if [ -f "$LOG_FILE" ]; then
        cat "$LOG_FILE"
    else
        echo -e "${YELLOW}No logs found yet.${RESET}"
    fi
    echo -e "-----------------------------------\n"
    read -p "Press [Enter] to return to the menu..." dummy
}

# --- Core Modules ---

# [Option 1] Requirements
install_dependencies() {
    echo -e "\n--- Installing Core Requirements ---"
    check_internet || return 1

    execute_step "Updating system package repositories" \
        'if [ "$PKG_MANAGER" = "apk" ]; then apk update; else opkg update; fi'
    
    execute_step "Removing standard dnsmasq to prevent conflicts" \
        'if [ "$PKG_MANAGER" = "apk" ]; then apk del dnsmasq || true; else opkg remove dnsmasq || true; fi'
        
    execute_step "Installing required core packages" \
        'if [ "$PKG_MANAGER" = "apk" ]; then apk add $DEPS_CORE; else opkg install $DEPS_CORE || true; fi'

    log_info "Requirements successfully installed!"
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
        log_warn "GUI URL does not start with http/https. It may be invalid."
    fi

    save_env

    if [ -z "$ZIP_URL" ] || [ -z "$APK_URL" ]; then
        log_err "Download URLs are missing. Cannot proceed."
        read -p "Press [Enter] to return to the menu..." dummy
        return 1
    fi

    check_internet || return 1
    echo -e "\n--- Installing PassWall 2 ---"
    
    execute_step "Downloading PassWall packages (ZIP file)" "wget -O \"$WORKDIR/passwall2.zip\" \"$ZIP_URL\"" || { read -p "Press [Enter] to return..." dummy; return 1; }
    
    rm -rf "$WORKDIR/pkg" && mkdir -p "$WORKDIR/pkg"
    execute_step "Extracting payload files" "unzip -o \"$WORKDIR/passwall2.zip\" -d \"$WORKDIR/pkg\""
    
    cd "$WORKDIR/pkg"
    local APK_FILES=$(find . -name "*.apk" -o -name "*.ipk")
    if [ -z "$APK_FILES" ]; then
        log_err "No valid package files found inside the archive!"
        cd "$WORKDIR"
        read -p "Press [Enter] to return to the menu..." dummy
        return 1
    fi

    execute_step "Installing local dependencies" \
        'if [ "$PKG_MANAGER" = "apk" ]; then apk add --allow-untrusted $APK_FILES; else opkg install $APK_FILES || true; fi'
    cd "$WORKDIR"

    execute_step "Downloading luci-app-passwall2" "wget -O \"$WORKDIR/luci-app-passwall2.${EXT}\" \"$APK_URL\"" || { read -p "Press [Enter] to return..." dummy; return 1; }

    execute_step "Installing luci-app-passwall2" \
        'if [ "$PKG_MANAGER" = "apk" ]; then apk add --allow-untrusted "$WORKDIR/luci-app-passwall2.apk"; else opkg install "$WORKDIR/luci-app-passwall2.ipk" || true; fi'

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

    execute_step "Installing OpenVPN components" \
        'if [ "$PKG_MANAGER" = "apk" ]; then apk add $OPENVPN_PKGS; else opkg install $OPENVPN_PKGS; fi'

    log_info "Configuring Firewall for tun+ interfaces..."
    uci -q del_list firewall.wan.device="tun+" || true
    uci add_list firewall.wan.device="tun+"
    uci commit firewall

    log_info "Configuring Secure DNS Routing..."
    uci set network.wan.peerdns='0'
    uci commit network

    echo -e "\n${CYAN}DNS Configuration${RESET}"
    echo -e "Would you like to override the system DNS with secure defaults (1.1.1.1 and 8.8.8.8)?"
    echo -e "Choose 'n' if you are using AdGuard Home, Pi-hole, or custom DNS."
    read -p "Override system DNS? (y/N): " OVERRIDE_DNS
    if [ "$OVERRIDE_DNS" = "y" ] || [ "$OVERRIDE_DNS" = "Y" ]; then
        log_info "Overriding DNS..."
        uci -q delete dhcp.@dnsmasq[0].server || true
        uci add_list dhcp.@dnsmasq[0].server='1.1.1.1'
        uci add_list dhcp.@dnsmasq[0].server='8.8.8.8'
        uci commit dhcp
    else
        log_info "Skipping DNS override. Using existing configuration."
    fi

    execute_step "Reloading Core Services (Network, Firewall, DNS)" \
        '/etc/init.d/network reload && /etc/init.d/firewall reload && /etc/init.d/dnsmasq reload'

    log_info "Enabling and starting OpenVPN service..."
    /etc/init.d/openvpn enable >> "$LOG_FILE" 2>&1
    /etc/init.d/openvpn start >> "$LOG_FILE" 2>&1

    echo -e "\n${GREEN}========================================${RESET}"
    echo -e "${GREEN}        OPENVPN INSTALLATION COMPLETE    ${RESET}"
    echo -e "${GREEN}========================================${RESET}"
    log_info "Proceed to LuCI > VPN > OpenVPN to import your .ovpn profile."
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
    echo -e " 5) View Logs"
    echo -e " 0) Exit"
    echo -e "${CYAN}========================================${RESET}"
    read -p "Select an option [0-5]: " OPTION

    case "$OPTION" in
        1) install_dependencies ;;
        2) install_passwall2 || { log_err "PassWall 2 installation sequence aborted. Check setup.log"; read -p "Press [Enter] to return..." dummy; } ;;
        3) install_openvpn || { log_err "OpenVPN installation sequence aborted. Check setup.log"; read -p "Press [Enter] to return..." dummy; } ;;
        4) check_status ;;
        5) view_logs ;;
        0) echo -e "\n${GREEN}[INFO] Exiting console. Goodbye!${RESET}"; exit 0 ;;
        *) log_err "Invalid selection. Please input 0 to 5."; sleep 2 ;;
    esac
done
