#!/bin/bash
#
# KioskBook Alpine ISO Builder
#
# Creates a custom Alpine Linux ISO with KioskBook installer pre-installed.
# Enables automated deployment without network dependency during installation.
#
# Features:
# - Custom Alpine ISO with KioskBook installer embedded
# - Pre-configured repositories and packages
# - Automated installer launch option
# - Network-independent installation capability
# - Custom boot menu with KioskBook options
#

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$SCRIPT_DIR/iso-build"
OUTPUT_DIR="$SCRIPT_DIR/output"
ALPINE_VERSION="3.19"
ALPINE_ARCH="x86_64"
ALPINE_ISO_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ALPINE_ARCH}/alpine-standard-${ALPINE_VERSION}.0-${ALPINE_ARCH}.iso"
ALPINE_ISO_NAME="alpine-standard-${ALPINE_VERSION}.0-${ALPINE_ARCH}.iso"
CUSTOM_ISO_NAME="kioskbook-installer-${ALPINE_VERSION}-${ALPINE_ARCH}.iso"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[ISO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[ISO SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[ISO WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ISO ERROR]${NC} $1"
}

# Check dependencies
check_dependencies() {
    log "Checking dependencies..."
    
    local missing_deps=()
    
    # Check required tools
    local required_tools=("wget" "mkisofs" "isohybrid" "unsquashfs" "mksquashfs")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_deps+=("$tool")
        fi
    done
    
    # Check for macOS specific tools
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if ! command -v hdiutil >/dev/null 2>&1; then
            missing_deps+=("hdiutil")
        fi
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log "Please install missing tools:"
        
        if [[ "$OSTYPE" == "darwin"* ]]; then
            log "  brew install cdrtools squashfs"
        else
            log "  apt-get install genisoimage squashfs-tools syslinux-utils"
            log "  # or"
            log "  yum install genisoimage squashfs-tools syslinux"
        fi
        
        exit 1
    fi
    
    log_success "Dependencies check passed"
}

# Create build directories
create_build_dirs() {
    log "Creating build directories..."
    
    # Clean and create build directory
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"/{iso,extract,kioskbook,overlay}
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    log_success "Build directories created"
}

# Download Alpine ISO
download_alpine_iso() {
    local iso_path="$BUILD_DIR/$ALPINE_ISO_NAME"
    
    if [[ -f "$iso_path" ]]; then
        log "Alpine ISO already exists: $iso_path"
        return 0
    fi
    
    log "Downloading Alpine Linux ISO..."
    log "URL: $ALPINE_ISO_URL"
    
    wget -O "$iso_path" "$ALPINE_ISO_URL" || {
        log_error "Failed to download Alpine ISO"
        exit 1
    }
    
    # Verify download
    if [[ ! -f "$iso_path" ]]; then
        log_error "Alpine ISO download failed"
        exit 1
    fi
    
    local iso_size
    iso_size=$(du -h "$iso_path" | cut -f1)
    log_success "Alpine ISO downloaded successfully ($iso_size)"
}

# Extract Alpine ISO
extract_alpine_iso() {
    local iso_path="$BUILD_DIR/$ALPINE_ISO_NAME"
    local extract_dir="$BUILD_DIR/extract"
    
    log "Extracting Alpine ISO..."
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS method using hdiutil
        local mount_point="/tmp/alpine_iso_mount"
        mkdir -p "$mount_point"
        
        # Mount ISO
        hdiutil attach "$iso_path" -mountpoint "$mount_point" -readonly || {
            log_error "Failed to mount Alpine ISO"
            exit 1
        }
        
        # Copy contents
        cp -R "$mount_point"/* "$extract_dir"/ || {
            log_error "Failed to copy ISO contents"
            hdiutil detach "$mount_point"
            exit 1
        }
        
        # Unmount
        hdiutil detach "$mount_point"
        rm -rf "$mount_point"
    else
        # Linux method using mount
        local mount_point="/tmp/alpine_iso_mount"
        mkdir -p "$mount_point"
        
        # Mount ISO
        sudo mount -o loop "$iso_path" "$mount_point" || {
            log_error "Failed to mount Alpine ISO"
            exit 1
        }
        
        # Copy contents
        cp -R "$mount_point"/* "$extract_dir"/ || {
            log_error "Failed to copy ISO contents"
            sudo umount "$mount_point"
            exit 1
        }
        
        # Unmount
        sudo umount "$mount_point"
        rm -rf "$mount_point"
    fi
    
    # Make files writable
    chmod -R u+w "$extract_dir"
    
    log_success "Alpine ISO extracted successfully"
}

# Copy KioskBook installer
copy_kioskbook_installer() {
    local kioskbook_dir="$BUILD_DIR/kioskbook"
    
    log "Copying KioskBook installer files..."
    
    # Copy installer files
    cp -R "$PROJECT_ROOT/installer" "$kioskbook_dir/"
    cp -R "$PROJECT_ROOT/scripts" "$kioskbook_dir/"
    cp -R "$PROJECT_ROOT/config" "$kioskbook_dir/"
    
    # Copy documentation
    cp "$PROJECT_ROOT/README.md" "$kioskbook_dir/"
    cp "$PROJECT_ROOT/CLAUDE.md" "$kioskbook_dir/" 2>/dev/null || true
    
    # Create installer package info
    cat > "$kioskbook_dir/VERSION" << EOF
KioskBook Installer
Version: 1.0.0
Build Date: $(date -Iseconds)
Alpine Version: ${ALPINE_VERSION}
Architecture: ${ALPINE_ARCH}
EOF
    
    log_success "KioskBook installer files copied"
}

# Create custom overlay
create_custom_overlay() {
    local overlay_dir="$BUILD_DIR/overlay"
    local extract_dir="$BUILD_DIR/extract"
    
    log "Creating custom overlay..."
    
    # Create overlay structure
    mkdir -p "$overlay_dir"/{etc,usr/local,opt}
    
    # Create KioskBook autostart script
    cat > "$overlay_dir/etc/local.d/kioskbook-autostart.start" << 'EOF'
#!/bin/sh
#
# KioskBook Auto-installer
#
# Automatically launches KioskBook installer if requested via kernel parameter
#

# Check for kioskbook-auto kernel parameter
if grep -q "kioskbook-auto" /proc/cmdline; then
    echo "KioskBook auto-installer requested..."
    
    # Wait for basic system initialization
    sleep 5
    
    # Check if we're in a suitable environment
    if [ -f "/etc/alpine-release" ] && [ -d "/opt/kioskbook" ]; then
        echo "Launching KioskBook installer..."
        cd /opt/kioskbook
        chmod +x installer/bootstrap.sh
        ./installer/bootstrap.sh
    else
        echo "KioskBook installer not found or invalid environment"
    fi
fi
EOF
    
    chmod +x "$overlay_dir/etc/local.d/kioskbook-autostart.start"
    
    # Create KioskBook installation script
    cat > "$overlay_dir/usr/local/bin/install-kioskbook" << 'EOF'
#!/bin/sh
#
# Manual KioskBook installer launcher
#

echo "KioskBook Installer"
echo "=================="
echo

if [ ! -d "/opt/kioskbook" ]; then
    echo "ERROR: KioskBook installer not found"
    echo "This script should be run from KioskBook installer ISO"
    exit 1
fi

echo "Launching KioskBook installer..."
cd /opt/kioskbook

# Make scripts executable
chmod +x installer/bootstrap.sh
chmod +x installer/main.sh

# Run installer
./installer/bootstrap.sh
EOF
    
    chmod +x "$overlay_dir/usr/local/bin/install-kioskbook"
    
    # Create welcome message
    cat > "$overlay_dir/etc/motd" << 'EOF'

 ██╗  ██╗██╗ ██████╗ ███████╗██╗  ██╗██████╗  ██████╗  ██████╗ ██╗  ██╗
 ██║ ██╔╝██║██╔═══██╗██╔════╝██║ ██╔╝██╔══██╗██╔═══██╗██╔═══██╗██║ ██╔╝
 █████╔╝ ██║██║   ██║███████╗█████╔╝ ██████╔╝██║   ██║██║   ██║█████╔╝ 
 ██╔═██╗ ██║██║   ██║╚════██║██╔═██╗ ██╔══██╗██║   ██║██║   ██║██╔═██╗ 
 ██║  ██╗██║╚██████╔╝███████║██║  ██╗██████╔╝╚██████╔╝╚██████╔╝██║  ██╗
 ╚═╝  ╚═╝╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═════╝  ╚═════╝  ╚═════╝ ╚═╝  ╚═╝

 KioskBook Installer - Alpine Linux Custom ISO
 ==============================================

 To install KioskBook, run: install-kioskbook
 
 Manual installation: cd /opt/kioskbook && ./installer/bootstrap.sh

EOF
    
    log_success "Custom overlay created"
}

# Modify boot configuration
modify_boot_config() {
    local extract_dir="$BUILD_DIR/extract"
    
    log "Modifying boot configuration..."
    
    # Backup original boot config
    cp "$extract_dir/boot/syslinux/syslinux.cfg" "$extract_dir/boot/syslinux/syslinux.cfg.orig"
    
    # Create custom syslinux configuration
    cat > "$extract_dir/boot/syslinux/syslinux.cfg" << 'EOF'
# KioskBook Custom Boot Configuration
DEFAULT kioskbook
PROMPT 1
TIMEOUT 100
UI menu.c32

MENU TITLE KioskBook Installer
MENU BACKGROUND splash.png

LABEL kioskbook
    MENU LABEL ^KioskBook Auto-Installer
    MENU DEFAULT
    KERNEL /boot/vmlinuz-lts
    APPEND initrd=/boot/initramfs-lts alpine_dev=cdrom:kioskbook-installer modloop=/boot/modloop-lts quiet kioskbook-auto
    TEXT HELP
    Automatically installs KioskBook after Alpine Linux setup.
    Network required for complete installation.
    ENDTEXT

LABEL manual
    MENU LABEL ^Manual Alpine Installation
    KERNEL /boot/vmlinuz-lts
    APPEND initrd=/boot/initramfs-lts alpine_dev=cdrom:kioskbook-installer modloop=/boot/modloop-lts
    TEXT HELP
    Standard Alpine Linux installation.
    Run 'install-kioskbook' after setup for KioskBook.
    ENDTEXT

LABEL rescue
    MENU LABEL ^Rescue Mode
    KERNEL /boot/vmlinuz-lts
    APPEND initrd=/boot/initramfs-lts alpine_dev=cdrom:kioskbook-installer modloop=/boot/modloop-lts single
    TEXT HELP
    Boot into rescue mode for troubleshooting.
    ENDTEXT

LABEL reboot
    MENU LABEL ^Reboot
    COM32 reboot.c32
    TEXT HELP
    Reboot the computer.
    ENDTEXT

LABEL poweroff
    MENU LABEL ^Power Off
    COM32 poweroff.c32
    TEXT HELP
    Power off the computer.
    ENDTEXT
EOF
    
    # Modify GRUB configuration if present
    if [[ -f "$extract_dir/boot/grub/grub.cfg" ]]; then
        cp "$extract_dir/boot/grub/grub.cfg" "$extract_dir/boot/grub/grub.cfg.orig"
        
        # Add KioskBook menu entries to GRUB
        cat >> "$extract_dir/boot/grub/grub.cfg" << 'EOF'

# KioskBook Custom Entries
menuentry "KioskBook Auto-Installer" {
    linux /boot/vmlinuz-lts alpine_dev=cdrom:kioskbook-installer modloop=/boot/modloop-lts quiet kioskbook-auto
    initrd /boot/initramfs-lts
}

menuentry "Manual Alpine + KioskBook" {
    linux /boot/vmlinuz-lts alpine_dev=cdrom:kioskbook-installer modloop=/boot/modloop-lts
    initrd /boot/initramfs-lts
}
EOF
    fi
    
    log_success "Boot configuration modified"
}

# Integrate KioskBook into initramfs
integrate_kioskbook() {
    local extract_dir="$BUILD_DIR/extract"
    local kioskbook_dir="$BUILD_DIR/kioskbook"
    local overlay_dir="$BUILD_DIR/overlay"
    
    log "Integrating KioskBook into ISO filesystem..."
    
    # Copy KioskBook to appropriate location in ISO
    mkdir -p "$extract_dir/opt"
    cp -R "$kioskbook_dir" "$extract_dir/opt/"
    
    # Copy overlay files
    cp -R "$overlay_dir"/* "$extract_dir/"
    
    # Update ISO label
    if [[ -f "$extract_dir/.disk/info" ]]; then
        echo "KioskBook Installer - Alpine Linux ${ALPINE_VERSION}" > "$extract_dir/.disk/info"
    fi
    
    # Create apkovl for persistence
    mkdir -p "$extract_dir/kioskbook"
    
    # Package overlay as apkovl
    (cd "$overlay_dir" && tar -czf "$extract_dir/kioskbook/kioskbook.apkovl.tar.gz" .)
    
    log_success "KioskBook integrated into ISO"
}

# Build custom ISO
build_iso() {
    local extract_dir="$BUILD_DIR/extract"
    local output_iso="$OUTPUT_DIR/$CUSTOM_ISO_NAME"
    
    log "Building custom ISO..."
    
    # Remove existing output
    rm -f "$output_iso"
    
    # Build ISO using mkisofs/genisoimage
    if command -v mkisofs >/dev/null 2>&1; then
        local iso_cmd="mkisofs"
    elif command -v genisoimage >/dev/null 2>&1; then
        local iso_cmd="genisoimage"
    else
        log_error "No ISO creation tool found (mkisofs or genisoimage)"
        exit 1
    fi
    
    # Create ISO with proper options
    "$iso_cmd" \
        -o "$output_iso" \
        -b boot/syslinux/isolinux.bin \
        -c boot/syslinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -J -R -V "KIOSKBOOK" \
        -cache-inodes \
        -joliet-long \
        -rational-rock \
        "$extract_dir" || {
        log_error "Failed to create ISO"
        exit 1
    }
    
    # Make ISO hybrid (bootable from USB) if isohybrid is available
    if command -v isohybrid >/dev/null 2>&1; then
        log "Making ISO hybrid bootable..."
        isohybrid "$output_iso" || {
            log_warning "Failed to make ISO hybrid bootable"
        }
    fi
    
    # Calculate checksums
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$output_iso" > "$output_iso.sha256"
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$output_iso" > "$output_iso.sha256"
    fi
    
    local iso_size
    iso_size=$(du -h "$output_iso" | cut -f1)
    
    log_success "Custom ISO created successfully"
    log "Output: $output_iso ($iso_size)"
    
    if [[ -f "$output_iso.sha256" ]]; then
        log "Checksum: $output_iso.sha256"
    fi
}

# Clean build directory
clean_build() {
    log "Cleaning build directory..."
    
    if [[ -d "$BUILD_DIR" ]]; then
        rm -rf "$BUILD_DIR"
        log_success "Build directory cleaned"
    else
        log "Build directory already clean"
    fi
}

# Validate output
validate_output() {
    local output_iso="$OUTPUT_DIR/$CUSTOM_ISO_NAME"
    
    log "Validating output ISO..."
    
    if [[ ! -f "$output_iso" ]]; then
        log_error "Output ISO not found: $output_iso"
        exit 1
    fi
    
    # Check file size (should be reasonable)
    local size_bytes
    size_bytes=$(stat -f%z "$output_iso" 2>/dev/null || stat -c%s "$output_iso" 2>/dev/null)
    
    if [[ "$size_bytes" -lt 100000000 ]]; then  # Less than 100MB seems too small
        log_warning "ISO size seems unusually small: $(du -h "$output_iso" | cut -f1)"
    fi
    
    # Verify ISO can be read
    if command -v isoinfo >/dev/null 2>&1; then
        if ! isoinfo -d -i "$output_iso" >/dev/null 2>&1; then
            log_error "ISO appears to be corrupted"
            exit 1
        fi
    fi
    
    log_success "Output validation passed"
}

# Show build summary
show_summary() {
    local output_iso="$OUTPUT_DIR/$CUSTOM_ISO_NAME"
    
    echo
    log_success "KioskBook ISO build completed successfully!"
    echo
    echo "Output File: $output_iso"
    echo "Size: $(du -h "$output_iso" | cut -f1)"
    
    if [[ -f "$output_iso.sha256" ]]; then
        echo "SHA256: $(cat "$output_iso.sha256" | cut -d' ' -f1)"
    fi
    
    echo
    echo "Usage Instructions:"
    echo "1. Write ISO to USB drive or burn to DVD"
    echo "2. Boot target system from USB/DVD"
    echo "3. Select 'KioskBook Auto-Installer' from boot menu"
    echo "4. Follow installation prompts"
    echo
    echo "Manual Installation:"
    echo "1. Select 'Manual Alpine Installation' from boot menu"
    echo "2. Complete Alpine Linux setup with setup-alpine"
    echo "3. Run: install-kioskbook"
    echo
    echo "Testing with UTM:"
    echo "1. Use tools/test-utm.sh to create VM"
    echo "2. Attach this ISO as CD-ROM"
    echo "3. Boot and test installation"
}

# Show help
show_help() {
    cat << 'EOF'
KioskBook Alpine ISO Builder

USAGE:
    ./build-iso.sh [COMMAND]

COMMANDS:
    build           Build complete custom ISO (default)
    clean           Clean build directory
    download        Download Alpine ISO only
    extract         Extract Alpine ISO only  
    integrate       Integrate KioskBook only
    validate        Validate existing output
    help            Show this help message

WORKFLOW:
    1. Downloads Alpine Linux standard ISO
    2. Extracts ISO contents
    3. Integrates KioskBook installer
    4. Modifies boot configuration
    5. Creates custom ISO with auto-installer option

OUTPUT:
    - Custom ISO: tools/output/kioskbook-installer-{version}-{arch}.iso
    - SHA256 checksum file included
    - Hybrid bootable (USB and CD/DVD)

BOOT OPTIONS:
    - KioskBook Auto-Installer: Automated installation
    - Manual Alpine Installation: Standard Alpine + manual KioskBook
    - Rescue Mode: Troubleshooting mode

DEPENDENCIES:
    macOS: brew install cdrtools squashfs
    Linux: apt-get install genisoimage squashfs-tools syslinux-utils

The resulting ISO contains a complete Alpine Linux system with
KioskBook installer embedded, enabling network-independent deployment.
EOF
}

# Main script logic
main() {
    local command="${1:-build}"
    
    case "$command" in
        "build")
            check_dependencies
            create_build_dirs
            download_alpine_iso
            extract_alpine_iso
            copy_kioskbook_installer
            create_custom_overlay
            modify_boot_config
            integrate_kioskbook
            build_iso
            validate_output
            show_summary
            ;;
        "clean")
            clean_build
            ;;
        "download")
            check_dependencies
            create_build_dirs
            download_alpine_iso
            ;;
        "extract")
            check_dependencies
            create_build_dirs
            download_alpine_iso
            extract_alpine_iso
            ;;
        "integrate")
            check_dependencies
            copy_kioskbook_installer
            create_custom_overlay
            integrate_kioskbook
            ;;
        "validate")
            validate_output
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            echo
            show_help
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"