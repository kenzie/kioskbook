#!/bin/bash
#
# 50-application.sh - Application Setup Module
#
# Installs Node.js runtime and sets up the Vue.js kiosk application.
# Creates Express server with API endpoints and static file serving.
#
# Features:
# - Vue.js application build and deployment
# - Express server with API endpoints
# - Static file serving with Vue Router support
# - Content management with local JSON data
# - OpenRC service for application lifecycle
#

set -e
set -o pipefail

# Import logging functions from main installer
source /dev/stdin <<< "$(declare -f log log_success log_warning log_error log_info add_rollback)"

# Module configuration
MODULE_NAME="50-application"
APP_DIR="/data/app"
CONTENT_DIR="/data/content"
SERVER_PORT="3000"

log_info "Starting application setup module..."

# Validate environment
validate_environment() {
    if [[ -z "$MOUNT_ROOT" || -z "$MOUNT_DATA" || -z "$GITHUB_REPO" ]]; then
        log_error "Required environment variables not set. Run previous modules first."
        exit 1
    fi
    
    if ! mountpoint -q "$MOUNT_ROOT"; then
        log_error "Root partition not mounted at $MOUNT_ROOT"
        exit 1
    fi
    
    if ! mountpoint -q "$MOUNT_DATA"; then
        log_error "Data partition not mounted at $MOUNT_DATA"
        exit 1
    fi
    
    # Check if Node.js and npm are installed
    if ! chroot "$MOUNT_ROOT" which node >/dev/null 2>&1; then
        log_error "Node.js not found. Run base system module first."
        exit 1
    fi
    
    if ! chroot "$MOUNT_ROOT" which npm >/dev/null 2>&1; then
        log_error "npm not found. Run base system module first."
        exit 1
    fi
    
    log_info "Environment validation passed"
    log_info "GitHub repository: $GITHUB_REPO"
}

# Clone application repository
clone_application() {
    log_info "Cloning Vue.js application repository..."
    
    local app_path="$MOUNT_DATA$APP_DIR"
    local repo_url="https://github.com/$GITHUB_REPO.git"
    
    # Remove existing application directory if present
    if [[ -d "$app_path" ]]; then
        log_info "Removing existing application directory..."
        rm -rf "$app_path"
    fi
    
    # Create parent directory
    mkdir -p "$(dirname "$app_path")"
    
    # Clone repository
    log_info "Cloning from $repo_url..."
    git clone "$repo_url" "$app_path" || {
        log_error "Failed to clone repository: $repo_url"
        exit 1
    }
    
    # Set ownership to kiosk user
    chroot "$MOUNT_ROOT" chown -R kiosk:kiosk "$APP_DIR"
    
    log_success "Application repository cloned to $APP_DIR"
    
    # Add rollback action
    add_rollback "rm -rf '$app_path'"
}

# Install application dependencies
install_dependencies() {
    log_info "Installing application dependencies..."
    
    local app_path="$MOUNT_DATA$APP_DIR"
    
    # Check if package.json exists
    if [[ ! -f "$app_path/package.json" ]]; then
        log_error "package.json not found in $app_path"
        exit 1
    fi
    
    # Install dependencies using npm ci for reproducible builds
    log_info "Running npm ci..."
    chroot "$MOUNT_ROOT" bash -c "cd '$APP_DIR' && npm ci --production=false" || {
        log_warning "npm ci failed, trying npm install..."
        chroot "$MOUNT_ROOT" bash -c "cd '$APP_DIR' && npm install" || {
            log_error "Failed to install dependencies"
            exit 1
        }
    }
    
    log_success "Application dependencies installed"
}

