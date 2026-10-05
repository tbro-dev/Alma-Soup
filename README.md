# Alma-Soup

A Bash bootstrap script for preparing a fresh AlmaLinux server for hosting web applications and services.

The script is designed primarily for Hetzner AlmaLinux servers and performs basic operating-system updates, SSH hardening, firewall configuration, Fail2ban setup, Caddy installation, and automatic package updates.

Warning: This script changes SSH authentication settings and firewall rules. Make sure you have working SSH key access and an alternative recovery method before running it on a production server.

What It Does

The bootstrap performs the following tasks:

Updates the operating system.

Installs common administration packages.

Enables and configures firewalld.

Enables Fail2ban.

Hardens SSH.

Installs and enables Caddy.

Configures automatic DNF updates.

Installed Packages

The script installs:

git

curl

wget

unzip

tar

vim

firewalld

fail2ban

policycoreutils-python-utils

caddy

dnf-automatic

Firewall

The script enables firewalld and allows the following services:

Service	Port	Purpose
SSH	22/tcp	Remote administration
HTTP	80/tcp	Web traffic / HTTP redirects
HTTPS	443/tcp	Secure web traffic

The firewall is enabled immediately and the configuration is reloaded.

SSH Hardening

The script modifies /etc/ssh/sshd_config to:

Disable password authentication.

Enable public-key authentication.

Prevent password-based root login.

Validate the SSH configuration before restarting sshd.

Create a timestamped backup of the original SSH configuration.

The intended result is key-based SSH authentication instead of password authentication.

Important

The script assumes that administrator SSH keys are already configured.

Do not run the script if you have not verified that you can log into the server using an SSH key.

The safest setup is to use a normal administrative user with sudo rather than relying on direct root SSH access.

Fail2ban

Fail2ban is installed and enabled to provide protection against repeated authentication failures.

Fail2ban monitors authentication activity and can temporarily block IP addresses that repeatedly fail authentication.

The script should explicitly configure the SSH jail rather than relying on distribution defaults.

A typical SSH jail configuration is:

[sshd]
enabled = true
backend = systemd


The configuration should be placed in /etc/fail2ban/jail.local or /etc/fail2ban/jail.d/.

Caddy

The script installs Caddy using the Caddy COPR repository for RHEL-compatible systems.

Caddy is enabled as a systemd service and starts automatically when the server boots.

Caddy is intended to act as the public-facing web server and reverse proxy.

A typical deployment architecture is:

Internet
   |
   | HTTPS :443
   v
 Caddy
   |
   | reverse proxy
   v
 Application
   |
   +-- PocketBase
   +-- Other services


Caddy can automatically obtain and renew HTTPS certificates when configured with a public domain and the appropriate DNS/firewall configuration.

Automatic Updates

The script installs dnf-automatic and enables its systemd timer.

The goal is to keep the server automatically updated with available package updates.

Automatic updates should be monitored carefully on production systems because package updates can occasionally require configuration changes or a reboot.

Prerequisites

Before running the script:

A fresh AlmaLinux server should be available.

You should have root access.

SSH key authentication should already work.

The server should have Internet access.

DNS should be available for future Caddy configuration.

The server should not already have a conflicting firewall or SSH configuration.

Running the Script

Copy the script to the server and make it executable:

chmod +x bootstrap.sh


Run it as root:

sudo ./bootstrap.sh


Or, if already logged in as root:

./bootstrap.sh

Verification

After the script completes, verify the important services.

SSH

Check the SSH service:

systemctl status sshd


Validate the effective SSH configuration:

sshd -T | grep -E 'passwordauthentication|pubkeyauthentication|permitrootlogin'


Expected settings should include:

passwordauthentication no
pubkeyauthentication yes

Firewall

Check firewalld:

systemctl status firewalld


List the active firewall configuration:

firewall-cmd --list-all

Fail2ban

Check Fail2ban:

systemctl status fail2ban


List active jails:

fail2ban-client status


If the SSH jail is enabled, check it with:

fail2ban-client status sshd

Caddy

Check Caddy:

systemctl status caddy


Check the installed version:

caddy version


Once a Caddyfile has been configured, validate it before reloading Caddy:

caddy validate --config /etc/caddy/Caddyfile

Automatic Updates

Check the timer:

systemctl status dnf-automatic.timer


List active timers:

systemctl list-timers --all

After Bootstrap

The bootstrap intentionally does not deploy an application.

Recommended next steps are:

Configure DNS records for the server.

Configure /etc/caddy/Caddyfile.

Validate and reload Caddy.

Install PocketBase.

Create a dedicated system user for PocketBase.

Create a systemd service for PocketBase.

Configure Caddy as a reverse proxy to PocketBase.

Verify HTTPS and application connectivity.

Configure backups.

Test server recovery procedures.

Security Considerations

This script provides baseline server hardening, not complete server security.

Additional production considerations include:

Use a non-root administrative account.

Use SSH keys rather than passwords.

Disable direct root SSH access where appropriate.

Keep the server patched.

Configure backups.

Monitor authentication and system logs.

Protect application databases and secrets.

Use least-privilege system users for applications.

Review Caddy configuration before exposing services publicly.

Configure Hetzner's firewall/security features where appropriate.

Test restoration of backups.

Important Limitations

The script does not:

Create an administrative user.

Install or configure sudo.

Configure DNS.

Configure a Caddy site.

Install PocketBase.

Create a PocketBase systemd service.

Configure application backups.

Configure monitoring.

Configure log retention.

Guarantee that Fail2ban's SSH jail is enabled unless an explicit jail configuration is added.

Guarantee that every SSH setting is effective if additional OpenSSH configuration files override or precede the settings.

For production use, these areas should be handled explicitly rather than relying on operating-system defaults.

Files Modified

The script may modify or create:

/etc/ssh/sshd_config
/etc/ssh/sshd_config.bak.*
/etc/dnf/automatic.conf


and system service/repository configuration associated with:

firewalld
fail2ban
caddy
dnf-automatic

Design Goal

The purpose of this script is to turn a fresh AlmaLinux server into a reasonable starting point for application deployment:

Fresh AlmaLinux Server
        |
        v
   OS Updates
        |
        v
 Common Packages
        |
        +----> Firewalld
        |
        +----> Fail2ban
        |
        +----> SSH Hardening
        |
        +----> Caddy
        |
        +----> Automatic Updates
        |
        v
 Application Deployment
        |
        +----> PocketBase
        +----> systemd
        +----> Caddy reverse proxy
        +----> HTTPS


The bootstrap is intentionally focused on server preparation. Application-specific configuration should be performed separately.