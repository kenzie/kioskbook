# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

KioskBook is a bulletproof kiosk deployment platform for Lenovo M75q-1 hardware. It transforms a minimal Debian installation into a fast-booting (<10 seconds), self-recovering kiosk running Vue.js applications in full-screen Chromium.

## Architecture

### Modular Debian Installation

The core of KioskBook is a modular installer system that transforms a minimal Debian installation into a bulletproof kiosk system. The modular design allows for:
- **Individual module updates** without full reinstall
- **Easy testing** of changes on live systems
- **Maintainability** through separation of concerns
- **Local development** with test-before-commit workflow

**Prerequisites:**
- Debian 13.1.0 (Trixie) netinst with SSH server only
- Root access
- Internet connectivity

**Installation Flow:**
1. Clone repository: `git clone https://github.com/kenzie/kioskbook.git`
2. Run installer: `sudo ./install.sh [github_repo] [tailscale_key]`
3. Installer executes modules in order: 10-base → 20-network → 30-display → 40-fonts → 50-app → 60-boot → 70-services

### Modular Structure

```
kioskbook/
├── install.sh              # Main installer orchestrator
├── modules/                # Installation modules (run in order)
│   ├── 10-base.sh         # Base system packages
│   ├── 20-network.sh      # SSH, Tailscale VPN
│   ├── 30-display.sh      # X11, OpenBox, LightDM, Chromium
│   ├── 40-fonts.sh        # Inter, CaskaydiaCove Nerd Font
│   ├── 50-app.sh          # Node.js, application deployment
│   ├── 60-boot.sh         # Silent boot configuration
│   └── 70-services.sh     # Monitoring, recovery, maintenance
├── configs/                # Configuration files (no heredocs in scripts)
│   ├── systemd/           # systemd service files
│   ├── openbox/           # OpenBox autostart
│   ├── grub/              # Boot configuration
│   ├── fonts/             # Font configuration
│   ├── monitoring/        # Health check and monitoring scripts
│   └── logrotate/         # Log rotation
├── bin/
│   └── kiosk              # Management CLI tool
└── lib/
    └── common.sh          # Shared functions and variables
```

### System Components

- **Base OS**: Debian 13.1.0 (Trixie) minimal installation
- **Init System**: systemd
- **Display Server**: X11 with Mesa AMD drivers (no desktop environment)
- **Window Manager**: OpenBox (minimal, lightweight)
- **Display Manager**: LightDM with auto-login
- **Browser**: Chromium in kiosk mode (full-screen, no UI elements)
- **Runtime**: Node.js 20.x + npm
- **Application**: Vue.js web application (served on port 5173 via Vite dev server)
- **Remote Access**: Tailscale VPN + SSH (optimized for fast startup)
- **Boot**: GRUB silent boot (no plymouth, completely silent)
- **Fonts**: Inter (UI) + CaskaydiaCove Nerd Font (monospace)
- **Monitoring**: Automated health checks every 5 minutes with automatic recovery
- **Maintenance**: Scheduled updates, log rotation, automatic restarts

### Key Design Principles

1. **Modular Installation**: Numbered modules (10, 20, 30...) for clean separation and selective updates
2. **Fast Boot**: <5 second boot time with completely silent GRUB boot
3. **Self-Recovery**: Multi-layer recovery (service, application, system level) with automatic monitoring
4. **Offline-First**: Must work without network using cached JSON data
5. **Minimal Surface**: Debian minimal installation for security and performance
6. **Unattended Operation**: Designed for months without physical access
7. **Silent Operation**: No boot text, completely black screen until application loads
8. **Local Development**: Test module updates on live system from local repo before committing

## Common Commands

### Installation
```bash
# Install Debian 13.1.0 netinst (SSH server only, no desktop)
# SSH into system, then:

git clone https://github.com/kenzie/kioskbook.git
cd kioskbook
sudo ./install.sh [github_repo] [tailscale_key]

# After installation completes:
sudo reboot
```

