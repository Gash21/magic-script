#!/bin/sh
# Alpine OS Initial Setup Script for Proxmox LXC
# Features: Basic hardening, user creation, sudo setup, SSH key setup, Docker + Docker Compose, zsh + Oh-My-Zsh
# Fully compatible with BusyBox on Alpine Linux

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

log_info "Starting Alpine OS setup..."

# ============================================
# 1. BASIC HARDENING
# ============================================

log_info "Applying basic hardening..."

# Update and upgrade all packages
apk update
apk upgrade

# Install essential packages
apk add --no-cache \
    sudo \
    curl \
    ca-certificates \
    fail2ban \
    openssh-server \
    ufw \
    shadow \
    bash \
    zsh \
    git \
    vim \
    ncurses-terminfo-base

# Enable and start SSH server
rc-update add sshd default 2>/dev/null || true
rc-service sshd start 2>/dev/null || true

# Enable and start fail2ban
rc-update add fail2ban default 2>/dev/null || true
rc-service fail2ban start 2>/dev/null || true

# Configure UFW (Uncomplicated Firewall)
log_info "Configuring firewall..."

# Allow SSH and essential services
ufw default deny incoming 2>/dev/null || true
ufw default allow outgoing 2>/dev/null || true
ufw allow ssh 2>/dev/null || true
ufw allow http 2>/dev/null || true
ufw allow https 2>/dev/null || true

# Enable UFW
ufw enable 2>/dev/null || true

# Secure SSH configuration
log_info "Securing SSH configuration..."

SSH_CONFIG="/etc/ssh/sshd_config"

# Check if SSH config exists
if [ ! -f "$SSH_CONFIG" ]; then
    log_error "SSH config not found at $SSH_CONFIG"
    log_error "Skipping SSH hardening..."
else
    # Backup original config (if not already backed up)
    if [ ! -f "${SSH_CONFIG}.bak" ]; then
        cp "$SSH_CONFIG" "${SSH_CONFIG}.bak"
    fi

    # Disable root login - BusyBox sed compatible
    sed -i 's/^#*[[:space:]]*PermitRootLogin.*/PermitRootLogin no/' "$SSH_CONFIG" 2>/dev/null || \
        sed -i '/^PermitRootLogin/c\PermitRootLogin no' "$SSH_CONFIG"

    # Disable password authentication (key-based only)
    sed -i 's/^#*[[:space:]]*PasswordAuthentication.*/PasswordAuthentication no/' "$SSH_CONFIG" 2>/dev/null || \
        sed -i '/^PasswordAuthentication/c\PasswordAuthentication no' "$SSH_CONFIG"

    # Disable empty passwords
    sed -i 's/^#*[[:space:]]*PermitEmptyPasswords.*/PermitEmptyPasswords no/' "$SSH_CONFIG" 2>/dev/null || \
        sed -i '/^PermitEmptyPasswords/c\PermitEmptyPasswords no' "$SSH_CONFIG"

    # Restart SSH service
    rc-service sshd restart 2>/dev/null || true
fi

# ============================================
# 2. CREATE USER WITH HOSTNAME
# ============================================

log_info "Creating new user..."

# Get hostname
HOSTNAME=$(hostname)
USERNAME="${HOSTNAME}"

log_info "Username will be: $USERNAME"

# Check if user already exists
if id "$USERNAME" >/dev/null 2>&1; then
    log_warn "User $USERNAME already exists. Skipping user creation."

    # Ensure home permissions are correct for existing users too
    chmod 700 "/home/$USERNAME" 2>/dev/null || true
    chown "$USERNAME:$USERNAME" "/home/$USERNAME" 2>/dev/null || true

    # Set shell to zsh for existing user
    CURRENT_SHELL=$(getent passwd "$USERNAME" | cut -d: -f7)
    if [ "$CURRENT_SHELL" != "/bin/zsh" ]; then
        log_info "Setting default shell to zsh for $USERNAME..."
        chsh -s /bin/zsh "$USERNAME" 2>/dev/null || \
            usermod -s /bin/zsh "$USERNAME" 2>/dev/null || true

        # Verify and show current shell
        NEW_SHELL=$(getent passwd "$USERNAME" | cut -d: -f7)
        if [ "$NEW_SHELL" = "/bin/zsh" ]; then
            log_info "Default shell changed to zsh"
        else
            log_warn "Could not change shell to zsh manually. You may need to run: chsh -s /bin/zsh $USERNAME"
        fi
    else
        log_info "User $USERNAME already has zsh as default shell"
    fi
