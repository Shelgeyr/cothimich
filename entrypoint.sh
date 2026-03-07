#!/bin/bash
set -e

GPS_DEVICE="${GPS_DEVICES:-/dev/ttyACM0}"
BAUD="${GPS_BAUD:-9600}"

echo "=== GPS Time Server ==="
echo "GPS device: $GPS_DEVICE"
echo "Baud rate:  $BAUD"

# Fix permissions on volume-mounted directories at runtime
# (volume mounts from Unraid overwrite build-time permissions)
mkdir -p /run/chrony /var/lib/chrony /var/log/chrony /run/gpsd
chown -R _chrony:_chrony /run/chrony /var/lib/chrony /var/log/chrony
chmod 750 /run/chrony
chmod 755 /var/lib/chrony /var/log/chrony

# Validate GPS device is present
if [ ! -e "$GPS_DEVICE" ]; then
    echo "WARNING: GPS device $GPS_DEVICE not found."
    echo "  - Continuing anyway; chrony will fall back to pool NTP."
fi

# Set baud rate if device exists
if [ -e "$GPS_DEVICE" ]; then
    stty -F "$GPS_DEVICE" "$BAUD" raw || true
fi

# Start gpsd
echo "Starting gpsd..."
gpsd -n -G -S 2947 -s "$BAUD" "$GPS_DEVICE" 2>&1 &
GPSD_PID=$!
echo "gpsd PID: $GPSD_PID"

# Wait for gpsd to initialize SHM segments
sleep 3

# Start chronyd in foreground, drops to _chrony after binding port 123
echo "Starting chronyd..."
exec chronyd -d -u _chrony -f /etc/chrony/chrony.conf
