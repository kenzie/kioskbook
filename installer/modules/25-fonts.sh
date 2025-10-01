#!/bin/bash
#
# 25-fonts.sh - Font Installation and Configuration Module
#
# Downloads and installs high-quality fonts for kiosk display.
# Configures font rendering with optimal settings for displays.
#
# Features:
# - Inter font family from GitHub releases
# - CaskaydiaCove Nerd Font (Caskaydia Code NF)
# - System-wide font configuration with fontconfig
# - Persistent font storage in /data/fonts
# - Optimized rendering with hinting and antialiasing
# - Chromium font configuration
#

set -e
set -o pipefail

# Import logging functions from main installer
source /dev/stdin <<< "$(declare -f log log_success log_warning log_error log_info add_rollback)"

# Module configuration
MODULE_NAME="25-fonts"
FONT_DIR="/data/fonts"
INTER_VERSION="4.0"
NERD_FONT_VERSION="3.1.1"

# Font URLs
INTER_URL="https://github.com/rsms/inter/releases/download/v${INTER_VERSION}/Inter-${INTER_VERSION}.zip"
NERD_FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERD_FONT_VERSION}/CascadiaCode.zip"

log_info "Starting font installation and configuration module..."

# Validate environment
validate_environment() {
    if [[ -z "$MOUNT_ROOT" || -z "$MOUNT_DATA" ]]; then
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
    
    log_info "Environment validation passed"
}

# Install font packages
install_font_packages() {
    log_info "Installing font packages and tools..."
    
    local packages=(
        "fontconfig"
        "fontconfig-dev"
        "freetype"
        "freetype-dev"
        "cairo"
        "cairo-dev"
        "pango"
        "pango-dev"
        "unzip"
        "wget"
    )
    
    apk --root "$MOUNT_ROOT" add "${packages[@]}" || {
        log_error "Failed to install font packages"
        exit 1
    }
    
    log_success "Font packages installed"
}

# Create font directories
create_font_directories() {
    log_info "Creating font directories..."
    
    # Create persistent font directory on data partition
    local font_path="$MOUNT_DATA$FONT_DIR"
    mkdir -p "$font_path"/{inter,caskaydiaCove,cache}
    
    # Create system font directories
    mkdir -p "$MOUNT_ROOT/usr/share/fonts"/{truetype,opentype}
    mkdir -p "$MOUNT_ROOT/home/kiosk/.local/share/fonts"
    mkdir -p "$MOUNT_ROOT/etc/fonts/conf.d"
    
    # Create symlink from system to data fonts
    ln -sf "$FONT_DIR" "$MOUNT_ROOT/usr/share/fonts/kioskbook" || {
        log_warning "Failed to create font symlink"
    }
    
    # Set ownership
    chroot "$MOUNT_ROOT" chown -R kiosk:kiosk /home/kiosk/.local/share/fonts
    chroot "$MOUNT_ROOT" chown -R root:root "$FONT_DIR"
    
    log_success "Font directories created"
}

# Download and install Inter font
install_inter_font() {
    log_info "Downloading and installing Inter font family..."
    
    local font_path="$MOUNT_DATA$FONT_DIR/inter"
    local temp_dir="/tmp/inter-font"
    
    # Create temporary directory
    mkdir -p "$temp_dir"
    
    # Download Inter font
    log_info "Downloading Inter v${INTER_VERSION}..."
    wget -O "$temp_dir/inter.zip" "$INTER_URL" || {
        log_error "Failed to download Inter font"
        exit 1
    }
    
    # Extract fonts
    log_info "Extracting Inter font files..."
    cd "$temp_dir"
    unzip -q inter.zip || {
        log_error "Failed to extract Inter font"
        exit 1
    }
    
    # Install Inter fonts
    log_info "Installing Inter font variants..."
    
    # Variable font (recommended)
    if [[ -f "Inter-Variable.ttf" ]]; then
        cp "Inter-Variable.ttf" "$font_path/"
        log_info "Installed Inter Variable font"
    fi
    
    # Static fonts for better compatibility
    if [[ -d "static" ]]; then
        find static -name "*.ttf" -exec cp {} "$font_path/" \;
        log_info "Installed Inter static fonts"
    elif [[ -d "Inter Desktop" ]]; then
        find "Inter Desktop" -name "*.ttf" -exec cp {} "$font_path/" \;
        log_info "Installed Inter desktop fonts"
    fi
    
    # Web fonts (subset for specific use cases)
    if [[ -d "web" ]]; then
        find web -name "*.woff2" -exec cp {} "$font_path/" \;
        log_info "Installed Inter web fonts"
    fi
    
    # Copy license and documentation
    find . -name "LICENSE*" -o -name "README*" -o -name "*.md" | head -5 | xargs -I {} cp {} "$font_path/" 2>/dev/null || true
    
    # Cleanup
    cd /
    rm -rf "$temp_dir"
    
    # Verify installation
    local font_count
    font_count=$(find "$font_path" -name "*.ttf" -o -name "*.woff2" | wc -l)
    if [[ "$font_count" -lt 1 ]]; then
        log_error "No Inter fonts were installed"
        exit 1
    fi
    
    log_success "Inter font installed ($font_count files)"
}

