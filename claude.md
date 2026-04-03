# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a collection of shell scripts for provisioning and configuring Proxmox LXC containers. There are two supported distributions: **Alpine Linux** and **Ubuntu/Debian**.

## Script Architecture

The scripts follow a two-phase setup pattern:

### Phase 1: System Setup (run as root)
- `alpine-setup.sh` - Alpine Linux system provisioning (BusyBox compatible)
- `ubuntu-setup.sh` - Ubuntu/Debian system provisioning

Both system scripts perform:
1. Basic hardening (UFW firewall, fail2ban)
2. SSH hardening (disable root login, password auth)
3. User creation (username derived from hostname)
4. Sudo configuration (NOPASSWD)
5. Docker + Docker Compose installation
6. Tailscale VPN installation
7. System-wide terminal type detection fixes for SSH
8. Oh-My-Zsh installation for the user

### Phase 2: User Setup (run as regular user)
- `alpine-user-script.sh` - Alpine user-level configuration
- `ubuntu-user-script.sh` - Ubuntu user-level configuration

Both user scripts perform:
1. SSH key setup (authorized_keys management)
2. Oh-My-Zsh installation and configuration
3. .zshrc configuration with custom aliases and key bindings
4. Git configuration
5. Creation of ~/projects, ~/bin, ~/tmp, ~/.local/bin directories

### Utility Scripts
- `fix-zsh-errors.sh` - Fixes common zsh bus errors and I/O errors in LXC containers (removes corrupted .zcompdump files, checks nvm, rebuilds completion)
- `merge-zshrc.sh` - Merges .zshrc.pre-oh-my-zsh backup into current .zshrc after Oh-My-Zsh installation

## Common Workflow

For a new Proxmox LXC container:

1. Run system setup as root:
   ```bash
   # Alpine
   ./alpine-setup.sh

   # Ubuntu
   ./ubuntu-setup.sh
   ```

2. Switch to user and run user setup:
   ```bash
   su - <hostname>
   ./alpine-user-script.sh  # or ubuntu-user-script.sh
   ```

3. If zsh errors occur:
   ```bash
   ./fix-zsh-errors.sh
   exec zsh
   ```

## Key Implementation Details

- **Username**: Derived from hostname via `HOSTNAME=$(hostname) && USERNAME="${HOSTNAME}"`
- **Sudo Access**: Users get NOPASSWD:ALL via `/etc/sudoers.d/<username>`
- **Terminal Fixes**: Scripts add TERM fallback logic to `/etc/profile` and `/etc/profile.d/termfix.sh`, plus SSH server-side TERM override via `Match * SetEnv TERM=xterm-256color` in sshd_config
- **SSH Hardening**: PermitRootLogin=no, PasswordAuthentication=no
- **Tailscale Subnet Router**: Configured to advertise 192.168.0.0/24
- **Docker**: Installed with docker-compose-plugin
- **Shell Compatibility**: Alpine scripts use `#!/bin/sh` (BusyBox compatible); Ubuntu scripts use `#!/bin/bash`

## Scripts Are Idempotent

All scripts are designed to be run multiple times safely - they check if components are already installed and skip appropriately.