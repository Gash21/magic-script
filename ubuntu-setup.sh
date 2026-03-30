#!/bin/bash
# Ubuntu/Debian Initial Setup Script for Proxmox LXC
# Features: Basic hardening, user creation, sudo setup, SSH key setup, Docker + Docker Compose, zsh + Oh-My-Zsh

set -e

# ============================================
# COLORS AND LOGGING FUNCTIONS
# ============================================

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

# ============================================
# 0. CHECK ROOT
# ============================================

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
    log_info "Starting Ubuntu/Debian setup..."
}

# ============================================
# 1. BASIC HARDENING
# ============================================

basic_hardening() {
    log_info "Applying basic hardening..."

    # Update and upgrade all packages
    export DEBIAN_FRONTEND=noninteractive
    apt update
    apt upgrade -y

    # Install essential packages
    apt install -y \
        sudo \
        curl \
        ca-certificates \
        fail2ban \
        openssh-server \
        ufw \
        bash \
        zsh \
        git \
        vim \
        ncurses-term \
        lsb-release \
        gnupg

    # Enable and start SSH server
    systemctl enable ssh 2>/dev/null || true
    systemctl start ssh 2>/dev/null || true

    # Enable and start fail2ban
    systemctl enable fail2ban 2>/dev/null || true
    systemctl start fail2ban 2>/dev/null || true

    # Configure UFW (Uncomplicated Firewall)
    log_info "Configuring firewall..."

    # Allow SSH and essential services
    ufw default deny incoming 2>/dev/null || true
    ufw default allow outgoing 2>/dev/null || true
    ufw allow ssh 2>/dev/null || true
    ufw allow http 2>/dev/null || true
    ufw allow https 2>/dev/null || true

    # Enable UFW
    ufw --force enable 2>/dev/null || true

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

        # Disable root login
        sed -i 's/^#*[[:space:]]*PermitRootLogin.*/PermitRootLogin no/' "$SSH_CONFIG" 2>/dev/null || \
            sed -i '/^PermitRootLogin/c\PermitRootLogin no' "$SSH_CONFIG"

        # Disable password authentication (key-based only)
        sed -i 's/^#*[[:space:]]*PasswordAuthentication.*/PasswordAuthentication no/' "$SSH_CONFIG" 2>/dev/null || \
            sed -i '/^PasswordAuthentication/c\PasswordAuthentication no' "$SSH_CONFIG"

        # Disable empty passwords
        sed -i 's/^#*[[:space:]]*PermitEmptyPasswords.*/PermitEmptyPasswords no/' "$SSH_CONFIG" 2>/dev/null || \
            sed -i '/^PermitEmptyPasswords/c\PermitEmptyPasswords no' "$SSH_CONFIG"

        # Restart SSH service
        systemctl restart ssh 2>/dev/null || true
    fi
}

# ============================================
# 2. CREATE USER WITH HOSTNAME
# ============================================

create_user() {
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
        adduser --disabled-password --gecos "" "$USERNAME"

        # CRITICAL FIX: Set home directory permissions to 700 to satisfy SSH StrictModes
        chmod 700 "/home/$USERNAME"
        chown "$USERNAME:$USERNAME" "/home/$USERNAME"

        # CRITICAL FIX: Unlock the account by setting a random complex password
        RANDOM_PASS=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
        echo "$USERNAME:$RANDOM_PASS" | chpasswd

        log_info "User $USERNAME created successfully (account unlocked with random password)"
    fi
}

# ============================================
# 3. SETUP SSH KEYS
# ============================================