# Download and install CaskaydiaCove Nerd Font
install_caskaydia_font() {
    log_info "Downloading and installing CaskaydiaCove Nerd Font..."
    
    local font_path="$MOUNT_DATA$FONT_DIR/caskaydiaCove"
    local temp_dir="/tmp/caskaydia-font"
    
    # Create temporary directory
    mkdir -p "$temp_dir"
    
    # Download CaskaydiaCove Nerd Font
    log_info "Downloading CaskaydiaCove Nerd Font v${NERD_FONT_VERSION}..."
    log_info "URL: $NERD_FONT_URL"
    
    if ! wget -O "$temp_dir/caskaydia.zip" "$NERD_FONT_URL"; then
        log_error "Failed to download CaskaydiaCove Nerd Font from $NERD_FONT_URL"
        log_info "Checking if file was partially downloaded..."
        if [[ -f "$temp_dir/caskaydia.zip" ]]; then
            log_info "Partial download found, file size: $(stat -c%s "$temp_dir/caskaydia.zip" 2>/dev/null || echo "unknown")"
            rm -f "$temp_dir/caskaydia.zip"
        fi
        exit 1
    fi
    
    # Verify download
    if [[ ! -f "$temp_dir/caskaydia.zip" ]]; then
        log_error "Downloaded file not found"
        exit 1
    fi
    
    local file_size
    file_size=$(stat -c%s "$temp_dir/caskaydia.zip" 2>/dev/null || echo "0")
    if [[ "$file_size" -lt 1000000 ]]; then
        log_warning "Downloaded file seems too small: ${file_size} bytes"
    fi
    log_info "Downloaded CaskaydiaCove Nerd Font (${file_size} bytes)"
    
    # Extract fonts
    log_info "Extracting CaskaydiaCove font files..."
    cd "$temp_dir"
    
    # Test zip file integrity first
    if ! unzip -t caskaydia.zip >/dev/null 2>&1; then
        log_error "Downloaded zip file is corrupted"
        log_info "Attempting to view file contents with 'file' command:"
        file caskaydia.zip || true
        log_info "First few bytes of file:"
        head -c 100 caskaydia.zip | xxd || true
        exit 1
    fi
    
    # Extract with verbose output for debugging
    log_info "Zip file is valid, extracting..."
    if ! unzip -q caskaydia.zip; then
        log_error "Failed to extract CaskaydiaCove Nerd Font"
        log_info "Attempting extraction with verbose output:"
        unzip caskaydia.zip || true
        exit 1
    fi
    
    log_info "Extraction completed, listing contents:"
    ls -la
    
    # Install CaskaydiaCove fonts
    log_info "Installing CaskaydiaCove font variants..."
    
    # List available TTF files for debugging
    log_info "Available TTF files in archive:"
    find . -name "*.ttf" | head -10
    
    # Try multiple patterns to find CaskaydiaCove fonts
    if find . -name "*CaskaydiaCove*NF*.ttf" -print -quit | grep -q .; then
        log_info "Found CaskaydiaCove NF fonts"
        find . -name "*CaskaydiaCove*NF*.ttf" -exec cp {} "$font_path/" \;
    elif find . -name "*CaskaydiaCove*.ttf" -print -quit | grep -q .; then
        log_info "Found CaskaydiaCove fonts (without NF suffix)"
        find . -name "*CaskaydiaCove*.ttf" -exec cp {} "$font_path/" \;
    elif find . -name "*Cascadia*NF*.ttf" -print -quit | grep -q .; then
        log_info "Found Cascadia NF fonts"
        find . -name "*Cascadia*NF*.ttf" -exec cp {} "$font_path/" \;
    elif find . -name "*Cascadia*.ttf" -print -quit | grep -q .; then
        log_info "Found Cascadia fonts"
        find . -name "*Cascadia*.ttf" -exec cp {} "$font_path/" \;
    else
        log_warning "No CaskaydiaCove/Cascadia fonts found, copying all TTF files"
        find . -name "*.ttf" -exec cp {} "$font_path/" \;
    fi
    
    # Copy license if available
    find . -name "LICENSE*" -o -name "readme*" -o -name "README*" | head -3 | xargs -I {} cp {} "$font_path/" 2>/dev/null || true
    
    # Cleanup
    cd /
    rm -rf "$temp_dir"
    
    # Verify installation
    local font_count
    font_count=$(find "$font_path" -name "*.ttf" | wc -l)
    if [[ "$font_count" -lt 1 ]]; then
        log_error "No CaskaydiaCove fonts were installed"
        exit 1
    fi
    
    log_success "CaskaydiaCove Nerd Font installed ($font_count files)"
}

