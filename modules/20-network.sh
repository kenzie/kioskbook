#!/bin/bash
#
# Module: 20-network.sh
# Description: Network configuration, SSH optimization, and Tailscale VPN
#

set -euo pipefail

# Get script directory for accessing configs
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

module_name="Network & SSH"

log_module "$module_name" "Starting network configuration..."

# Optimize SSH configuration
log_module "$module_name" "Optimizing SSH configuration..."
ssh_config="/etc/ssh/sshd_config"
updated=false

# Add UseDNS no if not present
if ! grep -q "^UseDNS no" "$ssh_config"; then
    echo "UseDNS no" >> "$ssh_config"
    updated=true
    log_module "$module_name" "Added UseDNS no"
fi

# Add GSSAPIAuthentication no if not present
if ! grep -q "^GSSAPIAuthentication no" "$ssh_config"; then
    echo "GSSAPIAuthentication no" >> "$ssh_config"
    updated=true
    log_module "$module_name" "Added GSSAPIAuthentication no"
fi

# Pre-generate SSH host keys if missing
if [[ ! -f /etc/ssh/ssh_host_rsa_key ]]; then
    ssh-keygen -A
    updated=true
    log_module "$module_name" "Generated SSH host keys"
fi

if [[ "$updated" == true ]]; then
    systemctl restart ssh
    log_module "$module_name" "SSH configuration updated and restarted"
fi

# Install Tailscale if auth key provided
if [[ -n "${TAILSCALE_KEY:-}" ]]; then
    log_module "$module_name" "Installing Tailscale VPN..."

    # Add Tailscale repository
    curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list

    # Install Tailscale
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y tailscale

    # Configure Tailscale
    tailscale up --authkey="$TAILSCALE_KEY" --ssh --hostname="kioskbook-$(hostname)"

    log_module "$module_name" "Tailscale configured"
else
    log_module "$module_name" "Skipping Tailscale (no auth key provided)"
fi

log_module_success "$module_name" "Network configuration complete"
