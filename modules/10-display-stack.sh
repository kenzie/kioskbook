#!/bin/bash
#
# KioskBook Module: Display Stack Installation
#
# Installs X11, Chromium, fonts, and display utilities.
# This module is idempotent - safe to re-run.
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
KIOSK_USER="kiosk"
KIOSK_HOME="/home/kiosk"

log_info() {
    echo -e "${GREEN}[DISPLAY]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[DISPLAY]${NC} $1"
}

log_error() {
    echo -e "${RED}[DISPLAY]${NC} $1"
    exit 1
}

# Check if display stack is already installed
check_existing() {
    if command -v chromium >/dev/null 2>&1 && command -v X >/dev/null 2>&1; then
        log_info "Display stack already installed"
        chromium_version=$(chromium --version | head -1)
        log_info "Chromium: $chromium_version"
        return 0
    fi
    return 1
}

# Install X11 and Chromium
install_display_packages() {
    log_info "Installing X11 and Chromium packages..."
    
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        xorg \
        xserver-xorg-video-amdgpu \
        chromium \
        chromium-driver \
        unclutter \
        x11-xserver-utils \
        fonts-inter \
        unzip \
        curl \
        fbi \
        xdotool
    
    log_info "Display packages installed"
}

# Install additional fonts
install_fonts() {
    log_info "Installing additional fonts..."
    
    # Install Caskaydia Cove Nerd Font
    mkdir -p /usr/local/share/fonts/nerd-fonts
    cd /usr/local/share/fonts/nerd-fonts
    
    if [ ! -f "CascadiaCode.zip" ]; then
        curl -fLo "CascadiaCode.zip" https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.zip
        unzip -o CascadiaCode.zip
        rm CascadiaCode.zip
    fi
    
    # Configure font defaults
    cat > /etc/fonts/local.conf << 'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
    <!-- Set Inter as default sans-serif font -->
    <alias>
        <family>sans-serif</family>
        <prefer>
            <family>Inter</family>
        </prefer>
    </alias>

    <!-- Set Caskaydia Cove Nerd Font as default monospace font -->
    <alias>
        <family>monospace</family>
        <prefer>
            <family>CaskaydiaCove Nerd Font</family>
            <family>CaskaydiaCove Nerd Font Mono</family>
        </prefer>
    </alias>

    <!-- Also set for common generic families -->
    <match target="pattern">
        <test qual="any" name="family">
            <string>sans</string>
        </test>
        <edit name="family" mode="prepend" binding="same">
            <string>Inter</string>
        </edit>
    </match>

    <match target="pattern">
        <test qual="any" name="family">
            <string>mono</string>
        </test>
        <edit name="family" mode="prepend" binding="same">
            <family>CaskaydiaCove Nerd Font Mono</family>
        </edit>
    </match>
</fontconfig>
EOF
    
    # Rebuild font cache
    fc-cache -f -v > /dev/null 2>&1
    
    log_info "Fonts installed and configured"
}

# Configure kiosk user X11 setup
configure_kiosk_x11() {
    log_info "Configuring kiosk user X11 setup..."
    
    # Create .xinitrc for kiosk user
    cat > $KIOSK_HOME/.xinitrc << 'EOF'
#!/bin/bash
# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Hide cursor
unclutter -idle 0.1 &

# Wait for kiosk app to be ready
while ! curl -s http://localhost:3000 > /dev/null; do
    sleep 1
done

# Detect display resolution
RESOLUTION=$(xrandr | grep '\*' | awk '{print $1}' | head -1)
WIDTH=$(echo $RESOLUTION | cut -d'x' -f1)
HEIGHT=$(echo $RESOLUTION | cut -d'x' -f2)

# Launch Chromium in kiosk mode with cache disabled for always-fresh content
chromium --kiosk --start-fullscreen --window-size=$WIDTH,$HEIGHT \
    --noerrdialogs --disable-infobars --no-first-run \
    --disable-session-crashed-bubble --disable-features=TranslateUI \
    --check-for-update-interval=31536000 \
    --disable-http-cache --disable-cache --disk-cache-size=1 \
    http://localhost:3000
EOF
    chmod +x $KIOSK_HOME/.xinitrc
    
    # Configure .bash_profile to start X
    cat > $KIOSK_HOME/.bash_profile << 'EOF'
if [[ -z $DISPLAY ]] && [[ $(tty) = /dev/tty1 ]]; then
    exec startx
fi
EOF
    
    chown -R $KIOSK_USER:$KIOSK_USER $KIOSK_HOME
    
    log_info "Kiosk user X11 configuration updated"
}

# Main function
main() {
    echo -e "${CYAN}=== Display Stack Module ===${NC}"
    
    # Skip if already installed and working
    if check_existing; then
        log_info "Display stack already installed, checking configuration..."
        configure_kiosk_x11
        return 0
    fi
    
    install_display_packages
    install_fonts
    configure_kiosk_x11
    
    log_info "Display stack installation complete"
}

main "$@"
