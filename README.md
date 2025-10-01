# KioskBook

Bulletproof kiosk deployment platform for Debian Linux. Transform any AMD-based system into a fast-booting (<5 seconds), self-recovering kiosk running Vue.js applications with professional-grade reliability.

## Features

- **🚀 Ultra-Fast Boot** - Sub-5 second boot to Chromium display
- **📦 Debian Base** - Minimal, stable, and reliable foundation  
- **🔧 Simple Installation** - Single-script bootstrap from Debian netinst ISO
- **🖥️ Professional Display** - X11 with AMD GPU acceleration and TearFree
- **🌐 Remote Management** - Tailscale VPN integration for secure access
- **📺 Optimized Kiosk** - Chromium with Inter fonts and CSS injection
- **🛡️ Self-Recovering** - Comprehensive health monitoring and auto-recovery
- **🎨 Premium Fonts** - Inter UI font and CaskaydiaCove Nerd Font
- **📊 Content Sync** - Manifest-based content updates with atomic swaps

## Installation Guide

### 1. Download Debian Netinst ISO

Download the minimal Debian installer (300MB):
- [Debian 12 netinst ISO](https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/)
- Create bootable USB with dd, Rufus, or Balena Etcher

### 2. Boot and Install Debian Minimal

Boot from USB and install minimal Debian:
- **No desktop environment** 
- **SSH server only**
- **Standard system utilities**

### 3. Run KioskBook Bootstrap

After Debian installation and first boot:

```bash
# Download and run bootstrap
wget -O bootstrap.sh https://raw.githubusercontent.com/kenzie/kioskbook/main/bootstrap.sh
chmod +x bootstrap.sh
sudo ./bootstrap.sh
```

The bootstrap will:
- Install X11, Chromium, and display drivers
- Configure auto-login and kiosk user
- Install Node.js and Vue.js application  
- Set up silent boot and fast startup
- Configure Tailscale VPN (optional)

### 4. First Boot

After bootstrap completes and reboot:
- **Fast boot** - <5 seconds to display
- **Auto-login** - Automatic kiosk user login
- **Full-screen Chromium** - Vue.js application display
- **Remote access** - SSH via Tailscale (if configured)

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

## Development Status

🚧 **Currently rebuilding on Debian foundation**

The Alpine Linux implementation has been moved to the `alpine-research` branch. 
This main branch is being rebuilt with Debian for better reliability and hardware support.

**Target completion**: Coming soon

## Previous Work

The Alpine Linux research and implementation can be found in the `alpine-research` branch, including:
- Complete Alpine bootstrap and setup scripts
- Silent boot configuration
- Auto-login implementation  
- Font installation and management
- Service optimization for fast boot

## License

MIT License - see LICENSE file for details.

## Support

For issues and questions:
- **GitHub Issues**: [kenzie/kioskbook](https://github.com/kenzie/kioskbook/issues)
- **Documentation**: This README and upcoming Debian implementation
- **Hardware Support**: Tested on Lenovo M75q-1, compatible with AMD APU systems

---

**KioskBook** - Professional kiosk deployment made bulletproof.