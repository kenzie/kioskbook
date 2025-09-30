# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

KioskBook is a bulletproof kiosk deployment platform for Lenovo M75q-1 hardware. It transforms a minimal Linux install into a fast-booting (<10 seconds), self-recovering kiosk running Vue.js applications in full-screen Chromium.

## Architecture

### Modular Alpine Linux Installation

The core of KioskBook is a modular installer system built on Alpine Linux, consisting of `bootstrap.sh` and `main.sh` with specialized modules that transform a minimal Alpine installation into a bulletproof kiosk system.

**Prerequisites:**
- Alpine Linux Live USB or minimal installation
- Root access
- Internet connectivity (configured automatically if needed)

**Installation Flow:**
1. **Bootstrap Phase** (`bootstrap.sh`): Network setup, package manager configuration, repository cloning
2. **Partition Module** (`00-partition.sh`): Disk partitioning and filesystem setup
3. **Base System** (`10-base-system.sh`): Core Alpine packages and system configuration
4. **Boot Optimization** (`20-boot-optimization.sh`): GRUB/syslinux with Plymouth silent boot
5. **Font Installation** (`25-fonts.sh`): Inter and CaskaydiaCove Nerd Font with fontconfig
6. **Display Stack** (`30-display.sh`): X11, Chromium, AMD drivers, kiosk user setup
7. **Application Setup** (`50-application.sh`): Node.js app deployment and systemd services
8. **Monitoring & Recovery** (`70-monitoring.sh`): Health checks, auto-recovery, remote access

### System Components

- **Base OS**: Alpine Linux (minimal, security-focused)
- **Init System**: OpenRC with systemd compatibility layer
- **Display Server**: X11 with Mesa AMD drivers (no desktop environment)
- **Browser**: Chromium in kiosk mode (full-screen, no UI elements)
- **Runtime**: Node.js 22.x + npm
- **Application**: Vue.js web application (served on port 3000)
- **Remote Access**: Tailscale VPN + SSH
- **Boot**: Plymouth silent boot with Route 19 logo
- **Fonts**: Inter (UI) + CaskaydiaCove Nerd Font (monospace)

### Key Design Principles

1. **Modular Installation**: Bootstrap + modular installer system for maintainability
2. **Fast Boot**: <5 second boot time with Plymouth silent boot (Route 19 logo only)
3. **Self-Recovery**: Multi-layer recovery (service, application, system level)
4. **Offline-First**: Must work without network using cached JSON data
5. **Minimal Surface**: Alpine Linux minimal installation for security and performance
6. **Unattended Operation**: Designed for months without physical access
7. **Silent Operation**: No boot text, only Route 19 logo on black background

## Common Commands

### Installation
```bash
# Boot from Alpine Linux Live USB
# Download and run bootstrap
wget -O - https://raw.githubusercontent.com/kenzie/kioskbook/alpine-rewrite/installer/bootstrap.sh | ash

# Or manually:
git clone -b alpine-rewrite https://github.com/kenzie/kioskbook.git
cd kioskbook/installer
ash bootstrap.sh
bash main.sh [github_repo] [tailscale_key]
```

### Management
```bash
# Check service status (OpenRC)
rc-status kiosk-app
rc-status tailscaled

# Check services (systemd compatibility)
systemctl status kiosk-app
systemctl status tailscaled

# View logs
journalctl -u kiosk-app -f
tail -f /var/log/kiosk-app.log

# Restart services
rc-service kiosk-app restart
systemctl restart kiosk-app

# Health check
/usr/local/bin/kiosk-health-check

# Update application
cd /opt/kiosk-app && git pull && npm install && rc-service kiosk-app restart

# Font management
font-status
update-fonts

# Boot validation
/opt/kioskbook/bin/validate-boot.sh
```

### Development/Testing
When developing the installer, test on Alpine Linux (latest) with hardware that matches the Lenovo M75q-1 specs (AMD-based, NVMe SSD). Use UTM on macOS for development testing.

