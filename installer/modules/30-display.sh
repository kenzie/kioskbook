#!/bin/bash
#
# 30-display-stack.sh - Display Stack Module
#
# Installs and configures X11, AMD GPU drivers, and Chromium browser
# for optimized kiosk display functionality with hardware acceleration.
#
# Features:
# - AMD GPU configuration with TearFree
# - Chromium kiosk mode with GPU acceleration
# - Hardware video decode acceleration
# - Power management disabled
# - Screen blanking disabled
#

set -e
set -o pipefail

# Import logging functions from main installer
source /dev/stdin <<< "$(declare -f log log_success log_warning log_error log_info add_rollback)"

# Module configuration
MODULE_NAME="30-display-stack"
KIOSK_URL="http://localhost:3000"

log_info "Starting display stack setup module..."

# Validate environment
validate_environment() {
    if [[ -z "$MOUNT_ROOT" || -z "$MOUNT_DATA" ]]; then
        log_error "Required mount points not set. Run partition and base modules first."
        exit 1
    fi
    
    if ! mountpoint -q "$MOUNT_ROOT"; then
        log_error "Root partition not mounted at $MOUNT_ROOT"
        exit 1
    fi
    
    # Check if kiosk user exists
    if ! chroot "$MOUNT_ROOT" id kiosk >/dev/null 2>&1; then
        log_error "Kiosk user not found. Run base system module first."
        exit 1
    fi
    
    log_info "Environment validation passed"
}

# Configure Xorg for AMD GPU
configure_xorg() {
    log_info "Configuring Xorg for AMD GPU with TearFree..."
    
    # Create Xorg configuration directory
    mkdir -p "$MOUNT_ROOT/etc/X11/xorg.conf.d"
    
    # AMD GPU configuration with TearFree and hardware acceleration
    cat > "$MOUNT_ROOT/etc/X11/xorg.conf.d/20-amdgpu.conf" << 'EOF'
# AMD GPU configuration for KioskBook
Section "Device"
    Identifier "AMD Graphics"
    Driver "amdgpu"
    Option "TearFree" "true"
    Option "DRI" "3"
    Option "AccelMethod" "glamor"
    Option "VariableRefresh" "true"
    Option "AsyncFlipSecondaries" "true"
EndSection

Section "Screen"
    Identifier "AMD Screen"
    Device "AMD Graphics"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1920x1080" "1680x1050" "1600x1200" "1400x1050" "1280x1024" "1024x768"
    EndSubSection
EndSection

Section "Extensions"
    Option "Composite" "Enable"
    Option "RENDER" "Enable"
    Option "DAMAGE" "Enable"
EndSection
EOF
    
    # Input device configuration
    cat > "$MOUNT_ROOT/etc/X11/xorg.conf.d/40-libinput.conf" << 'EOF'
# Input device configuration
Section "InputClass"
    Identifier "libinput pointer catchall"
    MatchIsPointer "on"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
EndSection

Section "InputClass"
    Identifier "libinput keyboard catchall"
    MatchIsKeyboard "on"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
EndSection

Section "InputClass"
    Identifier "libinput touchpad catchall"
    MatchIsTouchpad "on"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
EndSection
EOF
    
    # Server flags for optimal performance
    cat > "$MOUNT_ROOT/etc/X11/xorg.conf.d/99-serverflags.conf" << 'EOF'
# Server flags for kiosk operation
Section "ServerFlags"
    Option "BlankTime" "0"
    Option "StandbyTime" "0"
    Option "SuspendTime" "0"
    Option "OffTime" "0"
    Option "DontZap" "true"
    Option "DontVTSwitch" "true"
EndSection
EOF
    
    log_success "Xorg configured for AMD GPU with TearFree"
}

