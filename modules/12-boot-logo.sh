#!/bin/bash
# KioskBook Boot Logo Module

# Setup boot logo with Route 19 branding
setup_boot_logo() {
    log_step "Setting Up Route 19 Boot Logo"
    
    # Install image processing and display tools
    chroot /mnt/root apk add imagemagick fbi
    
    # Create boot logo directory
    mkdir -p /mnt/root/usr/share/kioskbook
    
    # Copy Route 19 logo to system (if available)
    if [ -f "route19-logo.png" ]; then
        cp route19-logo.png /mnt/root/usr/share/kioskbook/route19-logo.png
        log_info "Route 19 logo copied to system"
    else
        log_warning "Route 19 logo not found, creating placeholder"
        # Create a simple placeholder logo
        chroot /mnt/root convert -size 200x200 xc:blue -pointsize 24 -fill white -gravity center -annotate +0+0 "Route 19" /usr/share/kioskbook/route19-logo.png
    fi
    
    # Create boot logo with Route 19 on black background
    chroot /mnt/root convert /usr/share/kioskbook/route19-logo.png \
        -resize 800x600 \
        -background black \
        -gravity center \
        -extent 1024x768 \
        /usr/share/kioskbook/route19-boot-logo.png
    
    # Create simple boot logo for framebuffer display
    chroot /mnt/root convert /usr/share/kioskbook/route19-logo.png \
        -resize 640x480 \
        -background black \
        -gravity center \
        -extent 640x480 \
        /usr/share/kioskbook/route19-fb-logo.png
    
    # Create boot splash script that displays the actual logo
    cat > /mnt/root/usr/share/kioskbook/boot-splash.sh << 'EOF'
#!/bin/bash
# KioskBook Boot Splash Screen with Route 19 Logo

# Clear screen
clear
echo -e "\033[2J\033[H"

# Try to display Route 19 logo using framebuffer
if [ -c /dev/fb0 ]; then
    # Display Route 19 logo on framebuffer
    fbi -d /dev/fb0 -T 1 /usr/share/kioskbook/route19-fb-logo.png &
    sleep 3
    killall fbi 2>/dev/null
fi

# Fallback: show simple text message
echo -e "\033[1;32mProfessional Kiosk Deployment Platform\033[0m"
echo -e "\033[1;33mRoute 19 KioskBook\033[0m"
echo
echo -e "\033[1;37mStarting KioskBook...\033[0m"
EOF
    
    chmod +x /mnt/root/usr/share/kioskbook/boot-splash.sh
    
    # Note: Direct EFI boot configured in setup_minimal_boot()
    # No GRUB configuration needed for kiosk system
    
    # Create startup script that displays Route 19 logo
    cat > /mnt/root/etc/local.d/route19-startup.start << 'EOF'
#!/bin/sh
# Route 19 Startup Display

# Display Route 19 logo on startup
if [ -f /usr/share/kioskbook/boot-splash.sh ]; then
    /usr/share/kioskbook/boot-splash.sh
fi
EOF
    
    chmod +x /mnt/root/etc/local.d/route19-startup.start
    
    # Create Route 19 desktop wallpaper
    mkdir -p /mnt/root/home/kiosk/.config/wallpaper
    chroot /mnt/root convert /usr/share/kioskbook/route19-logo.png \
        -resize 1920x1080 \
        -background black \
        -gravity center \
        -extent 1920x1080 \
        /home/kiosk/.config/wallpaper/route19-wallpaper.png
    
    chroot /mnt/root chown -R kiosk:kiosk /home/kiosk/.config
    
    # Create desktop configuration
    cat > /mnt/root/home/kiosk/.xinitrc << 'EOF'
#!/bin/bash
# KioskBook Desktop Configuration with Route 19 Branding

# Set Route 19 wallpaper
feh --bg-scale /home/kiosk/.config/wallpaper/route19-wallpaper.png &

# Set desktop environment
export DESKTOP_SESSION=kioskbook
export XDG_CURRENT_DESKTOP=kioskbook

# Start X server
exec startx
EOF
    
    chroot /mnt/root chown kiosk:kiosk /home/kiosk/.xinitrc
    chmod +x /mnt/root/home/kiosk/.xinitrc
    
    # Install feh for wallpaper management
    chroot /mnt/root apk add feh
    
    # Create simple MOTD with Route 19 branding
    cat > /mnt/root/etc/motd << 'EOF'
Professional Kiosk Deployment Platform
Route 19 KioskBook

Welcome to KioskBook!
EOF
    
    log_info "Route 19 boot logo configured with actual image display"
}
