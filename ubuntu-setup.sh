#!/bin/bash
#===============================================================================
# Ubuntu VPS Hardening Script
# Purpose: Automatically harden a fresh Ubuntu VPS for Docker-based workflows
# Target: Go backends, Solid.js frontends, and AI agents
#===============================================================================

set -euo pipefail

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
readonly DOCKER_LOG_MAX_SIZE="10m"
readonly DOCKER_LOG_MAX_FILE="5"
readonly TAILSCALE_SUBNET="192.168.0.0/24"

# Username will be derived from hostname (set early for use in functions)
USERNAME="$(hostname)"

#-------------------------------------------------------------------------------
# Colors & Logging
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
log_warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; }
log_step()  { printf "${BLUE}[STEP]${NC} %s\n" "$1"; }

#-------------------------------------------------------------------------------
# Pre-flight Checks
#-------------------------------------------------------------------------------
check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    log_info "Starting Ubuntu VPS hardening..."
}

#-------------------------------------------------------------------------------
# 1. System Update
#-------------------------------------------------------------------------------
system_update() {
    log_step "Updating system packages..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get upgrade -y
}

#-------------------------------------------------------------------------------
# 2. Install Core Packages
#-------------------------------------------------------------------------------
install_packages() {
    log_step "Installing core packages..."
    apt-get install -y \
        sudo \
        curl \
        ca-certificates \
        gnupg \
        lsb-release \
        vim \
        git \
        zsh \
        ncurses-term \
        fail2ban \
        ufw \
        openssh-server \
        logrotate

    systemctl enable ssh --quiet || true
    systemctl start ssh   || true
}

#-------------------------------------------------------------------------------
# 3. SSH Hardening (Safe Mode - Checks for SSH keys first)
#-------------------------------------------------------------------------------
harden_ssh() {
    log_step "Hardening SSH configuration..."

    local sshd_config="/etc/ssh/sshd_config"
    local sshd_config_backup="/etc/ssh/sshd_config.bak"
    local ssh_dir="/home/$USERNAME/.ssh"
    local authorized_keys="$ssh_dir/authorized_keys"

    # Backup config if not already backed up
    [[ ! -f "$sshd_config_backup" ]] && cp "$sshd_config" "$sshd_config_backup"

    # Disable root login (safe - you'll still have user account)
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "$sshd_config"

    # Disable empty passwords
    sed -i 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords no/' "$sshd_config"

    # Check if user has SSH keys before disabling password auth
    if [[ -f "$authorized_keys" ]] && [[ -s "$authorized_keys" ]]; then
        # authorized_keys exists and is not empty - safe to disable password auth
        sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_config"
        sed -i 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "$sshd_config"
        log_info "SSH keys detected - password authentication disabled"
    else
        # No SSH keys found - keep password auth enabled to prevent lockout
        log_warn "No SSH keys found in $authorized_keys - password authentication LEFT ENABLED"
        log_warn "Add your SSH keys, then manually disable password auth"
        # Ensure password auth is enabled
        sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$sshd_config"
    fi

    # Ensure SSH uses our hardened config
    systemctl reload ssh || systemctl restart ssh || true

    log_info "SSH hardened: root login disabled"
}

#-------------------------------------------------------------------------------
# 4. Firewall (UFW) Configuration - Docker-Safe
#-------------------------------------------------------------------------------
configure_firewall() {
    log_step "Configuring UFW firewall..."

    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing

    # Allow SSH (the only way in)
    ufw allow "${SSH_PORT:-22}/tcp" comment 'SSH' || ufw allow 22/tcp comment 'SSH'

    # Allow HTTP/HTTPS for web services
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'

    # Allow Docker bridge network traffic (container-to-container)
    ufw allow in on docker0 from 172.17.0.0/16 comment 'Docker internal' 2>/dev/null || true

    # Enable UFW (--force skips confirmation)
    echo "y" | ufw enable --quiet 2>/dev/null || ufw --force enable

    systemctl enable ufw --quiet || true
    systemctl start ufw  || true

    log_info "UFW configured (SSH, HTTP, HTTPS, Docker networking allowed)"
}

#-------------------------------------------------------------------------------
# 5. Fail2ban Configuration
#-------------------------------------------------------------------------------
configure_fail2ban() {
    log_step "Configuring Fail2ban..."

    # Create Fail2ban config if it doesn't exist
    local jail_local="/etc/fail2ban/jail.local"
    if [[ ! -f "$jail_local" ]]; then
        cat > "$jail_local" << 'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
EOF
    fi

    systemctl enable fail2ban --quiet || true
    systemctl start fail2ban  || true

    log_info "Fail2ban enabled (3 SSH retry limit, 1hr ban)"
}

