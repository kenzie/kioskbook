# KioskBook

Professional kiosk deployment platform for Linux. Deploy web applications to dedicated kiosk hardware with minimal configuration.

## Features

- **🚀 Fast Installation** - Complete setup in under 10 minutes
- **⚡ Optimized Performance** - AMD GPU acceleration and system tuning
- **🔧 Auto-Detection** - Supports Node.js, Ruby, Python, and static web apps
- **🖥️ Professional Display** - Route 19 branding and boot logo
- **🌐 Remote Access** - Tailscale integration for management
- **📺 Kiosk Mode** - Chromium in full-screen kiosk mode
- **🛡️ Reliable** - Auto-restart services and crash detection

## Prerequisites

**Required Environment:**
- **Debian 13 (trixie)** - Minimal installation
- **Root access** - Installer must run as root
- **Internet connection** - Ethernet cable connected
- **Node.js and npm** - Pre-installed (tested with Node.js 22.x)

**Hardware Requirements:**
- **Lenovo M75q-1 Tiny** (tested configuration)
- **8-16GB RAM** (minimum 8GB recommended)
- **NVMe SSD** (64GB minimum)
- **AMD Ryzen** with integrated graphics
- **HDMI display** or TV
- **Ethernet connection** during installation

## Quick Install

1. **Install Debian 13 (trixie)**
   - Perform minimal Debian installation on Lenovo M75q-1
   - Install Node.js and npm (v22.x recommended)
   - Connect ethernet cable and verify connectivity

2. **Login as root**
   ```bash
   su -
   ```

3. **Clone and run installer**
   ```bash
   git clone https://github.com/kenzie/kioskbook.git
   cd kioskbook
   bash install.sh
   ```

4. **Follow prompts**
   - Enter GitHub repository for Vue.js app (default: kenzie/lobby-display)
   - Enter Tailscale auth key (get from https://login.tailscale.com/admin/settings/keys)
   - Confirm installation

5. **Reboot**
   - System will prompt for reboot
   - After reboot, kiosk will auto-login and start application

**Installation Time**: ~5-10 minutes depending on network speed

## Hardware Requirements

- **Lenovo M75q-1 Tiny** (tested configuration)
- Any AMD Ryzen system with integrated graphics
- TV or monitor with HDMI connection
- Ethernet connection during installation
- Minimum 8GB RAM, 64GB storage

## Configuration

The installer prompts for:
- GitHub repository for kiosk display app (default: kenzie/lobby-display)
- Tailscale auth key (required for remote management)

## Supported Applications

KioskBook is optimized for Vue.js applications:
- **Vue.js** - Automatically builds and serves Vue.js applications
- **Node.js** - Installs dependencies and builds production bundles
- **Static Files** - Serves built applications from `dist` directory
- **http-server** - Professional static file serving

## Default Configuration

- **Hostname**: `kioskbook`
- **Timezone**: America/Halifax
- **Network**: DHCP
- **SSH**: Enabled
- **Display**: Route 19 branding
- **App URL**: `http://localhost:3000`

## Management Commands

```bash
# Update system and app
/opt/update-kiosk.sh

# Test GPU acceleration
/opt/test-gpu.sh

# View system status
rc-status

# Restart kiosk app
rc-service kiosk-app restart

# Restart kiosk browser
rc-service kiosk-browser restart

# Check kiosk health
/opt/kiosk-health-check.sh

# Run immediate update (Alpine + packages + Vue app)
/opt/update-now.sh

# Check update status and logs
/opt/update-status.sh

# Manual screensaver control
/opt/screensaver-manual.sh

# Force switch to screensaver
/opt/screensaver-control.sh screensaver

# Force switch to kiosk app
/opt/screensaver-control.sh kiosk
```

## Tailscale Integration

Tailscale is required for installation and provides:
- Automatic connection on boot
- SSH access enabled
- Route acceptance enabled


### Recovery Options

**System Recovery:**
- Use recovery system: `kiosk recovery status`
- Reset recovery level: `kiosk recovery reset`
- Trigger recovery: `kiosk recovery trigger`
- Test recovery: `kiosk recovery test`

**Emergency Cleanup:**
- Run emergency cleanup: `/opt/emergency-cleanup.sh`
- Check resource status: `/opt/resource-status.sh`
- Monitor system health: `kiosk health`

**Complete Reinstall:**
- Boot from Linux ISO
- Run installer again
- Select same disk (will be reformatted)
- Use same configuration

## Installation Architecture

KioskBook uses a single comprehensive installer (`install.sh`) that handles all setup phases:

```
install.sh phases:
1. System Verification     # Check prerequisites and hardware
2. Boot Optimization       # Configure GRUB for <10s boot
3. Display Stack           # Install X11, Chromium, AMD drivers
4. Kiosk User             # Create auto-login kiosk user
5. Application Setup      # Clone, build, and deploy Vue.js app
6. Tailscale VPN          # Configure remote management
7. Monitoring & Recovery  # Health checks and auto-restart
8. Finalization           # Timezone, sync, and reboot
```

**Benefits:**
- **Simple**: Single script execution
- **Clear**: Progress displayed at each phase
- **Idempotent**: Can be re-run safely
- **Fast**: ~5-10 minute installation time

## Development

KioskBook is part of the Book family:
- **RinkBook** - Rink management
- **TeamBook** - Team management
- **GoalieBook** - Goalie-specific tools
- **KioskBook** - Kiosk deployment platform

## License

MIT License - see LICENSE file for details.

## Support

For issues and questions:
- GitHub Issues: [kenzie/kioskbook](https://github.com/kenzie/kioskbook)
- Documentation: [kenzie.github.io/kioskbook](https://kenzie.github.io/kioskbook)

---

**KioskBook** - Professional kiosk deployment made simple.
