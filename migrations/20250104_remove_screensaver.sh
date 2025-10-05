#!/bin/bash
#
# Migration: Remove deprecated screensaver service
# Created: 2025-01-04
# Version: v0.2.5
#
# This migration removes the old kioskbook-screensaver service which has been
# deprecated in favor of the macOS-style notification system. The screensaver
# was replaced by notification overlays in v0.2.5.
#

set -euo pipefail

# Get script directory for sourcing common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source common functions if available
if [[ -f "$SCRIPT_DIR/lib/common.sh" ]]; then
    source "$SCRIPT_DIR/lib/common.sh"
else
    # Fallback log function if common.sh not available
    log_migration() {
        echo "[MIGRATION $(basename "$0")] $1"
    }
fi

# Migration name for logging
MIGRATION_NAME=$(basename "$0")

log_migration "$MIGRATION_NAME" "Checking for deprecated screensaver service..."

# Check if screensaver service exists
if systemctl list-unit-files | grep -q "kioskbook-screensaver"; then
    log_migration "$MIGRATION_NAME" "Found screensaver service, removing..."

    # Stop the service if running
    if systemctl is-active --quiet kioskbook-screensaver; then
        systemctl stop kioskbook-screensaver 2>/dev/null || true
        log_migration "$MIGRATION_NAME" "Service stopped"
    fi

    # Disable the service
    if systemctl is-enabled --quiet kioskbook-screensaver 2>/dev/null; then
        systemctl disable kioskbook-screensaver 2>/dev/null || true
        log_migration "$MIGRATION_NAME" "Service disabled"
    fi

    # Remove service file
    if [[ -f /etc/systemd/system/kioskbook-screensaver.service ]]; then
        rm -f /etc/systemd/system/kioskbook-screensaver.service
        log_migration "$MIGRATION_NAME" "Service file removed"
    fi

    # Remove timer if it exists
    if [[ -f /etc/systemd/system/kioskbook-screensaver.timer ]]; then
        systemctl stop kioskbook-screensaver.timer 2>/dev/null || true
        systemctl disable kioskbook-screensaver.timer 2>/dev/null || true
        rm -f /etc/systemd/system/kioskbook-screensaver.timer
        log_migration "$MIGRATION_NAME" "Service timer removed"
    fi

    # Reload systemd
    systemctl daemon-reload
    log_migration "$MIGRATION_NAME" "Systemd daemon reloaded"

    log_migration "$MIGRATION_NAME" "Screensaver service successfully removed"
else
    log_migration "$MIGRATION_NAME" "Screensaver service not found (already removed or fresh install)"
fi

# Clean up old screensaver script if it exists
if [[ -f /usr/local/bin/kioskbook-screensaver ]]; then
    rm -f /usr/local/bin/kioskbook-screensaver
    log_migration "$MIGRATION_NAME" "Old screensaver script removed"
fi

log_migration "$MIGRATION_NAME" "Migration complete"