# Configure fontconfig
configure_fontconfig() {
    log_info "Configuring fontconfig for optimal font rendering..."
    
    # Create main fontconfig configuration
    cat > "$MOUNT_ROOT/etc/fonts/local.conf" << 'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <!-- Set preferred serif, sans-serif, and monospace fonts -->
  <alias>
    <family>sans-serif</family>
    <prefer><family>Inter</family></prefer>
  </alias>
  <alias>
    <family>serif</family>
    <prefer><family>Inter</family></prefer>
  </alias>
  <alias>
    <family>monospace</family>
    <prefer><family>CaskaydiaCove Nerd Font</family></prefer>
  </alias>

  <!-- Font rendering settings for display -->
  <match target="font">
    <edit name="antialias" mode="assign"><bool>true</bool></edit>
    <edit name="hinting" mode="assign"><bool>true</bool></edit>
    <edit name="hintstyle" mode="assign"><const>hintslight</const></edit>
    <edit name="rgba" mode="assign"><const>rgb</const></edit>
    <edit name="lcdfilter" mode="assign"><const>lcddefault</const></edit>
  </match>
</fontconfig>
EOF

    # Create specific configuration for Inter
    cat > "$MOUNT_ROOT/etc/fonts/conf.d/10-inter.conf" << 'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
    <!-- Inter font optimization -->
    <match target="font">
        <test name="family" compare="eq" ignore-blanks="true">
            <string>Inter</string>
        </test>
        <edit name="fontfeatures" mode="append">
            <string>ss01 on</string> <!-- Alternative a -->
            <string>ss02 on</string> <!-- Alternative g -->
            <string>ss03 on</string> <!-- Alternative f -->
            <string>cv01 on</string> <!-- Curved r -->
            <string>cv02 on</string> <!-- Open 4 -->
            <string>cv05 on</string> <!-- Alternative l -->
            <string>cv08 on</string> <!-- Upper case i with serif -->
            <string>cv11 on</string> <!-- Single-story a -->
        </edit>
    </match>
    
    <!-- Inter Variable font optimization -->
    <match target="font">
        <test name="family" compare="eq" ignore-blanks="true">
            <string>Inter Variable</string>
        </test>
        <edit name="fontfeatures" mode="append">
            <string>ss01 on</string>
            <string>ss02 on</string>
            <string>ss03 on</string>
            <string>cv01 on</string>
            <string>cv02 on</string>
            <string>cv05 on</string>
            <string>cv08 on</string>
            <string>cv11 on</string>
        </edit>
    </match>
</fontconfig>
EOF

    # Create specific configuration for CaskaydiaCove
    cat > "$MOUNT_ROOT/etc/fonts/conf.d/10-caskaydiaCove.conf" << 'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
    <!-- CaskaydiaCove Nerd Font optimization -->
    <match target="font">
        <test name="family" compare="contains" ignore-blanks="true">
            <string>CaskaydiaCove</string>
        </test>
        <edit name="fontfeatures" mode="append">
            <string>ss01 on</string> <!-- Cursive italics -->
            <string>ss19 on</string> <!-- Slashed zero -->
            <string>ss20 on</string> <!-- Graphical control characters -->
        </edit>
        <edit name="hintstyle" mode="assign">
            <const>hintslight</const>
        </edit>
    </match>
    
    <!-- Ensure monospace spacing -->
    <match target="font">
        <test name="family" compare="contains" ignore-blanks="true">
            <string>CaskaydiaCove</string>
        </test>
        <edit name="spacing" mode="assign">
            <const>mono</const>
        </edit>
    </match>
</fontconfig>
EOF

    log_success "Fontconfig configured"
}

