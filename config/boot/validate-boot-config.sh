#!/bin/bash

# KioskBook Boot Configuration Validator
# Validates silent boot setup and Plymouth configuration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo "KioskBook Boot Configuration Validator"
echo "======================================"
echo

# Check if Route 19 logo exists
echo -n "Route 19 logo file: "
if [[ -f "$PROJECT_DIR/route19-logo.png" ]]; then
    logo_size=$(identify "$PROJECT_DIR/route19-logo.png" 2>/dev/null | awk '{print $3}' || echo "unknown")
    echo "✓ Found ($logo_size)"
else
    echo "✗ Missing route19-logo.png"
fi

# Check Plymouth theme files
echo -n "Plymouth theme script: "
if [[ -f "$SCRIPT_DIR/plymouth-theme.script" ]]; then
    echo "✓ Found"
else
    echo "✗ Missing"
fi

echo -n "Plymouth theme descriptor: "
if [[ -f "$SCRIPT_DIR/route19.plymouth" ]]; then
    echo "✓ Found"
else
    echo "✗ Missing"
fi

# Check kernel parameters configuration
echo -n "Kernel parameters config: "
if [[ -f "$SCRIPT_DIR/kernel-params.conf" ]]; then
    param_count=$(grep -v '^#' "$SCRIPT_DIR/kernel-params.conf" | grep -v '^$' | wc -l)
    echo "✓ Found ($param_count parameters)"
else
    echo "✗ Missing"
fi

# Check initramfs configuration
echo -n "Initramfs config: "
if [[ -f "$SCRIPT_DIR/initramfs.conf" ]]; then
    echo "✓ Found"
else
    echo "✗ Missing"
fi

# Validate GRUB configuration
echo -n "GRUB timeout setting: "
if grep -q "set timeout=0" "$PROJECT_DIR/config/grub.cfg"; then
    echo "✓ Zero timeout configured"
else
    echo "✗ Timeout not optimized"
fi

echo -n "GRUB silent boot params: "
if grep -q "quiet splash loglevel=0" "$PROJECT_DIR/config/grub.cfg"; then
    echo "✓ Silent boot enabled"
else
    echo "✗ Silent boot not configured"
fi

echo -n "GRUB Plymouth support: "
if grep -q "plymouth.enable=1" "$PROJECT_DIR/config/grub.cfg"; then
    echo "✓ Plymouth enabled"
else
    echo "✗ Plymouth not enabled"
fi

echo -n "GRUB AMD GPU params: "
if grep -q "amdgpu.dc=1" "$PROJECT_DIR/config/grub.cfg"; then
    echo "✓ AMD GPU optimizations enabled"
else
    echo "✗ AMD GPU optimizations missing"
fi

# Check installer module
echo -n "Boot installer module: "
if [[ -f "$PROJECT_DIR/installer/modules/20-boot.sh" ]]; then
    if [[ -x "$PROJECT_DIR/installer/modules/20-boot.sh" ]]; then
        echo "✓ Found and executable"
    else
        echo "⚠ Found but not executable"
    fi
else
    echo "✗ Missing"
fi

echo
echo "Configuration Summary:"
echo "====================="
echo "Target boot time: <5 seconds to Chromium display"
echo "Boot splash: Route 19 logo centered on black background"
echo "GRUB timeout: 0 seconds (instant boot)"
echo "Console output: Completely hidden"
echo "Plymouth theme: Custom Route 19 theme"
echo "Kernel params: Optimized for AMD GPU and silence"
echo "Initramfs: LZ4 compressed, minimal modules"
echo
echo "Expected boot sequence:"
echo "1. BIOS/UEFI POST (~1-2 seconds)"
echo "2. GRUB loads kernel instantly (0 timeout)"
echo "3. Plymouth shows Route 19 logo on black background"
echo "4. Systemd starts essential services only"
echo "5. X11 and Chromium launch automatically"
echo "6. Total time: <5 seconds to application display"