# Create kiosk startup script
create_kiosk_script() {
    log_info "Creating kiosk startup script..."
    
    # Create scripts directory
    mkdir -p "$MOUNT_ROOT/usr/local/bin"
    
    # Create the main kiosk startup script
    cat > "$MOUNT_ROOT/usr/local/bin/start-kiosk" << EOF
#!/bin/bash
#
# KioskBook Startup Script
#
# Launches Chromium in kiosk mode with optimal settings for
# AMD GPU acceleration, video playback performance, and Inter font rendering.
#

set -e

# Configuration
KIOSK_URL="$KIOSK_URL"
CHROMIUM_USER_DATA_DIR="/home/kiosk/.config/chromium"
CUSTOM_CSS_FILE="/home/kiosk/.config/chromium/custom.css"

# Logging function
log() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') [KIOSK] \$1" | tee -a /var/log/kiosk.log
}

log "Starting KioskBook kiosk application..."

# Wait for display to be ready
wait_for_display() {
    local retries=0
    while [ \$retries -lt 30 ]; do
        if xset q >/dev/null 2>&1; then
            log "Display is ready"
            return 0
        fi
        log "Waiting for display... (\$retries/30)"
        sleep 1
        retries=\$((retries + 1))
    done
    log "ERROR: Display not available after 30 seconds"
    exit 1
}

# Configure display settings
configure_display() {
    log "Configuring display settings..."
    
    # Disable screen blanking and power management completely
    xset s off
    xset s noblank
    xset -dpms
    
    # Disable DPMS (Display Power Management Signaling)
    xset dpms 0 0 0
    
    # Set display brightness to maximum (if supported)
    xrandr --output \$(xrandr | grep " connected" | head -1 | cut -d" " -f1) --brightness 1.0 2>/dev/null || true
    
    log "Display settings configured - screen blanking and power management disabled"
}

# Set up environment for optimal AMD GPU performance
setup_environment() {
    export DISPLAY=:0
    export XAUTHORITY=/home/kiosk/.Xauthority
    
    # AMD GPU environment variables for optimal performance
    export LIBVA_DRIVER_NAME=radeonsi
    export VDPAU_DRIVER=radeonsi
    export MESA_LOADER_DRIVER_OVERRIDE=radeonsi
    export AMD_VULKAN_ICD=RADV
    export RADV_PERFTEST=aco
    
    # Chrome/Chromium environment
    export CHROME_DEVEL_SANDBOX=/usr/lib/chromium/chrome-sandbox
    
    # Font rendering environment
    export FONTCONFIG_PATH=/etc/fonts
    
    log "Environment configured for AMD GPU optimization"
}

# Create custom CSS for Inter font enforcement
create_custom_css() {
    log "Creating custom CSS for Inter font..."
    
    mkdir -p "\$(dirname "\$CUSTOM_CSS_FILE")"
    
    cat > "\$CUSTOM_CSS_FILE" << 'CSS_EOF'
/* KioskBook Custom CSS - Inter Font Enforcement */

/* Force Inter font family on all elements */
* {
    font-family: 'Inter', 'Inter Variable', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, system-ui, sans-serif !important;
    font-feature-settings: 'ss01' 1, 'ss02' 1, 'cv01' 1, 'cv02' 1, 'cv05' 1, 'cv08' 1, 'cv11' 1;
    font-variant-ligatures: contextual;
    text-rendering: optimizeLegibility;
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
}

/* Ensure body uses Inter */
body, html {
    font-family: 'Inter', 'Inter Variable', sans-serif !important;
    font-weight: 400;
    line-height: 1.5;
}

/* Headings with Inter */
h1, h2, h3, h4, h5, h6 {
    font-family: 'Inter', 'Inter Variable', sans-serif !important;
    font-weight: 600;
}

/* Input elements */
input, textarea, select, button {
    font-family: 'Inter', 'Inter Variable', sans-serif !important;
}

/* Code and monospace elements use CaskaydiaCove */
code, pre, kbd, samp, tt, .monospace {
    font-family: 'CaskaydiaCove Nerd Font', 'CaskaydiaCove NF', 'Cascadia Code', 'Consolas', monospace !important;
    font-feature-settings: 'ss01' 1, 'ss19' 1, 'ss20' 1;
}

/* Optimize font rendering for displays */
body {
    -webkit-text-size-adjust: 100%;
    -webkit-font-feature-settings: 'kern' 1;
    -moz-font-feature-settings: 'kern' 1;
    font-feature-settings: 'kern' 1;
}

/* Smooth animations and transitions */
* {
    -webkit-backface-visibility: hidden;
    backface-visibility: hidden;
    -webkit-perspective: 1000;
    perspective: 1000;
}
CSS_EOF

    log "Custom CSS created for Inter font enforcement"
}

