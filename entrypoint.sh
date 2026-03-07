#!/bin/bash
set -e

GPS_DEVICE="${GPS_DEVICES:-/dev/ttyACM0}"
BAUD="${GPS_BAUD:-9600}"
PPS_DEVICE="${PPS_DEVICE:-}"

echo "=== GPS Time Server ==="
echo "GPS device: $GPS_DEVICE"
echo "Baud rate:  $BAUD"
if [ -n "$PPS_DEVICE" ]; then
    echo "PPS device: $PPS_DEVICE"
else
    echo "PPS device: not configured"
fi

# Fix permissions on volume-mounted directories at runtime
mkdir -p /run/chrony /var/lib/chrony /var/log/chrony /run/gpsd
chown -R _chrony:_chrony /run/chrony /var/lib/chrony /var/log/chrony
chmod 750 /run/chrony
chmod 755 /var/lib/chrony /var/log/chrony

# Validate GPS device is present
if [ ! -e "$GPS_DEVICE" ]; then
    echo "WARNING: GPS device $GPS_DEVICE not found."
    echo "  - Continuing anyway; chrony will fall back to NIST servers."
fi

# Set baud rate if device exists
if [ -e "$GPS_DEVICE" ]; then
    stty -F "$GPS_DEVICE" "$BAUD" raw || true
fi

# Build gpsd device list - include PPS device if configured
GPSD_DEVICES="$GPS_DEVICE"
if [ -n "$PPS_DEVICE" ] && [ -e "$PPS_DEVICE" ]; then
    echo "PPS device found, adding to gpsd..."
    GPSD_DEVICES="$GPS_DEVICE $PPS_DEVICE"
fi

# Start gpsd
echo "Starting gpsd..."
gpsd -n -G -S 2947 -s "$BAUD" $GPSD_DEVICES 2>&1 &
GPSD_PID=$!
echo "gpsd PID: $GPSD_PID"

# Wait for gpsd to initialize SHM segments
sleep 3

# Generate chrony.conf with or without PPS refclock
if [ -n "$PPS_DEVICE" ] && [ -e "$PPS_DEVICE" ]; then
    echo "PPS enabled - using high precision refclock"
    # Uncomment PPS refclock in chrony.conf
    sed -i 's/^#PPS //' /etc/chrony/chrony.conf
fi

# Start chronyd in foreground, drops to _chrony after binding port 123
echo "Starting chronyd..."
exec chronyd -d -u _chrony -f /etc/chrony/chrony.conf
