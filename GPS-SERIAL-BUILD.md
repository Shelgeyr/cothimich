# Building a Serial GPS with PPS for cothimich

This guide covers building a u-blox NEO-M8T GPS receiver with PPS output connected to a DB9 serial port. This replaces the USB GPS dongle and brings chrony accuracy from ~1ms (NMEA over USB) down to ~1µs (PPS over serial).

---

## Quick Reference

### Parts List

| Part | Notes |
|---|---|
| u-blox NEO-M8T breakout board | Timing-specific variant, PPS pin broken out. Search "NEO-M8T breakout" on Amazon or CSG Shop. ~$40-60 |
| MAX3232 breakout board | 3.3v TTL to RS232 level shifter. ~$5 |
| Active GPS antenna with SMA connector | 28-35dB gain, u.FL to SMA adapter cable needed. ~$10-20 |
| u.FL to SMA adapter cable | Connects antenna to NEO-M8T onboard u.FL connector. ~$5 |
| DB9 female connector or cable | To connect to server's serial port |
| Jumper wires | For breadboard or direct wiring |
| 5v USB power source | To power the NEO-M8T |

### Wiring Quick Reference

| NEO-M8T Pin | MAX3232 Pin | DB9 Pin | Signal |
|---|---|---|---|
| TX | T1IN | Pin 2 | RX (data to host) |
| RX | R1OUT | Pin 3 | TX (data from host) |
| PPS | — (bypass) | Pin 1 | DCD (PPS signal) |
| GND | GND | Pin 5 | Ground |
| 3.3v | VCC | — | Power to MAX3232 |

**PPS bypasses the MAX3232 entirely** — connect it directly from the NEO-M8T PPS pin to DB9 pin 1 (DCD).

---

## Detailed Build Guide

### Understanding the Hardware

**Why NEO-M8T and not NEO-M8N?**
The M8T is u-blox's timing-specific variant. While the M8N is a navigation module that happens to have a PPS output, the M8T is designed from the ground up for timing applications. Key differences:
- Lower PPS jitter (~10ns RMS vs ~30ns on M8N)
- Dedicated timing firmware
- Can be locked to a single constellation for more stable timing
- Supports raw measurement output for post-processing

**Why a level shifter?**
The NEO-M8T operates at 3.3v TTL logic levels. RS232 (what your DB9 port uses) operates at ±12v. Connecting 3.3v TTL directly to an RS232 port will damage the module. The MAX3232 converts between the two safely.

**Why does PPS bypass the MAX3232?**
The PPS signal is read by the kernel as a voltage transition on the DCD (Data Carrier Detect) pin, not as serial data. The MAX3232 introduces propagation delay and signal distortion that would degrade PPS timing accuracy. A direct connection preserves the sharp edges of the PPS pulse that the kernel timestamps.

---

### Step 1 — Antenna Placement

Mount the active GPS antenna with a clear view of the sky. The antenna needs line-of-sight to satellites — even a partial sky view through a window will work but rooftop or outdoor mounting gives the best results.

- Keep coax cable runs under 10 meters where possible. Longer runs require higher gain antenna to compensate for cable loss.
- Active antennas require DC power on the coax center conductor. The NEO-M8T supplies this automatically — do not use a DC block between the module and antenna.
- The u.FL connector on the NEO-M8T is fragile. Connect and disconnect it carefully and avoid strain on the cable near the connector.

---

### Step 2 — Wiring the MAX3232

The MAX3232 breakout typically has these pins labeled:

```
VCC  — 3.3v from NEO-M8T
GND  — Ground
T1IN — TTL input  (connect to NEO-M8T TX)
R1OUT— TTL output (connect to NEO-M8T RX)
T1OUT— RS232 output (connect to DB9 pin 2)
R1IN — RS232 input  (connect to DB9 pin 3)
```

Wire it up in this order:

1. **NEO-M8T 3.3v → MAX3232 VCC**
2. **NEO-M8T GND → MAX3232 GND**
3. **NEO-M8T TX → MAX3232 T1IN**
4. **NEO-M8T RX → MAX3232 R1OUT**
5. **MAX3232 T1OUT → DB9 Pin 2** (RXD on host side)
6. **MAX3232 R1IN → DB9 Pin 3** (TXD on host side)
7. **NEO-M8T GND → DB9 Pin 5** (Ground)
8. **NEO-M8T PPS → DB9 Pin 1** (DCD — direct, no MAX3232)

Double-check pin 1 vs pin 2 on your DB9 — DB9 pin numbering can be confusing. Pin 1 is DCD, pin 2 is RXD, pin 3 is TXD, pin 5 is GND. The pins are numbered on the connector body.

---

### Step 3 — Powering the NEO-M8T

The NEO-M8T breakout board typically accepts 5v USB power via a micro-USB connector and has an onboard 3.3v regulator. Power it from any USB port or charger. The 3.3v output from the onboard regulator then powers the MAX3232 and feeds the logic levels.

If your breakout has no USB connector, power it directly at 3.3v or 5v depending on what the board accepts — check your specific breakout's documentation.

---

### Step 4 — Configure the NEO-M8T with u-center