# Launch Chromium in kiosk mode with Inter font support
launch_chromium() {
    log "Launching Chromium in kiosk mode with Inter font configuration..."
    
    # Create custom CSS file
    create_custom_css
    
    # Chromium flags for optimal kiosk operation with Inter font
    local chromium_flags=(
        # Kiosk mode flags
        "--kiosk"
        "--start-fullscreen"
        "--no-first-run"
        "--disable-infobars"
        "--disable-session-crashed-bubble"
        "--disable-dev-shm-usage"
        "--user-data-dir=\$CHROMIUM_USER_DATA_DIR"
        
        # GPU acceleration flags
        "--enable-gpu"
        "--enable-gpu-compositing"
        "--enable-gpu-rasterization"
        "--enable-zero-copy"
        "--enable-native-gpu-memory-buffers"
        "--use-gl=desktop"
        "--enable-gpu-sandbox"
        
        # Video acceleration flags (AMD specific)
        "--enable-accelerated-video-decode"
        "--enable-accelerated-video-encode"
        "--enable-hardware-overlays"
        "--enable-oop-rasterization"
        "--canvas-oop-rasterization"
        "--enable-raw-draw"
        
        # Display and scaling flags (as requested)
        "--force-device-scale-factor=1.0"
        "--force-color-profile=srgb"
        "--disable-pinch"
        "--overscroll-history-navigation=0"
        
        # Font rendering flags for Inter
        "--font-render-hinting=slight"
        "--enable-font-antialiasing"
        "--disable-lcd-text"
        
        # Performance flags for smooth video playback
        "--max-tiles-for-interest-area=512"
        "--max-unused-resource-memory-usage-percentage=5"
        "--enable-fast-unload"
        "--enable-aggressive-domstorage-flushing"
        "--enable-gpu-memory-buffer-video-frames"
        "--enable-checker-imaging"
        
        # Security and stability flags
        "--no-sandbox"
        "--disable-web-security"
        "--disable-features=TranslateUI,VizDisplayCompositor"
        "--disable-ipc-flooding-protection"
        "--disable-background-timer-throttling"
        "--disable-renderer-backgrounding"
        "--disable-backgrounding-occluded-windows"
        
        # Cache and storage flags
        "--disk-cache-size=268435456"
        "--media-cache-size=268435456"
        "--aggressive-cache-discard"
        "--memory-pressure-off"
        
        # Network flags
        "--enable-tcp-fast-open"
        "--enable-async-dns"
        "--max-connections-per-host=10"
        
        # Audio flags for video playback
        "--autoplay-policy=no-user-gesture-required"
        "--enable-features=MediaSessionService,VaapiVideoDecoder"
        "--disable-audio-sandbox"
        
        # Custom CSS injection
        "--user-stylesheet=file://\$CUSTOM_CSS_FILE"
        
        # Disable unnecessary features for kiosk
        "--disable-notifications"
        "--disable-default-apps"
        "--disable-extensions"
        "--disable-plugins-discovery"
        "--disable-sync"
        "--disable-background-mode"
        "--disable-client-side-phishing-detection"
        "--disable-component-update"
        "--disable-domain-reliability"
        "--disable-features=MediaRouter,Translate"
        "--disable-logging"
        "--disable-breakpad"
        
        # AMD GPU specific flags for video acceleration
        "--enable-accelerated-mjpeg-decode"
        "--enable-accelerated-video"
        "--ignore-gpu-blacklist"
        "--enable-native-gpu-memory-buffers"
        "--use-vulkan"
        
        # Disable power saving that might affect video
        "--disable-gpu-power-management"
        "--disable-background-networking"
        
        # Target URL
        "\$KIOSK_URL"
    )
    
    # Launch Chromium with restart loop
    while true; do
        log "Starting Chromium with Inter font configuration..."
        
        # Ensure Chromium user data directory exists with proper permissions
        mkdir -p "\$CHROMIUM_USER_DATA_DIR"
        chown -R kiosk:kiosk "\$CHROMIUM_USER_DATA_DIR"
        
        chromium "\${chromium_flags[@]}" 2>&1 | tee -a /var/log/chromium.log || {
            log "Chromium crashed, restarting in 5 seconds..."
            sleep 5
        }
        
        log "Chromium exited, restarting in 3 seconds..."
        sleep 3
    done
}