# Configure system-wide font defaults
configure_system_fonts() {
    log_info "Configuring system-wide font defaults..."
    
    # Configure X11 font settings
    cat > "$MOUNT_ROOT/etc/X11/Xresources" << 'EOF'
! KioskBook X11 Font Configuration

! DPI setting (adjust based on display)
Xft.dpi: 96

! Font rendering
Xft.antialias: true
Xft.hinting: true
Xft.hintstyle: hintslight
Xft.rgba: rgb
Xft.lcdfilter: lcddefault

! Default fonts
*.font: Inter:size=11
*.boldFont: Inter:weight=bold:size=11
*.italicFont: Inter:style=italic:size=11
*.boldItalicFont: Inter:weight=bold:style=italic:size=11

! Monospace fonts
*.faceName: CaskaydiaCove Nerd Font:size=10
*.faceNameDoublesize: CaskaydiaCove Nerd Font:size=20
EOF

    # Configure environment variables for font rendering
    cat > "$MOUNT_ROOT/etc/environment" << 'EOF'
# KioskBook Font Environment Variables

# FreeType settings
FREETYPE_PROPERTIES="truetype:interpreter-version=40 cff:no-stem-darkening=0"

# Cairo settings
CAIRO_FONT_OPTIONS="antialias=subpixel,hint-style=slight,hint-metrics=on,rgba=rgb"

# Qt font settings
QT_FONT_DPI=96
QT_AUTO_SCREEN_SCALE_FACTOR=0

# GTK font settings
GDK_SCALE=1
GDK_DPI_SCALE=1
EOF

    # Configure default fonts for desktop environment
    mkdir -p "$MOUNT_ROOT/etc/skel/.config/fontconfig"
    cat > "$MOUNT_ROOT/etc/skel/.config/fontconfig/fonts.conf" << 'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
    <!-- User font configuration -->
    <alias>
        <family>sans-serif</family>
        <prefer>
            <family>Inter</family>
        </prefer>
    </alias>
    
    <alias>
        <family>monospace</family>
        <prefer>
            <family>CaskaydiaCove Nerd Font</family>
        </prefer>
    </alias>
</fontconfig>
EOF

    # Copy configuration to kiosk user
    cp -r "$MOUNT_ROOT/etc/skel/.config" "$MOUNT_ROOT/home/kiosk/" 2>/dev/null || true
    chroot "$MOUNT_ROOT" chown -R kiosk:kiosk /home/kiosk/.config 2>/dev/null || true
    
    log_success "System-wide font defaults configured"
}

