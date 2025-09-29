# KioskBook Product Requirements Document

## Overview

KioskBook is a bulletproof kiosk deployment platform designed for unattended operation on Lenovo M75q-1 hardware. The system transforms a minimal Linux install into a fast-booting (<10 seconds), self-recovering kiosk that runs Vue.js applications in full-screen Chromium.

## Hardware Requirements

- **Primary Target**: Lenovo M75q-1 (AMD-based mini PC)
- **Storage**: NVMe SSD (will be completely erased)
- **Network**: Ethernet connection (fiber-backed)
- **Display**: Any monitor with HDMI/DisplayPort
- **Input**: Minimal (kiosk maintenance via ssh/tailscale only)

## Software Stack

- **Base OS**: Linux (minimal installation)
- **Bootloader**: Minimal, no boot menu
- **Display Server**: X11 (minimal, no desktop environment)
- **Browser**: Chromium (kiosk mode)
- **Runtime**: Node.js + npm
- **Application**: Vue.js web application
- **Remote Access**: SSH + Tailscale VPN

## Performance Requirements

- **Boot Time**: <10 seconds from power on to application display
- **Recovery Time**: <30 seconds for automatic service recovery
- **Uptime**: Designed for months of unattended operation
- **Offline Operation**: Must work without network using cached JSON data
- **Resource Usage**: Minimal linux footprint + application requirements

## Single-Script Installation Architecture

### One-Shot Installation (`install.sh`)

**Purpose**: Complete kiosk installation from bare metal linux install to running kiosk in one script execution

**Features:**
- Simple y/N disk wiping confirmation
- Minimal linux base system installation
- Automatic package installation (X11, Chromium, Node.js)
- Kiosk user creation and auto-login configuration
- Application repository cloning and setup
- Bootloader configuration (minimal, no boot menu)
- SSH and Tailscale setup for remote access
- Offline operation with cached JSON data support
- Complete system optimization for fast boot (network-independent)
- Automatic reboot into live kiosk

**Installation Process:**
1. **System Verification**: Check prerequisites (Debian, Node.js, npm, network)
2. **Boot Optimization**: Configure GRUB for instant boot, disable unnecessary services
3. **Display Stack**: Install X11 and Chromium with AMD GPU support
4. **Kiosk User**: Create kiosk user with auto-login and X11 auto-start
5. **Application Setup**: Clone Vue.js repository, install dependencies, build, and create systemd service
6. **Remote Access**: Install and configure Tailscale VPN with SSH access
7. **Monitoring**: Setup health checks and automatic service recovery
8. **Finalization**: Configure timezone, sync, and prepare for first boot

**Inputs:**
- GitHub repository for kiosk application (defaults to kenzie/lobby-display)
- Tailscale auth key for remote management (required)

**Outputs:**
- Fully functional kiosk system
- <10 second boot time to application
- Remote SSH and Tailscale access configured
- Automatic application startup
- Minimal bootloader (no visible boot menu)

**Success Criteria:**
- Single script execution completes without intervention
- System boots directly into kiosk application
- Remote access available immediately
- Application loads and displays correctly
- Boot time under 10 seconds consistently

## Security Model

- **Physical Access**: Assumed to be controlled environment
- **Network Security**: Tailscale VPN for remote access
- **System Security**: Minimal linux installation surface
- **Application Security**: Standard web application security practices
- **Update Security**: Automatic security patches enabled

## Recovery and Monitoring

### Automatic Recovery
- Service-level: Automatic restart of failed services
- Application-level: Browser and Node.js application monitoring
- System-level: Watchdog timers and health checks

### Logging and Diagnostics
- System logs: Standard system logging
- Application logs: Centralized application error logging
- Remote access: SSH + Tailscale for troubleshooting

### Update Management
- System updates: Automatic security patches
- Application updates: Git-based update mechanism
- Configuration updates: Remote configuration management

## Deployment Process

1. **Preparation**:
   - Install minimal Debian 13 (trixie) on Lenovo M75q-1
   - Install Node.js and npm
   - Ensure ethernet connectivity
   - Login as root

2. **One-Shot Installation**:
   ```bash
   git clone https://github.com/kenzie/kioskbook.git
   cd kioskbook
   bash install.sh
   ```
   - Script prompts for:
     - Vue.js application GitHub repository URL
     - Tailscale auth key for remote management
   - Installs all components automatically
   - Completes with automatic reboot into live kiosk

3. **Validation**:
   - System boots directly into kiosk application
   - Verify <10 second boot time achieved
   - Confirm application displays correctly in full-screen
   - Test remote SSH access via Tailscale
   - Verify kiosk services are running

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
