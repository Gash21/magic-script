#!/bin/sh
# Alpine OS Initial Setup Script for Proxmox LXC
# Features: Basic hardening, user creation, sudo setup, Docker + Docker Compose, zsh + Oh-My-Zsh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
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
    ufw \
    shadow \
    bash \
    zsh \
    git \
    vim

# Enable and start fail2ban
rc-update add fail2ban default
rc-service fail2ban start

# Configure UFW (Uncomplicated Firewall)
log_info "Configuring firewall..."

# Allow SSH and essential services
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow http
ufw allow https

# Enable UFW
ufw enable

# Secure SSH configuration
log_info "Securing SSH configuration..."

SSH_CONFIG="/etc/ssh/sshd_config"

# Backup original config
cp "$SSH_CONFIG" "${SSH_CONFIG}.bak"

# Disable root login
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "$SSH_CONFIG"

# Disable password authentication (key-based only)
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$SSH_CONFIG"

# Disable empty passwords
sed -i 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords no/' "$SSH_CONFIG"

# Restart SSH service
rc-service sshd restart

# ============================================
# 2. CREATE USER WITH HOSTNAME
# ============================================

log_info "Creating new user..."

# Get hostname
HOSTNAME=$(hostname)
USERNAME="${HOSTNAME}"

log_info "Username will be: $USERNAME"

# Check if user already exists
if id "$USERNAME" &>/dev/null; then
    log_warn "User $USERNAME already exists. Skipping user creation."
else
    # Create user with no password
    adduser -D -h "/home/$USERNAME" -s "/bin/zsh" "$USERNAME"

    # Unlock the account (no password required for sudo)
    passwd -u "$USERNAME"

    log_info "User $USERNAME created successfully"
fi

# ============================================
# 3. SETUP SUDOERS
# ============================================

log_info "Configuring sudoers..."

# Create sudoers.d directory if it doesn't exist
mkdir -p /etc/sudoers.d

# Add user to sudoers with no password requirement
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"

# Set proper permissions
chmod 0440 "/etc/sudoers.d/$USERNAME"

# Add user to wheel group (optional, for traditional sudo)
adduser "$USERNAME" wheel 2>/dev/null || true

# Ensure wheel group can use sudo
sed -i 's/^# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers

log_info "Sudoers configured for $USERNAME"

# ============================================
# 4. INSTALL DOCKER
# ============================================

log_info "Installing Docker..."

# Install Docker and Docker Compose
apk add --no-cache \
    docker \
    docker-cli-compose \
    docker-compose

# Enable Docker service
rc-update add docker default
rc-service docker start

# Add user to docker group
adduser "$USERNAME" docker

log_info "Docker installed and started"

# Display Docker version for verification
docker --version
docker compose version
docker-compose --version 2>/dev/null || echo "docker-compose (standalone) not available"

# ============================================
# 5. INSTALL OH-MY-ZSH
# ============================================

log_info "Installing Oh-My-Zsh..."

# Install oh-my-zsh for the user
su - "$USERNAME" -c 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'

# Set up a robust .zshrc with sensible defaults
ZSHRC="/home/$USERNAME/.zshrc"

# Backup original .zshrc
cp "$ZSHRC" "${ZSHRC}.bak"

# Add useful configurations to .zshrc
cat >> "$ZSHRC" << 'EOF'

# User configuration
export EDITOR=vim
export VISUAL=vim

# Add aliases
alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias ~='cd ~'

# Docker aliases
alias d='docker'
alias dc='docker compose'
alias dc1='docker-compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias dex='docker exec -it'
alias dl='docker logs -f'
alias dcp='docker compose pull'
alias dcup='docker compose up -d'
alias dcdown='docker compose down'
alias dcps='docker compose ps'

# Git aliases
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'

# History configuration
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE

# Completion
autoload -Uz compinit
compinit

# Better completion
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
EOF

# Fix permissions
chown "$USERNAME:$USERNAME" "$ZSHRC"

log_info "Oh-My-Zsh installed and configured for $USERNAME"

# ============================================
# 6. ADDITIONAL HARDENING
# ============================================

log_info "Applying additional hardening..."

# Set secure umask
echo "umask 027" >> /etc/profile

# Disable core dumps
echo "* hard core 0" >> /etc/security/limits.conf
echo "* soft core 0" >> /etc/security/limits.conf

# Enable randomize_va_space (ASLR)
echo 2 > /proc/sys/kernel/randomize_va_space
echo "kernel.randomize_va_space = 2" >> /etc/sysctl.conf

# Disable source routing
echo "net.ipv4.conf.all.accept_source_route = 0" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.accept_source_route = 0" >> /etc/sysctl.conf

# Disable ICMP redirects
echo "net.ipv4.conf.all.accept_redirects = 0" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.accept_redirects = 0" >> /etc/sysctl.conf
echo "net.ipv4.conf.all.send_redirects = 0" >> /etc/sysctl.conf

# Apply sysctl settings
sysctl -p

# ============================================
# 7. CLEANUP
# ============================================

log_info "Cleaning up..."

# Clear apk cache
rm -rf /var/cache/apk/*

# ============================================
# 8. SUMMARY
# ============================================

echo ""
log_info "=========================================="
log_info "Setup completed successfully!"
log_info "=========================================="
echo ""
log_info "Summary:"
echo "  - User created: $USERNAME"
echo "  - User has sudo access (no password)"
echo "  - Shell: zsh with Oh-My-Zsh"
echo "  - Docker & Docker Compose installed and running"
echo "  - Firewall enabled (UFW)"
echo "  - Fail2ban enabled"
echo "  - SSH hardened (root login disabled, password auth disabled)"
echo ""
log_warn "IMPORTANT NOTES:"
log_warn "1. You must setup SSH keys for $USERNAME before logging in"
log_warn "2. SSH password authentication is disabled"
log_warn "3. Root login is disabled"
log_warn "4. Switch to the new user: su - $USERNAME"
echo ""
log_info "To switch to the new user, run:"
echo "  su - $USERNAME"
echo ""
log_info "To verify Docker:"
echo "  docker run --rm hello-world"
echo ""
log_info "To verify Docker Compose:"
echo "  docker compose version"
echo "  docker-compose --version"
echo ""
