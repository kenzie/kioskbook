#!/bin/bash
# KioskBook Hardware Optimizations Module - Lenovo M75q-1 Tiny

# Setup hardware-specific optimizations for Lenovo M75q-1 Tiny
setup_hardware_optimizations() {
    log_step "Setting Up Lenovo M75q-1 Tiny Hardware Optimizations"
    
    # Install hardware monitoring and management tools
    chroot /mnt/root apk add lm-sensors hdparm smartmontools cpufrequtils
    
    # Create hardware optimization service
    cat > /mnt/root/etc/init.d/hardware-optimize << 'EOF'
#!/sbin/openrc-run

name="Hardware Optimize"
description="Lenovo M75q-1 Tiny hardware optimizations"

depend() {
    need localmount
    after localmount
}

start() {
    ebegin "Starting hardware optimizations"
    
    # Detect and configure hardware
    /opt/hardware-detect.sh
    
    # Apply optimizations
    /opt/hardware-optimize.sh
    
    eend $?
}

stop() {
    ebegin "Stopping hardware optimizations"
    eend 0
}
EOF
    
    chmod +x /mnt/root/etc/init.d/hardware-optimize
    chroot /mnt/root rc-update add hardware-optimize default
    
    # Create hardware detection script
    cat > /mnt/root/opt/hardware-detect.sh << 'EOF'
#!/bin/bash
# Lenovo M75q-1 Tiny Hardware Detection

HARDWARE_CONFIG="/etc/kioskbook/hardware.conf"
mkdir -p /etc/kioskbook

# Detect CPU
CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
CPU_CORES=$(nproc)
CPU_THREADS=$(grep -c processor /proc/cpuinfo)

# Detect memory
MEMORY_TOTAL=$(free -m | grep Mem | awk '{print $2}')
MEMORY_AVAILABLE=$(free -m | grep Mem | awk '{print $7}')

# Detect storage
STORAGE_DEVICE=$(lsblk -d -o NAME,TYPE | grep disk | head -1 | awk '{print $1}')
STORAGE_SIZE=$(lsblk -d -o NAME,SIZE | grep disk | head -1 | awk '{print $2}')
STORAGE_TYPE=$(cat /sys/block/$STORAGE_DEVICE/queue/rotational 2>/dev/null || echo "0")

# Detect GPU
GPU_MODEL=$(lspci | grep -i vga | head -1 | cut -d: -f3 | xargs)
GPU_DRIVER=$(lspci -k | grep -A 2 -i vga | grep "Kernel driver" | awk '{print $4}')

# Detect network
NETWORK_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
NETWORK_SPEED=$(ethtool $NETWORK_INTERFACE 2>/dev/null | grep "Speed" | awk '{print $2}' || echo "Unknown")

# Create hardware configuration
cat > "$HARDWARE_CONFIG" << 'CONFIGEOF'
# Lenovo M75q-1 Tiny Hardware Configuration
# Generated on $(date)

# CPU Information
CPU_MODEL="$CPU_MODEL"
CPU_CORES=$CPU_CORES
CPU_THREADS=$CPU_THREADS

# Memory Information
MEMORY_TOTAL=${MEMORY_TOTAL}MB
MEMORY_AVAILABLE=${MEMORY_AVAILABLE}MB

# Storage Information
STORAGE_DEVICE=/dev/$STORAGE_DEVICE
STORAGE_SIZE=$STORAGE_SIZE
STORAGE_TYPE=$([ "$STORAGE_TYPE" = "0" ] && echo "NVMe" || echo "HDD")

# GPU Information
GPU_MODEL="$GPU_MODEL"
GPU_DRIVER="$GPU_DRIVER"

# Network Information
NETWORK_INTERFACE=$NETWORK_INTERFACE
NETWORK_SPEED=$NETWORK_SPEED

# Hardware Profile
HARDWARE_PROFILE="lenovo-m75q-1-tiny"
CONFIGEOF

    echo "Hardware detection completed:"
    echo "  CPU: $CPU_MODEL ($CPU_CORES cores, $CPU_THREADS threads)"
    echo "  Memory: ${MEMORY_TOTAL}MB total, ${MEMORY_AVAILABLE}MB available"
    echo "  Storage: $STORAGE_SIZE $([ "$STORAGE_TYPE" = "0" ] && echo "NVMe" || echo "HDD")"
    echo "  GPU: $GPU_MODEL ($GPU_DRIVER driver)"
    echo "  Network: $NETWORK_INTERFACE ($NETWORK_SPEED)"
}
EOF
    
    chmod +x /mnt/root/opt/hardware-detect.sh
    
    # Create hardware optimization script
    cat > /mnt/root/opt/hardware-optimize.sh << 'EOF'
