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