# Build Vue.js application
build_application() {
    log_info "Building Vue.js application..."
    
    local app_path="$MOUNT_DATA$APP_DIR"
    
    # Check if build script exists in package.json
    if ! chroot "$MOUNT_ROOT" bash -c "cd '$APP_DIR' && npm run-script build --silent" >/dev/null 2>&1; then
        log_warning "Build script not found, checking for alternative build commands..."
        
        # Try alternative build commands
        for build_cmd in "npm run build:prod" "npm run production" "npm run compile"; do
            if chroot "$MOUNT_ROOT" bash -c "cd '$APP_DIR' && $build_cmd" >/dev/null 2>&1; then
                log_success "Application built using: $build_cmd"
                return 0
            fi
        done
        
        log_error "No suitable build command found"
        exit 1
    else
        # Run the build
        chroot "$MOUNT_ROOT" bash -c "cd '$APP_DIR' && npm run build" || {
            log_error "Failed to build application"
            exit 1
        }
    fi
    
    # Verify dist directory was created
    if [[ ! -d "$app_path/dist" ]]; then
        log_error "Build output directory (dist) not found"
        exit 1
    fi
    
    log_success "Vue.js application built successfully"
}

# Create Express server
create_express_server() {
    log_info "Creating Express server..."
    
    local app_path="$MOUNT_DATA$APP_DIR"
    
    # Install Express and dependencies
    log_info "Installing Express server dependencies..."
    chroot "$MOUNT_ROOT" bash -c "cd '$APP_DIR' && npm install express cors helmet compression morgan" || {
        log_error "Failed to install Express dependencies"
        exit 1
    }
    
    # Create server.js
    cat > "$app_path/server.js" << 'EOF'
#!/usr/bin/env node
/**
 * KioskBook Express Server
 * 
 * Serves Vue.js application with API endpoints for kiosk operation.
 * Handles static file serving, content API, and Vue Router support.
 */

const express = require('express');
const path = require('path');
const fs = require('fs').promises;
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const morgan = require('morgan');

const app = express();
const PORT = process.env.PORT || 3000;
const APP_DIR = __dirname;
const DIST_DIR = path.join(APP_DIR, 'dist');
const CONTENT_DIR = '/data/content';

// Logging
const logger = {
    info: (msg) => console.log(`${new Date().toISOString()} [INFO] ${msg}`),
    error: (msg) => console.error(`${new Date().toISOString()} [ERROR] ${msg}`),
    warn: (msg) => console.warn(`${new Date().toISOString()} [WARN] ${msg}`)
};

// Middleware
app.use(helmet({
    contentSecurityPolicy: false, // Disable CSP for kiosk operation
    crossOriginResourcePolicy: { policy: "cross-origin" }
}));
app.use(compression());
app.use(cors());
app.use(morgan('combined'));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({ 
        status: 'healthy', 
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
        version: process.env.npm_package_version || '1.0.0'
    });
});

// Content API endpoint
app.get('/api/content', async (req, res) => {
    try {
        const contentFile = path.join(CONTENT_DIR, 'current', 'content.json');
        
        // Check if content file exists
        try {
            await fs.access(contentFile);
        } catch (error) {
            logger.warn(`Content file not found: ${contentFile}`);
            return res.json({
                error: 'Content not available',
                message: 'Content file not found',
                timestamp: new Date().toISOString()
            });
        }
        
        // Read and parse content
        const contentData = await fs.readFile(contentFile, 'utf8');
        const content = JSON.parse(contentData);
        
        // Add metadata
        const response = {
            ...content,
            _metadata: {
                timestamp: new Date().toISOString(),
                source: 'local'
            }
        };
        
        res.json(response);
        logger.info('Content served successfully');
        
    } catch (error) {
        logger.error(`Content API error: ${error.message}`);
        res.status(500).json({
            error: 'Internal server error',
            message: 'Failed to load content',
            timestamp: new Date().toISOString()
        });
    }
});