# Main execution
main() {
    log "KioskBook startup initiated with Inter font support"
    
    setup_environment
    wait_for_display
    configure_display
    launch_chromium
}

# Execute main function
main "\$@"
EOF
    
    # Make script executable
    chmod +x "$MOUNT_ROOT/usr/local/bin/start-kiosk"
    
    log_success "Kiosk startup script created"
}

# Configure X11 session for kiosk user
configure_x11_session() {
    log_info "Configuring X11 session for kiosk user..."
    
    # Create .xinitrc for kiosk user
    mkdir -p "$MOUNT_DATA/home/kiosk"
    cat > "$MOUNT_DATA/home/kiosk/.xinitrc" << 'EOF'
#!/bin/bash
#
# KioskBook X11 session startup
#

# Start D-Bus session
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax --exit-with-session)
fi

# Disable screen blanking and power management completely
xset s off
xset s noblank
xset -dpms
xset dpms 0 0 0

# Set screen saver timeout to never
xset s 0 0

# Hide cursor after 1 second of inactivity
unclutter -idle 1 -root &

# Start window manager (lightweight)
openbox --config-file /dev/null &

# Start kiosk application
exec /usr/local/bin/start-kiosk
EOF
    
    # Make .xinitrc executable
    chmod +x "$MOUNT_DATA/home/kiosk/.xinitrc"
    
    # Create .bash_profile for auto-starting X11 on login
    cat > "$MOUNT_DATA/home/kiosk/.bash_profile" << 'EOF'
#!/bin/bash
#
# KioskBook auto-start X11 session
#

# Only start X11 if not already running and on tty1
if [[ -z "$DISPLAY" && "$XDG_VTNR" = "1" ]]; then
    echo "Starting X11 session..."
    exec startx
fi
EOF
    
    # Make .bash_profile executable
    chmod +x "$MOUNT_DATA/home/kiosk/.bash_profile"
    
    # Create symlinks from home directory on data partition to root partition
    ln -sf /data/home/kiosk/.xinitrc "$MOUNT_ROOT/home/kiosk/.xinitrc" || true
    ln -sf /data/home/kiosk/.bash_profile "$MOUNT_ROOT/home/kiosk/.bash_profile" || true
    
    # Create minimal OpenBox configuration
    mkdir -p "$MOUNT_DATA/home/kiosk/.config/openbox"
    cat > "$MOUNT_DATA/home/kiosk/.config/openbox/rc.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <resistance>
    <strength>10</strength>
    <screen_edge_strength>20</screen_edge_strength>
  </resistance>
  <focus>
    <focusNew>yes</focusNew>
    <followMouse>no</followMouse>
    <focusLast>yes</focusLast>
    <underMouse>no</underMouse>
    <focusDelay>200</focusDelay>
    <raiseOnFocus>no</raiseOnFocus>
  </focus>
  <placement>
    <policy>Smart</policy>
    <center>yes</center>
    <monitor>Any</monitor>
  </placement>
  <theme>
    <name>Clearlooks</name>
    <titleLayout>NLIMC</titleLayout>
    <keepBorder>yes</keepBorder>
    <animateIconify>yes</animateIconify>
  </theme>
  <desktops>
    <number>1</number>
    <firstdesk>1</firstdesk>
    <names>
      <name>Desktop</name>
    </names>
    <popupTime>875</popupTime>
  </desktops>
  <resize>
    <drawContents>yes</drawContents>
    <popupShow>Nonpixel</popupShow>
    <popupPosition>Center</popupPosition>
  </resize>
  <margins>
    <top>0</top>
    <bottom>0</bottom>
    <left>0</left>
    <right>0</right>
  </margins>
  <dock>
    <position>TopLeft</position>
    <floatingX>0</floatingX>
    <floatingY>0</floatingY>
    <noStrut>no</noStrut>
    <stacking>Above</stacking>
    <direction>Vertical</direction>
    <autoHide>no</autoHide>
    <hideDelay>300</hideDelay>
    <showDelay>300</showDelay>
    <moveButton>Middle</moveButton>
  </dock>
  <keyboard>
    <chainQuitKey>C-g</chainQuitKey>
  </keyboard>
  <mouse>
    <dragThreshold>8</dragThreshold>
    <doubleClickTime>200</doubleClickTime>
    <screenEdgeWarpTime>400</screenEdgeWarpTime>
  </mouse>
  <menu>
    <file>/dev/null</file>
    <hideDelay>200</hideDelay>
    <middle>no</middle>
    <submenuShowDelay>100</submenuShowDelay>
    <applicationIcons>yes</applicationIcons>
    <manageDesktops>yes</manageDesktops>
  </menu>
  <applications>
    <application name="chromium*">
      <decor>no</decor>
      <maximized>true</maximized>
      <fullscreen>yes</fullscreen>
    </application>
  </applications>
