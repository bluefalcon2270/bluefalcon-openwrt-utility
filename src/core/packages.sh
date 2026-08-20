check_internet() {
    echo -n "Checking internet connection... "
    if ! ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
        echo -e "${RED}FAIL${RESET}"
        echo -e "${RED}[ERROR] Router has no internet connection.${RESET}"
        return 1
    fi
    echo -e "${GREEN}OK${RESET}"
}

run_with_retry() {
    local max_retries=3
    local count=0
    while [ $count -lt $max_retries ]; do
        if "$@"; then return 0; fi
        count=$((count + 1))
        echo -e "${YELLOW}[WARN] Task failed or network dropped. Auto-retrying ($count/$max_retries)...${RESET}"
        sleep 2
    done
    return 1
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

    # Add backward compatibility for base ARM/Cortex architectures
    if [ "$PKG_MANAGER" = "apk" ] && [ -f /etc/apk/arch ]; then
        if echo "$SYS_ARCH" | grep -q "_neon"; then
            BASE_ARCH=$(echo "$SYS_ARCH" | sed 's/_neon.*//')
            if ! grep -q "^$BASE_ARCH$" /etc/apk/arch; then
                echo "$BASE_ARCH" >> /etc/apk/arch
            fi
        fi
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

    echo -e "\n${YELLOW}[WARN] Safeguarding DNS...${RESET}\n"
    echo "nameserver 1.1.1.1" > /tmp/resolv.conf.tmp
    cat /etc/resolv.conf >> /tmp/resolv.conf.tmp 2>/dev/null || true
    mv /tmp/resolv.conf.tmp /etc/resolv.conf

    echo -e "\n${CYAN}[INFO] Updating system package repositories...${RESET}"
    if [ "$PKG_MANAGER" = "apk" ]; then
        run_with_retry apk update || true
    else
        run_with_retry opkg update || true
    fi

    echo -e "\n${CYAN}[INFO] Removing standard dnsmasq to prevent conflicts...${RESET}"
    if [ "$PKG_MANAGER" = "apk" ]; then apk del dnsmasq || true; else opkg remove dnsmasq || true; fi
        
    echo -e "\n${CYAN}[INFO] Installing required core packages...${RESET}"
    if [ "$PKG_MANAGER" = "apk" ]; then
        run_with_retry apk add libnghttp2-14 libcurl4 curl kmod-nf-conntrack-netlink libnfnetlink0 libnetfilter-conntrack3 libgmp10 libnettle8 dnsmasq-full kmod-nf-ipt kmod-ipt-core kmod-ipt-ipset libipset13 ipset kmod-nft-compat libxtables12 libiptext-nft0 libiptext0 libiptext6-0 xtables-nft iptables-nft kmod-nf-socket kmod-nft-socket kmod-nf-tproxy kmod-nft-tproxy unzip || return 1
    else
        run_with_retry opkg install curl kmod-nf-conntrack-netlink libnfnetlink libnetfilter-conntrack libgmp libnettle8 dnsmasq-full kmod-nf-ipt kmod-ipt-core kmod-ipt-ipset libipset ipset kmod-nft-compat libxtables libiptext-nft libiptext libiptext6 xtables-nft iptables-nft kmod-nf-socket kmod-nft-socket kmod-nf-tproxy kmod-nft-tproxy unzip || return 1
    fi

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