// Content status endpoint
app.get('/api/content/status', async (req, res) => {
    try {
        const contentDir = path.join(CONTENT_DIR, 'current');
        const contentFile = path.join(contentDir, 'content.json');
        
        let status = {
            contentAvailable: false,
            lastUpdated: null,
            mediaFiles: [],
            timestamp: new Date().toISOString()
        };
        
        try {
            // Check content file
            const contentStat = await fs.stat(contentFile);
            status.contentAvailable = true;
            status.lastUpdated = contentStat.mtime.toISOString();
            
            // List media files
            try {
                const files = await fs.readdir(contentDir);
                status.mediaFiles = files.filter(file => 
                    /\.(jpg|jpeg|png|gif|mp4|webm|ogg|mp3|wav)$/i.test(file)
                );
            } catch (error) {
                logger.warn(`Could not read media directory: ${error.message}`);
            }
            
        } catch (error) {
            logger.info('Content file not available');
        }
        
        res.json(status);
        
    } catch (error) {
        logger.error(`Content status error: ${error.message}`);
        res.status(500).json({
            error: 'Internal server error',
            timestamp: new Date().toISOString()
        });
    }
});

// Serve media files from content directory
app.use('/media', express.static(path.join(CONTENT_DIR, 'current'), {
    maxAge: '1d',
    etag: true,
    lastModified: true,
    setHeaders: (res, path) => {
        // Set appropriate MIME types for media files
        if (path.endsWith('.mp4')) {
            res.setHeader('Content-Type', 'video/mp4');
        } else if (path.endsWith('.webm')) {
            res.setHeader('Content-Type', 'video/webm');
        } else if (path.endsWith('.ogg')) {
            res.setHeader('Content-Type', 'video/ogg');
        }
        
        // Enable range requests for video files
        res.setHeader('Accept-Ranges', 'bytes');
    }
}));

// Serve Vue.js static files
app.use('/assets', express.static(path.join(DIST_DIR, 'assets'), {
    maxAge: '1y',
    etag: true,
    immutable: true
}));

// Serve other static files
app.use(express.static(DIST_DIR, {
    maxAge: '1h',
    etag: true,
    index: false // Don't serve index.html for static routes
}));

// Vue Router support - serve index.html for all non-API routes
app.get('*', (req, res) => {
    const indexPath = path.join(DIST_DIR, 'index.html');
    res.sendFile(indexPath, (err) => {
        if (err) {
            logger.error(`Failed to serve index.html: ${err.message}`);
            res.status(500).send('Internal Server Error');
        }
    });
});

// Error handling middleware
app.use((error, req, res, next) => {
    logger.error(`Unhandled error: ${error.message}`);
    res.status(500).json({
        error: 'Internal server error',
        timestamp: new Date().toISOString()
    });
});

