#!/bin/bash
# setup-ntp-client.sh
# Configures a client machine to use cothimich as NTP server
# and installs gpsd client tools for GPS data access.
# Supports: Ubuntu/Debian, Arch Linux

set -e

# ─── Configuration ────────────────────────────────────────────────────────────
NTP_SERVER="${NTP_SERVER:-192.168.87.10}"  # Override with: NTP_SERVER=x.x.x.x ./setup-ntp-client.sh
GPSD_HOST="${GPSD_HOST:-$NTP_SERVER}"
GPSD_PORT="${GPSD_PORT:-2947}"
# ──────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

ask() {
    # ask <prompt> -- returns 0 for yes, 1 for no
    local prompt="$1"
    while true; do
        read -rp "$(echo -e "${YELLOW}[?]${NC} $prompt [y/N]: ")" yn
        case "$yn" in
            [Yy]*) return 0 ;;
            [Nn]*|"") return 1 ;;
        esac
    done
}

# ─── Root check ───────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    error "Please run as root: sudo $0"
fi

# ─── Detect OS ────────────────────────────────────────────────────────────────
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_LIKE="${ID_LIKE:-}"
    else
        error "Cannot detect OS — /etc/os-release not found."
    fi

    case "$OS_ID" in
        ubuntu|debian|linuxmint|pop)
            DISTRO="debian"
            PKG_INSTALL="apt-get install -y"
            PKG_UPDATE="apt-get update"
            CHRONY_PKG="chrony"
            GPSD_PKG="gpsd-clients"
            ;;
        arch|manjaro|endeavouros)
            DISTRO="arch"
            PKG_INSTALL="pacman -S --noconfirm"
            PKG_UPDATE="pacman -Sy"
            CHRONY_PKG="chrony"
            GPSD_PKG="gpsd"
            ;;
        *)
            # Fallback: check ID_LIKE
            if echo "$OS_LIKE" | grep -q "debian\|ubuntu"; then
                DISTRO="debian"
                PKG_INSTALL="apt-get install -y"
                PKG_UPDATE="apt-get update"
                CHRONY_PKG="chrony"
                GPSD_PKG="gpsd-clients"
            elif echo "$OS_LIKE" | grep -q "arch"; then
                DISTRO="arch"
                PKG_INSTALL="pacman -S --noconfirm"
                PKG_UPDATE="pacman -Sy"
                CHRONY_PKG="chrony"
                GPSD_PKG="gpsd"
            else
                error "Unsupported OS: $OS_ID. This script supports Ubuntu/Debian and Arch."
            fi
            ;;
    esac

    info "Detected OS: $OS_ID ($DISTRO)"
}

# ─── Remove conflicting NTP daemons ──────────────────────────────────────────
remove_conflicting_ntp() {
    local removed=0

    # systemd-timesyncd
    if systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
        warn "systemd-timesyncd is running and will conflict with chrony."
        if ask "Disable and stop systemd-timesyncd?"; then
            systemctl stop systemd-timesyncd
            systemctl disable systemd-timesyncd
            systemctl mask systemd-timesyncd
            success "systemd-timesyncd disabled."
            removed=1
        else
            warn "Leaving systemd-timesyncd running — chrony may not work correctly."
        fi
    fi

    # ntpd
    if systemctl is-active --quiet ntp 2>/dev/null || systemctl is-active --quiet ntpd 2>/dev/null; then
        warn "ntpd is running and will conflict with chrony."
        if ask "Stop and remove ntpd?"; then
            systemctl stop ntp ntpd 2>/dev/null || true
            systemctl disable ntp ntpd 2>/dev/null || true
            case "$DISTRO" in
                debian) apt-get remove -y ntp ntpdate 2>/dev/null || true ;;
                arch)   pacman -R --noconfirm ntp 2>/dev/null || true ;;
            esac
            success "ntpd removed."
            removed=1
        else
            warn "Leaving ntpd running — chrony may not work correctly."
        fi
    fi
}