### Management (kiosk CLI)
```bash
# Show version
kiosk version

# System status
kiosk status

# Health check (basic)
kiosk health

# Health check (detailed)
kiosk health --detailed

# View logs (last 50 lines)
kiosk logs

# Follow logs in real-time
kiosk logs -f

# View specific number of lines
kiosk logs -n 100

# List available modules
kiosk modules

# Update specific module
sudo kiosk update 30-display
sudo kiosk update 70-services

# Update all modules
sudo kiosk update all

# Restart services
sudo kiosk restart app       # Restart application only
sudo kiosk restart display   # Restart display manager
sudo kiosk restart all       # Restart both

# Run maintenance
sudo kiosk maintenance

# Run monitoring check
sudo kiosk monitor
```

### Direct systemd Management
```bash
# Check service status
systemctl status kioskbook-app
systemctl status lightdm

# View logs
journalctl -u kioskbook-app -f

# Restart services
systemctl restart kioskbook-app
systemctl restart lightdm
```

### Development/Testing Workflow

**Local Module Development:**
```bash
# On your dev machine, make changes to a module
vim modules/30-display.sh

# SSH to kiosk system
ssh kiosk@192.168.1.100

# Clone/update your working branch on the kiosk
cd /tmp
git clone https://github.com/kenzie/kioskbook.git -b feature-branch
cd kioskbook

# Test the specific module
sudo bash modules/30-display.sh

# If it works, update via kiosk CLI
sudo cp -r . /opt/kioskbook-repo/
sudo kiosk update 30-display

# Verify changes
kiosk status
kiosk health

# Once confirmed working, commit and push from dev machine
```

**Testing on Debian VM:**
Use UTM or VirtualBox with Debian 13.1.0 netinst. Match Lenovo M75q-1 specs:
- AMD CPU (or x86_64)
- 8GB+ RAM
- 40GB+ disk

## Critical Requirements

### Performance Targets
- Boot time: <5 seconds from power on to application display (completely silent boot)
- Recovery time: <30 seconds for automatic service recovery
- Uptime: Designed for months of unattended operation
- Font rendering: Optimized Inter + CaskaydiaCove with subpixel antialiasing
- Monitoring: Automated health checks every 5 minutes

### Hardware Target
- Primary: Lenovo M75q-1 (AMD-based mini PC)
- GPU: AMD Radeon Vega (integrated)
- Storage: NVMe SSD (238GB+ recommended)
- RAM: 8-16GB
- Network: Ethernet (fiber-backed preferred)

### Security Model
- Physical access assumed controlled
- Tailscale VPN for remote access
- Debian minimal installation surface (security-focused)
- Automatic security patches via unattended-upgrades (scheduled weekly)
- systemd init system

## Application Integration

The kiosk system is designed to run Vue.js applications. Default application repository is `kenzie/lobby-display`, but this is configurable during installation.

**Application Requirements:**
- Must be a Node.js/npm-based application
- Should support full-screen display
- Must handle offline operation with cached JSON data
- Should be compatible with Chromium kiosk mode

## Recovery Architecture

### Multi-Layer Recovery
1. **Service-level**: Automatic restart of failed services (systemd with RestartSec=10)
2. **Application-level**: Browser and Node.js monitoring via kioskbook-monitor
3. **System-level**: Automated recovery checks every 5 minutes via systemd timer
4. **Manual recovery**: `kiosk restart` command for manual intervention

### Automated Monitoring (70-services module)
- **kioskbook-monitor** script runs every 5 minutes
- Checks: Memory usage, CPU load, Chromium process, application HTTP response
- Auto-recovery: Restarts lightdm if Chromium dies, restarts kioskbook-app if HTTP fails
- Logging: All recovery actions logged to /var/log/kioskbook/monitor.log

