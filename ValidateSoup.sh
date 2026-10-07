#!/usr/bin/env bash

set -Eeuo pipefail

fail() {
    echo "[FAIL] $*"
    exit 1
}

pass() {
    echo "[PASS] $*"
}

echo
echo "=============================================="
echo " Alma-Soup Validation"
echo "=============================================="
echo

# --------------------------------------------------
# OS Validation
# --------------------------------------------------

source /etc/os-release

[[ "${ID}" == "almalinux" ]] \
    || fail "Expected AlmaLinux"

[[ "${VERSION_ID%%.*}" == "10" ]] \
    || fail "Expected AlmaLinux 10"

pass "Operating system is AlmaLinux 10"

# --------------------------------------------------
# Packages
# --------------------------------------------------

PACKAGES=(
    git
    curl
    wget
    unzip
    tar
    vim
    firewalld
    fail2ban
    caddy
    dnf-automatic
)

for pkg in "${PACKAGES[@]}"; do
    rpm -q "$pkg" >/dev/null 2>&1 \
        || fail "Package missing: $pkg"

    pass "Package installed: $pkg"
done

# --------------------------------------------------
# EPEL
# --------------------------------------------------

dnf repolist enabled | grep -q "^epel" \
    || fail "EPEL repository is not enabled"

pass "EPEL repository enabled"

# --------------------------------------------------
# Firewalld
# --------------------------------------------------

systemctl is-active --quiet firewalld \
    || fail "firewalld is not active"

pass "firewalld running"

FIREWALL_ZONE="$(firewall-cmd --get-default-zone)"

for svc in ssh http https; do
    firewall-cmd \
        --zone="$FIREWALL_ZONE" \
        --list-services | grep -qw "$svc" \
        || fail "Firewall missing service: $svc"

    pass "Firewall service present: $svc"
done

# --------------------------------------------------
# Fail2ban
# --------------------------------------------------

systemctl is-active --quiet fail2ban \
    || fail "fail2ban is not active"

pass "fail2ban running"

fail2ban-client status sshd >/dev/null 2>&1 \
    || fail "Fail2ban SSH jail inactive"

pass "Fail2ban SSH jail active"

# --------------------------------------------------
# SSH
# --------------------------------------------------

[[ -f /etc/ssh/sshd_config.d/99-bootstrap.conf ]] \
    || fail "SSH drop-in missing"

pass "SSH drop-in exists"

sshd -t \
    || fail "sshd configuration validation failed"

pass "sshd config valid"

SSH_CONFIG="$(sshd -T)"

grep -q '^passwordauthentication no$' <<< "$SSH_CONFIG" \
    || fail "PasswordAuthentication not disabled"

grep -q '^pubkeyauthentication yes$' <<< "$SSH_CONFIG" \
    || fail "PubkeyAuthentication not enabled"

grep -q '^permitrootlogin prohibit-password$' <<< "$SSH_CONFIG" \
    || fail "PermitRootLogin not configured correctly"

pass "SSH hardening verified"

# --------------------------------------------------
# Caddy
# --------------------------------------------------

systemctl is-active --quiet caddy \
    || fail "Caddy is not active"

pass "Caddy running"

caddy validate \
    --config /etc/caddy/Caddyfile \
    --adapter caddyfile \
    || fail "Caddyfile validation failed"

pass "Caddy configuration valid"

# --------------------------------------------------
# Automatic Updates
# --------------------------------------------------

systemctl is-enabled --quiet dnf-automatic.timer \
    || fail "dnf-automatic.timer not enabled"

systemctl is-active --quiet dnf-automatic.timer \
    || fail "dnf-automatic.timer not active"

pass "Automatic updates enabled"

grep -q "^apply_updates = yes" /etc/dnf/automatic.conf \
    || fail "apply_updates not enabled"

grep -q "^download_updates = yes" /etc/dnf/automatic.conf \
    || fail "download_updates not enabled"

pass "DNF automatic configuration validated"

# --------------------------------------------------
# SELinux
# --------------------------------------------------

SELINUX_STATE="$(getenforce)"

echo
echo "SELinux: $SELINUX_STATE"

# --------------------------------------------------
# Final Summary
# --------------------------------------------------

echo
echo "=============================================="
echo " VALIDATION SUCCESSFUL"
echo "=============================================="
echo
echo "Host: $(hostname)"
echo "OS: ${PRETTY_NAME}"
echo "Firewall Zone: ${FIREWALL_ZONE}"
echo "SELinux: ${SELINUX_STATE}"
echo
echo "Alma-Soup appears to be configured correctly."