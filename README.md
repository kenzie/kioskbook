# KioskBook

Bulletproof kiosk deployment platform for Debian Linux. Transform any AMD-based system into a fast-booting (under 10 seconds), self-recovering kiosk running Vue.js applications with professional-grade reliability.

**Version 0.2.4** - Modular architecture with automated monitoring and recovery

## Features

- **🚀 Ultra-Fast Boot** - Under 10 second boot with branded Plymouth splash (Route 19 logo)
- **📦 Debian 13 Base** - Minimal, stable, and reliable Trixie foundation
- **🔧 Modular Installation** - Update individual components without full reinstall
- **🖥️ Professional Display** - X11 + OpenBox with AMD GPU acceleration
- **🌐 Remote Management** - Tailscale VPN integration for secure access
- **📺 Optimized Kiosk** - Chromium with Inter fonts and font rendering optimization
- **🛡️ Self-Recovering** - Automated monitoring every 5 minutes with auto-recovery
- **🎨 Premium Fonts** - Inter UI font and CaskaydiaCove Nerd Font
- **📊 Automated Maintenance** - Daily/weekly scheduled updates and cleanups
- **🛠️ kiosk CLI** - Powerful management tool for status, health, logs, and updates
- **📝 Version Tracking** - Track installed version and available updates

## Quick Start

### 1. Install Debian 13.1.0 (Trixie) Netinst

