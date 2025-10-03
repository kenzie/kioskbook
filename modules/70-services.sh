#!/bin/bash
#
# Module: 70-services.sh
# Description: Monitoring, recovery, and scheduled maintenance
#

set -euo pipefail

# Get script directory for accessing configs
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

module_name="Services & Monitoring"

log_module "$module_name" "Starting services and monitoring setup..."

# Create log directory
mkdir -p /var/log/kioskbook

# Install kiosk CLI
log_module "$module_name" "Installing kiosk CLI..."
cp "$SCRIPT_DIR/bin/kiosk" /usr/local/bin/kiosk
chmod +x /usr/local/bin/kiosk

# Install monitoring scripts
log_module "$module_name" "Installing monitoring scripts..."
cp "$SCRIPT_DIR/configs/monitoring/kioskbook-monitor" /usr/local/bin/kioskbook-monitor
chmod +x /usr/local/bin/kioskbook-monitor

cp "$SCRIPT_DIR/configs/monitoring/manage-swap" /usr/local/bin/manage-swap
chmod +x /usr/local/bin/manage-swap

cp "$SCRIPT_DIR/configs/monitoring/kioskbook-health" /usr/local/bin/kioskbook-health
chmod +x /usr/local/bin/kioskbook-health

# Configure log rotation
log_module "$module_name" "Configuring log rotation..."
cp "$SCRIPT_DIR/configs/logrotate/kioskbook" /etc/logrotate.d/kioskbook

# Configure journald limits
log_module "$module_name" "Configuring journald limits..."
mkdir -p /etc/systemd/journald.conf.d
cp "$SCRIPT_DIR/configs/systemd/journald.conf" /etc/systemd/journald.conf.d/kioskbook.conf
systemctl restart systemd-journald

# Install automatic recovery service and timer
log_module "$module_name" "Installing automatic recovery..."
cp "$SCRIPT_DIR/configs/systemd/kioskbook-recovery.service" /etc/systemd/system/kioskbook-recovery.service
cp "$SCRIPT_DIR/configs/systemd/kioskbook-recovery.timer" /etc/systemd/system/kioskbook-recovery.timer

systemctl daemon-reload
systemctl enable kioskbook-recovery.timer
systemctl start kioskbook-recovery.timer

# Setup scheduled maintenance
log_module "$module_name" "Setting up scheduled maintenance..."
cp "$SCRIPT_DIR/configs/monitoring/kioskbook-cron" /etc/cron.d/kioskbook
systemctl restart cron

# Clean up old packages
log_module "$module_name" "Cleaning up system..."
DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y
apt-get clean

log_module_success "$module_name" "Services and monitoring configured"