setup_ssh_keys() {
    log_info "Setting up SSH keys..."

    # Create .ssh directory
    SSH_DIR="/home/$USERNAME/.ssh"
    mkdir -p "$SSH_DIR"
    chown "$USERNAME:$USERNAME" "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"

    # Check if authorized_keys already exists
    if [ -f "$AUTHORIZED_KEYS" ]; then
        log_warn "authorized_keys already exists for $USERNAME"
        printf ""
        printf "${YELLOW}Current SSH keys:${NC}\n"
        cat "$AUTHORIZED_KEYS"
        printf ""

        # Ask if user wants to add more keys
        printf "${YELLOW}Do you want to add more SSH keys? (y/n)${NC}\n"
        read -r ADD_MORE

        if [ "$ADD_MORE" != "y" ] && [ "$ADD_MORE" != "Y" ]; then
            log_info "Skipping SSH key addition"
        else
            while true; do
                printf ""
                printf "${GREEN}Paste SSH public key (or press Enter to finish):${NC}\n"
                read -r SSH_KEY

                if [ -z "$SSH_KEY" ]; then
                    break
                fi

                # Check if key already exists
                if grep -qF "$SSH_KEY" "$AUTHORIZED_KEYS" 2>/dev/null; then
                    log_warn "This SSH key already exists. Skipping."
                else
                    printf "%s\n" "$SSH_KEY" >> "$AUTHORIZED_KEYS"
                    log_info "SSH key added successfully"
                fi
            done
        fi
    else
        # No existing keys, prompt for new ones
        printf ""
        printf "${GREEN}==========================================\n"
        printf "SSH Key Setup\n"
        printf "==========================================${NC}\n"
        printf ""
        printf "You can now add SSH public keys for $USERNAME\n"
        printf "${YELLOW}IMPORTANT: Paste the entire key on a single line. Avoid extra newlines.${NC}\n"
        printf "Paste one key at a time, or press Enter to finish\n"
        printf ""

        KEY_COUNT=0
        while true; do
            printf "${YELLOW}Enter SSH public key #%d (or press Enter to finish):${NC}\n" "$((KEY_COUNT + 1))"
            read -r SSH_KEY

            if [ -z "$SSH_KEY" ]; then
                if [ $KEY_COUNT -eq 0 ]; then
                    log_warn "No SSH keys were added!"
                    printf ""
                    printf "${RED}WARNING: You won't be able to SSH into this server without SSH keys!${NC}\n"
                    printf "${YELLOW}You can add keys later by manually editing: $AUTHORIZED_KEYS${NC}\n"
                else
                    log_info "SSH key setup completed. $KEY_COUNT key(s) added."
                fi
                break
            fi

            # Basic validation - check if it looks like an SSH key
            if printf "%s\n" "$SSH_KEY" | grep -qE '^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp|ssh-dss) '; then
                printf "%s\n" "$SSH_KEY" >> "$AUTHORIZED_KEYS"
                KEY_COUNT=$((KEY_COUNT + 1))
                log_info "SSH key #$KEY_COUNT added"
            else
                log_warn "Invalid SSH key format. Please paste a valid public key."
                log_warn "Key should start with: ssh-rsa, ssh-ed25519, ecdsa-sha2-nistp*, or ssh-dss"
            fi
        done
    fi

    # Set proper permissions for authorized_keys
    if [ -f "$AUTHORIZED_KEYS" ]; then
        chown "$USERNAME:$USERNAME" "$AUTHORIZED_KEYS"
        chmod 600 "$AUTHORIZED_KEYS"
        log_info "SSH keys configured for $USERNAME"
    fi
}

# ============================================
# 4. SETUP SUDOERS
# ============================================

setup_sudoers() {
    log_info "Configuring sudoers..."

    # Create sudoers.d directory if it doesn't exist
    mkdir -p /etc/sudoers.d

    # Add user to sudoers with no password requirement
    if [ ! -f "/etc/sudoers.d/$USERNAME" ]; then
        printf "%s ALL=(ALL) NOPASSWD:ALL\n" "$USERNAME" > "/etc/sudoers.d/$USERNAME"
    fi

    # Set proper permissions
    chmod 0440 "/etc/sudoers.d/$USERNAME"

    # Add user to sudo group
    usermod -aG sudo "$USERNAME" 2>/dev/null || true

    log_info "Sudoers configured for $USERNAME"

    # Add convenience alias for root to switch to user
    ROOT_PROFILE="/root/.bashrc"
    if [ -f "$ROOT_PROFILE" ]; then
        if ! grep -q "alias to-$USERNAME=" "$ROOT_PROFILE" 2>/dev/null; then
            printf "" >> "$ROOT_PROFILE"
            printf "# Quick alias to switch to %s\n" "$USERNAME" >> "$ROOT_PROFILE"
            printf "alias to-%s='su - %s'\n" "$USERNAME" "$USERNAME" >> "$ROOT_PROFILE"
            log_info "Added alias 'to-$USERNAME' to root's bashrc"
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

    # Test sudo configuration
    log_info "Verifying sudo configuration..."
    if [ -f "/etc/sudoers.d/$USERNAME" ] && grep -q "$USERNAME.*NOPASSWD.*ALL" "/etc/sudoers.d/$USERNAME"; then
        log_info "✓ User $USERNAME has sudo access (verified via config)"
    else
        log_warn "Could not verify sudo access for $USERNAME"
    fi
}

# ============================================
# 5. INSTALL TAILSCALE
# ============================================

install_tailscale() {
    log_info "Installing Tailscale..."

    # Add Tailscale repository
    curl -fsSL https://tailscale.com/install.sh | sh

    # Enable and start Tailscale
    systemctl enable tailscaled 2>/dev/null || true
    systemctl start tailscaled 2>/dev/null || true

    log_info "Starting Tailscale daemon..."
    sleep 2

    if systemctl is-active --quiet tailscaled; then
        log_info "✓ Tailscale daemon is running"
    else
        log_warn "Tailscale daemon may not be running properly"
        log_warn "You may need to manually start it with: systemctl start tailscaled"
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
    printf "   ${YELLOW}sudo tailscale up --advertise-routes=192.168.0.0/24 --accept-routes${NC}\n"
    printf ""
    printf "2. Open the URL shown in the output to authenticate via your Tailscale account\n"
    printf ""
    printf "3. In the Tailscale admin console, approve the subnet routes for this machine\n"
    printf ""
    printf "${GREEN}After setup, your local network (192.168.0.0/24) will be accessible from Tailscale.${NC}\n"
    printf ""
}

