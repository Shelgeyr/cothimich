# cothimich

A Docker container that runs `gpsd` and `chrony` together to provide a GPS-disciplined NTP server for your LAN.

---

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Container definition |
| `entrypoint.sh` | Starts gpsd then chronyd |
| `chrony.conf` | Chrony config with GPS SHM + fallback pool |
| `gpsd.conf` | gpsd defaults (device, options) |
| `docker-compose.yml` | Compose file for testing or Unraid |

---

## Requirements

- A GPS receiver connected via USB or serial (e.g. u-blox, GlobalTop, SiRF)
- Optionally: a GPS with a PPS output for sub-millisecond accuracy
- Unraid with the **Community Applications** plugin for easy template setup

---

## Building

```bash
docker build -t cothimich .
```

---

## Running on Unraid

### Option A: Docker Compose (via Unraid terminal)
```bash
cd /your/path
docker compose up -d
```

### Option B: Unraid GUI (Add Container manually)

1. In Unraid, go to **Docker → Add Container**
2. Use these settings:

| Setting | Value |
|---|---|
| Name | `cothimich` |
| Repository | your built image or a registry tag |
| Network Type | **Host** |
| IPC | **Host** |
| Extra Parameters | `--cap-add=SYS_TIME --cap-add=SYS_NICE` |

3. Add a **Device** mapping:
   - `/dev/ttyUSB0` → `/dev/ttyUSB0` (or your GPS device)

4. Add **Environment Variables**:
   - `GPS_DEVICES` = `/dev/ttyUSB0`
   - `GPS_BAUD` = `9600` (57600 or 115200 for faster GPS modules)

---

## Key Design Decisions

### Why `ipc: host` and `network_mode: host`?

- **`ipc: host`** — gpsd communicates with chrony via POSIX SHM (shared memory). This only works if both processes share the host's IPC namespace. Without it, SHM segments are invisible to chrony and GPS discipline won't work.
- **`network_mode: host`** — NTP runs on UDP 123. NAT/bridge mode causes issues with NTP client compatibility and broadcast. Host networking is the clean solution.

### SHM 0 vs SHM 1

gpsd writes to two SHM segments:
- **SHM 0** — NMEA sentence timestamps (~1 second accuracy, coarse)
- **SHM 1** — PPS pulse (sub-millisecond accuracy, only if your GPS has a PPS pin)

If your GPS lacks PPS, comment out the `refclock SHM 1` line in `chrony.conf`. Chrony will still work with SHM 0 + pool servers but accuracy will be ~10ms rather than ~1µs.

### PPS Accuracy

For high-accuracy PPS, you may also need:
- `/dev/pps0` passed through to the container
- `linuxpps` driver support (check your Unraid kernel: `modprobe pps_ldisc`)
- Replacing `refclock SHM 1` with `refclock PPS /dev/pps0`

---

## Verifying It Works

```bash
# Check GPS lock
docker exec cothimich gpsmon

# Check chrony sync sources
docker exec cothimich chronyc sources -v

# Check tracking
docker exec cothimich chronyc tracking
```

In `chronyc sources`, you want to see:
- `GPS` with a `*` or `+` prefix (selected/combined)
- `PPS` with `*` prefix (preferred source) if PPS is wired up

---

## Finding Your GPS Device

```bash
# On Unraid host:
ls /dev/ttyUSB* /dev/ttyACM*

# Or watch for new device after plugging in:
dmesg | tail -20
```

---

## Client Setup

Any machine on your LAN can use cothimich as its NTP server and optionally query gpsd for GPS location data.

### Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/Shelgeyr/cothimich/main/setup-cothimich.sh -o setup-cothimich.sh
chmod +x setup-cothimich.sh
sudo ./setup-cothimich.sh
```

The script will:
- Detect your OS (Ubuntu/Debian and Arch supported)
- Remove conflicting NTP daemons (systemd-timesyncd, ntpd) after asking
- Install chrony and gpsd client tools
- Configure chrony to use cothimich as primary NTP with NIST as fallback
- Configure `cgps` to connect to cothimich automatically

### Override the Server IP

By default the script targets `192.168.87.10`. Override it if needed:

```bash
sudo NTP_SERVER=192.168.87.x ./setup-cothimich.sh
```

### Verify Client Sync

After running the script:

```bash
# Check NTP sources — cothimich should show as * or +
chronyc sources -v

# Check GPS data from cothimich
source /etc/profile.d/gpsd-client.sh
cgps 192.168.87.10
# or
```

### Manual chrony config (if you prefer)

Add this to `/etc/chrony.conf` or `/etc/chrony/chrony.conf`:

```
server 192.168.87.10 iburst prefer
makestep 1 3
driftfile /var/lib/chrony/drift
```

Then restart chrony:
```bash
sudo systemctl restart chrony
```

---

## Upgrading

The container image rebuilds automatically every Sunday via GitHub Actions, picking up base image updates. On Unraid, update the container via the Docker tab or use Watchtower to automate pulls.

To manually pull the latest image:
```bash
docker pull ghcr.io/shelgeyr/cothimich:latest
docker restart cothimich
```

---

## PPS Upgrade Path

The container is ready for a PPS-capable GPS on a serial port. When you have a u-blox NEO-M8T connected to `/dev/ttyS0` with PPS wired to the DCD pin:

1. In the Unraid template set:
   - `GPS Device` → `/dev/ttyS0`
   - `GPS Device Path` → `/dev/ttyS0`
   - `PPS Device` → `/dev/pps0`
2. Restart the container — PPS refclock is enabled automatically

This will bring chrony accuracy down from ~1ms (NMEA) to ~1µs (PPS).
