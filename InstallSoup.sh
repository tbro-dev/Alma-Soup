#!/usr/bin/env bash

# AlmaLinux Server Bootstrap
#
# Purpose:
#   - Validate the host/environment
#   - Update the operating system
#   - Install common administration packages
#   - Configure firewalld
#   - Configure Fail2ban for SSH
#   - Harden SSH
#   - Install and enable Caddy
#   - Validate Caddy configuration
#   - Configure automatic DNF updates
#   - Verify critical services
#
# Assumptions:
#   - AlmaLinux 10
#   - Run as root
#   - Administrator SSH key access already works
#   - Intended for Hetzner AlmaLinux servers
#
# WARNING:
#   This script modifies SSH and firewall configuration.
#   Keep your current SSH session open until you have verified
#   that a new SSH session works after the script completes.
#
# NOTE:
#   This script does NOT automatically reboot the server.
#   A reboot may be appropriate after an OS/kernel update.

set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SSH_CONFIG="/etc/ssh/sshd_config"
readonly FAIL2BAN_CONFIG="/etc/fail2ban/jail.d/sshd.local"
readonly DNF_AUTOMATIC_CONFIG="/etc/dnf/automatic.conf"
readonly CADDY_CONFIG="/etc/caddy/Caddyfile"

log() {
    echo
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

die() {
    echo
    echo "ERROR: $*" >&2
    exit 1
}

cleanup_on_error() {
    local exit_code=$?
    echo
    echo "=================================================="
    echo " Bootstrap FAILED"
    echo "=================================================="
    echo
    echo "The script exited with status: ${exit_code}"
    echo "Review the output above before continuing."
    exit "$exit_code"
}

trap cleanup_on_error ERR

# --------------------------------------------------
# 1. Validate environment
# --------------------------------------------------

log "[1/10] Validating environment..."

if [[ "${EUID}" -ne 0 ]]; then
    die "This script must be run as root."
fi

if [[ ! -f /etc/almalinux-release ]]; then
    die "This script is intended for AlmaLinux."
fi

if [[ ! -r /etc/os-release ]]; then
    die "Cannot determine operating system version."
fi

source /etc/os-release

if [[ "${ID:-}" != "almalinux" ]]; then
    die "Unsupported operating system: ${ID:-unknown}"
fi

if [[ "${VERSION_ID%%.*}" != "10" ]]; then
    die "This script is intended for AlmaLinux 10. Detected: ${VERSION_ID:-unknown}"
fi

if ! command -v dnf >/dev/null 2>&1; then
    die "dnf is required but was not found."
fi

if ! command -v systemctl >/dev/null 2>&1; then
    die "systemctl is required but was not found."
fi

echo "OS: ${PRETTY_NAME:-AlmaLinux}"
echo "Running as: $(whoami)"
echo "Hostname: $(hostname)"

# --------------------------------------------------
# 2. Update operating system
# --------------------------------------------------

log "[2/10] Updating operating system..."

dnf -y upgrade

# --------------------------------------------------
# 3. Install common packages
# --------------------------------------------------

log "[3/10] Enabling repositories and installing common packages..."

log "Enabling EPEL..."

dnf -y install epel-release
dnf makecache

if ! dnf repolist enabled | grep -q '^epel'; then
    die "EPEL repository is not enabled."
fi

dnf -y install \
    git \
    curl \
    wget \
    unzip \
    tar \
    vim \
    firewalld \
    fail2ban \
    policycoreutils-python-utils \
    dnf-automatic

rpm -q fail2ban >/dev/null \
    || die "Fail2ban was not installed successfully."

# --------------------------------------------------
# 4. Configure firewalld
# --------------------------------------------------

log "[4/10] Configuring firewall..."

systemctl enable --now firewalld

FIREWALL_ZONE="$(firewall-cmd --get-default-zone)"

if [[ -z "${FIREWALL_ZONE}" ]]; then
    die "Could not determine the default firewalld zone."
fi

echo "Default firewalld zone: ${FIREWALL_ZONE}"

firewall-cmd \
    --permanent \
    --zone="${FIREWALL_ZONE}" \
    --add-service=ssh

firewall-cmd \
    --permanent \
    --zone="${FIREWALL_ZONE}" \
    --add-service=http

firewall-cmd \
    --permanent \
    --zone="${FIREWALL_ZONE}" \
    --add-service=https

firewall-cmd --reload

echo
echo "Active firewall zone:"
firewall-cmd --get-active-zones

echo
echo "Firewall services in ${FIREWALL_ZONE}:"
firewall-cmd \
    --zone="${FIREWALL_ZONE}" \
    --list-services

# Verify required firewall services.
FIREWALL_SERVICES="$(firewall-cmd --zone="${FIREWALL_ZONE}" --list-services)"

for service in ssh http https; do
    if ! grep -qw "${service}" <<< "${FIREWALL_SERVICES}"; then
        die "Required firewall service is not enabled: ${service}"
    fi
done

# --------------------------------------------------
# 5. Configure Fail2ban
# --------------------------------------------------

log "[5/10] Configuring Fail2ban..."

mkdir -p /etc/fail2ban/jail.d

cat > "${FAIL2BAN_CONFIG}" <<'EOF'
[sshd]
enabled = true
port = ssh
backend = systemd
banaction = firewallcmd-rich-rules
bantime = 1h
findtime = 10m
maxretry = 5
EOF

echo "Fail2ban configuration:"
cat "${FAIL2BAN_CONFIG}"

# Validate the Fail2ban configuration before starting the service.
log "Validating Fail2ban configuration..."

fail2ban-client -t

systemctl enable --now fail2ban

# Verify Fail2ban is running.
if ! systemctl is-active --quiet fail2ban; then
    die "Fail2ban failed to start."
fi

# Verify the SSH jail is active.
if ! fail2ban-client status sshd >/dev/null 2>&1; then
    die "Fail2ban SSH jail is not active."
fi

echo
echo "Fail2ban status:"
fail2ban-client status sshd

# --------------------------------------------------
# 6. Harden SSH
# --------------------------------------------------

log "[6/10] Hardening SSH..."

# Keep a timestamped backup before making changes.
SSH_BACKUP="${SSH_CONFIG}.bak.$(date +%Y%m%d-%H%M%S)"
cp -a "${SSH_CONFIG}" "${SSH_BACKUP}"

echo "SSH configuration backup: ${SSH_BACKUP}"

# Use a dedicated drop-in rather than repeatedly modifying sshd_config.
#
# OpenSSH reads configuration files in lexical order. The 99-bootstrap.conf
# filename makes the intended settings easy to identify and maintain.
#
# Note:
#   PermitRootLogin prohibit-password still permits root login using SSH keys.
#   This is intentional here to avoid unexpectedly locking out an existing
#   root-only installation.
#
# Once a non-root sudo user is confirmed, consider changing this to:
#
#   PermitRootLogin no
#
SSH_DROPIN="/etc/ssh/sshd_config.d/99-bootstrap.conf"

mkdir -p /etc/ssh/sshd_config.d

cat > "${SSH_DROPIN}" <<'EOF'
# Managed by AlmaLinux Server Bootstrap

PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password
EOF

# Validate the complete SSH configuration BEFORE restarting sshd.
log "Validating SSH configuration..."

sshd -t

# Verify the effective configuration rather than only checking the file.
log "Checking effective SSH configuration..."

SSH_EFFECTIVE_CONFIG="$(sshd -T)"

grep -q '^passwordauthentication no$' <<< "${SSH_EFFECTIVE_CONFIG}" \
    || die "Effective SSH configuration does not disable password authentication."

grep -q '^pubkeyauthentication yes$' <<< "${SSH_EFFECTIVE_CONFIG}" \
    || die "Effective SSH configuration does not enable public-key authentication."

grep -q '^permitrootlogin prohibit-password$' <<< "${SSH_EFFECTIVE_CONFIG}" \
    || die "Effective SSH configuration does not contain the expected root-login policy."

echo
echo "Effective SSH settings:"
grep -E '^(passwordauthentication|pubkeyauthentication|permitrootlogin) ' \
    <<< "${SSH_EFFECTIVE_CONFIG}"

# Restart only after successful validation.
systemctl restart sshd

if ! systemctl is-active --quiet sshd; then
    die "sshd is not running after configuration."
fi

# --------------------------------------------------
# 7. Install and enable Caddy
# --------------------------------------------------

log "[7/10] Installing Caddy..."

dnf -y install 'dnf-command(copr)'

if ! dnf copr list | grep -q '@caddy/caddy'; then
    dnf -y copr enable @caddy/caddy
fi

dnf -y install caddy

# Validate the installed Caddy configuration before starting Caddy.
if [[ -f "${CADDY_CONFIG}" ]]; then
    log "Validating Caddy configuration..."

    caddy validate \
        --config "${CADDY_CONFIG}" \
        --adapter caddyfile
else
    die "Caddy configuration file not found: ${CADDY_CONFIG}"
fi

systemctl enable --now caddy

if ! systemctl is-active --quiet caddy; then
    die "Caddy failed to start."
fi

echo
echo "Caddy version:"
caddy version

# --------------------------------------------------
# 8. Configure automatic updates
# --------------------------------------------------

log "[8/10] Configuring automatic updates..."

if [[ ! -f "${DNF_AUTOMATIC_CONFIG}" ]]; then
    die "DNF automatic configuration file not found: ${DNF_AUTOMATIC_CONFIG}"
fi

# Configure automatic update installation explicitly.
if grep -qE '^[[:space:]]*apply_updates[[:space:]]*=' "${DNF_AUTOMATIC_CONFIG}"; then
    sed -i \
        's/^[[:space:]]*apply_updates[[:space:]]*=.*/apply_updates = yes/' \
        "${DNF_AUTOMATIC_CONFIG}"
else
    printf '\napply_updates = yes\n' >> "${DNF_AUTOMATIC_CONFIG}"
fi

# Ensure updates are downloaded as part of the automatic process.
if grep -qE '^[[:space:]]*download_updates[[:space:]]*=' "${DNF_AUTOMATIC_CONFIG}"; then
    sed -i \
        's/^[[:space:]]*download_updates[[:space:]]*=.*/download_updates = yes/' \
        "${DNF_AUTOMATIC_CONFIG}"
else
    printf 'download_updates = yes\n' >> "${DNF_AUTOMATIC_CONFIG}"
fi

# Enable the timer.
systemctl enable --now dnf-automatic.timer

if ! systemctl is-enabled --quiet dnf-automatic.timer; then
    die "dnf-automatic.timer is not enabled."
fi

# --------------------------------------------------
# 9. Verify services and configuration
# --------------------------------------------------

log "[9/10] Running final health checks..."

declare -a REQUIRED_SERVICES=(
    "firewalld"
    "fail2ban"
    "sshd"
    "caddy"
)

for service in "${REQUIRED_SERVICES[@]}"; do
    if systemctl is-active --quiet "${service}"; then
        echo "OK: ${service} is running"
    else
        die "Required service is not running: ${service}"
    fi
done

echo
echo "Firewall:"
echo "  Zone: ${FIREWALL_ZONE}"
firewall-cmd \
    --zone="${FIREWALL_ZONE}" \
    --list-services

echo
echo "Fail2ban:"
fail2ban-client status
fail2ban-client status sshd

echo
echo "Caddy:"
caddy validate \
    --config "${CADDY_CONFIG}" \
    --adapter caddyfile

echo
echo "Automatic updates:"
echo "  Enabled: $(systemctl is-enabled dnf-automatic.timer)"
echo "  Active:  $(systemctl is-active dnf-automatic.timer)"

echo
echo "SSH:"
sshd -t
sshd -T | grep -E '^(passwordauthentication|pubkeyauthentication|permitrootlogin) '

# --------------------------------------------------
# 10. Final summary
# --------------------------------------------------

log "[10/10] Bootstrap complete."

echo
echo "=================================================="
echo " AlmaLinux Bootstrap Complete"
echo "=================================================="
echo
echo "Host:"
echo "  $(hostname)"
echo "  ${PRETTY_NAME:-AlmaLinux}"
echo
echo "Installed/configured:"
echo "  - Common administration tools"
echo "  - Firewalld"
echo "  - Fail2ban"
echo "  - Caddy"
echo "  - DNF automatic updates"
echo
echo "Firewall:"
echo "  Zone: ${FIREWALL_ZONE}"
echo "  - SSH  (22/tcp)"
echo "  - HTTP (80/tcp)"
echo "  - HTTPS (443/tcp)"
echo
echo "SSH:"
echo "  - Password authentication disabled"
echo "  - Public-key authentication enabled"
echo "  - Root password login disabled"
echo
echo "Fail2ban:"
echo "  - SSH jail enabled"
echo "  - Backend: systemd"
echo "  - Ban action: firewallcmd-rich-rules"
echo
echo "Services:"
echo "  - firewalld:        $(systemctl is-active firewalld)"
echo "  - fail2ban:         $(systemctl is-active fail2ban)"
echo "  - sshd:             $(systemctl is-active sshd)"
echo "  - caddy:            $(systemctl is-active caddy)"
echo "  - auto updates:     $(systemctl is-active dnf-automatic.timer)"
echo
echo "Next steps:"
echo "  1. Verify a NEW SSH connection before closing this session."
echo "  2. Confirm the firewall allows SSH, HTTP, and HTTPS."
echo "  3. Confirm Fail2ban SSH jail is active."
echo "  4. Configure DNS."
echo "  5. Configure /etc/caddy/Caddyfile."
echo "  6. Validate and reload Caddy."
echo "  7. Install PocketBase."
echo "  8. Create a dedicated PocketBase system user."
echo "  9. Create a PocketBase systemd service."
echo " 10. Configure Caddy as a reverse proxy."
echo " 11. Configure backups."
echo
echo "NOTE:"
echo "  A reboot may be appropriate after the OS upgrade,"
echo "  particularly if the kernel was updated."
echo
echo "=================================================="
