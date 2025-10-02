#!/bin/bash
#
# KioskBook Migration Script: v0.1.0 → v0.2.0
#
# Safely migrates existing v0.1.0 installations to the new modular architecture.
# This script is idempotent and safe to run multiple times.
#
# Usage: sudo ./migrate-from-v0.1.0.sh
#

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Configuration
readonly REPO_DIR="/opt/kioskbook-repo"
readonly APP_DIR="/opt/kioskbook"
readonly BACKUP_DIR="/var/backups/kioskbook-migration-$(date +%Y%m%d-%H%M%S)"

# Logging
log() { printf "${CYAN}[MIGRATE]${NC} %s\n" "$1"; }
log_success() { printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"; }
log_warning() { printf "${YELLOW}[WARNING]${NC} %s\n" "$1"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; exit 1; }

# Banner
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "═══════════════════════════════════════════════════════"
    echo "     KioskBook Migration: v0.1.0 → v0.2.0"
    echo "     Upgrading to Modular Architecture"
    echo "═══════════════════════════════════════════════════════"
    echo -e "${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    # Must be root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
    fi

    # Check if this is a v0.1.0 system
    if [[ ! -f /etc/systemd/system/kioskbook-app.service ]]; then
        log_error "This doesn't appear to be a KioskBook v0.1.0 installation"
    fi

    # Check if already migrated
    if [[ -f /etc/kioskbook/version ]]; then
        local current_version=$(cat /etc/kioskbook/version)
        log_warning "System already shows version: $current_version"
        echo -n "Continue with migration anyway? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log "Migration cancelled"
            exit 0
        fi
    fi

    # Check network connectivity
    if ! ping -c 1 github.com >/dev/null 2>&1; then
        log_error "Network connectivity required for migration"
    fi

    log_success "Prerequisites verified"
}

# Backup current configuration
backup_configuration() {
    log "Creating backup of current configuration..."

    mkdir -p "$BACKUP_DIR"

    # Backup systemd service files
    if [[ -f /etc/systemd/system/kioskbook-app.service ]]; then
        cp /etc/systemd/system/kioskbook-app.service "$BACKUP_DIR/"
    fi

    # Backup LightDM config
    if [[ -f /etc/lightdm/lightdm.conf ]]; then
        cp /etc/lightdm/lightdm.conf "$BACKUP_DIR/"
    fi

    # Backup OpenBox config
    if [[ -d /home/kiosk/.config/openbox ]]; then
        cp -r /home/kiosk/.config/openbox "$BACKUP_DIR/"
    fi

    # Backup GRUB config
    if [[ -f /etc/default/grub ]]; then
        cp /etc/default/grub "$BACKUP_DIR/"
    fi

    log_success "Backup created at: $BACKUP_DIR"
}

# Clone modular repository
clone_modular_repo() {
    log "Cloning modular KioskBook repository..."

    # Remove old repo if exists
    if [[ -d "$REPO_DIR" ]]; then
        log_warning "Removing existing repository at $REPO_DIR"
        rm -rf "$REPO_DIR"
    fi

    # Clone new modular repository
    git clone https://github.com/kenzie/kioskbook.git "$REPO_DIR"

    log_success "Repository cloned to $REPO_DIR"
}

# Install kiosk CLI
install_kiosk_cli() {
    log "Installing kiosk management CLI..."

    if [[ ! -f "$REPO_DIR/bin/kiosk" ]]; then
        log_error "kiosk CLI not found in repository"
    fi

    cp "$REPO_DIR/bin/kiosk" /usr/local/bin/kiosk
    chmod +x /usr/local/bin/kiosk

    log_success "kiosk CLI installed to /usr/local/bin/kiosk"
}

# Ensure kiosk user has sudo access
ensure_kiosk_sudo() {
    log "Ensuring kiosk user has sudo access..."

    if ! groups kiosk | grep -q sudo; then
        usermod -aG sudo kiosk
        log "Added kiosk to sudo group"
    else
        log "Kiosk user already in sudo group"
    fi

    log_success "Kiosk user sudo access configured"
}

# Update configurations (idempotent)
update_configurations() {
    log "Updating system configurations..."

    # Load common functions
    source "$REPO_DIR/lib/common.sh"

    # Update configs that are safe to refresh
    log "Updating font configuration..."
    mkdir -p /etc/fonts/conf.d
    cp "$REPO_DIR/configs/fonts/10-inter-default.conf" /etc/fonts/conf.d/
    fc-cache -fv >/dev/null 2>&1

    log "Updating OpenBox configuration..."
    cp "$REPO_DIR/configs/openbox/autostart" /home/kiosk/.config/openbox/autostart
    chmod +x /home/kiosk/.config/openbox/autostart
    chown -R kiosk:kiosk /home/kiosk/.config

    log "Updating systemd configurations..."
    cp "$REPO_DIR/configs/systemd/silent.conf" /etc/systemd/system.conf.d/silent.conf
    cp "$REPO_DIR/configs/systemd/journald.conf" /etc/systemd/journald.conf.d/kioskbook.conf
    cp "$REPO_DIR/configs/systemd/getty-override.conf" /etc/systemd/system/getty@tty1.service.d/override.conf

    log_success "Configurations updated"
}