</openbox_config>
EOF
    
    log_success "X11 session configured"
}

# Install additional display packages
install_display_packages() {
    log_info "Installing additional display packages..."
    
    # Additional packages for optimal display experience
    local packages=(
        "openbox"           # Lightweight window manager
        "unclutter"         # Hide mouse cursor
        "xset"              # X11 settings utility
        "xrandr"            # Display configuration
        "mesa-demos"        # Graphics testing tools
        "libva-utils"       # Video acceleration utilities
        "vdpau-tools"       # Video decode acceleration tools
    )
    
    apk --root "$MOUNT_ROOT" add "${packages[@]}" || {
        log_error "Failed to install display packages"
        exit 1
    }
    
    log_success "Display packages installed"
}

# Configure autologin and display services
configure_autologin() {
    log_info "Configuring autologin for kiosk user..."
    
    # Configure inittab for autologin on tty1
    cat > "$MOUNT_ROOT/etc/inittab" << 'EOF'
# /etc/inittab - KioskBook inittab configuration

# System initialization
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default

# Set up autologin on tty1 for kiosk user
tty1::respawn:/sbin/agetty --autologin kiosk --noclear tty1 linux

# Regular getty for other ttys (for emergency access)
tty2::respawn:/sbin/agetty 38400 tty2 linux
tty3::respawn:/sbin/agetty 38400 tty3 linux

# Shutdown and reboot
::shutdown:/sbin/openrc shutdown
::restart:/sbin/reboot
::ctrlaltdel:/sbin/reboot
EOF

    log_success "Autologin configured for kiosk user on tty1"
}

# Configure OpenRC services for display
configure_display_services() {
    log_info "Configuring OpenRC services for display..."
    
    # Create OpenRC service for kiosk display (backup method)
    cat > "$MOUNT_ROOT/etc/init.d/kiosk-display" << 'EOF'
#!/sbin/openrc-run

name="kiosk-display"
description="KioskBook Display Service (Backup)"

depend() {
    need localmount
    after bootmisc gpu-optimize
    provide kiosk-display
}

start() {
    ebegin "Starting kiosk display service"
    
    # Ensure proper permissions for kiosk user
    chown -R kiosk:kiosk /home/kiosk /data/home/kiosk
    
    # This service is primarily for backup - autologin handles the main startup
    eend 0
}

stop() {
    ebegin "Stopping kiosk display service"
    
    # Kill any running X sessions for kiosk user
    pkill -u kiosk || true
    
    eend 0
}
EOF
    
    # Make service executable
    chmod +x "$MOUNT_ROOT/etc/init.d/kiosk-display"
    
    # Enable the service for consistency
    chroot "$MOUNT_ROOT" rc-update add kiosk-display default || {
        log_warning "Failed to enable kiosk-display service"
    }
    
    log_success "Display services configured"
}