# ============================================
# 6. INSTALL DOCKER
# ============================================

install_docker() {
    log_info "Installing Docker..."

    # Remove old Docker versions if present
    apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    # Set up Docker repository
    DISTRO=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
    CODENAME=$(lsb_release -cs)

    # Install dependencies
    apt install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/${DISTRO}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Set up Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DISTRO} \
      ${CODENAME} stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Update package index
    apt update

    # Install Docker and Docker Compose
    apt install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    # Enable Docker service
    systemctl enable docker 2>/dev/null || true
    systemctl start docker 2>/dev/null || true

    # Add user to docker group
    usermod -aG docker "$USERNAME" 2>/dev/null || true

    log_info "Docker installed and started"

    # Display Docker version for verification
    docker --version
    docker compose version
}

# ============================================
# 7. INSTALL OH-MY-ZSH
# ============================================

install_oh_my_zsh() {
    log_info "Installing Oh-My-Zsh..."

    # Verify git is available (required for Oh-My-Zsh)
    if ! command -v git >/dev/null 2>&1; then
        log_error "git is not installed. Installing git first..."
        apt install -y git
    fi

    # Check if oh-my-zsh is already installed
    if [ -d "/home/$USERNAME/.oh-my-zsh" ]; then
        log_warn "Oh-My-Zsh already installed for $USERNAME. Skipping installation."
    else
        log_info "Downloading Oh-My-Zsh installation script..."

        # Save current directory
        CURRENT_DIR=$(pwd)

        # Download oh-my-zsh directly (avoiding su permission issues in LXC)
        cd "/home/$USERNAME" || { log_error "Cannot access home directory"; exit 1; }

        # Download and install oh-my-zsh using a non-interactive method
        if command -v curl >/dev/null 2>&1; then
            if ! curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o install.sh; then
                log_error "Failed to download Oh-My-Zsh installer with curl"
                cd "$CURRENT_DIR" || exit 1
                exit 1
            fi
        elif command -v wget >/dev/null 2>&1; then
            if ! wget -q https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -O install.sh; then
                log_error "Failed to download Oh-My-Zsh installer with wget"
                cd "$CURRENT_DIR" || exit 1
                exit 1
            fi
        else
            log_error "Neither curl nor wget is available"
            cd "$CURRENT_DIR" || exit 1
            exit 1
        fi

        # Verify installer was downloaded
        if [ ! -f install.sh ]; then
            log_error "Installer script not found after download"
            cd "$CURRENT_DIR" || exit 1
            exit 1
        fi

        # Run the installer in unattended mode
        log_info "Running Oh-My-Zsh installer..."
        if ! bash install.sh --unattended --keep-zshrc; then
            log_warn "Oh-My-Zsh installer failed, but continuing..."
        fi

        # Clean up
        rm -f install.sh

        # Return to original directory
        cd "$CURRENT_DIR" || exit 1

        # Fix ownership (ensure all files belong to the user) - ONLY if directory exists
        if [ -d "/home/$USERNAME/.oh-my-zsh" ]; then
            chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.oh-my-zsh" 2>/dev/null || true
            log_info "Oh-My-Zsh installed successfully"
        else
            log_warn "Oh-My-Zsh installation may have failed - .oh-my-zsh directory not found"
            log_warn "You can install it manually later by running as the user: sh -c \"$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" \"\" --unattended"
        fi

        # Fix .zshrc ownership if it exists
        if [ -f "/home/$USERNAME/.zshrc" ]; then
            chown "$USERNAME:$USERNAME" "/home/$USERNAME/.zshrc" 2>/dev/null || true
        fi
    fi

    # Set up a robust .zshrc with sensible defaults
    ZSHRC="/home/$USERNAME/.zshrc"

    # Backup original .zshrc if it exists
    if [ -f "$ZSHRC" ]; then
        cp "$ZSHRC" "${ZSHRC}.bak"
    fi

    # Add useful configurations to .zshrc (if not already added)
    if grep -q "# User configuration" "$ZSHRC" 2>/dev/null; then
        log_warn "Custom zsh configuration already exists. Skipping .zshrc modification."
    else
        cat >> "$ZSHRC" << 'EOF'

# ============================================
# TERMINAL & KEY BINDINGS FIX
# ============================================
# Fix backspace, delete, arrow keys, and other terminal issues over SSH

# Smart terminal detection - fall back to known-good terminals
# This handles terminals like xterm-ghostty, wezterm, etc. that Ubuntu doesn't have
if ! infocmp "$TERM" >/dev/null 2>&1; then
    # Current TERM not available, try common alternatives in order of preference
    for term in xterm-256color xterm-color xterm vt100; do
        if infocmp "$term" >/dev/null 2>&1; then
            export TERM="$term"
            break
        fi
    done
fi

# Fix terminal key bindings for SSH sessions
autoload -Uz zsh-line-init
zsh-line-init() {
    # Fix backspace key (most common issue)
    bindkey '^?' backward-delete-char
    bindkey '^H' backward-delete-char
    # Fix delete key
    bindkey "^[[3~" delete-char
    bindkey "^[3;5~" delete-char
    # Fix home/end keys
    bindkey "^[[1~" beginning-of-line
    bindkey "^[[4~" end-of-line
    bindkey "^[[H" beginning-of-line
    bindkey "^[[F" end-of-line
    # Fix arrow keys
    bindkey "^[[A" up-line-or-history
    bindkey "^[[B" down-line-or-history
    bindkey "^[[C" forward-char
    bindkey "^[[D" backward-char
}
zsh-line-init

# Set terminal erase character properly
stty erase '^?' 2>/dev/null || true

# ============================================
# USER CONFIGURATION
# ============================================
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

# Tailscale aliases
alias ts='tailscale'
alias tss='tailscale status'
alias tsup='sudo tailscale up --advertise-routes=192.168.0.0/24 --accept-routes'
alias tsdown='sudo tailscale down'

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
    fi

    log_info "Oh-My-Zsh installed and configured for $USERNAME"
}

