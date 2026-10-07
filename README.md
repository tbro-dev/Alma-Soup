## Usage

Clone the repository:

```bash
git clone https://github.com/tbro-dev/Alma-Soup.git
cd Alma-Soup
```

Convert line endings if the files were edited on Windows:

```bash
sudo dnf -y install dos2unix
dos2unix Server10Bootstrap.sh
dos2unix BootstrapValidation.sh
```

Make the scripts executable:

```bash
chmod +x Server10Bootstrap.sh
chmod +x BootstrapValidation.sh
```

Validate the bootstrap script syntax:

```bash
bash -n Server10Bootstrap.sh
```

Run the bootstrap:

```bash
sudo ./Server10Bootstrap.sh
```

After the bootstrap completes, validate the server:

```bash
sudo ./BootstrapValidation.sh
```

## Recommended Workflow

1. Provision a fresh AlmaLinux 10 server.
2. Keep your existing SSH session open.
3. Run the bootstrap.
4. Open a NEW SSH session and verify login works.
5. Run the validation script.
6. Review:
   - firewalld
   - Fail2ban
   - SSH configuration
   - Caddy
   - automatic updates
7. Only after validation succeeds should application deployment begin.

## Troubleshooting

### Permission denied

```text
-bash: ./BootstrapValidation.sh: Permission denied
```

Fix:

```bash
chmod +x BootstrapValidation.sh
```

### bash\r: No such file or directory

```text
/usr/bin/env: 'bash\r': No such file or directory
```

Cause: Windows (CRLF) line endings.

Fix:

```bash
sudo dnf -y install dos2unix
dos2unix *.sh
```

### Script must be run as root

```text ERROR: This script must be run as root.
```

Run using:

```bash sudo ./Server10Bootstrap.sh
```

## Validation
The bootstrap is considered successful only when:

- A new SSH session succeeds.
- firewalld is active.
- Fail2ban is active.
- The Fail2ban SSH jail is active.
- Caddy is active
- dnf-automatic timer is active.
- BootstrapValidation.sh completes successfully.