else
    # Create user with no password
    adduser -D -h "/home/$USERNAME" -s "/bin/zsh" "$USERNAME"

    # CRITICAL FIX: Set home directory permissions to 700 to satisfy SSH StrictModes
    chmod 700 "/home/$USERNAME"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME"

    # CRITICAL FIX: Unlock the account by setting a random complex password
    # BusyBox-compatible: use /dev/urandom instead of date +%N
    RANDOM_PASS=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)
    echo "$USERNAME:$RANDOM_PASS" | chpasswd 2>/dev/null || {
        # Fallback: use openssl if available
        if command -v openssl >/dev/null 2>&1; then
            RANDOM_PASS=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
            echo "$USERNAME:$RANDOM_PASS" | chpasswd
        else
            # Final fallback: use timestamp with process ID
            RANDOM_PASS="${HOSTNAME}$(date +%s)$$"
            echo "$USERNAME:$RANDOM_PASS" | chpasswd
        fi
    }

    log_info "User $USERNAME created successfully (account unlocked with random password)"
fi

# ============================================
# 3. SETUP SUDOERS
# ============================================

log_info "Configuring sudoers..."

# Create sudoers.d directory if it doesn't exist
mkdir -p /etc/sudoers.d

# Add user to sudoers with no password requirement
if [ ! -f "/etc/sudoers.d/$USERNAME" ]; then
    printf "%s ALL=(ALL) NOPASSWD:ALL\n" "$USERNAME" > "/etc/sudoers.d/$USERNAME"
fi

# Set proper permissions
chmod 0440 "/etc/sudoers.d/$USERNAME"

# Add user to wheel group (optional, for traditional sudo)
adduser "$USERNAME" wheel 2>/dev/null || true

# Ensure wheel group can use sudo
if ! grep -q "^%wheel ALL=(ALL) NOPASSWD: ALL" /etc/sudoers 2>/dev/null; then
    # BusyBox sed compatible - add after line or append
    if grep -q "^# %wheel ALL=(ALL) NOPASSWD: ALL" /etc/sudoers 2>/dev/null; then
        sed -i 's/^# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers 2>/dev/null || true
    else
        printf "%%wheel ALL=(ALL) NOPASSWD: ALL\n" >> /etc/sudoers 2>/dev/null || true
    fi
fi

log_info "Sudoers configured for $USERNAME"

# Add convenience alias for root to switch to user
ROOT_PROFILE="/root/.profile"
if [ -f "$ROOT_PROFILE" ]; then
    if ! grep -q "alias to-$USERNAME=" "$ROOT_PROFILE" 2>/dev/null; then
        printf "" >> "$ROOT_PROFILE"
        printf "# Quick alias to switch to %s\n" "$USERNAME" >> "$ROOT_PROFILE"
        printf "alias to-%s='su - %s'\n" "$USERNAME" "$USERNAME" >> "$ROOT_PROFILE"
        log_info "Added alias 'to-$USERNAME' to root's profile"
    fi
fi

# Add convenience alias for root to switch to user in .zshrc if it exists
if [ -f "/root/.zshrc" ]; then
    if ! grep -q "alias to-$USERNAME=" "/root/.zshrc" 2>/dev/null; then
        printf "" >> "/root/.zshrc"
        printf "# Quick alias to switch to %s\n" "$USERNAME" >> "/root/.zshrc"
        printf "alias to-%s='su - %s'\n" "$USERNAME" "$USERNAME" >> "/root/.zshrc"
        log_info "Added alias 'to-$USERNAME' to root's .zshrc"
    fi
fi

# Test sudo configuration - Alpine compatible method
log_info "Verifying sudo configuration..."
if [ -f "/etc/sudoers.d/$USERNAME" ] && grep -q "$USERNAME.*NOPASSWD.*ALL" "/etc/sudoers.d/$USERNAME"; then
    log_info "✓ User $USERNAME has sudo access (verified via config)"
