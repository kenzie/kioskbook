# KioskBook

Professional kiosk deployment platform for Alpine Linux. Deploy web applications to dedicated kiosk hardware with minimal configuration.

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
- **Alpine Linux ISO** (latest version recommended)
- **Root access** (installer must run as root)
- **Internet connection** (ethernet cable connected)
- **Target disk** (minimum 64GB, will be completely erased)

**Required Tools (usually pre-installed on Alpine):**
- `parted` - Disk partitioning
- `mkfs.ext4` - Ext4 filesystem creation
- `mkfs.fat` - FAT32 filesystem creation
- `mount` - Filesystem mounting
- `chroot` - System installation

**Hardware Requirements:**
- **Lenovo M75q-1 Tiny** (tested configuration)
- **8-16GB RAM** (minimum 8GB recommended)
- **NVMe SSD** (64GB minimum)
- **AMD Ryzen** with integrated graphics
- **HDMI display** or TV
- **Ethernet connection** during installation

## Quick Install

1. **Boot from Alpine Linux ISO**
   - Download latest Alpine Linux ISO
   - Boot from USB/DVD
   - Login as `root` (no password)

2. **Connect ethernet cable**
   - Ensure internet connectivity
   - Test with: `ping 8.8.8.8`

3. **Run installer**
   ```bash
   curl -sSL https://raw.githubusercontent.com/kenzie/kioskbook/main/install.sh | sh
   ```

4. **Follow prompts**
   - Confirm disk overwrite (auto-detects NVMe/SATA)
   - Enter GitHub repository for Vue.js app
   - Enter Tailscale auth key (required)

**Note**: The installer is now modular, breaking down the installation into focused, manageable components for better maintainability and debugging.

## Hardware Requirements

- **Lenovo M75q-1 Tiny** (tested configuration)
- Any AMD Ryzen system with integrated graphics
- TV or monitor with HDMI connection
- Ethernet connection during installation
- Minimum 8GB RAM, 64GB storage

## Configuration

The installer prompts for:
- Root password
- Tailscale auth key (required)
- GitHub repository for kiosk display app

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

## Troubleshooting

### Installation Issues

**"Invalid disk" Error:**
- Ensure disk is not mounted: `umount /dev/nvme0n1*` or `umount /dev/sda*`
- Check disk exists: `lsblk`
- Verify disk is not in use by another process
- For NVMe: Check `/dev/nvme0n1` exists
- For SATA: Check `/dev/sda` exists

**"No internet connection" Error:**
- Check ethernet cable connection
- Verify network interface: `ip link show`
- Test connectivity: `ping 8.8.8.8`
- Check DHCP: `ip addr show`

**"Required tool not found" Error:**
- Install missing tools: `apk add parted e2fsprogs dosfstools util-linux`
- Update package index: `apk update`

**Installation Fails Mid-Process:**
- Check error messages for specific failure point
- Verify disk has sufficient space (64GB minimum)
- Ensure stable internet connection
- Restart from Alpine Linux ISO and try again

### Boot Issues

**System Won't Boot:**
- Check EFI boot entry: `efibootmgr -v`
- Verify boot order in BIOS/UEFI
- Check NVMe drive detection in BIOS
- Ensure ethernet is connected
- For NVMe: Verify `/dev/nvme0n1` is detected in BIOS
- Check EFI partition: `ls -la /boot/EFI/BOOT/`

**Boot Hangs:**
- Check for hardware issues (RAM, storage)
- Verify AMD GPU drivers are loaded
- Check system logs: `dmesg | tail -50`

### Display Issues

**No Display Output:**
- Run GPU test: `/opt/test-gpu.sh`
- Check GPU status: `lspci | grep VGA`
- Verify AMD drivers: `lsmod | grep amdgpu`
- Check display connection (HDMI)

**Browser Won't Start:**
- Check browser service: `rc-service kiosk-browser status`
- View browser logs: `rc-service kiosk-browser log`
- Restart browser: `rc-service kiosk-browser restart`
- Check GPU acceleration: `chrome://gpu`

### App Issues

**Vue.js App Not Loading:**
- Check app service: `rc-service kiosk-app status`
- View app logs: `rc-service kiosk-app log`
- Restart app: `rc-service kiosk-app restart`
- Check app build: `ls -la /opt/kiosk-app/dist/`
- Verify GitHub repository access

**App Build Failures:**
- Check Node.js installation: `node --version`
- Verify npm packages: `cd /opt/kiosk-app && npm list`
- Check build logs: `cd /opt/kiosk-app && npm run build`
- Ensure package.json exists and is valid

### Network Issues

**Tailscale Connection Problems:**
- Check Tailscale status: `tailscale status`
- Restart Tailscale: `rc-service tailscaled restart`
- Verify auth key: `tailscale status --json`
- Check network connectivity: `ping 8.8.8.8`

**SSH Access Issues:**
- Check SSH service: `rc-service sshd status`
- Verify SSH keys: `ls -la /root/.ssh/`
- Check firewall: `iptables -L`
- Test local SSH: `ssh root@localhost`

### Performance Issues

**Slow Performance:**
- Check hardware status: `kiosk hardware status`
- Monitor resources: `htop`
- Check temperature: `sensors`
- Verify hardware optimizations: `kiosk hardware optimize`

**Memory Issues:**
- Check memory usage: `free -h`
- Monitor memory pressure: `cat /proc/pressure/memory`
- Check for memory leaks: `ps aux --sort=-%mem`
- Restart services: `kiosk restart`

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
- Boot from Alpine Linux ISO
- Run installer again
- Select same disk (will be reformatted)
- Use same configuration

## Modular Architecture

KioskBook uses a modular installation system for better maintainability:

```
modules/
├── 01-core-setup.sh           # Core system setup (network, bootloader, packages)
├── 02-kiosk-app.sh            # Vue.js application setup
├── 03-watchdog.sh             # Browser watchdog and health monitoring
├── 04-auto-update.sh          # Auto-update service
├── 05-screensaver.sh          # Screensaver service
├── 06-kiosk-cli.sh            # Management CLI
├── 07-resource-management.sh   # Resource monitoring and cleanup
├── 08-escalating-recovery.sh  # Progressive recovery system
├── 09-logging-debugging.sh    # Structured logging and debugging
├── 10-tailscale.sh            # Tailscale VPN configuration
├── 11-utilities.sh            # System optimizations and management tools
└── 12-boot-logo.sh            # Boot logo configuration
```

**Benefits:**
- **Maintainable**: Each module ~200 lines vs 2495 monolithic
- **Debuggable**: Individual modules can be tested independently
- **Scalable**: Easy to add new features without affecting existing ones
- **Professional**: Clean separation of concerns

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
