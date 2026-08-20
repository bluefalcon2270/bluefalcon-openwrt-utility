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