# Configure Chromium fonts
configure_chromium_fonts() {
    log_info "Configuring Chromium font settings..."
    
    # Create Chromium preferences directory
    mkdir -p "$MOUNT_ROOT/home/kiosk/.config/chromium/Default"
    
    # Configure Chromium font preferences
    cat > "$MOUNT_ROOT/home/kiosk/.config/chromium/Default/Preferences" << 'EOF'
{
   "webkit": {
      "webprefs": {
         "default_encoding": "UTF-8",
         "fonts": {
            "fixed": {
               "Zyyy": [ "CaskaydiaCove Nerd Font", 13 ]
            },
            "sansserif": {
               "Zyyy": [ "Inter", 14 ]
            },
            "serif": {
               "Zyyy": [ "Inter", 14 ]
            },
            "standard": {
               "Zyyy": [ "Inter", 14 ]
            }
         },
         "default_fixed_font_size": 13,
         "default_font_size": 14,
         "minimum_font_size": 9,
         "minimum_logical_font_size": 6
      }
   },
   "countryid_at_install": 21843,
   "default_apps_install_state": 3,
   "intl": {
      "accept_languages": "en-US,en"
   }
}
EOF

    # Create Chromium Local State for system-wide settings
    cat > "$MOUNT_ROOT/home/kiosk/.config/chromium/Local State" << 'EOF'
{
   "browser": {
      "enabled_labs_experiments": [
         "font-access@1"
      ]
   },
   "user_experience_metrics": {
      "stability": {
         "stats_version": 10
      }
   }
}
EOF

    # Set ownership
    chroot "$MOUNT_ROOT" chown -R kiosk:kiosk /home/kiosk/.config/chromium
    
    # Create Chromium font configuration script
    cat > "$MOUNT_ROOT/usr/local/bin/configure-chromium-fonts" << 'EOF'
#!/bin/bash
#
# Configure Chromium fonts for kiosk user
#

CHROMIUM_DIR="/home/kiosk/.config/chromium"
PROFILE_DIR="$CHROMIUM_DIR/Default"

# Ensure directories exist
mkdir -p "$PROFILE_DIR"

# Update font settings if Preferences file exists
if [[ -f "$PROFILE_DIR/Preferences" ]]; then
    # Use jq to update font settings if available
    if command -v jq >/dev/null 2>&1; then
        jq '.webkit.webprefs.fonts.sansserif.Zyyy = ["Inter", 14] |
            .webkit.webprefs.fonts.serif.Zyyy = ["Inter", 14] |
            .webkit.webprefs.fonts.standard.Zyyy = ["Inter", 14] |
            .webkit.webprefs.fonts.fixed.Zyyy = ["CaskaydiaCove Nerd Font", 13]' \
            "$PROFILE_DIR/Preferences" > "$PROFILE_DIR/Preferences.tmp" && \
            mv "$PROFILE_DIR/Preferences.tmp" "$PROFILE_DIR/Preferences"
    fi
fi

# Set ownership
chown -R kiosk:kiosk "$CHROMIUM_DIR"

echo "Chromium fonts configured"
EOF

    chmod +x "$MOUNT_ROOT/usr/local/bin/configure-chromium-fonts"
    
    log_success "Chromium font configuration created"
}

# Build font cache
build_font_cache() {
    log_info "Building font cache..."
    
    # Build system font cache
    chroot "$MOUNT_ROOT" fc-cache -fv || {
        log_warning "Failed to build system font cache"
    }
    
    # Build user font cache for kiosk user
    chroot "$MOUNT_ROOT" su - kiosk -c "fc-cache -fv" || {
        log_warning "Failed to build user font cache"
    }
    
    # Verify fonts are available
    local inter_found caskaydia_found
    inter_found=$(chroot "$MOUNT_ROOT" fc-list | grep -i "inter" | wc -l)
    caskaydia_found=$(chroot "$MOUNT_ROOT" fc-list | grep -i "caskaydia" | wc -l)
    
    log_info "Font cache built - Inter: $inter_found fonts, CaskaydiaCove: $caskaydia_found fonts"
    
    if [[ "$inter_found" -eq 0 ]]; then
        log_warning "Inter fonts not found in font cache"
    fi
    
    if [[ "$caskaydia_found" -eq 0 ]]; then
        log_warning "CaskaydiaCove fonts not found in font cache"
    fi
    
    log_success "Font cache built successfully"
}