# ============================================
# 8. ADDITIONAL HARDENING
# ============================================

additional_hardening() {
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
}

# ============================================
# 9. CLEANUP
# ============================================

cleanup() {
    log_info "Cleaning up..."

    # Clean apt cache
    apt clean
    apt autoremove -y
}

# ============================================
# 10. SUMMARY
# ============================================

print_summary() {
    printf ""
    log_info "=========================================="
    log_info "Setup completed successfully!"
    log_info "=========================================="
    printf ""
    log_info "Summary:"
    printf "  - User created: %s\n" "$USERNAME"
    printf "  - User has full sudo access (NOPASSWD)\n"
    printf "  - SSH keys configured (if added during setup)\n"
    printf "  - Shell: zsh with Oh-My-Zsh\n"
    printf "  - Tailscale installed (requires manual setup)\n"
    printf "  - Docker & Docker Compose installed and running\n"
    printf "  - Firewall enabled (UFW)\n"
    printf "  - Fail2ban enabled\n"
    printf "  - SSH hardened (root login disabled, password auth disabled)\n"
    printf "  - Root alias 'to-%s' added for quick user switching\n" "$USERNAME"
    printf ""
    log_warn "IMPORTANT NOTES:"
    log_warn "1. SSH password authentication is disabled - use SSH keys only"
    log_warn "2. Root login is disabled"
    log_warn "3. If you didn't add SSH keys, add them manually to: $AUTHORIZED_KEYS"
    log_warn "4. User $USERNAME has full sudo access (no password required)"
    log_warn "5. From root, use 'to-$USERNAME' or 'su - $USERNAME' to switch to user"
    log_warn "6. Tailscale is installed but NOT authenticated - see instructions above"
    log_warn "7. If Tailscale daemon is not running, restart with: systemctl restart tailscaled"
    log_warn "8. Terminal key bindings (backspace/arrows) are auto-configured for SSH"
    printf ""
    log_info "To switch to the new user, run:"
    printf "  su - %s\n" "$USERNAME"
    printf "  or use the alias: to-%s\n" "$USERNAME"
    printf ""
    log_info "To verify sudo access:"
    printf "  sudo -u %s sudo whoami\n" "$USERNAME"
    printf ""
    log_info "To verify Docker:"
    printf "  docker run --rm hello-world\n"
    printf ""
    log_info "To verify Docker Compose:"
    printf "  docker compose version\n"
    printf ""
    log_info "To connect Tailscale (subnet router for 192.168.0.0/24):"
    printf "  sudo tailscale up --advertise-routes=192.168.0.0/24 --accept-routes\n"
    printf "  (Then approve routes in Tailscale admin console)\n"
    printf ""
    log_info "To test SSH connection (from another machine):"
    printf "  ssh %s@%s\n" "$USERNAME" "$(hostname -i | awk '{print $1}')"
    printf ""
}

# ============================================
# MAIN EXECUTION
# ============================================

main() {
    check_root
    basic_hardening
    create_user
    setup_ssh_keys
    setup_sudoers
    install_tailscale
    install_docker
    install_oh_my_zsh
    additional_hardening
    cleanup
    print_summary
}

# Run main function
main