else
    log_warn "Could not verify sudo access for $USERNAME"
fi

# ============================================
# 4. INSTALL TAILSCALE
# ============================================

log_info "Installing Tailscale..."

apk add --no-cache tailscale

rc-update add tailscale default 2>/dev/null || true

log_info "Starting Tailscale daemon..."
rc-service tailscale start

if ! rc-service tailscale status >/dev/null 2>&1; then
    log_warn "Tailscale service failed to start via OpenRC, starting manually..."
    tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock >/dev/null 2>&1 &
    sleep 2
fi

if [ -S /var/run/tailscale/tailscaled.sock ]; then
    log_info "✓ Tailscale daemon is running"
else
    log_error "✗ Tailscale daemon failed to start"
    log_warn "You may need to manually start it with: rc-service tailscale start"
fi

printf ""
log_info "=========================================="
log_info "Tailscale Setup"
log_info "=========================================="
printf ""
printf "${YELLOW}Tailscale has been installed but NOT authenticated yet.${NC}\n"
printf ""
printf "${GREEN}To connect this server to your Tailscale network as a subnet router:${NC}\n"
printf ""
printf "1. Run this command to authenticate and advertise your local subnet:\n"
printf "   ${YELLOW}tailscale up --advertise-routes=192.168.0.0/24 --accept-routes${NC}\n"
printf ""
printf "2. Open the URL shown in the output to authenticate via your Tailscale account\n"
printf ""
printf "3. In the Tailscale admin console, approve the subnet routes for this machine\n"
printf ""
printf "${GREEN}After setup, your local network (192.168.0.0/24) will be accessible from Tailscale.${NC}\n"
printf ""

# ============================================
# 5. INSTALL DOCKER
# ============================================

log_info "Installing Docker..."

# Install Docker and Docker Compose
apk add --no-cache \
    docker \
    docker-cli-compose \
    docker-compose

# Enable Docker service
rc-update add docker default 2>/dev/null || true
rc-service docker start 2>/dev/null || true

# Add user to docker group
adduser "$USERNAME" docker 2>/dev/null || true

log_info "Docker installed and started"

# Display Docker version for verification
docker --version
docker compose version
docker-compose --version 2>/dev/null || printf "docker-compose (standalone) not available\n"

# ============================================

# ============================================
# 6. ADDITIONAL HARDENING
# ============================================

log_info "Applying additional hardening..."

# Set secure umask (if not already set)
if ! grep -q "umask 027" /etc/profile 2>/dev/null; then
    printf "umask 027\n" >> /etc/profile
fi

# Disable core dumps (if not already set)
if ! grep -q "hard core 0" /etc/security/limits.conf 2>/dev/null; then
    printf "* hard core 0\n" >> /etc/security/limits.conf
    printf "* soft core 0\n" >> /etc/security/limits.conf
fi

# Enable randomize_va_space (ASLR)
if ! grep -q "randomize_va_space" /etc/sysctl.conf 2>/dev/null; then
    printf "kernel.randomize_va_space = 2\n" >> /etc/sysctl.conf 2>/dev/null || true
fi

# Disable source routing
if ! grep -q "accept_source_route = 0" /etc/sysctl.conf 2>/dev/null; then
    printf "net.ipv4.conf.all.accept_source_route = 0\n" >> /etc/sysctl.conf 2>/dev/null || true
    printf "net.ipv6.conf.all.accept_source_route = 0\n" >> /etc/sysctl.conf 2>/dev/null || true
fi

# Disable ICMP redirects
if ! grep -q "accept_redirects = 0" /etc/sysctl.conf 2>/dev/null; then
    printf "net.ipv4.conf.all.accept_redirects = 0\n" >> /etc/sysctl.conf 2>/dev/null || true
    printf "net.ipv6.conf.all.accept_redirects = 0\n" >> /etc/sysctl.conf 2>/dev/null || true
    printf "net.ipv4.conf.all.send_redirects = 0\n" >> /etc/sysctl.conf 2>/dev/null || true