## Critical Requirements

### Performance Targets
- Boot time: <5 seconds from power on to application display (silent boot with Route 19 logo)
- Recovery time: <30 seconds for automatic service recovery
- Uptime: Designed for months of unattended operation
- Font rendering: Optimized Inter + CaskaydiaCove with subpixel antialiasing

### Hardware Target
- Primary: Lenovo M75q-1 (AMD-based mini PC)
- GPU: AMD Radeon Vega (integrated)
- Storage: NVMe SSD (238GB+ recommended)
- RAM: 8-16GB
- Network: Ethernet (fiber-backed preferred)

### Security Model
- Physical access assumed controlled
- Tailscale VPN for remote access
- Alpine Linux minimal installation surface (security-focused)
- Automatic security patches enabled via apk
- OpenRC init system (simpler than systemd)

## Application Integration

The kiosk system is designed to run Vue.js applications. Default application repository is `kenzie/lobby-display`, but this is configurable during installation.

**Application Requirements:**
- Must be a Node.js/npm-based application
- Should support full-screen display
- Must handle offline operation with cached JSON data
- Should be compatible with Chromium kiosk mode

## Recovery Architecture

### Multi-Layer Recovery
1. **Service-level**: Automatic restart of failed services (systemd)
2. **Application-level**: Browser and Node.js monitoring
3. **System-level**: Watchdog timers and health checks

### Remote Management
- SSH access for diagnostics
- Tailscale VPN for secure remote access
- Git-based update mechanism for applications
- Centralized logging for troubleshooting

## Installation System Development

The Alpine rewrite uses a modular installer system:

### Bootstrap Script (`bootstrap.sh`)
1. **POSIX sh compatibility**: Uses Alpine's busybox shell
2. **Network configuration**: Automatic setup if needed
3. **Package manager**: Configure Alpine package repositories
4. **Repository cloning**: Download installer modules

### Main Installer (`main.sh`) 
1. **Modular execution**: Each phase is a separate module
2. **Error handling**: Comprehensive rollback on failure (set -e)
3. **Minimal prompts**: Only GitHub repo and Tailscale key required
4. **Progress display**: Color-coded output with clear phase indicators

### Module Development Guidelines
1. **00-partition.sh**: Disk partitioning with persistent data partition
2. **10-base-system.sh**: Core Alpine packages and system configuration
3. **20-boot-optimization.sh**: Silent boot with Plymouth Route 19 theme
4. **25-fonts.sh**: Inter and CaskaydiaCove font installation with fontconfig
5. **30-display.sh**: X11, Chromium, kiosk user with auto-login
6. **50-application.sh**: Node.js app deployment and service configuration
7. **70-monitoring.sh**: Health checks, recovery, and remote access

## Testing Validation

After installation, validate:
- [ ] System boots in <5 seconds with only Route 19 logo visible
- [ ] Application displays full-screen automatically
- [ ] SSH access works
- [ ] Tailscale VPN connectivity established
- [ ] Application works offline with cached data
- [ ] Services auto-restart on failure (OpenRC + systemd compatibility)
- [ ] Inter font used for UI, CaskaydiaCove for monospace
- [ ] Silent boot (no kernel messages, only Route 19 logo)

## Development Tools

### Testing Environments
- **UTM on macOS**: Use `tools/utm-setup.md` for VM testing
- **QEMU**: Use `tools/test-vm.sh` for cross-platform testing
- **Physical Hardware**: Lenovo M75q-1 for final validation

### Useful Scripts
- **USB Creation**: `tools/build-usb.sh` for bootable Alpine installer
- **Boot Validation**: `config/boot/validate-boot-config.sh`
- **Font Status**: `font-status` and `update-fonts` commands

## Deployment Target

The installation assumes:
- Alpine Linux Live USB or minimal installation
- Internet connectivity during installation (configured automatically)
- Target hardware is Lenovo M75q-1 or compatible AMD-based system
- Root access available
- Complete disk installation (not in-place upgrade)