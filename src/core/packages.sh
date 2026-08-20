check_internet() {
    if ! ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] No internet connection detected. Please check your router's network settings.${RESET}"
        return 1
    fi
}

detect_system() {
    mkdir -p "$WORKDIR"

    # Detect Package Manager
    if command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
        EXT="apk"
        DEPS_CORE="curl unzip dnsmasq-full ipset iptables-nft kmod-nft-tproxy kmod-nft-socket"
        DEPS_STATUS="curl unzip ipset iptables-nft kmod-nft-tproxy kmod-nft-socket"
        OPENVPN_PKGS="openvpn-openssl luci-app-openvpn kmod-tun"
    elif command -v opkg >/dev/null 2>&1; then
        PKG_MANAGER="opkg"
        EXT="ipk"
        DEPS_CORE="curl unzip dnsmasq-full ipset iptables kmod-nft-tproxy kmod-nft-socket"
        DEPS_STATUS="curl unzip ipset iptables kmod-nft-tproxy kmod-nft-socket"
        OPENVPN_PKGS="openvpn-openssl luci-app-openvpn kmod-tun"
    else
        echo -e "${RED}[ERROR] No supported package manager found (apk or opkg).${RESET}"
        exit 1
    fi

    if [ -f /etc/os-release ]; then
        SYS_ARCH=$(grep '^OPENWRT_ARCH=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr -d "'") || true
    fi
    if [ -z "$SYS_ARCH" ]; then
        SYS_ARCH="UNKNOWN_ARCH"
    fi
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

install_dependencies() {
    echo -e "\n--- Installing Core Requirements ---"
    check_internet || return 1

    echo -e "\n${CYAN}[INFO] Updating system package repositories...${RESET}"
    if [ "$PKG_MANAGER" = "apk" ]; then apk update || return 1; else opkg update || return 1; fi
    
    echo -e "\n${YELLOW}[WARN] Safeguarding DNS before removing dnsmasq...${RESET}"
    # Failsafe DNS so the router doesn't lose internet during dnsmasq swap
    echo "nameserver 1.1.1.1" > /tmp/resolv.conf.tmp
    cat /etc/resolv.conf >> /tmp/resolv.conf.tmp 2>/dev/null || true
    mv /tmp/resolv.conf.tmp /etc/resolv.conf

    echo -e "\n${CYAN}[INFO] Removing standard dnsmasq to prevent conflicts...${RESET}"
    if [ "$PKG_MANAGER" = "apk" ]; then apk del dnsmasq || true; else opkg remove dnsmasq || true; fi
        
    echo -e "\n${CYAN}[INFO] Installing required core packages...${RESET}"
    if [ "$PKG_MANAGER" = "apk" ]; then apk add $DEPS_CORE || return 1; else opkg install $DEPS_CORE || true; fi

    echo -e "\n${CYAN}[INFO] Restarting DNS services...${RESET}"
    /etc/init.d/dnsmasq restart 2>/dev/null || true

    echo -e "\n${GREEN}[INFO] Requirements successfully installed!${RESET}"
    read -p "Press [Enter] to return to the menu..." dummy
}

check_status() {
    echo -e "\n--- Installation Status ---"
    local check_cmd=""
    
    if [ "$PKG_MANAGER" = "apk" ]; then
        check_cmd="apk info 2>/dev/null | grep -q"
    else
        check_cmd="opkg list-installed 2>/dev/null | grep -q"
    fi

    # Check DNS Stack
    if eval "$check_cmd '^dnsmasq-full\b'"; then
        echo -e "dnsmasq-full: [${GREEN}Installed${RESET}]"
    elif eval "$check_cmd '^dnsmasq\b'"; then
        echo -e "dnsmasq: [${RED}Incorrect (Run Option 1)${RESET}]"
    else
        echo -e "dnsmasq-full: [${RED}Missing${RESET}]"
    fi

    # Check Core
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
