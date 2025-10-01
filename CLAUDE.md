# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

KioskBook is a bulletproof kiosk deployment platform for Lenovo M75q-1 hardware. It transforms a minimal Linux install into a fast-booting (<10 seconds), self-recovering kiosk running Vue.js applications in full-screen Chromium.

## Architecture

### Alpine Linux Installation

The core of KioskBook is a two-phase installer system built on Alpine Linux that transforms a minimal Alpine installation into a bulletproof kiosk system.

**Prerequisites:**
- Alpine Linux Live USB or minimal installation
- Root access
- Internet connectivity

**Installation Flow:**
1. **Bootstrap Phase** (`bootstrap.sh`): Network setup, package manager configuration, repository cloning, basic Alpine installation
2. **Setup Phase** (`setup.sh`): Complete kiosk transformation including display stack, fonts, applications, and configuration

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
wget -O - https://raw.githubusercontent.com/kenzie/kioskbook/main/bootstrap.sh | ash

# Or manually:
git clone https://github.com/kenzie/kioskbook.git
cd kioskbook
ash bootstrap.sh
ash setup.sh [github_repo] [tailscale_key]
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

## Installation System

KioskBook uses a simple two-phase installer system:

### Bootstrap Script (`bootstrap.sh`)
1. **POSIX sh compatibility**: Uses Alpine's busybox shell
2. **Network configuration**: Automatic setup if needed
3. **Package manager**: Configure Alpine package repositories
4. **Repository cloning**: Download KioskBook configuration and scripts

### Setup Script (`setup.sh`)
1. **Complete system transformation**: Single script that handles all kiosk setup
2. **Error handling**: Robust error handling and cleanup
3. **Minimal prompts**: Only GitHub repo and Tailscale key required
4. **Progress display**: Clear status output for each installation phase

**Setup phases:**
1. System package updates and base package installation
2. Display stack installation (X11, Chromium, drivers)
3. Font installation (Inter, CaskaydiaCove Nerd Font)
4. Kiosk user creation and auto-login configuration
5. Node.js and application deployment
6. Boot optimization and Plymouth splash screen
7. Tailscale VPN setup (optional)
8. System finalization

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