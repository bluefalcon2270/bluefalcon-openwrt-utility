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
    if [ "$PKG_MANAGER" = "apk" ]; then
        run_with_retry apk add openvpn-openssl luci-app-openvpn || return 1
    else
        run_with_retry opkg install openvpn-openssl luci-app-openvpn || return 1
    fi

    echo -e "\n${CYAN}[INFO] Configuring Firewall for tun+ interfaces...${RESET}"
    local WAN_ZONE=$(uci show firewall | grep "name='wan'" | cut -d. -f2 | head -n 1)
    if [ -n "$WAN_ZONE" ]; then
        uci -q del_list firewall.$WAN_ZONE.device="tun+" || true
        uci add_list firewall.$WAN_ZONE.device="tun+" 2>/dev/null || true
        uci commit firewall 2>/dev/null || true
    else
        echo -e "${YELLOW}[WARN] Could not automatically detect a 'wan' zone in the firewall. You may need to assign the tun interface manually in LuCI.${RESET}"
    fi

    echo -e "\n${CYAN}[INFO] Configuring Secure DNS Routing...${RESET}"
    if [ -n "$WAN_ZONE" ]; then
        uci set network.wan.peerdns='0' 2>/dev/null || true
        uci commit network 2>/dev/null || true
    fi

    echo -e "\n${CYAN}DNS Configuration${RESET}"
    echo -e "Would you like to override the system DNS with secure defaults (1.1.1.1 and 8.8.8.8)?"
    echo -e "Choose 'n' if you are using AdGuard Home, Pi-hole, or custom DNS."
    read -p "Override system DNS? (y/N): " OVERRIDE_DNS
    if [ "$OVERRIDE_DNS" = "y" ] || [ "$OVERRIDE_DNS" = "Y" ]; then
        echo -e "${GREEN}[INFO] Overriding DNS...${RESET}"
        uci -q delete dhcp.@dnsmasq[0].server || true
        uci add_list dhcp.@dnsmasq[0].server='1.1.1.1' 2>/dev/null || true
        uci add_list dhcp.@dnsmasq[0].server='8.8.8.8' 2>/dev/null || true
        uci commit dhcp 2>/dev/null || true
    else
        echo -e "${GREEN}[INFO] Skipping DNS override. Using existing configuration.${RESET}"
    fi

    echo -e "\n${CYAN}[INFO] Reloading Core Services (Network, Firewall, DNS)...${RESET}"
    /etc/init.d/network reload 2>/dev/null || true
    /etc/init.d/firewall reload 2>/dev/null || true
    /etc/init.d/dnsmasq reload 2>/dev/null || true

    echo -e "\n${CYAN}[INFO] Enabling and starting OpenVPN service...${RESET}"
    /etc/init.d/openvpn enable 2>/dev/null || true
    /etc/init.d/openvpn start 2>/dev/null || true

    echo -e "\n${GREEN}========================================${RESET}"
    echo -e "${GREEN}        OPENVPN INSTALLATION COMPLETE    ${RESET}"
    echo -e "${GREEN}========================================${RESET}"
    echo -e "${GREEN}[INFO] Proceed to LuCI > VPN > OpenVPN to import your .ovpn profile.${RESET}"
    read -p "Press [Enter] to return to the menu..." dummy
}
