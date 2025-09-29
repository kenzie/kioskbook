#!/bin/bash
# KioskBook Application Setup Module

# Setup kiosk display app
setup_kiosk_app() {
    log_step "Setting Up Kiosk Display Application"
    
    # Create app directory
    mkdir -p /mnt/root/opt/kiosk-app
    
    # Create clone script for first boot
    log_info "Will clone and build Vue.js kiosk app from GitHub: $GITHUB_REPO"
    
    # Clone during first boot to ensure network is available
    cat > /mnt/root/etc/local.d/clone-app.start << EOF
#!/bin/sh
if [ ! -f /opt/kiosk-app/.git/config ]; then
    cd /opt/kiosk-app
    git clone $GITHUB_URL .
    chown -R kiosk:kiosk /opt/kiosk-app
    
    # Install Node.js dependencies
    if [ -f package.json ]; then
        npm install
        
        # Build Vue.js app for production
        if [ -f vue.config.js ] || grep -q "vue" package.json; then
            npm run build
        fi
    fi
fi
EOF
    
    chmod +x /mnt/root/etc/local.d/clone-app.start
    
    # Create kiosk app service
    cat > /mnt/root/etc/init.d/kiosk-app << 'EOF'
#!/sbin/openrc-run

name="Kiosk App"
description="Vue.js kiosk display application"

depend() {
    need net
    after net
}

start() {
    ebegin "Starting Vue.js kiosk app"
    cd /opt/kiosk-app
    
    # Serve built Vue.js app from dist directory
    if [ ! -d dist ]; then
        eend 1 "Vue.js app not built - dist directory missing"
        return 1
    fi
    
    start-stop-daemon --start --pidfile /run/kiosk-app.pid \
        --make-pidfile --background --chdir /opt/kiosk-app/dist \
        --user kiosk --exec /usr/bin/http-server -- -p 3000
    
    eend $?
}

stop() {
    ebegin "Stopping kiosk display app"
    start-stop-daemon --stop --pidfile /run/kiosk-app.pid
    eend $?
}

restart() {
    stop
    start
}
EOF
    
    chmod +x /mnt/root/etc/init.d/kiosk-app
    chroot /mnt/root rc-update add kiosk-app default
    
    # Create update script for kiosk app
    cat > /mnt/root/opt/update-kiosk.sh << 'EOF'
#!/bin/bash
# Update kiosk app from GitHub

cd /opt/kiosk-app

if [ -d .git ]; then
    echo "Updating kiosk app from GitHub..."
    git pull
    
    # Rebuild Vue.js app if package.json exists
    if [ -f package.json ]; then
        npm install
        npm install -g http-server
        if [ -f vue.config.js ] || grep -q "vue" package.json; then
            npm run build
        fi
    fi
    
    # Restart kiosk app service
    rc-service kiosk-app restart
    echo "Kiosk app updated and restarted"
else
    echo "No git repository found in /opt/kiosk-app"
fi
EOF
    
    chmod +x /mnt/root/opt/update-kiosk.sh
    
    log_info "Kiosk app setup completed"
}