#-------------------------------------------------------------------------------
# 6. User Creation (Idempotent)
#-------------------------------------------------------------------------------
create_user() {
    log_step "Creating user account..."

    # USERNAME is already set globally from hostname
    local USER_HOME="/home/$USERNAME"

    if id "$USERNAME" &>/dev/null; then
        log_warn "User '$USERNAME' already exists - skipping creation"
    else
        # Create user with locked password (no login password)
        adduser --disabled-password --gecos "" "$USERNAME"
        log_info "User '$USERNAME' created"
    fi

    # Ensure home directory has correct permissions
    chmod 700 "$USER_HOME" 2>/dev/null || true
    chown -R "$USERNAME:$USERNAME" "$USER_HOME" 2>/dev/null || true

    # Set zsh as default shell
    local current_shell
    current_shell="$(getent passwd "$USERNAME" | cut -d: -f7)"
    if [[ "$current_shell" != *"zsh"* ]]; then
        chsh -s /bin/zsh "$USERNAME" 2>/dev/null || \
        usermod -s /bin/zsh "$USERNAME" 2>/dev/null || true
        log_info "Zsh set as default shell for '$USERNAME'"
    fi
}

#-------------------------------------------------------------------------------
# 7. Sudo Configuration (Idempotent)
#-------------------------------------------------------------------------------
configure_sudo() {
    log_step "Configuring sudo access..."

    local sudoers_file="/etc/sudoers.d/$USERNAME"

    # Create sudoers file if it doesn't exist
    if [[ ! -f "$sudoers_file" ]]; then
        echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "$sudoers_file"
        chmod 0440 "$sudoers_file"
    fi

    # Add user to sudo group (idempotent - won't fail if already a member)
    usermod -aG sudo "$USERNAME" 2>/dev/null || true

    # Validate sudo access
    if grep -q "NOPASSWD:ALL" "$sudoers_file" 2>/dev/null; then
        log_info "Sudo access configured for '$USERNAME'"
    fi
}

#-------------------------------------------------------------------------------
# 8. SSH Key Setup (Idempotent)
#-------------------------------------------------------------------------------
setup_ssh_keys() {
    log_step "Setting up SSH authorized_keys..."

    local ssh_dir="/home/$USERNAME/.ssh"
    local authorized_keys="$ssh_dir/authorized_keys"

    # Create .ssh directory with correct permissions
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    chown "$USERNAME:$USERNAME" "$ssh_dir"

    # If authorized_keys doesn't exist, create empty file with proper permissions
    if [[ ! -f "$authorized_keys" ]]; then
        touch "$authorized_keys"
    fi
    chmod 600 "$authorized_keys"
    chown "$USERNAME:$USERNAME" "$authorized_keys"

    # Check if authorized_keys is empty, if so, prompt for SSH key
    if [[ ! -s "$authorized_keys" ]]; then
        echo ""
        echo "=========================================="
        echo "SSH Public Key Setup"
        echo "=========================================="
        echo "Paste your SSH public key below (or press Enter to skip):"
        echo "You can find your public key in: ~/.ssh/id_rsa.pub or ~/.ssh/id_ed25519.pub"
        echo ""
        read -p "SSH public key: " ssh_public_key

        # Validate and add the key if provided
        if [[ -n "$ssh_public_key" ]]; then
            # Basic validation: check if it looks like an SSH public key
            if [[ "$ssh_public_key" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521) ]]; then
                echo "$ssh_public_key" >> "$authorized_keys"
                log_info "SSH public key added to authorized_keys"
            else
                log_warn "Invalid SSH public key format (should start with ssh-rsa, ssh-ed25519, etc.)"
                log_warn "You'll need to manually add your key later to: $authorized_keys"
            fi
        else
            log_warn "No SSH key provided - password authentication will remain enabled"
            log_warn "Add your SSH key later to: $authorized_keys"
        fi
    else
        log_info "SSH keys already exist in authorized_keys - skipping prompt"
    fi

    log_info "SSH directory configured at '$ssh_dir'"
}