#!/bin/bash
# Lenovo M75q-1 Tiny Hardware Optimizations

HARDWARE_CONFIG="/etc/kioskbook/hardware.conf"

if [ ! -f "$HARDWARE_CONFIG" ]; then
    echo "Hardware configuration not found, running detection..."
    /opt/hardware-detect.sh
fi

source "$HARDWARE_CONFIG"

echo "Applying Lenovo M75q-1 Tiny optimizations..."

# CPU Optimizations
optimize_cpu() {
    echo "Optimizing CPU for kiosk operation..."
    
    # Set CPU governor to performance for consistent kiosk operation
    if [ -d /sys/devices/system/cpu/cpufreq ]; then
        echo performance > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null || true
        echo performance > /sys/devices/system/cpu/cpufreq/policy1/scaling_governor 2>/dev/null || true
    fi
    
    # Disable CPU frequency scaling for consistent performance
    echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || true
    
    # Set CPU to maximum frequency
    echo 100 > /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq 2>/dev/null || true
    echo 100 > /sys/devices/system/cpu/cpufreq/policy1/scaling_max_freq 2>/dev/null || true
}

# Memory Optimizations
optimize_memory() {
    echo "Optimizing memory for kiosk operation..."
    
    # Optimize memory settings for kiosk
    echo 10 > /proc/sys/vm/swappiness
    echo 15 > /proc/sys/vm/dirty_ratio
    echo 5 > /proc/sys/vm/dirty_background_ratio
    
    # Enable memory overcommit for kiosk applications
    echo 1 > /proc/sys/vm/overcommit_memory
    
    # Optimize page cache
    echo 1 > /proc/sys/vm/drop_caches
}

# Storage Optimizations
optimize_storage() {
    echo "Optimizing NVMe storage..."
    
    # NVMe specific optimizations
    if [ "$STORAGE_TYPE" = "NVMe" ]; then
        # Enable NVMe power management
        echo 1 > /sys/module/nvme/parameters/default_ps_max_latency_us 2>/dev/null || true
        
        # Optimize I/O scheduler for NVMe
        echo mq-deadline > /sys/block/$STORAGE_DEVICE/queue/scheduler 2>/dev/null || true
        
        # Increase read-ahead for kiosk applications
        echo 1024 > /sys/block/$STORAGE_DEVICE/queue/read_ahead_kb 2>/dev/null || true
        
        # Enable write caching
        hdparm -W 1 /dev/$STORAGE_DEVICE 2>/dev/null || true
    fi
}

# GPU Optimizations
optimize_gpu() {
    echo "Optimizing AMD GPU for kiosk operation..."
    
    # AMD GPU specific optimizations
    if echo "$GPU_MODEL" | grep -i amd >/dev/null; then
        # Enable GPU acceleration
        echo "amdgpu" > /etc/modules-load.d/amdgpu.conf 2>/dev/null || true
        
        # Set GPU power profile to performance
        echo high > /sys/class/drm/card0/device/power_dpm_force_performance_level 2>/dev/null || true
        
        # Disable GPU power management for consistent performance
        echo 0 > /sys/class/drm/card0/device/power_dpm_state 2>/dev/null || true
    fi
}

# Network Optimizations
optimize_network() {
    echo "Optimizing network for kiosk operation..."
    
    # Optimize network buffer sizes
    echo 16777216 > /proc/sys/net/core/rmem_max
    echo 16777216 > /proc/sys/net/core/wmem_max
    echo 4096 87380 16777216 > /proc/sys/net/ipv4/tcp_rmem
    echo 4096 65536 16777216 > /proc/sys/net/ipv4/tcp_wmem
    
    # Optimize network interface
    if [ -n "$NETWORK_INTERFACE" ]; then
        # Enable network interface optimizations
        ethtool -G $NETWORK_INTERFACE rx 1024 tx 1024 2>/dev/null || true
        ethtool -K $NETWORK_INTERFACE gro on gso on tso on 2>/dev/null || true
    fi
}

# Power Management Optimizations
optimize_power() {
    echo "Optimizing power management for kiosk operation..."
    
    # Disable power management features that can cause issues
    echo 0 > /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null || true
    echo 0 > /sys/module/usbcore/parameters/autosuspend 2>/dev/null || true
    
    # Set power management to performance mode
    echo performance > /sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference 2>/dev/null || true
    echo performance > /sys/devices/system/cpu/cpufreq/policy1/energy_performance_preference 2>/dev/null || true
}

