# UTM Configuration Guide for KioskBook Testing

This guide provides step-by-step instructions for setting up UTM (Universal Turing Machine) on macOS to simulate the Lenovo M75q-1 hardware for KioskBook development and testing.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [UTM Installation](#utm-installation)
3. [VM Configuration](#vm-configuration)
4. [Operating System Installation](#operating-system-installation)
5. [KioskBook Installation](#kioskbook-installation)
6. [Development Workflow](#development-workflow)
7. [Troubleshooting](#troubleshooting)
8. [Performance Optimization](#performance-optimization)

## Prerequisites

### System Requirements

- **macOS**: 11.0 (Big Sur) or later
- **RAM**: 8GB minimum (16GB recommended for optimal performance)
- **Storage**: 50GB free space for VM and ISOs
- **CPU**: Intel or Apple Silicon (M1/M2/M3)

### Downloads Required

1. **UTM**: Download from [mac.getutm.app](https://mac.getutm.app) or App Store
2. **Debian ISO**: Download Debian 13 (trixie) netinst from [debian.org](https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/)
3. **KioskBook Installer**: Clone this repository or download installer script

## UTM Installation

### Method 1: App Store (Recommended)
1. Open **App Store** on your Mac
2. Search for **"UTM Virtual Machines"**
3. Click **"Get"** to install (requires macOS 12.0+)
4. Launch UTM from Applications folder

### Method 2: Direct Download
1. Visit [mac.getutm.app](https://mac.getutm.app)
2. Download UTM for your Mac architecture:
   - **Apple Silicon**: UTM.dmg
   - **Intel**: UTM.dmg
3. Open the DMG file and drag UTM to Applications
4. Launch UTM (you may need to allow it in System Preferences > Security)

### Initial Setup
```bash
# Optional: Install UTM via Homebrew
brew install --cask utm
```

## VM Configuration

### Creating a New Virtual Machine

1. **Launch UTM** and click **"Create a New Virtual Machine"**
2. Choose **"Virtualize"** (for best performance)
3. Select operating system: **"Linux"**

### System Configuration

#### Basic Settings
- **Name**: `KioskBook-Test`
- **Notes**: `Lenovo M75q-1 simulation for KioskBook testing`

#### Architecture Selection
- **Apple Silicon Macs**: Select **"Use Apple Virtualization"**
- **Intel Macs**: Select **"Use QEMU Virtualization"**

*Screenshot placeholder: [UTM_Architecture_Selection.png]*

### Hardware Configuration

#### System Settings
```
Architecture: ARM64 (Apple Silicon) or x86_64 (Intel)
System: QEMU 8.2 virt (Apple Silicon) or Q35 (Intel)
CPU: Default
CPU Count: 4 cores
```

#### Memory Configuration
```
Memory: 4096 MB (4 GB)
Enable Balloon Device: ✓ (for dynamic memory)
```

*Screenshot placeholder: [UTM_Memory_Settings.png]*

#### Storage Configuration

**Boot Drive (Primary)**
```
Interface: NVMe (virtio for Apple Silicon)
Size: 20 GB
```

**Steps to configure storage:**
1. Click **"New Drive"**
2. Set **Interface** to **"NVMe"** (or **"VirtIO"** on Apple Silicon)
3. Set **Size** to **"20 GB"**
4. **Import Drive**: Leave unchecked for new installation
5. **Removable**: Leave unchecked

*Screenshot placeholder: [UTM_Storage_Configuration.png]*

#### Network Configuration
```
Network Mode: Shared Network
MAC Address: Auto-generate
```

**Port Forwarding Setup** (for SSH and web access):
```
Host Port 2222 → Guest Port 22 (SSH)
Host Port 3000 → Guest Port 3000 (Web App)
Host Port 5901 → Guest Port 5901 (VNC, if needed)
```

*Screenshot placeholder: [UTM_Network_Settings.png]*

#### Display Configuration
```
Emulated Display Card: virtio-gpu-pci
Resolution: 1920x1080
Retina Mode: OFF (for accurate kiosk simulation)
```

**Display Settings:**
1. **Graphics**: Select **"Full Graphics"**
2. **Resolution**: Set to **"1920x1080"** (common kiosk display size)
3. **Retina Mode**: **Disabled** (to simulate standard displays)
4. **HiDPI**: **Disabled**

*Screenshot placeholder: [UTM_Display_Configuration.png]*

#### Audio Configuration
```
Audio Card: intel-hda (for AMD GPU simulation)
Audio Backend: Core Audio
```

#### Input Configuration
```
USB Support: ✓ Enabled
Input: ✓ Show mouse cursor
Capture input when mouse enters the view: ✓
Release input when mouse leaves the view: ✓
```

### Advanced Settings

#### CPU Features (Intel Macs only)
```
Force Multicore: ✓
Hardware Acceleration: ✓ (if available)
```

#### QEMU Arguments (Advanced Users)
For Intel Macs, add these QEMU arguments for better AMD GPU simulation:
```
-cpu host,+svm,+amd-ssbd,+amd-no-ssb
-machine q35,accel=hvf
-device amd-iommu
```

*Screenshot placeholder: [UTM_Advanced_Settings.png]*

## Operating System Installation

### Preparing Installation Media

#### Option 1: Debian Netinst ISO
1. Download **debian-13.0.0-amd64-netinst.iso**
2. In UTM, click **"Browse"** next to **"Boot ISO Image"**
3. Select the downloaded Debian ISO

#### Option 2: KioskBook Custom Installer
If you've created a custom installer USB using `tools/build-usb.sh`:
1. Create an ISO from the USB using:
   ```bash
   # Convert USB to ISO (if needed)
   dd if=/dev/diskX of=kioskbook-installer.iso
   ```
2. Import the ISO into UTM

### Installation Process

#### Boot Configuration
1. **Start the VM**: Click the play button
2. **Boot Menu**: Select **"Install"** or **"KioskBook Automated Install"**
3. **Language**: English
4. **Location**: United States (or your location)
5. **Keyboard**: American English

*Screenshot placeholder: [UTM_Boot_Menu.png]*

#### Network Configuration
```
Auto-configure network: Yes
Hostname: kioskbook-test
Domain: local
```

#### Partitioning
**Recommended for testing:**
```
Partitioning method: Guided - use entire disk
Partition scheme: All files in one partition
Write changes to disk: Yes
```

#### User Account Setup
```
Root password: kioskbook (for testing)
Full name: Kiosk User
Username: kiosk
Password: kioskbook (for testing)
```

#### Package Selection
```
Desktop environment: None (minimal install)
Standard system utilities: Yes
SSH server: Yes
```

*Screenshot placeholder: [UTM_Package_Selection.png]*

### Post-Installation Setup

#### First Boot
1. **Login as root** with password `kioskbook`
2. **Update system**:
   ```bash
   apt update && apt upgrade -y
   ```

#### Install Prerequisites
```bash
# Install Node.js 22.x
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

# Install Git and essential tools
apt-get install -y git curl wget sudo
```

#### Enable sudo for kiosk user
```bash
usermod -aG sudo kiosk
```

## KioskBook Installation

### Method 1: Direct Install
```bash
# Download and run KioskBook installer
wget -O /tmp/kioskbook-install.sh https://raw.githubusercontent.com/kenzie/kioskbook/main/install.sh
chmod +x /tmp/kioskbook-install.sh
bash /tmp/kioskbook-install.sh
```

### Method 2: Development Install
```bash
# Clone repository for development
git clone https://github.com/kenzie/kioskbook.git /opt/kioskbook
cd /opt/kioskbook
bash install.sh
```

### Installation Configuration
When prompted during installation:
```
GitHub repository: kenzie/lobby-display (or your app repo)
Tailscale auth key: [your-tailscale-key] (optional for testing)
```

## Development Workflow

### Shared Folders Setup

#### Configure Shared Folder in UTM
1. **VM Settings** → **Sharing**
2. **Add Shared Folder**:
   ```
   Name: kioskbook-dev
   Path: /path/to/your/kioskbook/project
   Mode: Read/Write
   ```
3. **Restart VM** to apply changes

*Screenshot placeholder: [UTM_Shared_Folders.png]*

#### Mount Shared Folder in VM
```bash
# Install VirtFS support
apt-get install -y 9mount

# Create mount point
mkdir -p /mnt/kioskbook-dev

# Mount shared folder
mount -t 9p -o trans=virtio kioskbook-dev /mnt/kioskbook-dev

# Make permanent (add to /etc/fstab)
echo "kioskbook-dev /mnt/kioskbook-dev 9p trans=virtio,rw 0 0" >> /etc/fstab
```

### Snapshot Management

#### Creating Snapshots
1. **Shutdown VM** cleanly
2. **Right-click VM** in UTM
3. **Create Snapshot**:
   ```
   Name: fresh-install
   Description: Clean Debian install before KioskBook
   ```

#### Useful Snapshots to Create
```
1. fresh-debian: Clean Debian 13 installation
2. pre-kioskbook: After Node.js install, before KioskBook
3. kioskbook-installed: After successful KioskBook installation
4. working-config: Known good configuration for testing
```

*Screenshot placeholder: [UTM_Snapshot_Management.png]*

### Development Commands

#### Access VM from Host
```bash
# SSH into VM (port forwarding must be configured)
ssh kiosk@localhost -p 2222

# View web application
open http://localhost:3000
```

#### Monitor VM Status
```bash
# Check KioskBook services
systemctl status kiosk-app kiosk-browser

# View logs
journalctl -u kiosk-app -f

# Check display
export DISPLAY=:0
ps aux | grep chromium
```

## Troubleshooting

### Common Issues and Solutions

#### VM Won't Start
**Symptoms**: UTM fails to boot VM
**Solutions**:
1. **Check available RAM**: Ensure Mac has enough free memory
2. **Disable other VMs**: Close other running virtual machines
3. **Reset VM**: Right-click VM → **"Delete Saved State"**
4. **Check Virtualization**: Ensure Virtualization is enabled in System Settings

#### Poor Performance
**Symptoms**: Slow boot times, laggy interface
**Solutions**:
1. **Enable Hardware Acceleration**: Settings → **"Use Apple Virtualization"**
2. **Increase Memory**: Bump to 6GB or 8GB if available
3. **Close Background Apps**: Quit unnecessary Mac applications
4. **Use SSD Storage**: Ensure VM is on SSD, not spinning disk

#### Network Issues
**Symptoms**: No internet connectivity in VM
**Solutions**:
1. **Check Network Mode**: Use **"Shared Network"** not **"Bridged"**
2. **Reset Network**: In VM run `dhclient` or restart networking
3. **Firewall Settings**: Check macOS firewall isn't blocking UTM
4. **DNS Configuration**: Set DNS to 8.8.8.8 or 1.1.1.1

#### Display Problems
**Symptoms**: Wrong resolution, graphics artifacts
**Solutions**:
1. **Install Guest Additions**: If available for your VM type
2. **Disable Retina Mode**: In display settings
3. **Set Fixed Resolution**: Use 1920x1080 for consistency
4. **Graphics Driver**: Ensure virtio-gpu driver is loaded

#### File Sharing Issues
**Symptoms**: Cannot access shared folders
**Solutions**:
1. **Install 9mount**: `apt-get install 9mount`
2. **Check Folder Permissions**: Ensure write access on host
3. **Remount**: `umount /mnt/shared && mount -t 9p ...`
4. **Use Alternative**: SCP/SFTP for file transfer

### Performance Optimization

#### Host System Optimization
```bash
# Free up memory before running VM
sudo purge

# Check available memory
vm_stat

# Monitor CPU usage
top -o cpu
```

#### VM Optimization
```bash
# Disable unnecessary services in VM
systemctl disable bluetooth cups avahi-daemon

# Optimize kernel parameters
echo 'vm.swappiness=10' >> /etc/sysctl.conf

# Clear package cache
apt-get clean && apt-get autoremove
```

### Logging and Debugging

#### UTM Logs
```bash
# View UTM logs on macOS
tail -f ~/Library/Containers/com.utmapp.UTM/Data/Documents/*.utm/Logs/qemu.log
```

#### VM Kernel Logs
```bash
# View boot messages
dmesg | head -50

# Monitor system logs
journalctl -f
```

#### KioskBook Specific Logs
```bash
# Application logs
journalctl -u kiosk-app -f

# Browser logs
journalctl -u kiosk-browser -f

# X11 logs
cat /var/log/Xorg.0.log
```

## Hardware Simulation Accuracy

### Lenovo M75q-1 Target Specs
```
CPU: AMD Ryzen 5 PRO 3400GE (4 cores, 8 threads, 3.3-4.2 GHz)
GPU: AMD Radeon Vega 11 (integrated)
RAM: 8-16GB DDR4-2400
Storage: 238GB+ NVMe SSD
Network: Gigabit Ethernet
```

### UTM VM Configuration Mapping
```
CPU: 4 cores (simulates target core count)
GPU: virtio-gpu (closest available simulation)
RAM: 4GB (reduced for development, can increase to 8GB)
Storage: 20GB NVMe (sufficient for testing)
Network: Shared (simulates ethernet connectivity)
```

### Limitations and Considerations

1. **GPU Acceleration**: UTM cannot perfectly simulate AMD Vega 11
2. **Boot Times**: VM boot slower than bare metal due to virtualization overhead
3. **Power Management**: Different power states than target hardware
4. **Hardware IDs**: Different PCI device IDs than target system

### Testing Recommendations

1. **Focus on Application Logic**: Test KioskBook functionality, not hardware-specific features
2. **Use Real Hardware**: Final testing should be on actual Lenovo M75q-1
3. **Monitor Performance**: Track resource usage to ensure kiosk app efficiency
4. **Test Recovery**: Simulate failures and test auto-recovery features

## Advanced Configuration

### Custom Kernel Parameters
Add AMD-specific kernel parameters for better simulation:
```bash
# Edit /etc/default/grub
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash amd_pstate=active processor.max_cstate=1"

# Update GRUB
update-grub && reboot
```

### QEMU Monitor Access
For advanced debugging, enable QEMU monitor:
```
UTM Settings → Advanced → QEMU Arguments:
-monitor telnet:127.0.0.1:4444,server,nowait
```

Access via: `telnet localhost 4444`

### GPU Passthrough (Advanced)
For Intel Macs with discrete GPUs, experimental GPU passthrough:
```
Prerequisites:
- Intel Mac with discrete GPU
- Disabled SIP (System Integrity Protection)
- IOMMU support

Note: This is complex and may cause system instability
```

## Conclusion

This UTM configuration provides a solid development environment for KioskBook testing on macOS. While it cannot perfectly replicate the Lenovo M75q-1 hardware, it offers sufficient accuracy for application development, boot sequence testing, and integration validation.

For production deployment validation, always test on actual target hardware. Use this VM environment for rapid development iteration and initial testing phases.

### Quick Reference Commands

```bash
# Start development session
ssh kiosk@localhost -p 2222

# Update KioskBook
cd /opt/kioskbook && git pull && bash install.sh

# View application
open http://localhost:3000

# Monitor services
systemctl status kiosk-app kiosk-browser

# Restart services
sudo systemctl restart kiosk-app

# View logs
journalctl -u kiosk-app -f
```

---

*For additional support, refer to the UTM documentation at [docs.getutm.app](https://docs.getutm.app) or the KioskBook project README.*