u-center is u-blox's free Windows configuration tool. You'll want to configure the module before connecting it to cothimich.

**Download:** https://www.u-blox.com/en/product/u-center

Connect the NEO-M8T via USB to a Windows machine for initial configuration. Once configured, settings are saved to the module's flash and persist when you move it to the serial connection.

**Recommended settings:**

1. **Set baud rate to 115200**
   - View → Configuration → PRT (Ports)
   - Set UART1 baud rate to 115200
   - Send configuration

2. **Enable required NMEA sentences**
   - View → Configuration → MSG (Messages)
   - Enable: GGA, RMC, GSA, GSV on UART1
   - Disable unnecessary sentences to reduce serial load

3. **Configure PPS output**
   - View → Configuration → TP (Timepulse)
   - Set timepulse period to 1000000 µs (1 second)
   - Set pulse length to 100000 µs (100ms — gives a clean detectable pulse)
   - Set time source to GPS
   - Enable timepulse

4. **Lock to GPS constellation only (optional but recommended for timing)**
   - View → Configuration → GNSS
   - Disable GLONASS, Galileo, BeiDou
   - Keep GPS enabled
   - This gives more stable timing at the cost of fewer satellites

5. **Save configuration to flash**
   - View → Configuration → CFG
   - Click "Save current configuration" → Send

---

### Step 5 — Test Before Connecting to Server

Before connecting to the Unraid server, verify the serial output is working:

On any Linux machine with the DB9 connected:

```bash
# Install minicom if needed
sudo apt install minicom

# Check serial output at 115200 baud
sudo minicom -D /dev/ttyS0 -b 115200
```

You should see a stream of NMEA sentences like:
```
$GNGGA,123456.00,4012.12345,N,10512.12345,W,1,08,1.2,1500.0,M,...
$GNRMC,123456.00,A,4012.12345,N,10512.12345,W,0.0,0.0,...
```

If you see garbage characters the baud rate is wrong. If you see nothing, check your TX/RX wiring — they may need to be swapped.

**Test PPS signal:**

```bash
# Load the PPS line discipline kernel module
sudo modprobe pps_ldisc

# Attach PPS to the serial port
sudo ldattach PPS /dev/ttyS0

# Check PPS device was created
ls /dev/pps*

# Install pps-tools and test
sudo apt install pps-tools
sudo ppstest /dev/pps0
```

You should see output like:
```
trying PPS source "/dev/pps0"
found PPS source "/dev/pps0"
ok, found 1 source(s), now start fetching data...
source 0 - assert 1234567890.000012345, sequence: 1
source 0 - assert 1234567890.999987654, sequence: 2
```

The assert timestamps should be very close to whole seconds. If ppstest shows no data, check the PPS wire connection to DB9 pin 1.

---

### Step 6 — Connect to Unraid and Update cothimich

1. Connect the DB9 cable to your Unraid server's serial port
2. Verify the device appears: `ls /dev/ttyS0`
3. Load the PPS kernel module on Unraid:
   ```bash
   modprobe pps_ldisc
   ldattach PPS /dev/ttyS0
   ```
   To make this persistent across reboots, add to `/boot/config/go`:
   ```bash
   modprobe pps_ldisc
   ldattach PPS /dev/ttyS0
   ```

4. Update cothimich container settings in Unraid:
   - `GPS Device` → `/dev/ttyS0`
   - `GPS Device Path` → `/dev/ttyS0`
   - `GPS Baud Rate` → `115200`
   - `PPS Device` → `/dev/pps0`

5. Restart the container and verify:
   ```bash
   docker exec cothimich chronyc sources -v
   ```

   You should now see PPS as the preferred source (`*`) with an error bound of ~1µs rather than ~200ms.

---

### Expected chronyc Output with PPS

```
MS Name/IP address    Stratum Poll Reach LastRx Last sample
================================================================
#* PPS                      0   4   377    5    +123ns[ +123ns] +/-  500ns
#- GPS                      0   4   377    5    +1ms[   +1ms] +/-  200ms
^+ time-a-wwv.nist.gov      1   6   377   10    -45us[  -45us] +/-   10ms
```

PPS with `*` and nanosecond-level offset is what you're aiming for. At that point cothimich is a genuine stratum 1 server.

---

### Troubleshooting

**PPS device not created after ldattach**
- Check `dmesg | grep pps` — the module may not be loading
- Verify the PPS wire is on DB9 pin 1 (DCD), not pin 6 (DSR) or pin 8 (CTS)
- Try `sudo stty -F /dev/ttyS0 115200 raw` before ldattach

**chrony shows PPS as `?` (unusable)**
- GPS needs a fix first — PPS is only valid when the module has locked to satellites
- Check `docker exec cothimich cgps 192.168.87.10` to confirm GPS fix

**NMEA sentences garbled**
- Baud rate mismatch — try 9600 if 115200 doesn't work (default NEO-M8T baud is 9600 before u-center configuration)
- TX/RX wired backwards — swap the T1IN/R1OUT connections on the MAX3232

**No NMEA output at all**
- Check power to NEO-M8T — the LED on most breakout boards indicates power and fix status
- Verify GND is connected between NEO-M8T, MAX3232, and DB9
