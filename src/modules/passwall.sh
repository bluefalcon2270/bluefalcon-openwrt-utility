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

    # Save env
    cat << EOF > "$CONFIG_FILE"
ZIP_URL="$ZIP_URL"
APK_URL="$APK_URL"
EOF

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
    unzip -o "$WORKDIR/passwall2.zip" -d "$WORKDIR/pkg" || return 1
    
    cd "$WORKDIR/pkg"
    local APK_FILES=$(find . -name "*.apk" -o -name "*.ipk")
    if [ -z "$APK_FILES" ]; then
        echo -e "${RED}[ERROR] No valid package files found inside the archive!${RESET}"
        cd "$WORKDIR"
        read -p "Press [Enter] to return to the menu..." dummy
        return 1
    fi

    echo -e "\n${CYAN}[INFO] Installing local dependencies...${RESET}"
    if [ "$PKG_MANAGER" = "apk" ]; then
        run_with_retry apk add --allow-untrusted $APK_FILES || return 1
    else
        run_with_retry opkg install $IPK_FILES || return 1
    fi
    cd "$WORKDIR"

    echo -e "\n${CYAN}[INFO] Downloading luci-app-passwall2...${RESET}"
    wget -O "$WORKDIR/luci-app-passwall2.${EXT}" "$APK_URL" || { read -p "Press [Enter] to return..." dummy; return 1; }

    echo -e "\n${CYAN}[INFO] Installing luci-app-passwall2...${RESET}"
    if [ "$PKG_MANAGER" = "apk" ]; then
        run_with_retry apk add --allow-untrusted "$WORKDIR/luci-app-passwall2.apk" || return 1
    else
        run_with_retry opkg install "$WORKDIR/luci-app-passwall2.ipk" || return 1
    fi

    echo -e "\n${CYAN}[INFO] Cleaning up storage space...${RESET}"
    rm -rf "$WORKDIR/pkg" "$WORKDIR/passwall2.zip" "$WORKDIR/luci-app-passwall2."*

    echo -e "\n${GREEN}========================================${RESET}"
    echo -e "${GREEN}      PASSWALL 2 INSTALLATION COMPLETE  ${RESET}"
    echo -e "${GREEN}========================================${RESET}"
    read -p "Press [Enter] to return to the menu..." dummy
}
