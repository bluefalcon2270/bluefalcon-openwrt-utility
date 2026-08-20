# UI Color Codes
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
RESET="\033[0m"

draw_menu() {
    clear
    echo -e "${CYAN}========================================${RESET}"
    echo -e "${CYAN}        🦅 BLUEFALCON OPENWRT UTILITY       ${RESET}"
    echo -e "${CYAN}                Version ${VERSION}               ${RESET}"
    echo -e "${CYAN}========================================${RESET}"
    echo -e " 1) Install Core Requirements"
    echo -e " 2) Install PassWall 2"
    echo -e " 3) Install OpenVPN"
    echo -e " 4) Installation Status"
    echo -e " 5) Update Utility"
    echo -e " 0) Exit"
    echo -e "${CYAN}========================================${RESET}"
}
