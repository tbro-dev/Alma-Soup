# Alma-Soup

A Bash bootstrap script for preparing a fresh AlmaLinux server for hosting web applications and services.

The script is designed primarily for Hetzner AlmaLinux servers and performs basic operating-system updates, SSH hardening, firewall configuration, Fail2ban setup, Caddy installation, and automatic package updates.

Warning: This script changes SSH authentication settings and firewall rules. Make sure you have working SSH key access and an alternative recovery method before running it on a production server.

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