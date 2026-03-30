#!/bin/bash
# Ubuntu/Debian User-Level Setup Script
# Run this as your regular user (NOT root)
# Features: Oh-My-Zsh installation, shell configuration, SSH key setup, dotfiles

set -e

# ============================================
# COLORS AND LOGGING FUNCTIONS
# ============================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    printf "${BLUE}[STEP]${NC} %s\n" "$1"
}

# ============================================
# CHECK RUNNING AS USER (NOT ROOT)
# ============================================

check_not_root() {
    if [ "$(id -u)" -eq 0 ]; then
        log_error "This script should NOT be run as root"
        log_error "Run this as your regular user account"
        exit 1
    fi

    USERNAME=$(whoami)
    log_info "Running user-level setup for: $USERNAME"
}

# ============================================
# 1. SETUP SSH KEYS
# ============================================

setup_ssh_keys() {
    log_step "Setting up SSH keys..."

    # Create .ssh directory
    SSH_DIR="$HOME/.ssh"
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"

    # Check if authorized_keys already exists
    if [ -f "$AUTHORIZED_KEYS" ]; then
        log_warn "authorized_keys already exists"
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
        printf "You can now add SSH public keys\n"
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
        chmod 600 "$AUTHORIZED_KEYS"
        log_info "SSH keys configured"
    fi
}

# ============================================
# 2. INSTALL OH-MY-ZSH
# ============================================

install_oh_my_zsh() {
    log_step "Installing Oh-My-Zsh..."

    # Check if zsh is available
    if ! command -v zsh >/dev/null 2>&1; then
        log_error "zsh is not installed. Please run the system setup script first (as root)."
        log_error "Or ask your admin to install zsh: sudo apt install zsh"
        exit 1
    fi

    # Verify git is available (required for Oh-My-Zsh)
    if ! command -v git >/dev/null 2>&1; then
        log_error "git is not installed. Please install git first."
        exit 1
    fi

    # Check if oh-my-zsh is already installed
    if [ -d "$HOME/.oh-my-zsh" ]; then
        log_warn "Oh-My-Zsh already installed. Skipping installation."
    else
        log_info "Downloading Oh-My-Zsh installation script..."

        # Download and install oh-my-zsh using a non-interactive method
        if command -v curl >/dev/null 2>&1; then
            if ! curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o /tmp/install.sh; then
                log_error "Failed to download Oh-My-Zsh installer with curl"
                exit 1
            fi
        elif command -v wget >/dev/null 2>&1; then
            if ! wget -q https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -O /tmp/install.sh; then
                log_error "Failed to download Oh-My-Zsh installer with wget"
                exit 1
            fi
        else
            log_error "Neither curl nor wget is available"
            exit 1
        fi

        # Run the installer in unattended mode
        log_info "Running Oh-My-Zsh installer..."
        if ! bash /tmp/install.sh --unattended --keep-zshrc; then
            log_warn "Oh-My-Zsh installer failed, but continuing..."
        fi

        # Clean up
        rm -f /tmp/install.sh

        # Verify installation
        if [ -d "$HOME/.oh-my-zsh" ]; then
            log_info "Oh-My-Zsh installed successfully"
        else
            log_warn "Oh-My-Zsh installation may have failed - .oh-my-zsh directory not found"
            log_warn "You can install it manually later:"
            log_warn "  sh -c \"$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" \"\" --unattended"
        fi
    fi

    # Set up .zshrc with sensible defaults
    setup_zshrc
}

# ============================================
# 3. SETUP .ZSHRC CONFIGURATION
# ============================================

setup_zshrc() {
    log_step "Configuring .zshrc..."

    ZSHRC="$HOME/.zshrc"

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

        log_info ".zshrc configured successfully"
    fi

    # Change default shell to zsh if not already
    CURRENT_SHELL=$(getent passwd "$USERNAME" | cut -d: -f7)
    if [ "$CURRENT_SHELL" != "/bin/zsh" ]; then
        log_info "Changing default shell to zsh..."
        if ! chsh -s /bin/zsh; then
            log_warn "Could not change shell automatically. Ask your admin to run: sudo chsh -s /bin/zsh $USERNAME"
        else
            log_info "Default shell changed to zsh. Restart your session to apply."
        fi
    fi
}

# ============================================
# 4. SETUP GIT CONFIGURATION
# ============================================

setup_git() {
    log_step "Setting up Git configuration..."

    # Check if git is available
    if ! command -v git >/dev/null 2>&1; then
        log_warn "git is not installed. Skipping git configuration."
        return
    fi

    GITCONFIG="$HOME/.gitconfig"

    # Check if .gitconfig already exists
    if [ -f "$GITCONFIG" ]; then
        log_warn ".gitconfig already exists. Skipping git configuration."
        return
    fi

    printf ""
    printf "${GREEN}==========================================\n"
    printf "Git Configuration\n"
    printf "==========================================${NC}\n"
    printf ""

    # Prompt for user name
    printf "${YELLOW}Enter your Git user name:${NC}\n"
    read -r GIT_NAME

    # Prompt for email
    printf "${YELLOW}Enter your Git email:${NC}\n"
    read -r GIT_EMAIL

    if [ -n "$GIT_NAME" ] && [ -n "$GIT_EMAIL" ]; then
        git config --global user.name "$GIT_NAME"
        git config --global user.email "$GIT_EMAIL"
        log_info "Git configuration saved"
    else
        log_warn "Git configuration skipped (name or email not provided)"
    fi
}

# ============================================
# 5. CREATE USEFUL DIRECTORIES
# ============================================

setup_directories() {
    log_step "Creating useful directories..."

    # Create common directories
    mkdir -p "$HOME/projects"
    mkdir -p "$HOME/bin"
    mkdir -p "$HOME/tmp"
    mkdir -p "$HOME/.local/bin"

    log_info "Directories created: projects, bin, tmp, .local/bin"
}

# ============================================
# 6. SUMMARY
# ============================================

print_summary() {
    printf ""
    log_info "=========================================="
    log_info "User-level setup completed successfully!"
    log_info "=========================================="
    printf ""
    log_info "What was configured:"
    printf "  - SSH keys (if added)\n"
    printf "  - Oh-My-Zsh installed\n"
    printf "  - .zshrc configured with aliases and key bindings\n"
    printf "  - Git configured (if provided)\n"
    printf "  - Useful directories created\n"
    printf ""
    log_warn "IMPORTANT NOTES:"
    log_warn "1. Restart your shell or run: exec zsh"
    log_warn "2. If you didn't add SSH keys, add them to: $HOME/.ssh/authorized_keys"
    log_warn "3. Your default shell is now zsh"
    printf ""
    log_info "To restart your shell:"
    printf "  exec zsh\n"
    printf ""
    log_info "To verify Git:"
    printf "  git config --user.name\n"
    printf "  git config --user.email\n"
    printf ""
}

# ============================================
# MAIN EXECUTION
# ============================================

main() {
    printf ""
    printf "${GREEN}==========================================\n"
    printf "Ubuntu/Debian User-Level Setup\n"
    printf "==========================================${NC}\n"
    printf ""

    check_not_root
    setup_ssh_keys
    install_oh_my_zsh
    setup_git
    setup_directories
    print_summary
}

# Run main function
main