# Configure GPU-specific optimizations
configure_gpu_optimizations() {
    log_info "Configuring AMD GPU optimizations..."
    
    # Create GPU optimization script
    cat > "$MOUNT_ROOT/usr/local/bin/gpu-optimize" << 'EOF'
#!/bin/bash
#
# AMD GPU optimization script for KioskBook
#

# Set GPU performance profile
echo "performance" > /sys/class/drm/card0/device/power_dpm_force_performance_level 2>/dev/null || true

# Set GPU clock speeds (if supported)
echo "high" > /sys/class/drm/card0/device/power_dpm_state 2>/dev/null || true

# Enable GPU power management
echo "auto" > /sys/class/drm/card0/device/power/control 2>/dev/null || true

# Configure video memory
echo 1 > /sys/module/amdgpu/parameters/audio 2>/dev/null || true
echo 1 > /sys/module/amdgpu/parameters/dpm 2>/dev/null || true
EOF
    
    chmod +x "$MOUNT_ROOT/usr/local/bin/gpu-optimize"
    
    # Create systemd service to run GPU optimizations at boot
    cat > "$MOUNT_ROOT/etc/init.d/gpu-optimize" << 'EOF'
#!/sbin/openrc-run

name="gpu-optimize"
description="AMD GPU Optimization Service"

depend() {
    after modules
    before kiosk-display
}

start() {
    ebegin "Optimizing AMD GPU settings"
    /usr/local/bin/gpu-optimize
    eend $?
}
EOF
    
    chmod +x "$MOUNT_ROOT/etc/init.d/gpu-optimize"
    chroot "$MOUNT_ROOT" rc-update add gpu-optimize boot || {
        log_warning "Failed to enable gpu-optimize service"
    }
    
    log_success "GPU optimizations configured"
}

# Create log directories
create_log_directories() {
    log_info "Creating log directories..."
    
    # Create persistent log directories on data partition
    mkdir -p "$MOUNT_DATA/var/log"
    
    # Create kiosk-specific log directory
    mkdir -p "$MOUNT_DATA/var/log/kiosk"
    
    # Set permissions
    chroot "$MOUNT_ROOT" chown -R kiosk:kiosk /data/var/log/kiosk
    
    log_success "Log directories created"
}

# Validate display configuration
validate_display_config() {
    log_info "Validating display configuration..."
    
    # Check essential files
    local essential_files=(
        "$MOUNT_ROOT/etc/X11/xorg.conf.d/20-amdgpu.conf"
        "$MOUNT_ROOT/usr/local/bin/start-kiosk"
        "$MOUNT_DATA/home/kiosk/.xinitrc"
        "$MOUNT_ROOT/etc/init.d/kiosk-display"
    )
    
    for file in "${essential_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Essential display file missing: $file"
            exit 1
        fi
    done
    
    # Check if packages are installed
    local check_packages=("openbox" "unclutter" "mesa-demos")
    for pkg in "${check_packages[@]}"; do
        if ! chroot "$MOUNT_ROOT" apk info -e "$pkg" >/dev/null 2>&1; then
            log_error "Display package not installed: $pkg"
            exit 1
        fi
    done
    
    log_success "Display configuration validation passed"
}

# Main display stack setup
main() {
    log_info "=========================================="
    log_info "Module: Display Stack Setup"
    log_info "=========================================="
    
    validate_environment
    configure_xorg
    install_display_packages
    create_kiosk_script
    configure_x11_session
    configure_autologin
    configure_display_services
    configure_gpu_optimizations
    create_log_directories
    validate_display_config
    
    log_success "Display stack setup completed successfully"
    log_info "Chromium kiosk configured with:"
    log_info "  - Target URL: $KIOSK_URL"
    log_info "  - AMD GPU acceleration with TearFree"
    log_info "  - Inter font with CSS injection"
    log_info "  - Auto-login on tty1 -> X11 -> Chromium kiosk"
    log_info "  - Screen blanking and power management disabled"
    log_info "  - Optimal video playback performance"
}

# Execute main function
main "$@"