# Create font management scripts
create_font_scripts() {
    log_info "Creating font management scripts..."
    
    # Create font status script
    cat > "$MOUNT_ROOT/usr/local/bin/font-status" << 'EOF'
#!/bin/bash
#
# KioskBook Font Status Script
#

echo "KioskBook Font Status"
echo "===================="
echo

# Font directories
echo "Font Directories:"
echo "  System: /usr/share/fonts"
echo "  User: /home/kiosk/.local/share/fonts"
echo "  Data: /data/fonts"
echo

# Available fonts
echo "Installed Fonts:"
echo "  Inter variants:"
fc-list | grep -i "inter" | awk -F: '{print "    " $2}' | sort | uniq
echo
echo "  CaskaydiaCove variants:"
fc-list | grep -i "caskaydia" | awk -F: '{print "    " $2}' | sort | uniq
echo

# Default font aliases
echo "Font Aliases:"
echo "  Sans-serif: $(fc-match sans-serif | awk -F: '{print $1}')"
echo "  Serif: $(fc-match serif | awk -F: '{print $1}')"
echo "  Monospace: $(fc-match monospace | awk -F: '{print $1}')"
echo

# Font cache status
echo "Font Cache:"
if fc-cache -v 2>&1 | grep -q "succeeded"; then
    echo "  ✓ Font cache is up to date"
else
    echo "  ✗ Font cache needs rebuilding"
fi
echo

# Font rendering settings
echo "Font Rendering:"
echo "  Antialias: $(fc-match --format='%{antialias}' sans-serif)"
echo "  Hinting: $(fc-match --format='%{hinting}' sans-serif)"
echo "  Hint Style: $(fc-match --format='%{hintstyle}' sans-serif)"
echo "  RGBA: $(fc-match --format='%{rgba}' sans-serif)"
EOF

    chmod +x "$MOUNT_ROOT/usr/local/bin/font-status"
    
    # Create font update script
    cat > "$MOUNT_ROOT/usr/local/bin/update-fonts" << 'EOF'
#!/bin/bash
#
# KioskBook Font Update Script
#

echo "Updating font cache..."
fc-cache -fv

echo "Configuring Chromium fonts..."
/usr/local/bin/configure-chromium-fonts

echo "Font update completed"
EOF

    chmod +x "$MOUNT_ROOT/usr/local/bin/update-fonts"
    
    log_success "Font management scripts created"
}

# Validate font installation
validate_fonts() {
    log_info "Validating font installation..."
    
    # Check font files exist
    local font_dirs=(
        "$MOUNT_DATA$FONT_DIR/inter"
        "$MOUNT_DATA$FONT_DIR/caskaydiaCove"
    )
    
    for dir in "${font_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_error "Font directory missing: $dir"
            exit 1
        fi
        
        local font_count
        font_count=$(find "$dir" -name "*.ttf" -o -name "*.woff2" | wc -l)
        if [[ "$font_count" -eq 0 ]]; then
            log_error "No fonts found in: $dir"
            exit 1
        fi
    done
    
    # Check fontconfig files
    local config_files=(
        "$MOUNT_ROOT/etc/fonts/local.conf"
        "$MOUNT_ROOT/etc/fonts/conf.d/10-inter.conf"
        "$MOUNT_ROOT/etc/fonts/conf.d/10-caskaydiaCove.conf"
    )
    
    for file in "${config_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Font configuration file missing: $file"
            exit 1
        fi
    done
    
    # Check if fonts are available in fc-list
    if ! chroot "$MOUNT_ROOT" fc-list | grep -qi "inter"; then
        log_error "Inter fonts not available in font cache"
        exit 1
    fi
    
    if ! chroot "$MOUNT_ROOT" fc-list | grep -qi "caskaydia"; then
        log_error "CaskaydiaCove fonts not available in font cache"
        exit 1
    fi
    
    log_success "Font installation validation passed"
}

# Main font installation function
main() {
    log_info "=========================================="
    log_info "Module: Font Installation and Configuration"
    log_info "=========================================="
    
    validate_environment
    install_font_packages
    create_font_directories
    install_inter_font
    install_caskaydia_font
    configure_fontconfig
    configure_system_fonts
    configure_chromium_fonts
    build_font_cache
    create_font_scripts
    validate_fonts
    
    log_success "Font installation and configuration completed successfully"
    log_info "Fonts installed:"
    log_info "  - Inter font family (UI/sans-serif)"
    log_info "  - CaskaydiaCove Nerd Font (monospace)"
    log_info "Font storage: $FONT_DIR (persistent)"
    log_info "Rendering: Optimized with hinting and antialiasing"
    log_info "Management: Use 'font-status' and 'update-fonts' commands"
}

# Execute main function
main "$@"