# Thermal Management
optimize_thermal() {
    echo "Configuring thermal management..."
    
    # Set thermal management to performance mode
    echo performance > /sys/class/thermal/thermal_zone0/policy 2>/dev/null || true
    echo performance > /sys/class/thermal/thermal_zone1/policy 2>/dev/null || true
    
    # Configure fan control for consistent cooling
    echo 1 > /sys/class/hwmon/hwmon0/pwm1_enable 2>/dev/null || true
    echo 100 > /sys/class/hwmon/hwmon0/pwm1 2>/dev/null || true
}

# Apply all optimizations
main() {
    optimize_cpu
    optimize_memory
    optimize_storage
    optimize_gpu
    optimize_network
    optimize_power
    optimize_thermal
    
    echo "Lenovo M75q-1 Tiny hardware optimizations completed"
}

# Run optimizations
main
EOF
    
    chmod +x /mnt/root/opt/hardware-optimize.sh
    
    # Create hardware monitoring script
    cat > /mnt/root/opt/hardware-monitor.sh << 'EOF'
#!/bin/bash
# Lenovo M75q-1 Tiny Hardware Monitoring

HARDWARE_CONFIG="/etc/kioskbook/hardware.conf"
source "$HARDWARE_CONFIG"

echo "=== Lenovo M75q-1 Tiny Hardware Status ==="
echo

# CPU Status
echo "CPU Status:"
echo "  Model: $CPU_MODEL"
echo "  Cores: $CPU_CORES"
echo "  Threads: $CPU_THREADS"
echo "  Load: $(cat /proc/loadavg | awk '{print $1}')"
echo "  Temperature: $(sensors 2>/dev/null | grep "Core 0" | awk '{print $3}' || echo "N/A")"
echo

# Memory Status
echo "Memory Status:"
echo "  Total: $MEMORY_TOTAL"
echo "  Available: $MEMORY_AVAILABLE"
echo "  Usage: $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')"
echo

# Storage Status
echo "Storage Status:"
echo "  Device: $STORAGE_DEVICE"
echo "  Size: $STORAGE_SIZE"
echo "  Type: $STORAGE_TYPE"
echo "  Usage: $(df / | tail -1 | awk '{print $5}')"
echo "  Health: $(smartctl -H $STORAGE_DEVICE 2>/dev/null | grep "SMART overall-health" | awk '{print $6}' || echo "N/A")"
echo

# GPU Status
echo "GPU Status:"
echo "  Model: $GPU_MODEL"
echo "  Driver: $GPU_DRIVER"
echo "  Temperature: $(sensors 2>/dev/null | grep "GPU" | awk '{print $2}' || echo "N/A")"
echo

# Network Status
echo "Network Status:"
echo "  Interface: $NETWORK_INTERFACE"
echo "  Speed: $NETWORK_SPEED"
echo "  Status: $(ip link show $NETWORK_INTERFACE | grep "state" | awk '{print $9}')"
echo

# Thermal Status
echo "Thermal Status:"
sensors 2>/dev/null | grep -E "(Core|GPU|temp)" || echo "  Temperature sensors not available"
echo

# Power Status
echo "Power Status:"
echo "  CPU Governor: $(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null || echo "N/A")"
echo "  GPU Power Level: $(cat /sys/class/drm/card0/device/power_dpm_force_performance_level 2>/dev/null || echo "N/A")"
EOF
    
    chmod +x /mnt/root/opt/hardware-monitor.sh
    
    # Add hardware monitoring to crontab (every 5 minutes)
    echo "*/5 * * * * /opt/hardware-monitor.sh >> /var/log/hardware-monitor.log 2>&1" | chroot /mnt/root crontab -
    
    # Update kiosk CLI to include hardware commands
    cat >> /mnt/root/usr/local/bin/kiosk << 'EOF'

# Add hardware commands to kiosk CLI
    "hardware")
        case "$2" in
            "status")
                /opt/hardware-monitor.sh
                ;;
            "optimize")
                /opt/hardware-optimize.sh
                ;;
            "detect")
                /opt/hardware-detect.sh
                ;;
            *)
                echo "Usage: kiosk hardware {status|optimize|detect}"
                echo
                echo "Commands:"
                echo "  status   Show hardware status and monitoring"
                echo "  optimize Apply hardware optimizations"
                echo "  detect   Detect and configure hardware"
                ;;
        esac
        ;;
    "hw-status")
        /opt/hardware-monitor.sh
        ;;
    "hw-optimize")
        /opt/hardware-optimize.sh
        ;;
    "hw-detect")
        /opt/hardware-detect.sh
        ;;
EOF
    
    # Update kiosk CLI help
    sed -i '/Commands:/a\
    hardware     Hardware management and monitoring\
    hw-status    Show hardware status\
    hw-optimize  Apply hardware optimizations\
    hw-detect    Detect hardware configuration' /mnt/root/usr/local/bin/kiosk
    
    log_info "Lenovo M75q-1 Tiny hardware optimizations installed"
}