#-------------------------------------------------------------------------------
# 9. Docker Installation with Log Rotation
#-------------------------------------------------------------------------------
install_docker() {
    log_step "Installing Docker and Docker Compose..."

    # Remove old Docker versions
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    local distro
    local codename
    distro="$(lsb_release -is | tr '[:upper:]' '[:lower:]')"
    codename="$(lsb_release -cs)"

    # Install prerequisites
    apt-get install -y ca-certificates curl gnupg lsb-release

    # Add Docker GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/${distro}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/${distro} ${codename} stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -y
    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    # Enable and start Docker
    systemctl enable docker --quiet || true
    systemctl start docker  || true

    # Add user to docker group
    usermod -aG docker "$USERNAME" 2>/dev/null || true

    log_info "Docker installed successfully"
}

#-------------------------------------------------------------------------------
# 10. Docker Log Rotation (Storage Protection)
#-------------------------------------------------------------------------------
configure_docker_logging() {
    log_step "Configuring Docker log rotation..."

    local daemon_json="/etc/docker/daemon.json"

    # Create daemon.json with log rotation if it doesn't exist
    if [[ ! -f "$daemon_json" ]]; then
        cat > "$daemon_json" << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "${DOCKER_LOG_MAX_SIZE}",
    "max-file": "${DOCKER_LOG_MAX_FILE}"
  }
}
EOF
    log_info "Docker log rotation configured: max ${DOCKER_LOG_MAX_SIZE} per file, ${DOCKER_LOG_MAX_FILE} files retained"
    else
        # If daemon.json exists, ensure log opts are configured
        if ! grep -q "max-size" "$daemon_json" 2>/dev/null; then
            log_warn "Docker daemon.json exists but log rotation not configured - please add manually"
        fi
    fi

    # Restart Docker to apply log settings
    systemctl restart docker || true
}

#-------------------------------------------------------------------------------
# 11. Oh My Zsh Installation (Unattended)
#-------------------------------------------------------------------------------
install_oh_my_zsh() {
    log_step "Installing Oh My Zsh..."

    local user_home="/home/$USERNAME"
    local oh_my_zsh_dir="$user_home/.oh-my-zsh"
    local zshrc="$user_home/.zshrc"

    # Skip if already installed
    if [[ -d "$oh_my_zsh_dir" ]]; then
        log_warn "Oh My Zsh already installed - skipping"
        return 0
    fi

    # Clone Oh My Zsh directly (avoids interactive installer)
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$oh_my_zsh_dir"

    # Create fresh .zshrc from template
    if [[ ! -f "$oh_my_zsh_dir/templates/zshrc.zsh-template" ]]; then
        log_error "Oh My Zsh template not found"
        return 1
    fi

    cp "$oh_my_zsh_dir/templates/zshrc.zsh-template" "$zshrc"

    # Backup original if it existed
    [[ -f "$zshrc.bak" ]] && rm -f "$zshrc.bak"

    # Configure Oh My Zsh
    sed -i 's/^ZSH_THEME=.*/ZSH_THEME="robbyrussell"/' "$zshrc"

    # Add essential plugins (git, docker, docker-compose)
    sed -i 's/^plugins=.*/plugins=(git docker docker-compose sudo)/' "$zshrc"

    # Append terminal fixes and user aliases
    cat >> "$zshrc" << 'TERMDEOF'

#------------------------------------------------------------------------------
# Terminal Fixes (handle unknown terminal types over SSH)
#------------------------------------------------------------------------------
if ! infocmp "$TERM" &>/dev/null; then
    for term in xterm-256color xterm-color xterm vt100; do
        infocmp "$term" &>/dev/null && export TERM="$term" && break
    done
fi

# Fix key bindings for SSH sessions
bindkey '^?' backward-delete-char
bindkey '^H' backward-delete-char
bindkey "^[[3~" delete-char
bindkey "^[3;5~" delete-char
bindkey "^[[1~" beginning-of-line
bindkey "^[[4~" end-of-line
bindkey "^[[H" beginning-of-line
bindkey "^[[F" end-of-line
bindkey "^[[A" up-line-or-history
bindkey "^[[B" down-line-or-history
bindkey "^[[C" forward-char
bindkey "^[[D" backward-char

#------------------------------------------------------------------------------
# User Aliases
#------------------------------------------------------------------------------
export EDITOR=vim
export VISUAL=vim

# Navigation
alias ll='ls -lah'
alias la='ls -A'
alias ..='cd ..'
alias ...='cd ../..'

# Docker shortcuts
alias d='docker'
alias dc='docker compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias dex='docker exec -it'
alias dl='docker logs -f'
alias dcup='docker compose up -d'
alias dcdown='docker compose down'
alias dcps='docker compose ps'

# Git shortcuts
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'

# History configuration
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE

# Better completion
autoload -Uz compinit
compinit
zstyle ':completion:*' menu select
TERMDEOF

    # Set ownership
    chown -R "$USERNAME:$USERNAME" "$oh_my_zsh_dir"
    chown "$USERNAME:$USERNAME" "$zshrc"

    log_info "Oh My Zsh installed and configured"
}