### Scheduled Maintenance
- **Daily** (3 AM): General maintenance via `kiosk maintenance`
- **Weekly** (Sunday 2 AM): System updates via `kiosk update all`
- **Weekly** (Sunday 4 AM): Service restarts after updates
- **Daily** (1 AM): Journal log cleanup (7-day retention)

### Remote Management
- SSH access for diagnostics (optimized for fast startup)
- Tailscale VPN for secure remote access
- Git-based update mechanism for both application and system modules
- Centralized logging via journald
- `kiosk` CLI for all management tasks

## Installation System

KioskBook uses a modular installation system with numbered modules executed in sequence.

### Main Installer (`install.sh`)
1. **Prerequisites check**: Verify root, Debian, network connectivity
2. **Configuration**: Prompt for GitHub repo and Tailscale key (or use CLI args)
3. **Module execution**: Run all modules in numeric order (10, 20, 30, ...)
4. **CLI installation**: Install `kiosk` command to /usr/local/bin/
5. **Version tracking**: Save version to /etc/kioskbook/version
6. **Repository copy**: Copy repo to /opt/kioskbook-repo for future module updates

### Installation Modules

**10-base.sh** - Base System
- Update package lists and upgrade system
- Install essential packages (curl, wget, git, etc.)
- Disable swap for performance
- Set graphical target
- Disable unnecessary services (bluetooth, cups, etc.)

**20-network.sh** - Network & SSH
- Optimize SSH configuration (UseDNS no, GSSAPIAuthentication no)
- Generate SSH host keys
- Install and configure Tailscale VPN (if auth key provided)

**30-display.sh** - Display System
- Install X11, OpenBox, LightDM, Chromium
- Install AMD GPU drivers (xserver-xorg-video-amdgpu, mesa-vulkan-drivers)
- Create kiosk user with auto-login
- Configure OpenBox autostart with Chromium kiosk mode

**40-fonts.sh** - Fonts
- Install Inter and Noto fonts from Debian repos
- Download and install CaskaydiaCove Nerd Font
- Configure fontconfig to prioritize Inter for sans-serif
- Update font cache

**50-app.sh** - Application
- Install Node.js 20 from NodeSource
- Clone application repository
- Install npm dependencies
- Create and enable kioskbook-app systemd service
- Start application

**60-boot.sh** - Silent Boot
- Configure GRUB for completely silent boot (timeout=0, hidden, loglevel=0)
- Configure systemd for silent startup
- Set kernel parameters to suppress messages
- Mask verbose services
- Configure getty for silent auto-login

**70-services.sh** - Monitoring & Services
- Install kioskbook-monitor script (automated recovery)
- Install kioskbook-health script (manual health checks)
- Configure systemd timer for 5-minute monitoring intervals
- Setup log rotation (7-day retention)
- Configure journald limits
- Setup cron jobs for daily/weekly maintenance
- Create emergency swap management script

## Testing Validation

After installation, validate using `kiosk` CLI:

```bash
# Check version
kiosk version

# Check system status
kiosk status

# Run detailed health check
kiosk health --detailed

# Verify logs for errors
kiosk logs -n 100
```

**Manual validation checklist:**
- [ ] System boots in <5 seconds with completely silent boot (black screen)
- [ ] Application displays full-screen automatically on port 5173
- [ ] SSH access works (fast startup, no DNS delays)
- [ ] Tailscale VPN connectivity established (if configured)
- [ ] Application works offline with cached data
- [ ] Services auto-restart on failure (systemd RestartSec=10)
- [ ] Inter font used for UI, CaskaydiaCove for monospace
- [ ] Completely silent boot (no kernel messages, no plymouth, just black screen)
- [ ] Automated monitoring working (`systemctl status kioskbook-recovery.timer`)
- [ ] `kiosk` command available and all subcommands working

## Development Workflow

### Modular Development
The key advantage of the modular system is the ability to develop and test individual modules:

1. **Make changes** to a module in your local repo
2. **Test on live kiosk** by running the module directly: `sudo bash modules/30-display.sh`
3. **Verify changes** work correctly: `kiosk status && kiosk health`
4. **Commit and push** when confirmed working
5. **Update production systems**: `sudo kiosk update all`

### Module Update Workflow
```bash
# On development machine
cd kioskbook
vim modules/30-display.sh  # Make changes

# Commit to feature branch
git add modules/30-display.sh
git commit -m "Update display configuration"
git push origin feature-branch

# On kiosk system (for testing)
cd /tmp
git clone https://github.com/kenzie/kioskbook.git -b feature-branch
cd kioskbook
sudo bash modules/30-display.sh  # Test directly

# If successful, update repo and run via kiosk CLI
sudo cp -r . /opt/kioskbook-repo/
sudo kiosk update 30-display

# Verify
kiosk status
kiosk health
kiosk logs -n 50

# Once confirmed, merge feature branch to main
# Then update all production kiosks:
sudo kiosk update all
```

### Testing Environments
- **Debian VM** (UTM/VirtualBox): Debian 13.1.0 netinst, minimal install
- **Physical Hardware**: Lenovo M75q-1 for final validation

### Configuration Files vs Scripts
All configuration files are in `configs/` directory, not embedded as heredocs in scripts. This makes it easy to:
- Edit configurations without touching shell scripts
- Version control configurations separately
- Test configuration changes quickly

## Deployment Target

The installation assumes:
- Debian 13.1.0 (Trixie) netinst minimal installation
- SSH server installed and accessible
- Internet connectivity during installation
- Target hardware is Lenovo M75q-1 or compatible AMD-based system
- Root access available via sudo
- Clean installation (not in-place upgrade from v0.1.0 - use migration script)

## Development Guidelines

### Critical: Always Use Repo → Module → System Flow

**❌ NEVER edit system files directly:**
```bash
# DON'T do this:
sudo vim /etc/systemd/system/kioskbook-app.service
sudo vim /usr/local/bin/kioskbook-monitor
sudo vim /etc/lightdm/lightdm.conf
```

**✅ ALWAYS work through the repo and modules:**
```bash
# DO this instead:
cd /opt/kioskbook-repo  # or your local clone
vim configs/systemd/kioskbook-app.service
vim configs/monitoring/kioskbook-monitor
vim configs/systemd/lightdm.conf

# Then update via module:
sudo bash modules/70-services.sh  # Direct test
# OR
sudo kiosk update 70-services     # Via kiosk CLI

# This ensures:
# 1. Changes are tracked in git
# 2. Changes can be rolled back
# 3. Changes can be deployed to other kiosks
# 4. Changes are testable before commit
```

### Working on Live System

Even when debugging on a live kiosk system, use the repo-based workflow:

```bash
# 1. Clone repo to /tmp for testing
cd /tmp
git clone https://github.com/kenzie/kioskbook.git -b my-fix-branch
cd kioskbook

# 2. Make changes to configs or modules
vim configs/systemd/kioskbook-app.service

# 3. Test by running module
sudo bash modules/50-app.sh

# 4. If it works, update the system repo
sudo cp -r . /opt/kioskbook-repo/
sudo kiosk update 50-app

# 5. Verify
kiosk status
kiosk health

# 6. Commit and push from your dev machine once confirmed
```

### General Guidelines

- **Module naming**: Use numeric prefixes (10, 20, 30...) for execution order
- **Idempotency**: All modules must be safe to run multiple times
- **Error handling**: Use `set -euo pipefail` in all scripts
- **Logging**: Use `log_module` functions from `lib/common.sh`
- **Configuration**: Keep configs in `configs/` directory, not as heredocs
- **No direct edits**: Never edit system files directly - always work through repo + modules
- **Testing**: Test each module individually before committing
- **Version tracking**: Update VERSION file when making significant changes