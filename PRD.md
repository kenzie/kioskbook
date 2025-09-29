# KioskBook Product Requirements Document

## Overview

KioskBook is a bulletproof kiosk deployment platform designed for unattended operation on Lenovo M75q-1 hardware. The system transforms Alpine Linux into a fast-booting (<10 seconds), self-recovering kiosk that runs Vue.js applications in full-screen Chromium.

## Hardware Requirements

- **Primary Target**: Lenovo M75q-1 (AMD-based mini PC)
- **Storage**: NVMe SSD (will be completely erased)
- **Network**: Ethernet connection (fiber-backed)
- **Display**: Any monitor with HDMI/DisplayPort
- **Input**: Minimal (kiosk operation)

## Software Stack

- **Base OS**: Alpine Linux 3.22.1
- **Bootloader**: GRUB (EFI)
- **Display Server**: X11 (minimal, no desktop environment)
- **Browser**: Chromium (kiosk mode)
- **Runtime**: Node.js + npm
- **Application**: Vue.js web application
- **Remote Access**: SSH + Tailscale VPN

## Performance Requirements

- **Boot Time**: <10 seconds from power on to application display
- **Recovery Time**: <30 seconds for automatic service recovery
- **Uptime**: Designed for months of unattended operation
- **Resource Usage**: Minimal Alpine footprint + application requirements

## Three-Phase Architecture

### Phase 1: Brutal Alpine Installation (`install.sh`)

**Purpose**: Establish a clean, bootable Alpine Linux system

**Features:**
- Brutal disk wiping (user confirms with "DESTROY")
- Automated Alpine Linux installation using `setup-alpine`
- SSH access configuration with user-defined root password
- NVMe drive auto-detection (`/dev/nvme0n1`)
- Network connectivity validation
- Phase 2/3 script preparation

**Inputs:**
- GitHub repository for kiosk application
- Root password for remote access
- User confirmation for data destruction

**Outputs:**
- Bootable Alpine Linux system
- SSH enabled for remote access
- Hostname set to "kioskbook"
- Phase 2 and 3 scripts ready for execution

**Success Criteria:**
- System boots from NVMe drive
- SSH access works with configured password
- Alpine package manager functional
- Phase scripts present in `/root/`

### Phase 2: System Hardening (`phase2-harden.sh`)

**Purpose**: Configure system for bulletproof unattended operation

**Features:**
- Automatic system updates configuration
- Tailscale VPN installation and configuration
- Log rotation and system monitoring setup
- Service auto-recovery mechanisms
- Basic firewall configuration
- System health monitoring
- Remote access optimization

**Components:**
- **Update Management**: Automatic security updates
- **VPN Access**: Tailscale for secure remote management
- **Monitoring**: System health checks and logging
- **Recovery**: Automatic service restart on failure
- **Security**: Minimal attack surface configuration

**Success Criteria:**
- System automatically updates security patches
- Tailscale VPN accessible for remote management
- Services automatically restart on failure
- Comprehensive logging for troubleshooting
- System survives common failure scenarios

### Phase 3: Fast Kiosk Setup (`phase3-kiosk.sh`)

**Purpose**: Configure ultra-fast kiosk application environment

**Features:**
- Minimal X11 server installation
- Chromium browser in kiosk mode
- Node.js and npm installation
- Vue.js application deployment
- Auto-start configuration
- Boot time optimization
- Display and power management

**Boot Optimization:**
- Parallel service initialization
- Minimal service set
- Optimized kernel parameters
- Fast filesystem options
- Preloaded application assets

**Application Management:**
- Git clone of specified repository
- Automatic npm install and build
- Application health monitoring
- Auto-restart on application crashes
- Update mechanism for application code

**Success Criteria:**
- <10 second boot time to application display
- Application starts automatically on boot
- Full-screen kiosk mode operation
- Automatic recovery from application failures
- Application updates work reliably

## Security Model

- **Physical Access**: Assumed to be controlled environment
- **Network Security**: Tailscale VPN for remote access
- **System Security**: Minimal Alpine installation surface
- **Application Security**: Standard web application security practices
- **Update Security**: Automatic security patches enabled

## Recovery and Monitoring

### Automatic Recovery
- Service-level: Automatic restart of failed services
- Application-level: Browser and Node.js application monitoring
- System-level: Watchdog timers and health checks

### Logging and Diagnostics
- System logs: Standard Alpine/OpenRC logging
- Application logs: Centralized application error logging
- Remote access: SSH + Tailscale for troubleshooting

### Update Management
- System updates: Automatic security patches
- Application updates: Git-based update mechanism
- Configuration updates: Remote configuration management

## Deployment Process

1. **Preparation**:
   - Boot Lenovo M75q-1 from Alpine 3.22.1 USB
   - Ensure ethernet connectivity
   - Download installation script

2. **Phase 1 - Installation**:
   ```bash
   wget https://raw.githubusercontent.com/kenzie/kioskbook/main/install.sh
   chmod +x install.sh
   ./install.sh
   ```

3. **Phase 2 - Hardening** (post-reboot):
   ```bash
   ./phase2-harden.sh
   ```

4. **Phase 3 - Kiosk Setup**:
   ```bash
   ./phase3-kiosk.sh
   ```

5. **Validation**:
   - Verify <10 second boot time
   - Confirm application loads and displays correctly
   - Test remote SSH access
   - Verify automatic recovery mechanisms

## Maintenance and Operations

### Regular Maintenance
- Monitor system logs via SSH/Tailscale
- Update application code as needed
- Monitor system performance metrics

### Troubleshooting
- SSH access for remote diagnostics
- Comprehensive logging for issue identification
- Recovery procedures for common failure modes

### Scaling
- Each kiosk is independently deployable
- Configuration management via Git repositories
- Remote update capabilities for fleet management

## Success Metrics

- **Installation Success Rate**: >95% successful installations
- **Boot Time**: <10 seconds consistently achieved
- **Uptime**: >99% uptime over 30-day periods
- **Recovery Time**: <30 seconds for automatic recovery
- **Remote Access**: 100% accessibility via Tailscale VPN

## Risk Mitigation

- **Hardware Failure**: Logging and remote monitoring for early detection
- **Network Issues**: Local application caching and offline operation
- **Software Crashes**: Multi-layer automatic recovery mechanisms
- **Update Failures**: Staged update process with rollback capability
- **Security Issues**: Minimal attack surface and automatic security updates