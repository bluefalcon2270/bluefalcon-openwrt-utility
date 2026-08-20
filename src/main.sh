#!/bin/sh

set -e

# --- Configuration ---
export VERSION="2.0"
export WORKDIR="/opt/bluefalcon-openwrt-utility"
export CONFIG_FILE="$WORKDIR/.env"

# Source Modules
. "$WORKDIR/src/core/ui.sh"
. "$WORKDIR/src/core/packages.sh"
. "$WORKDIR/src/modules/passwall.sh"
. "$WORKDIR/src/modules/openvpn.sh"

detect_system

if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
fi

while true; do
    draw_menu
    read -p "Select an option [0-5]: " OPTION

    case "$OPTION" in
        1) install_dependencies ;;
        2) install_passwall2 || { echo -e "${RED}[ERROR] PassWall 2 installation sequence aborted.${RESET}"; read -p "Press [Enter] to return..." dummy; } ;;
        3) install_openvpn || { echo -e "${RED}[ERROR] OpenVPN installation sequence aborted.${RESET}"; read -p "Press [Enter] to return..." dummy; } ;;
        4) check_status ;;
        5) 
            echo -e "\n${CYAN}[INFO] Updating utility...${RESET}"
            exec sh "$WORKDIR/update.sh"
            ;;
        0) echo -e "\n${GREEN}[INFO] Exiting console. Type 'bluefalcon' in terminal to return anytime!${RESET}"; exit 0 ;;
        *) echo -e "${RED}[ERROR] Invalid selection.${RESET}"; sleep 2 ;;
    esac
done
