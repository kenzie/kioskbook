# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

KioskBook is a bulletproof kiosk deployment platform for Lenovo M75q-1 hardware. It transforms a minimal Linux install into a fast-booting (<10 seconds), self-recovering kiosk running Vue.js applications in full-screen Chromium.

## Architecture

### Single-Script In-Place Installation

The core of KioskBook is `install.sh`, a comprehensive installation script that transforms an existing minimal Debian installation into a fully functional kiosk system.

**Prerequisites:**
- Debian 13 (trixie) installed
- Node.js and npm pre-installed
- Root access
- Internet connectivity

**Installation Flow:**
1. Configuration input (GitHub repo, Tailscale key)
2. System verification (prerequisites, hardware, network)
3. Boot optimization (GRUB timeout=0, disable unnecessary services)
4. Display stack installation (X11, Chromium, AMD drivers)
5. Kiosk user creation with auto-login and X11 auto-start
6. Application setup (clone, build, systemd service)
7. Tailscale VPN installation and authentication
8. Monitoring and recovery configuration
9. Finalization and optional reboot

### System Components

- **Base OS**: Debian 13 (trixie) - minimal installation
- **Display Server**: X11 with xserver-xorg-video-amdgpu (no desktop environment)
- **Browser**: Chromium in kiosk mode (full-screen, no UI elements)
- **Runtime**: Node.js 22.x + npm
- **Application**: Vue.js web application (served on port 3000)
- **Remote Access**: Tailscale VPN + SSH
- **User**: Auto-login kiosk user with X11 auto-start

### Key Design Principles

1. **Single Script Execution**: Entire installation in one `install.sh` run
2. **Fast Boot**: <10 second boot time (network-independent)
3. **Self-Recovery**: Automatic restart of failed services
4. **Offline-First**: Must work without network using cached JSON data
5. **Minimal Surface**: Minimal Linux installation for security and performance
6. **Unattended Operation**: Designed for months without physical access

## Common Commands

### Installation
```bash
git clone https://github.com/kenzie/kioskbook.git
cd kioskbook
bash install.sh
```

### Management
```bash
# Check service status
systemctl status kiosk-app
systemctl status tailscaled

# View logs
journalctl -u kiosk-app -f

# Restart services
systemctl restart kiosk-app

# Health check
/opt/kiosk-health-check.sh

# Update application
cd /opt/kiosk-app && git pull && npm install && systemctl restart kiosk-app
```

### Development/Testing
When developing the install script, test on Debian 13 (trixie) with hardware that matches the Lenovo M75q-1 specs (AMD-based, NVMe SSD).

## Critical Requirements

### Performance Targets
- Boot time: <10 seconds from power on to application display
- Recovery time: <30 seconds for automatic service recovery
- Uptime: Designed for months of unattended operation

### Hardware Target
- Primary: Lenovo M75q-1 (AMD-based mini PC)
- GPU: AMD Radeon Vega (integrated)
- Storage: NVMe SSD (238GB+ recommended)
- RAM: 8-16GB
- Network: Ethernet (fiber-backed preferred)

### Security Model
- Physical access assumed controlled
- Tailscale VPN for remote access
- Minimal installation surface
- Automatic security patches enabled

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

## Installation Script Development

When working on `install.sh`:

1. **Prerequisites**: Assumes Debian 13 + Node.js/npm already installed
2. **Idempotency**: Script sections should be safe to re-run
3. **Error Handling**: Check success of critical operations (set -e for fail-fast)
4. **Minimal Prompts**: Only GitHub repo and Tailscale key required
5. **Boot Optimization**: GRUB timeout=0, disable unnecessary services
6. **Auto-login**: Kiosk user auto-login on tty1, X11 auto-start via .bash_profile
7. **Systemd Services**: kiosk-app.service with auto-restart enabled
8. **Progress Display**: Color-coded output with clear phase indicators

## Testing Validation

After installation, validate:
- [ ] System boots in <10 seconds
- [ ] Application displays full-screen automatically
- [ ] SSH access works
- [ ] Tailscale VPN connectivity established
- [ ] Application works offline with cached data
- [ ] Services auto-restart on failure

## Deployment Target

The installation assumes:
- Existing Debian 13 (trixie) minimal installation
- Node.js and npm pre-installed (v22.x tested)
- Ethernet connectivity during installation
- Target hardware is Lenovo M75q-1 or compatible AMD-based system
- Root access available
- No disk wiping (works on running system)