# Changelog

All notable changes to the BlueFalcon OpenWrt Utility project will be documented in this file.

## [v2.5] - 2026-08-23
### Added
- Inserted the `wget` quick-run installer script directly into `README.md` for fast, copy-paste OpenWrt deployment.

### Fixed
- Fixed chaotic version mismatches across the repository. Unified `setup.sh` (was v2.0), `src/main.sh` (was v2.3), and `VERSION` (was 2.4) so all correctly identify as `v2.5`.

## [v2.4] - 2026-08-23
### Changed
- Standardized project name, README, and common files structure.

## [v2.3] - 2026-08-20
### Fixed
- Fixed an edge-case bug where if a user's SSH session drops mid-installation immediately after `dnsmasq` is uninstalled, attempting to re-run the script would crash because `apk update` would fail to resolve repository domains. The DNS failsafe override (`1.1.1.1`) has now been moved *before* the repository update sequence to guarantee recovery.

## [v2.2] - 2026-08-20
### Fixed
- Added a dynamic architecture resolution layer for the `apk` package manager. The script now parses the router's base architecture (e.g., stripping `_neon-vfpv4` to `arm_cortex-a7`) and dynamically injects it into `/etc/apk/arch` as a valid fallback architecture. This allows users to safely install 100% compatible generic packages when PassWall developers fail to compile sub-architecture specific releases.

## [v2.1] - 2026-08-20
### Fixed
- Fixed a silent crash where strict POSIX error handling (`set -e`) caused the script to immediately exit if the architecture detection fallback logic evaluated to false. 

## [v2.0] - 2026-08-20
### Added
- **Major Architectural Rewrite**: The script has been modularized into separate, maintainable files (`src/core/` and `src/modules/`) following enterprise coding standards.
- Persistent Installation: The utility now permanently installs itself onto the router memory (`/opt/bluefalcon-openwrt-utility/`).
- Global Shortcut: Users can now simply type `bluefalcon` into their OpenWrt terminal to instantly launch the utility at any time.
- Temporary DNS Failsafe: Added a temporary DNS injection (`1.1.1.1`) to prevent the router from losing internet connectivity when `dnsmasq` is hot-swapped for `dnsmasq-full`.
- Auto-Updater: Added a new `5) Update Utility` menu option that automatically pulls the latest modular scripts from GitHub.
- Storage Cleanup: Aggressively removes residual `.zip` files and `/pkg` folders after PassWall installations to preserve router flash memory.

### Changed
- Dynamic UCI Firewall Targeting: Removed hardcoded `@zone[1]` and `wan` assumptions. The OpenVPN module now dynamically queries the UCI database to intelligently detect the correct WAN firewall zone, guaranteeing compatibility across highly-customized routers.

## [v1.8] - 2026-08-20
### Changed
- Reverted `apk` package manager back to its default output behavior by removing the forced verbose (`-v`) flags. The installation log will once again use standard animated progress updates to match the native OpenWrt terminal experience.

## [v1.7] - 2026-08-20
### Fixed
- Fixed an issue where the script would continue running and throw cascading errors if a package installation failed. The script now strictly evaluates exit codes within the menu subroutines and immediately aborts a module if a core dependency (`apk`/`opkg`) fails to install.
- Suppressed erroneous standard errors on missing firewall zones/configurations when OpenVPN installation is forced to skip.

## [v1.6] - 2026-08-20
### Changed
- Forced `apk` package manager to use verbose (`-v`) output. This disables the dynamic carriage-return progress bars and forces the installer to print explicit line-by-line logs directly to the terminal.

## [v1.5] - 2026-08-20
### Removed
- Entirely removed the background logging system and command execution wrappers to prioritize absolute stability. The script is now purely native, meaning `apk`, `wget`, and `unzip` commands run naturally without any interception or complex redirection.
- Removed the "View Logs" menu option since background logs are no longer generated.

## [v1.4] - 2026-08-20
### Changed
- Re-engineered the logging system to use standard synchronous POSIX pipelines (`tee`) instead of background async streams (`tail -f`). This makes the terminal output behave exactly like a native installation experience while preserving strict exit-code error handling and background logging.

## [v1.3] - 2026-08-20
### Changed
- Replaced the visual spinner with real-time log streaming to the console so users can see exact package installation progress, while still safely maintaining the background log file.

## [v1.2] - 2026-08-20
### Fixed
- Fixed an issue where the visual spinner would crash on minimal OpenWrt installations due to the BusyBox `sleep` command not supporting fractional seconds (`0.1`). Delay adjusted to 1 second.

## [v1.1] - 2026-08-20
### Added
- Added an interactive prompt for DNS override during OpenVPN installation.
- Added a new main menu option to view the system installation logs.
- Added a visual spinner to indicate progress for long-running tasks.

### Fixed
- Prevented potential network disconnects by removing aggressive firewall zone renaming; now modifies the `wan` zone device list directly.

## [v1.0] - 2024-05-10
### Added
- Initial public release with architecture auto-detection, hybrid background logging, and integrated OS network soft-reloads.

