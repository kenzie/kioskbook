#!/bin/bash
#
# Module: 50-app.sh
# Description: Node.js installation and application deployment
#

set -euo pipefail

# Get script directory for accessing configs
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

module_name="Application"
APP_DIR="/opt/kioskbook"
APP_USER="kioskbook-app"
DEFAULT_REPO="https://github.com/kenzie/lobby-display"

log_module "$module_name" "Starting application installation..."

# Create dedicated service user if it doesn't exist
if ! id "$APP_USER" &>/dev/null; then
    log_module "$module_name" "Creating service user: $APP_USER"
    useradd -r -s /bin/false -d "$APP_DIR" -c "KioskBook Application Service" "$APP_USER"
else
    log_module "$module_name" "Service user $APP_USER already exists"
fi

# Use provided GitHub repo or default
GITHUB_REPO="${GITHUB_REPO:-$DEFAULT_REPO}"
log_module "$module_name" "Using repository: $GITHUB_REPO"

# Install Node.js 20 from NodeSource
log_module "$module_name" "Installing Node.js 20..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs

# Clone or update application
if [[ -d "$APP_DIR" ]]; then
    log_module "$module_name" "Application directory exists, updating..."
    cd "$APP_DIR"
    if [[ -d .git ]]; then
        git pull
    else
        log_module "$module_name" "Not a git repository, removing and cloning fresh..."
        cd /
        rm -rf "$APP_DIR"
        git clone "$GITHUB_REPO" "$APP_DIR"
        cd "$APP_DIR"
    fi
else
    log_module "$module_name" "Cloning application..."
    git clone "$GITHUB_REPO" "$APP_DIR"
    cd "$APP_DIR"
fi

# Install dependencies
log_module "$module_name" "Installing dependencies..."
npm ci

# Install serve for production static file serving
log_module "$module_name" "Installing serve globally..."
npm install -g serve

# Build production version
log_module "$module_name" "Building production version..."
npm run build

# Set ownership to service user
log_module "$module_name" "Setting ownership to $APP_USER..."
chown -R "$APP_USER:$APP_USER" "$APP_DIR"

# Install systemd service
log_module "$module_name" "Installing systemd service..."
cp "$SCRIPT_DIR/configs/systemd/kioskbook-app.service" /etc/systemd/system/kioskbook-app.service

# Enable and restart service
systemctl daemon-reload
systemctl enable kioskbook-app
systemctl restart kioskbook-app

log_module_success "$module_name" "Application installed and running"