# ─── Install packages ─────────────────────────────────────────────────────────
install_packages() {
    info "Updating package database..."
    $PKG_UPDATE

    info "Installing chrony..."
    $PKG_INSTALL $CHRONY_PKG

    info "Installing gpsd client tools..."
    $PKG_INSTALL $GPSD_PKG

    success "Packages installed."
}

# ─── Configure chrony ─────────────────────────────────────────────────────────
configure_chrony() {
    local conf_file="/etc/chrony.conf"
    [ "$DISTRO" = "debian" ] && conf_file="/etc/chrony/chrony.conf"

    if [ -f "$conf_file" ]; then
        warn "Existing chrony config found at $conf_file"
        if ask "Back up and replace with cothimich config?"; then
            cp "$conf_file" "${conf_file}.bak.$(date +%Y%m%d%H%M%S)"
            success "Backed up to ${conf_file}.bak.*"
        else
            warn "Skipping chrony configuration — you will need to manually add:"
            echo "  server $NTP_SERVER iburst prefer"
            return
        fi
    fi

    info "Writing chrony config pointing to cothimich ($NTP_SERVER)..."
    cat > "$conf_file" << EOF
# chrony.conf - client config for cothimich GPS NTP server
# Generated by setup-ntp-client.sh

# cothimich GPS-disciplined NTP server
server $NTP_SERVER iburst prefer

# Fallback: WWV Fort Collins and NIST Boulder
server time-a-wwv.nist.gov iburst
server time-b-wwv.nist.gov iburst
server time-a-b.nist.gov iburst
server time-b-b.nist.gov iburst

# Step clock if off by more than 1 second on first three updates
makestep 1 3

# Record drift
driftfile /var/lib/chrony/drift

# Allow chronyc to connect locally
bindcmdaddress 127.0.0.1
EOF

    success "Chrony configured."
}

# ─── Configure gpsd client ────────────────────────────────────────────────────
configure_gpsd_client() {
    info "Configuring gpsd client to connect to cothimich ($GPSD_HOST:$GPSD_PORT)..."

    # Set GPSD_HOSTS env so gpsd client tools find the remote server by default
    local profile_file="/etc/profile.d/gpsd-client.sh"
    cat > "$profile_file" << EOF
# gpsd client configuration - points to cothimich GPS server
export GPSD_HOSTS="$GPSD_HOST"
export GPSD_PORT="$GPSD_PORT"
EOF
    chmod +x "$profile_file"
    success "gpsd client configured — use 'cgps $GPSD_HOST' to view GPS data"
    info "Note: You may need to log out and back in, or run: source $profile_file"
}

# ─── Enable and start chrony ──────────────────────────────────────────────────
enable_chrony() {
    info "Enabling and starting chrony..."
    systemctl enable chrony 2>/dev/null || systemctl enable chronyd 2>/dev/null || true
    systemctl restart chrony 2>/dev/null || systemctl restart chronyd 2>/dev/null || true
    success "Chrony started."
}

# ─── Verify ───────────────────────────────────────────────────────────────────
verify() {
    info "Waiting 5 seconds for chrony to connect to sources..."
    sleep 5

    echo ""
    echo -e "${BLUE}=== Chrony Sources ===${NC}"
    chronyc sources 2>/dev/null || warn "chronyc not available yet — try running 'chronyc sources' manually in a moment."

    echo ""
    echo -e "${BLUE}=== Chrony Tracking ===${NC}"
    chronyc tracking 2>/dev/null || true

    echo ""
    info "To test gpsd connection run:"
    echo "  cgps $GPSD_HOST"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     cothimich NTP/GPS Client Setup           ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
echo ""
info "NTP server:  $NTP_SERVER"
info "GPSD server: $GPSD_HOST:$GPSD_PORT"
echo ""

if ! ask "Proceed with setup on this machine?"; then
    echo "Aborted."
    exit 0
fi

detect_os
remove_conflicting_ntp
install_packages
configure_chrony
configure_gpsd_client
enable_chrony
verify

echo ""
success "Setup complete. This machine is now using cothimich for NTP."
echo ""