Download and install minimal Debian:
- [Debian 13 netinst ISO](https://cdimage.debian.org/cdimages/trixie_di_rc2/amd64/iso-cd/)
- During installation: **SSH server only, no desktop environment**
- Standard system utilities only

### 2. Install KioskBook

SSH into the freshly installed Debian system:

```bash
# Clone repository
git clone https://github.com/kenzie/kioskbook.git
cd kioskbook

# Run installer
sudo ./install.sh [github_repo] [tailscale_key]

# Arguments (optional):
#   github_repo    - Vue.js app repository (default: kenzie/lobby-display)
#   tailscale_key  - Tailscale auth key for VPN access
```

### 3. Reboot

```bash
sudo reboot
```

System will:
- Boot in under 10 seconds with Route 19 branded Plymouth splash
- Auto-login as kiosk user
- Launch Chromium in full-screen kiosk mode
- Display your Vue.js application on port 5173

## Management with kiosk CLI

After installation, use the `kiosk` command for all management tasks:

```bash
# Check version
kiosk version

# Show system status
kiosk status

# Run health check
kiosk health --detailed

# View logs (real-time)
kiosk logs -f

# List available modules
kiosk modules

# Update specific module
sudo kiosk update 30-display
sudo kiosk update 70-services

# Update everything
sudo kiosk update all

# Restart services
sudo kiosk restart app       # Restart application
sudo kiosk restart display   # Restart display manager
sudo kiosk restart all       # Restart both

# Run maintenance
sudo kiosk maintenance
```

## Modular Architecture

KioskBook v0.2.4 uses a modular architecture for easy maintenance and selective updates:

```
kioskbook/
├── install.sh              # Main installer orchestrator
├── modules/                # Installation modules (run in order)
│   ├── 10-base.sh         # Base system packages
│   ├── 20-network.sh      # SSH, Tailscale VPN
│   ├── 30-display.sh      # X11, OpenBox, LightDM, Chromium
│   ├── 40-fonts.sh        # Inter, CaskaydiaCove Nerd Font
│   ├── 50-app.sh          # Node.js, application deployment
│   ├── 60-boot.sh         # Branded boot with Plymouth
│   └── 70-services.sh     # Monitoring, recovery, maintenance
├── configs/                # All configuration files
├── bin/kiosk              # Management CLI tool
└── lib/common.sh          # Shared functions
```

### Module Development Workflow

1. Make changes to a module in your local repo
2. Test on live kiosk: `sudo bash modules/30-display.sh`
3. Verify: `kiosk status && kiosk health`
4. Commit and push when confirmed working
5. Update production: `sudo kiosk update all`

## Automated Features

### Monitoring & Recovery
- **Every 5 minutes**: Automated health checks
- **Auto-recovery**: Restarts failed services automatically
- **Logging**: All recovery actions logged to `/var/log/kioskbook/monitor.log`

### Scheduled Maintenance
- **Daily (3 AM)**: General maintenance
- **Weekly (Sunday 2 AM)**: System updates
- **Weekly (Sunday 4 AM)**: Service restarts after updates
- **Daily (1 AM)**: Journal log cleanup (7-day retention)

## Hardware Requirements

### Recommended Hardware

**Primary Target: Lenovo M75q-1 Tiny**
- **CPU**: AMD Ryzen 5 PRO 3400GE (or similar AMD APU)
- **RAM**: 8-16GB DDR4 (16GB recommended for video content)
- **Storage**: 256GB+ NVMe SSD (M.2 2280)
- **GPU**: AMD Radeon Vega 11 (integrated)
- **Ports**: HDMI 2.0, USB 3.1, Ethernet
- **Form Factor**: 175mm x 175mm x 34.5mm

### Minimum Requirements

- **CPU**: AMD Ryzen APU with Vega graphics
- **RAM**: 4GB DDR4 minimum (8GB recommended)
- **Storage**: 32GB SSD (NVMe preferred for fast boot)
- **Display**: HDMI 1.4 or higher
- **Network**: Ethernet connection during installation

## Version History

### v0.2.4 (Current) - 2025-10-03
- ✅ Switched from Vite dev server to production `serve` for stability
- ✅ Enhanced kiosk CLI with short module names support (e.g., `kiosk update app`)
- ✅ Auto-restart app service after updates
- ✅ Fixed systemd silent boot configuration
- ✅ Improved color rendering in CLI output

### v0.2.3 - 2025-10-03
- ✅ Added kiosk CLI installation to 70-services module
- ✅ Fixed CLI color rendering with proper escape sequences

### v0.2.2 - 2025-10-03
- ✅ Switched to production build with `serve` package
- ✅ Fixed JSON parsing and Chrome DevTools API integration

### v0.2.1 - 2025-10-02
- ✅ Added scheduled maintenance system
- ✅ Plymouth theme improvements

### v0.2.0 - 2025-10-02
- ✅ Modular architecture with numbered modules
- ✅ kiosk CLI for comprehensive system management
- ✅ Automated monitoring and recovery every 5 minutes
- ✅ Scheduled maintenance (daily/weekly)
- ✅ Version tracking
- ✅ Configuration files separated from scripts
- ✅ Individual module updates without full reinstall

### v0.1.0 - 2025-10-01
- Initial Debian implementation
- Monolithic bootstrap and update scripts
- Basic kiosk functionality
- Silent boot configuration

## Application Integration

The default application is `kenzie/lobby-display`, but any Vue.js application works. Requirements:

- **Node.js/npm-based** with production build (`npm run build`)
- **Port 5173** (served via `npx serve` for production stability)
- **Full-screen compatible** for kiosk display
- **Offline-first** with cached JSON data support

To use a different application, pass the GitHub repository URL during installation:

```bash
sudo ./install.sh https://github.com/your-username/your-kiosk-app
```

## Troubleshooting

### Check System Status
```bash
kiosk status
kiosk health --detailed
```

### View Logs
```bash
kiosk logs -f                      # Follow logs
journalctl -u kioskbook-app -f     # Direct systemd logs
```

### Restart Services
```bash
sudo kiosk restart all
```

### Manual Service Management
```bash
systemctl status kioskbook-app
systemctl status lightdm
systemctl restart kioskbook-app
```

### Check Monitoring
```bash
systemctl status kioskbook-recovery.timer
/usr/local/bin/kioskbook-monitor
```

## Development

See [CLAUDE.md](CLAUDE.md) for detailed development guidelines, including:
- Module development workflow
- Configuration file management
- Testing on live systems
- Version control best practices

## License

MIT License - see LICENSE file for details.

## Support

For issues and questions:
- **GitHub Issues**: [kenzie/kioskbook](https://github.com/kenzie/kioskbook/issues)
- **Documentation**: [CLAUDE.md](CLAUDE.md) for development details
- **Hardware Support**: Tested on Lenovo M75q-1, compatible with AMD APU systems

---

**KioskBook** - Professional kiosk deployment made bulletproof.