// Start server
const server = app.listen(PORT, '0.0.0.0', () => {
    logger.info(`KioskBook server started on port ${PORT}`);
    logger.info(`Serving Vue.js app from: ${DIST_DIR}`);
    logger.info(`Content directory: ${CONTENT_DIR}`);
    logger.info(`Process ID: ${process.pid}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
    logger.info('SIGTERM received, shutting down gracefully');
    server.close(() => {
        logger.info('Server closed');
        process.exit(0);
    });
});

process.on('SIGINT', () => {
    logger.info('SIGINT received, shutting down gracefully');
    server.close(() => {
        logger.info('Server closed');
        process.exit(0);
    });
});

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
    logger.error(`Uncaught exception: ${error.message}`);
    process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
    logger.error(`Unhandled rejection at: ${promise}, reason: ${reason}`);
    process.exit(1);
});

module.exports = app;
EOF
    
    # Make server.js executable
    chmod +x "$app_path/server.js"
    
    log_success "Express server created"
}

# Create content directories
create_content_directories() {
    log_info "Creating content directories..."
    
    local content_path="$MOUNT_DATA$CONTENT_DIR"
    
    # Create content directory structure
    mkdir -p "$content_path"/{current,cache,updates}
    
    # Create default content.json
    cat > "$content_path/current/content.json" << 'EOF'
{
    "title": "KioskBook",
    "subtitle": "Welcome to KioskBook Kiosk System",
    "message": "System is ready and operational",
    "data": {
        "status": "ready",
        "timestamp": "2024-01-01T00:00:00Z",
        "version": "1.0.0"
    },
    "settings": {
        "refreshInterval": 300000,
        "theme": "default"
    }
}
EOF
    
    # Set ownership
    chroot "$MOUNT_ROOT" chown -R kiosk:kiosk "$CONTENT_DIR"
    
    log_success "Content directories created"
}

# Create OpenRC service
create_openrc_service() {
    log_info "Creating OpenRC service for application..."
    
    # Create OpenRC service script
    cat > "$MOUNT_ROOT/etc/init.d/kiosk-app" << 'EOF'
#!/sbin/openrc-run

name="kiosk-app"
description="KioskBook Vue.js Application Server"

: ${kiosk_app_user:="kiosk"}
: ${kiosk_app_group:="kiosk"}
: ${kiosk_app_dir:="/data/app"}
: ${kiosk_app_logfile:="/var/log/kiosk-app.log"}
: ${kiosk_app_port:="3000"}

command="/usr/bin/node"
command_args="server.js"
command_user="$kiosk_app_user:$kiosk_app_group"
command_background="yes"
pidfile="/var/run/${RC_SVCNAME}.pid"
start_stop_daemon_args="
    --chdir $kiosk_app_dir
    --env NODE_ENV=production
    --env PORT=$kiosk_app_port
    --stdout $kiosk_app_logfile
    --stderr $kiosk_app_logfile
"

depend() {
    need localmount net
    after bootmisc
    before kiosk-display
    provide kiosk-app
}

start_pre() {
    # Ensure log file exists and has correct permissions
    checkpath --file --owner "$kiosk_app_user:$kiosk_app_group" --mode 0644 "$kiosk_app_logfile"
    
    # Ensure app directory exists
    if [ ! -d "$kiosk_app_dir" ]; then
        eerror "Application directory does not exist: $kiosk_app_dir"
        return 1
    fi
    
    # Ensure server.js exists
    if [ ! -f "$kiosk_app_dir/server.js" ]; then
        eerror "Server script does not exist: $kiosk_app_dir/server.js"
        return 1
    fi
    
    # Ensure dist directory exists
    if [ ! -d "$kiosk_app_dir/dist" ]; then
        eerror "Built application not found: $kiosk_app_dir/dist"
        return 1
    fi
    
    return 0
}

start() {
    ebegin "Starting $name"
    start-stop-daemon --start \
        --exec "$command" \
        --pidfile "$pidfile" \
        --make-pidfile \
        --background \
        --user "$command_user" \
        $start_stop_daemon_args \
        -- $command_args
    eend $?
}

stop() {
    ebegin "Stopping $name"
    start-stop-daemon --stop \
        --pidfile "$pidfile" \
        --exec "$command"
    eend $?
}

reload() {
    ebegin "Reloading $name"
    if [ -f "$pidfile" ]; then
        kill -USR2 $(cat "$pidfile")
        eend $?
    else
        eerror "PID file not found"
        eend 1
    fi
}

status() {
    if [ -f "$pidfile" ] && kill -0 $(cat "$pidfile") 2>/dev/null; then
        einfo "$name is running"
        return 0
    else
        einfo "$name is not running"
        return 1
    fi
}
EOF
    
    # Make service executable
    chmod +x "$MOUNT_ROOT/etc/init.d/kiosk-app"
    
    # Enable the service
    chroot "$MOUNT_ROOT" rc-update add kiosk-app default || {
        log_error "Failed to enable kiosk-app service"
        exit 1
    }
    
    log_success "OpenRC service created and enabled"
}

# Create application management scripts
create_management_scripts() {
    log_info "Creating application management scripts..."
    
    # Create update script
    cat > "$MOUNT_ROOT/usr/local/bin/update-app" << 'EOF'
#!/bin/bash
#
# KioskBook Application Update Script
#

set -e

APP_DIR="/data/app"
BACKUP_DIR="/data/app-backup"
SERVICE_NAME="kiosk-app"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [UPDATE] $1"
}

# Create backup
log "Creating backup of current application..."
if [ -d "$BACKUP_DIR" ]; then
    rm -rf "$BACKUP_DIR"
fi
cp -r "$APP_DIR" "$BACKUP_DIR"

# Stop service
log "Stopping application service..."
rc-service "$SERVICE_NAME" stop || true

# Update repository
log "Updating application from repository..."
cd "$APP_DIR"
git fetch origin
git reset --hard origin/main

# Install dependencies and build
log "Installing dependencies..."
npm ci --production=false

log "Building application..."
npm run build

# Start service
log "Starting application service..."
rc-service "$SERVICE_NAME" start

log "Application update completed successfully"
EOF
    
    chmod +x "$MOUNT_ROOT/usr/local/bin/update-app"
    
    # Create status script
    cat > "$MOUNT_ROOT/usr/local/bin/app-status" << 'EOF'
#!/bin/bash
#
# KioskBook Application Status Script
#

APP_DIR="/data/app"
SERVICE_NAME="kiosk-app"
PORT="3000"

echo "KioskBook Application Status"
echo "============================"
echo ""

# Service status
echo "Service Status:"
rc-service "$SERVICE_NAME" status
echo ""

# Process status
echo "Process Status:"
if pgrep -f "node.*server.js" >/dev/null; then
    echo "✓ Node.js server is running"
    ps aux | grep -v grep | grep "node.*server.js"
else
    echo "✗ Node.js server is not running"
fi
echo ""

# Port status
echo "Port Status:"
if netstat -ln | grep ":$PORT " >/dev/null; then
    echo "✓ Port $PORT is listening"
else
    echo "✗ Port $PORT is not listening"
fi
echo ""

# Application files
echo "Application Files:"
if [ -d "$APP_DIR" ]; then
    echo "✓ Application directory exists"
    if [ -f "$APP_DIR/server.js" ]; then
        echo "✓ Server script exists"
    else
        echo "✗ Server script missing"
    fi
    if [ -d "$APP_DIR/dist" ]; then
        echo "✓ Built application exists"
        echo "  Files in dist/: $(ls -1 "$APP_DIR/dist" | wc -l)"
    else
        echo "✗ Built application missing"
    fi
else
    echo "✗ Application directory missing"
fi
echo ""

# Health check
echo "Health Check:"
if curl -s "http://localhost:$PORT/health" >/dev/null; then
    echo "✓ Application responds to health check"
    curl -s "http://localhost:$PORT/health" | python3 -m json.tool 2>/dev/null || echo "  Response received but not valid JSON"
else
    echo "✗ Application does not respond to health check"
fi
EOF
    
    chmod +x "$MOUNT_ROOT/usr/local/bin/app-status"
    
    log_success "Management scripts created"
}

# Validate application setup
validate_application() {
    log_info "Validating application setup..."
    
    local app_path="$MOUNT_DATA$APP_DIR"
    
    # Check essential files
    local essential_files=(
        "$app_path/package.json"
        "$app_path/server.js"
        "$app_path/dist/index.html"
        "$MOUNT_ROOT/etc/init.d/kiosk-app"
    )
    
    for file in "${essential_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Essential application file missing: $file"
            exit 1
        fi
    done
    
    # Check content directory
    if [[ ! -d "$MOUNT_DATA$CONTENT_DIR/current" ]]; then
        log_error "Content directory missing: $CONTENT_DIR/current"
        exit 1
    fi
    
    # Check if service is enabled
    if ! chroot "$MOUNT_ROOT" rc-status default | grep -q kiosk-app; then
        log_error "kiosk-app service not enabled"
        exit 1
    fi
    
    log_success "Application setup validation passed"
}

# Main application setup
main() {
    log_info "=========================================="
    log_info "Module: Application Setup"
    log_info "=========================================="
    
    validate_environment
    clone_application
    install_dependencies
    build_application
    create_content_directories
    create_express_server
    create_openrc_service
    create_management_scripts
    validate_application
    
    log_success "Application setup completed successfully"
    log_info "Vue.js application ready to serve on port $SERVER_PORT"
}

# Execute main function
main "$@"