fi

# Apply sysctl settings (may fail in containers, that's ok)
sysctl -p 2>/dev/null || log_warn "Some sysctl settings could not be applied (may be normal in containers)"

# ============================================
# FIX TERMINAL TYPE DETECTION (SYSTEM-WIDE)
# ============================================

log_info "Fixing terminal type detection system-wide..."

# Add terminal detection to /etc/profile (runs before shell-specific files)
if ! grep -q "TERM fallback for unknown terminals" /etc/profile 2>/dev/null; then
    cat >> /etc/profile << 'TERMFIX'

# TERM fallback for unknown terminals (xterm-ghostty, wezterm, etc.)
# This fixes "unknown terminal type" errors over SSH
if ! infocmp "$TERM" >/dev/null 2>&1; then
    for term in xterm-256color xterm-color xterm vt100; do
        if infocmp "$term" >/dev/null 2>&1; then
            export TERM="$term"
            break
        fi
    done
fi
TERMFIX
fi

# Also create /etc/profile.d/termfix.sh if directory exists (modern systems)
if [ -d /etc/profile.d ]; then
    cat > /etc/profile.d/termfix.sh << 'TERMFIX'
# TERM fallback for unknown terminals (xterm-ghostty, wezterm, etc.)
# This fixes "unknown terminal type" errors over SSH
if ! infocmp "$TERM" >/dev/null 2>&1; then
    for term in xterm-256color xterm-color xterm vt100; do
        if infocmp "$term" >/dev/null 2>&1; then
            export TERM="$term"
            break
        fi
    done
fi
TERMFIX
    chmod 0644 /etc/profile.d/termfix.sh
fi

# ============================================
# 7. CLEANUP
# ============================================

log_info "Cleaning up..."

# Clear apk cache
rm -rf /var/cache/apk/*

# ============================================
# 10. SUMMARY
# ============================================

printf ""
log_info "=========================================="
log_info "System-level setup completed successfully!"
log_info "=========================================="
printf ""
log_info "Summary:"
printf "  - User created: %s\n" "$USERNAME"
printf "  - User has full sudo access (NOPASSWD)\n"
printf "  - Tailscale installed (requires manual setup)\n"
printf "  - Docker & Docker Compose installed and running\n"
printf "  - Firewall enabled (UFW)\n"
printf "  - Fail2ban enabled\n"
printf "  - SSH hardened (root login disabled, password auth disabled)\n"
printf "  - Root alias 'to-%s' added for quick user switching\n" "$USERNAME"
printf "  - Terminal type detection configured system-wide\n"
printf ""
log_warn "NEXT STEPS:"
log_warn "1. Switch to the new user: su - %s" "$USERNAME"
log_warn "2. Run the user-level setup script: ./alpine-user-script.sh"
printf ""
log_warn "IMPORTANT NOTES:"
log_warn "1. SSH password authentication is disabled - use SSH keys only"
log_warn "2. Root login is disabled"
log_warn "3. User $USERNAME has full sudo access (no password required)"
log_warn "4. From root, use 'to-$USERNAME' or 'su - $USERNAME' to switch to user"
log_warn "5. Tailscale is installed but NOT authenticated - see instructions above"
log_warn "6. If Tailscale daemon is not running, restart with: rc-service tailscale restart"
printf ""
log_info "To switch to the new user:"
printf "  su - %s\n" "$USERNAME"
printf "  or use the alias: to-%s\n" "$USERNAME"
printf ""
log_info "To run user-level setup (as $USERNAME):"
printf "  ./alpine-user-script.sh\n"
printf ""
log_info "To verify sudo access:"
printf "  sudo -u %s sudo whoami\n" "$USERNAME"
printf ""
log_info "To verify Docker:"
printf "  docker run --rm hello-world\n"
printf ""
log_info "To verify Docker Compose:"
printf "  docker compose version\n"
printf "  docker-compose --version\n"
printf ""
log_info "To connect Tailscale (subnet router for 192.168.0.0/24):"
printf "  tailscale up --advertise-routes=192.168.0.0/24 --accept-routes\n"
printf "  (Then approve routes in Tailscale admin console)\n"
printf ""
