#!/bin/sh
# Alpine Linux Kiosk Setup Script
# Run this after Alpine base installation is complete

set -e

echo "Alpine Linux Kiosk Configuration"
echo "================================="

# Update package repositories
echo "Updating package repositories..."
apk update && apk upgrade

# Enable community repository
echo "Enabling community repository..."
sed -i '/community/s/^#//' /etc/apk/repositories
apk update

# Install X11 and display drivers
echo "Installing X11 and display drivers..."
setup-xorg-base

# Install packages individually to handle missing packages gracefully
echo "Installing display and input packages..."
for pkg in xf86-video-fbdev xf86-video-vesa xf86-input-evdev xf86-input-keyboard xf86-input-mouse mesa-dri-gallium dbus xrandr xset; do
    if apk add "$pkg" 2>/dev/null; then
        echo "✓ Installed $pkg"
    else
        echo "⚠ Skipping $pkg (not available)"
    fi
done

# Try optional packages
echo "Installing optional packages..."
for pkg in xf86-video-intel xf86-video-amdgpu setxkbmap kbd; do
    if apk add "$pkg" 2>/dev/null; then
        echo "✓ Installed $pkg"
    else
        echo "⚠ Skipping $pkg (not available)"
    fi
done

# Install essential packages
echo "Installing essential packages..."
for pkg in chromium nodejs npm git curl; do
    if apk add "$pkg" 2>/dev/null; then
        echo "✓ Installed $pkg"
    else
        echo "❌ Failed to install $pkg - this may cause issues"
    fi
done

# Install Tailscale for remote access
echo "Installing Tailscale..."
if curl -fsSL https://tailscale.com/install.sh | sh; then
    rc-update add tailscaled default || echo "⚠ Could not enable tailscaled service"
    echo "✓ Tailscale installed"
else
    echo "⚠ Tailscale installation failed - continuing without it"
fi

# Create kiosk user
echo "Creating kiosk user..."
adduser -D -s /bin/sh kiosk
adduser kiosk input
adduser kiosk video

# Get repository URL
echo ""
echo "Enter the Git repository URL for your kiosk application:"
echo "Example: https://github.com/kenzie/lobby-display.git"
read -p "Repository URL: " REPO_URL

if [ -z "$REPO_URL" ]; then
    REPO_URL="https://github.com/kenzie/lobby-display.git"
    echo "Using default: $REPO_URL"
fi

# Clone and setup kiosk application
echo "Setting up kiosk application..."
mkdir -p /opt/kiosk-app
cd /opt/kiosk-app
git clone "$REPO_URL" .
chown -R kiosk:kiosk /opt/kiosk-app

# Install application dependencies
if [ -f "package.json" ]; then
    echo "Installing application dependencies..."
    sudo -u kiosk npm install
    
    # Build if needed
    if grep -q '"build"' package.json; then
        echo "Building application..."
        sudo -u kiosk npm run build
    fi
fi

# Create kiosk startup script
echo "Creating kiosk startup script..."
cat > /home/kiosk/.xinitrc << 'EOF'
#!/bin/sh

# Disable screensaver and power management
xset s off
xset -dpms
xset s noblank

# Set background
xsetroot -solid black

# Start application server if needed
cd /opt/kiosk-app
if [ -f package.json ] && grep -q '"start"' package.json; then
    npm start &
    sleep 5
fi

# Start Chromium in kiosk mode
exec chromium-browser \
    --kiosk \
    --no-sandbox \
    --disable-dev-shm-usage \
    --disable-gpu \
    --disable-extensions \
    --disable-plugins \
    --disable-translate \
    --disable-background-timer-throttling \
    --disable-backgrounding-occluded-windows \
    --disable-renderer-backgrounding \
    --start-fullscreen \
    --window-size=1920,1080 \
    http://localhost:3000
EOF

chmod +x /home/kiosk/.xinitrc
chown kiosk:kiosk /home/kiosk/.xinitrc

# Configure auto-login for kiosk user
echo "Configuring auto-login..."
sed -i 's/^tty1:.*$/tty1::respawn:\/bin\/login -f kiosk/' /etc/inittab

# Configure auto-start X
echo "Configuring auto-start X..."
cat >> /home/kiosk/.profile << 'EOF'

# Auto-start X if not already running
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec startx
fi
EOF

chown kiosk:kiosk /home/kiosk/.profile

# Enable services
echo "Enabling services..."
rc-update add dbus default

# Create systemd-style service for application management
cat > /etc/init.d/kiosk-app << 'EOF'
#!/sbin/openrc-run

name="kiosk-app"
description="Kiosk Application Manager"
pidfile="/var/run/kiosk-app.pid"

depend() {
    need net
    after networking
}

start() {
    ebegin "Starting kiosk application"
    start-stop-daemon --start --background \
        --pidfile "$pidfile" --make-pidfile \
        --user kiosk --chdir /opt/kiosk-app \
        --exec /bin/sh -- -c "npm start"
    eend $?
}

stop() {
    ebegin "Stopping kiosk application"
    start-stop-daemon --stop --pidfile "$pidfile"
    eend $?
}
EOF

chmod +x /etc/init.d/kiosk-app
rc-update add kiosk-app default

echo ""
echo "Kiosk setup complete!"
echo ""
echo "Configuration:"
echo "- Kiosk user: kiosk (auto-login enabled)"
echo "- Application: $REPO_URL" 
echo "- Browser: Chromium in kiosk mode"
echo "- Remote access: Tailscale (authenticate with 'tailscale up')"
echo ""
echo "The system will auto-start the kiosk on reboot."
echo "Reboot now? (y/N)"
read -p "> " REBOOT

if [ "$REBOOT" = "y" ] || [ "$REBOOT" = "Y" ]; then
    reboot
fi