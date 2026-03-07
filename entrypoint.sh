#!/bin/bash
set -e

GPS_DEVICE="${GPS_DEVICES:-/dev/ttyUSB0}"
BAUD="${GPS_BAUD:-9600}"

echo "=== GPS Time Server ==="
echo "GPS device: $GPS_DEVICE"
echo "Baud rate:  $BAUD"

# Validate GPS device is present
if [ ! -e "$GPS_DEVICE" ]; then
    echo "WARNING: GPS device $GPS_DEVICE not found."
    echo "  - Check your device path and Unraid passthrough settings."
    echo "  - Continuing anyway; chrony will fall back to pool NTP."
fi

# Set baud rate if device exists
if [ -e "$GPS_DEVICE" ]; then
    stty -F "$GPS_DEVICE" "$BAUD" raw || true
fi

# Start gpsd
echo "Starting gpsd..."
gpsd \
    -n \
    -G \
    -S 2947 \
    -s "$BAUD" \
    "$GPS_DEVICE" \
    2>&1 &

GPSD_PID=$!
echo "gpsd PID: $GPSD_PID"

# Brief pause to let gpsd initialize SHM segments before chrony starts
sleep 2

# Start chronyd in foreground
echo "Starting chronyd..."
exec chronyd -d -f /etc/chrony/chrony.conf
