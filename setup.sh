#!/bin/sh

echo "========================================"
echo "  Downloading BlueFalcon Utility v2.5   "
echo "========================================"

WORKDIR="/opt/bluefalcon-openwrt-utility"
REPO_RAW="https://raw.githubusercontent.com/bluefalcon2270/bluefalcon-openwrt-utility/main"

mkdir -p "$WORKDIR/src/core"
mkdir -p "$WORKDIR/src/modules"

echo "[1/5] Downloading main logic..."
wget -q -O "$WORKDIR/src/main.sh" "$REPO_RAW/src/main.sh"
echo "[2/5] Downloading UI engine..."
wget -q -O "$WORKDIR/src/core/ui.sh" "$REPO_RAW/src/core/ui.sh"
echo "[3/5] Downloading package manager..."
wget -q -O "$WORKDIR/src/core/packages.sh" "$REPO_RAW/src/core/packages.sh"
echo "[4/5] Downloading PassWall module..."
wget -q -O "$WORKDIR/src/modules/passwall.sh" "$REPO_RAW/src/modules/passwall.sh"
echo "[5/5] Downloading OpenVPN module..."
wget -q -O "$WORKDIR/src/modules/openvpn.sh" "$REPO_RAW/src/modules/openvpn.sh"

chmod +x "$WORKDIR/src/main.sh"

# Create a global command shortcut
cat << 'EOF' > /usr/bin/bluefalcon
#!/bin/sh
sh /opt/bluefalcon-openwrt-utility/src/main.sh
EOF
chmod +x /usr/bin/bluefalcon

# Save the downloader script so it can be called for updates
cat << 'EOF' > "$WORKDIR/update.sh"
#!/bin/sh
wget -O /tmp/setup.sh https://raw.githubusercontent.com/bluefalcon2270/bluefalcon-openwrt-utility/main/setup.sh && sh /tmp/setup.sh
EOF
chmod +x "$WORKDIR/update.sh"

echo ""
echo "Installation Complete! Launching BlueFalcon..."
sleep 1
exec sh "$WORKDIR/src/main.sh"