# Install monitoring and recovery (70-services module)
install_monitoring() {
    log "Installing monitoring and recovery system..."

    # Load common functions
    source "$REPO_DIR/lib/common.sh"

    # Run the services module to install monitoring
    bash "$REPO_DIR/modules/70-services.sh"

    log_success "Monitoring and recovery installed"
}

# Update GRUB for silent boot
update_grub_config() {
    log "Updating GRUB configuration for silent boot..."

    # Load common functions
    source "$REPO_DIR/lib/common.sh"

    # Run the boot module
    bash "$REPO_DIR/modules/60-boot.sh"

    log_success "GRUB configuration updated"
}

# Update version
update_version() {
    log "Updating version information..."

    mkdir -p /etc/kioskbook

    if [[ -f "$REPO_DIR/VERSION" ]]; then
        cp "$REPO_DIR/VERSION" /etc/kioskbook/version
        local new_version=$(cat /etc/kioskbook/version)
        log "Updated to version: $new_version"
    else
        echo "0.2.0" > /etc/kioskbook/version
        log "Set version to: 0.2.0"
    fi

    log_success "Version updated"
}

# Restart services if needed
restart_services() {
    log "Checking if services need restart..."

    # Reload systemd
    systemctl daemon-reload

    # Restart journald for new config
    systemctl restart systemd-journald

    # Ask before restarting display (will log out kiosk user)
    echo -e "\n${YELLOW}The display service needs to be restarted to apply changes.${NC}"
    echo -n "Restart display service now? (y/N): "
    read -r response

    if [[ "$response" =~ ^[Yy]$ ]]; then
        systemctl restart lightdm
        log_success "Display service restarted"
    else
        log_warning "Display service not restarted. Changes will apply after reboot."
    fi
}

# Show completion
show_completion() {
    local version=$(cat /etc/kioskbook/version 2>/dev/null || echo "unknown")

    echo -e "\n${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}     Migration Complete!${NC}"
    echo -e "${GREEN}     Version: $version${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"

    echo -e "\n${CYAN}What's New in v0.2.0:${NC}"
    echo -e "  ✅ Modular architecture for easy updates"
    echo -e "  ✅ kiosk CLI for system management"
    echo -e "  ✅ Automated monitoring every 5 minutes"
    echo -e "  ✅ Automated recovery for failed services"
    echo -e "  ✅ Scheduled maintenance (daily/weekly)"
    echo -e "  ✅ Log rotation with 7-day retention"
    echo -e "  ✅ Version tracking"

    echo -e "\n${CYAN}New Management Commands:${NC}"
    echo -e "  Status: ${YELLOW}kiosk status${NC}"
    echo -e "  Health: ${YELLOW}kiosk health${NC}"
    echo -e "  Logs: ${YELLOW}kiosk logs -f${NC}"
    echo -e "  Version: ${YELLOW}kiosk version${NC}"
    echo -e "  Modules: ${YELLOW}kiosk modules${NC}"
    echo -e "  Update: ${YELLOW}sudo kiosk update <module>${NC}"

    echo -e "\n${CYAN}Backup Location:${NC}"
    echo -e "  $BACKUP_DIR"

    echo -e "\n${CYAN}Next Steps:${NC}"
    echo -e "1. Test the new kiosk CLI: ${YELLOW}kiosk status${NC}"
    echo -e "2. Check health: ${YELLOW}kiosk health --detailed${NC}"
    echo -e "3. View monitoring: ${YELLOW}systemctl status kioskbook-recovery.timer${NC}"
    echo -e "4. ${YELLOW}Reboot${NC} to apply all changes if display wasn't restarted"

    echo -e "\n${CYAN}Module Updates:${NC}"
    echo -e "You can now update individual modules without full reinstall:"
    echo -e "  ${YELLOW}sudo kiosk update 30-display${NC}  # Update display config"
    echo -e "  ${YELLOW}sudo kiosk update 70-services${NC} # Update monitoring"
    echo -e "  ${YELLOW}sudo kiosk update all${NC}         # Update everything"
}

# Main migration
main() {
    show_banner
    check_prerequisites
    backup_configuration
    clone_modular_repo
    install_kiosk_cli
    ensure_kiosk_sudo
    update_configurations
    install_monitoring
    update_grub_config
    update_version
    restart_services
    show_completion
}

# Run migration
main "$@"
