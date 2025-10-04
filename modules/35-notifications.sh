#!/bin/bash
#
# Module: 35-notifications.sh
# Description: System notification daemon and utilities
#

set -euo pipefail

# Get script directory for accessing configs
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

module_name="Notifications"
KIOSK_USER="kiosk"
KIOSK_HOME="/home/kiosk"

log_module "$module_name" "Starting notification system installation..."

# Install dunst notification daemon
log_module "$module_name" "Installing dunst notification daemon..."
DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    dunst \
    libnotify-bin \
    dbus-x11

# Create dunst config directory
mkdir -p "$KIOSK_HOME/.config/dunst"

# Install dunst configuration
log_module "$module_name" "Configuring dunst for kiosk display..."
cat > "$KIOSK_HOME/.config/dunst/dunstrc" << 'EOF'
[global]
    monitor = 0
    follow = none
    width = (300, 400)
    height = 100
    origin = top-right
    offset = 20x50
    scale = 0
    notification_limit = 5

    progress_bar = true
    progress_bar_height = 8
    progress_bar_frame_width = 1
    progress_bar_min_width = 150
    progress_bar_max_width = 300

    indicate_hidden = yes
    transparency = 10
    separator_height = 1
    padding = 16
    horizontal_padding = 16
    text_icon_padding = 12
    frame_width = 0
    gap_size = 6
    separator_color = auto
    sort = yes

    font = Inter 14
    line_height = 2
    markup = full
    format = "<b>%s</b>\n%b"
    alignment = left
    vertical_alignment = center
    show_age_threshold = 60
    ellipsize = end
    ignore_newline = no
    stack_duplicates = true
    hide_duplicate_count = false
    show_indicators = no

    enable_recursive_icon_lookup = true
    icon_position = left
    min_icon_size = 32
    max_icon_size = 48
    icon_path = /usr/share/icons/gnome/48x48/status/:/usr/share/icons/gnome/48x48/devices/:/usr/share/icons/gnome/48x48/legacy/

    sticky_history = yes
    history_length = 20

    dmenu = /usr/bin/dmenu -p dunst:
    browser = /usr/bin/xdg-open

    always_run_script = true
    title = Dunst
    class = Dunst
    corner_radius = 8
    ignore_dbusclose = false

    force_xwayland = false
    force_xinerama = false

    mouse_left_click = close_current
    mouse_middle_click = close_current
    mouse_right_click = close_all

[experimental]
    per_monitor_dpi = false

[urgency_low]
    background = "#f5f5f7"
    foreground = "#1d1d1f"
    timeout = 5

[urgency_normal]
    background = "#ffffff"
    foreground = "#1d1d1f"
    timeout = 8

[urgency_critical]
    background = "#ffffff"
    foreground = "#1d1d1f"
    timeout = 0
EOF

chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.config/dunst"

# Add dunst to OpenBox autostart if not already present
if ! grep -q "dunst" "$KIOSK_HOME/.config/openbox/autostart" 2>/dev/null; then
    log_module "$module_name" "Adding dunst to OpenBox autostart..."
    echo "" >> "$KIOSK_HOME/.config/openbox/autostart"
    echo "# Start notification daemon" >> "$KIOSK_HOME/.config/openbox/autostart"
    echo "dunst &" >> "$KIOSK_HOME/.config/openbox/autostart"
    chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.config/openbox/autostart"
fi

# Create notification helper script
log_module "$module_name" "Installing notification helper script..."
cat > /usr/local/bin/kioskbook-notify << 'EOF'
#!/bin/bash
#
# KioskBook Notification Helper
# Send desktop notifications to the kiosk display
#
# Usage: kioskbook-notify "Title" "Message" [urgency]
#   urgency: low, normal, critical (default: normal)
#

TITLE="${1:-Notification}"
MESSAGE="${2:-}"
URGENCY="${3:-normal}"
KIOSK_USER="kiosk"

if [[ -z "$MESSAGE" ]]; then
    echo "Usage: kioskbook-notify \"Title\" \"Message\" [urgency]"
    echo "  urgency: low, normal, critical (default: normal)"
    exit 1
fi

# Send notification to the kiosk display
if [[ "$USER" == "$KIOSK_USER" ]]; then
    # Already running as kiosk user
    DISPLAY=:0 notify-send \
        -u "$URGENCY" \
        -a "KioskBook" \
        "$TITLE" \
        "$MESSAGE"
else
    # Running as another user (e.g., root)
    DISPLAY=:0 sudo -u "$KIOSK_USER" notify-send \
        -u "$URGENCY" \
        -a "KioskBook" \
        "$TITLE" \
        "$MESSAGE"
fi
EOF

chmod +x /usr/local/bin/kioskbook-notify

log_module_success "$module_name" "Notification system configured"
