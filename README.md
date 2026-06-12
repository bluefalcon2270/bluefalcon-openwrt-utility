<div align="center">

# 🦅 BlueFalcon OpenWrt Utility

**The unified, interactive deployment tool for PassWall 2 and OpenVPN.**

![OpenWrt](https://img.shields.io/badge/Platform-OpenWrt-2ca5e0?style=for-the-badge&logo=openwrt)
[![Version](https://img.shields.io/badge/Version-1.3-blue?style=for-the-badge)]()
[![Language](https://img.shields.io/badge/Written%20in-Shell-121011?style=for-the-badge&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](LICENSE)
[![YouTube](https://img.shields.io/badge/YouTube-FF0000?style=for-the-badge&logo=youtube&logoColor=white)](YOUR_YOUTUBE_CHANNEL_LINK_HERE)

<br />
</div>

This utility provides a single, interactive script to install PassWall 2 and OpenVPN on OpenWrt without dependency conflicts. By centralizing the installation of `dnsmasq-full` and core packages as a prerequisite step, it ensures both VPN and proxy routing tools operate seamlessly. It automatically adapts to your system architecture, supporting both legacy `opkg` and modern `apk` environments.
<br>

## 🚀 Quick Run
Run this single command in your OpenWrt SSH terminal:

```sh
wget -O setup.sh https://raw.githubusercontent.com/bluefalcon2270/openwrt-utility/main/setup.sh && sh setup.sh
```

<br>

## 🌟 Core Features
* **Easy All-in-One Menu:** Simple numbers guide you through the setup from start to finish without requiring any coding knowledge.
* **No More Internet Conflicts:** Automatically stops PassWall and OpenVPN from blocking each other so your connection stays stable.
* **Smart Link Memory:** Safely remembers your download links so you never have to type or paste them a second time.
* **Automatic Router Matching:** Instantly recognizes your specific router version and applies the exact files it needs.
* **Quick Health Check:** Soft-scans your system with a clean checklist showing you exactly what is working or missing.
* **Clean Screen, Hidden Errors:** Keeps your terminal looking beautiful by wiping the screen between actions and hiding messy system text inside a background log file (`/opt/bluefalcon-openwrt-utility/setup.log`).

<br><br>

## ✅ Supported Systems

| Distribution Engine | Build Status | Underlying Package Manager |
| :--- | :---: | :---: |
| **OpenWrt** (v24.x / Newer Versions) | ✅ Full | Native `apk` ecosystem infrastructure |
| **OpenWrt** (v23.x / Older Versions) | ✅ Full | `opkg` manager configuration |
| **ImmortalWrt** (All variants) | ✅ Full | `opkg` / `apk` depending on branch |

<br><br>

## 📜 Changelog
* **v1.3:** Eliminated UI flickering by hiding the terminal cursor during active spinner animations.
* **v1.2:** Fixed integer sleep delays to ensure native BusyBox compatibility.
* **v1.1:** Rebranded to BlueFalcon, added visual loading spinners for background tasks, and standardized UI colors.
* **v1.0:** Initial public release with architecture auto-detection, hybrid background logging, and integrated OS network soft-reloads.

---
**Watch the Tutorial:** I use this exact utility in my YouTube tutorials to ensure viewers have a standardized, error-free environment before we dive into advanced server routing and VPN setups.