#-------------------------------------------------------------------------------
# 12. System-Wide Terminal Fix
#-------------------------------------------------------------------------------
fix_terminal_detection() {
    log_step "Fixing terminal type detection system-wide..."

    # Add TERM fallback to /etc/profile
    if ! grep -q "TERM fallback" /etc/profile 2>/dev/null; then
        cat >> /etc/profile << 'EOF'

# TERM fallback for unknown terminals (xterm-ghostty, wezterm, etc.)
if ! infocmp "$TERM" &>/dev/null; then
    for term in xterm-256color xterm-color xterm vt100; do
        infocmp "$term" &>/dev/null && export TERM="$term" && break
    done
fi
EOF
    fi

    # Create /etc/profile.d/termfix.sh
    if [[ -d /etc/profile.d ]]; then
        cat > /etc/profile.d/termfix.sh << 'EOF'
# TERM fallback for unknown terminals
if ! infocmp "$TERM" &>/dev/null; then
    for term in xterm-256color xterm-color xterm vt100; do
        infocmp "$term" &>/dev/null && export TERM="$term" && break
    done
fi
EOF
        chmod 0644 /etc/profile.d/termfix.sh
    fi

    # SSH server-side TERM override (most reliable fix)
    local sshd_config="/etc/ssh/sshd_config"
    if [[ -f "$sshd_config" ]] && ! grep -q "^SetEnv TERM" "$sshd_config"; then
        # Comment out AcceptEnv TERM to prevent client override
        sed -i 's/^AcceptEnv TERM/#AcceptEnv TERM/' "$sshd_config" 2>/dev/null || true

        # Add server-side TERM override (no Match block - applies to all)
        {
            echo ""
            echo "# Server-side TERM override for unknown terminal types"
            echo "SetEnv TERM=xterm-256color"
        } >> "$sshd_config"

        systemctl reload ssh 2>/dev/null || systemctl restart ssh 2>/dev/null || true
    fi

    log_info "Terminal type detection fixed"
}

#-------------------------------------------------------------------------------
# 13. Additional Hardening
#-------------------------------------------------------------------------------
additional_hardening() {
    log_step "Applying additional hardening..."

    # Secure umask
    grep -q "umask 027" /etc/profile 2>/dev/null || echo "umask 027" >> /etc/profile

    # Disable core dumps
    grep -q "hard core 0" /etc/security/limits.conf 2>/dev/null || {
        echo "* hard core 0" >> /etc/security/limits.conf
        echo "* soft core 0" >> /etc/security/limits.conf
    }

    # Sysctl hardening (ignore errors in containers)
    sysctl -p 2>/dev/null || true

    log_info "Additional hardening applied"
}

#-------------------------------------------------------------------------------
# 14. Cleanup
#-------------------------------------------------------------------------------
cleanup() {
    log_step "Cleaning up..."
    apt-get autoremove -y --quiet
    apt-get clean --quiet
}

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------
print_summary() {
    echo ""
    log_info "=========================================="
    log_info "Ubuntu VPS Hardening Complete"
    log_info "=========================================="
    echo ""
    echo "User:       $USERNAME"
    echo "Shell:      /bin/zsh (Oh My Zsh)"
    echo "Docker:     Installed with ${DOCKER_LOG_MAX_SIZE} log rotation"
    echo "Firewall:   UFW (SSH, HTTP, HTTPS, Docker allowed)"
    echo "Fail2ban:   Enabled (3 retries, 1hr ban)"
    echo "SSH:        Root login disabled, password auth enabled (add keys to disable)"
    echo ""
    echo "Next steps:"
    echo "  1. Test SSH access: ssh $USERNAME@$(hostname -I | awk '{print $1}')"
    echo "  2. If SSH works, optionally disable password auth:"
    echo "     sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config"
    echo "     sudo systemctl restart ssh"
    echo "  3. Switch to user:  su - $USERNAME"
    echo "  4. Connect Tailscale: sudo tailscale up --advertise-routes=${TAILSCALE_SUBNET}"
    echo ""
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------
main() {
    check_root
    system_update
    install_packages
    harden_ssh
    configure_firewall
    configure_fail2ban
    create_user
    configure_sudo
    setup_ssh_keys
    install_docker
    configure_docker_logging
    install_oh_my_zsh
    fix_terminal_detection
    additional_hardening
    cleanup
    print_summary
}

main "$@"