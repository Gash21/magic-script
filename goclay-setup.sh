#!/bin/bash
#===============================================================================
# GoClaw Development Environment Setup Script
# Purpose: Install GoClaw, Node.js, Claude Code, and development dependencies
# Target: Ubuntu/Debian systems (after ubuntu-setup.sh has been run)
#===============================================================================

set -euo pipefail

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
readonly NODE_VERSION="22"
readonly GOCLAW_IMAGE="ghcr.io/nextlevelbuilder/goclaw:full"
readonly GOCLAW_PORT="18789"
readonly USERNAME="$(hostname)"

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
    log_info "Starting GoClaw development environment setup..."
}

#-------------------------------------------------------------------------------
# 1. System Packages (skip if already installed)
#-------------------------------------------------------------------------------
install_system_packages() {
    log_step "Installing system packages..."

    apt-get update -y

    # Packages that may already be installed from ubuntu-setup.sh
    apt-get install -y \
        tmux \
        git \
        curl \
        wget \
        jq \
        redis-server \
        postgresql-client \
        build-essential \
        unzip \
        || true

    # Enable and start redis
    systemctl enable redis-server --quiet || true
    systemctl start redis-server || true

    log_info "System packages installed"
}

#-------------------------------------------------------------------------------
# 2. fnm (Fast Node Manager)
#-------------------------------------------------------------------------------
install_fnm() {
    log_step "Installing fnm (Node.js version manager)..."

    # Check if fnm is already installed
    if command -v fnm &>/dev/null; then
        log_info "fnm already installed - skipping"
        return 0
    fi

    # Install fnm
    curl -fsSL https://fnm.vercel.app/install | bash

    # Make fnm available for root
    export PATH="/root/.local/share/fnm:$PATH"
    if [[ -f "/root/.local/share/fnm/fnm" ]]; then
        # Add fnm to .bashrc for future sessions
        grep -q "fnm env" /root/.bashrc 2>/dev/null || echo 'export PATH="/root/.local/share/fnm:$PATH"' >> /root/.bashrc
        grep -q "fnm env" /root/.bashrc 2>/dev/null || echo 'eval "$(fnm env --use-on-cd)"' >> /root/.bashrc
        log_info "fnm installed and added to .bashrc"
    else
        log_error "fnm installation failed"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# 3. Node.js via fnm
#-------------------------------------------------------------------------------
install_nodejs() {
    log_step "Installing Node.js ${NODE_VERSION} via fnm..."

    # Ensure fnm is in PATH
    export PATH="/root/.local/share/fnm:$PATH"

    if ! command -v fnm &>/dev/null; then
        log_error "fnm not found - cannot install Node.js"
        return 1
    fi

    # Install Node.js 22
    fnm install "${NODE_VERSION}" 2>/dev/null || log_warn "Node.js ${NODE_VERSION} already installed"

    # Use Node.js 22
    fnm use "${NODE_VERSION}"

    # Set as default
    fnm default "${NODE_VERSION}"

    # Verify installation
    if command -v node &>/dev/null; then
        local node_version
        node_version="$(node --version)"
        local npm_version
        npm_version="$(npm --version)"
        log_info "Node.js installed: ${node_version}, npm: ${npm_version}"
    else
        log_error "Node.js installation verification failed"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# 4. Claude Code CLI
#-------------------------------------------------------------------------------
install_claude_code() {
    log_step "Installing Claude Code CLI..."

    # Ensure Node.js is available
    export PATH="/root/.local/share/fnm:$PATH"
    fnm use "${NODE_VERSION}" &>/dev/null || true

    # Check if already installed
    if command -v claude &>/dev/null; then
        local claude_version
        claude_version="$(claude --version 2>/dev/null || echo 'unknown')"
        log_info "Claude Code already installed: ${claude_version}"
        return 0
    fi

    # Install Claude Code
    npm install -g @anthropic-ai/claude-code

    # Verify installation
    if command -v claude &>/dev/null; then
        log_info "Claude Code CLI installed: $(claude --version)"
    else
        log_error "Claude Code CLI installation failed"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# 5. Happy-Coder CLI
#-------------------------------------------------------------------------------
install_happy_coder() {
    log_step "Installing Happy-Coder CLI..."

    # Ensure Node.js is available
    export PATH="/root/.local/share/fnm:$PATH"
    fnm use "${NODE_VERSION}" &>/dev/null || true

    # Check if already installed
    if command -v happy &>/dev/null; then
        local happy_version
        happy_version="$(happy --version 2>/dev/null || echo 'unknown')"
        log_info "Happy-Coder already installed: ${happy_version}"
        return 0
    fi

    # Install Happy-Coder
    npm install -g happy-coder

    # Verify installation
    if command -v happy &>/dev/null; then
        log_info "Happy-Coder installed: $(happy --version)"
        echo ""
        echo "=========================================="
        echo "Happy-Coder Usage Instructions"
        echo "=========================================="
        echo "- Run 'happy' instead of 'claude' to start mobile-enabled sessions"
        echo "- Download Happy Coder app (iOS/Android) and scan QR code"
        echo "- Use 'happy codex' for Codex sessions"
        echo ""
    else
        log_error "Happy-Coder installation failed"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# 6. OpenAI Codex CLI
#-------------------------------------------------------------------------------
install_openai_codex() {
    log_step "Installing OpenAI Codex CLI..."

    # Ensure Node.js is available
    export PATH="/root/.local/share/fnm:$PATH"
    fnm use "${NODE_VERSION}" &>/dev/null || true

    # Check if already installed
    if command -v codex &>/dev/null; then
        local codex_version
        codex_version="$(codex --version 2>/dev/null || echo 'unknown')"
        log_info "OpenAI Codex already installed: ${codex_version}"
        return 0
    fi

    # Install OpenAI Codex
    npm install -g @openai/codex

    # Verify installation
    if command -v codex &>/dev/null; then
        log_info "OpenAI Codex CLI installed: $(codex --version)"
    else
        log_error "OpenAI Codex CLI installation failed"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# 7. GoClaw via Docker
#-------------------------------------------------------------------------------
install_goclaw() {
    log_step "Installing GoClaw via Docker..."

    # Check if Docker is available
    if ! command -v docker &>/dev/null; then
        log_error "Docker not found. Please run ubuntu-setup.sh first"
        return 1
    fi

    # Pull GoClaw image
    log_info "Pulling GoClaw Docker image..."
    docker pull "${GOCLAW_IMAGE}"

    # Create goclaw config directory for root user
    mkdir -p /root/.goclaw
    chmod 700 /root/.goclaw

    # Also create for the regular user
    mkdir -p "/home/${USERNAME}/.goclaw"
    chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.goclaw"
    chmod 700 "/home/${USERNAME}/.goclaw"

    # Create docker-compose file for GoClaw
    local compose_file="/root/docker-compose.goclaw.yml"

    if [[ ! -f "$compose_file" ]]; then
        cat > "$compose_file" << 'EOF'
version: '3.8'
services:
  goclaw:
    image: ghcr.io/nextlevelbuilder/goclaw:full
    container_name: goclaw-pipeline
    restart: unless-stopped
    ports:
      - "18789:18789"
    volumes:
      - /root/.goclaw:/root/.goclaw
      - /var/run/docker.sock:/var/run/docker.sock
      - ./:/workspace:ro
    environment:
      - GOCLAW_OPENAI_API_KEY=${OPENAI_API_KEY}
      - GOCLAW_MINIMAX_API_KEY=${MINIMAX_API_KEY}
      - GOCLAW_TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
      - GOCLAW_TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID}
    env_file:
      - .env
EOF
        log_info "Docker Compose file created: ${compose_file}"
    else
        log_info "Docker Compose file already exists - skipping"
    fi

    log_info "GoClaw setup complete"
}

#-------------------------------------------------------------------------------
# 8. GitHub CLI (gh)
#-------------------------------------------------------------------------------
install_gh_cli() {
    log_step "Installing GitHub CLI (gh)..."

    # Check if already installed
    if command -v gh &>/dev/null; then
        local gh_version
        gh_version="$(gh --version 2>/dev/null | head -n1 || echo 'unknown')"
        log_info "GitHub CLI already installed: ${gh_version}"

        # Check auth status
        echo ""
        echo "GitHub CLI Authentication Status:"
        gh auth status 2>&1 || true
        echo ""

        return 0
    fi

    # Install GitHub CLI via official apt repo
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    apt-get update -y
    apt-get install -y gh

    # Verify installation
    if command -v gh &>/dev/null; then
        log_info "GitHub CLI installed: $(gh --version | head -n1)"
        echo ""
        echo "=========================================="
        echo "GitHub CLI Authentication Required"
        echo "=========================================="
        echo "To authenticate with GitHub, run:"
        echo "  gh auth login"
        echo ""
    else
        log_error "GitHub CLI installation failed"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# 9. Environment Setup for Regular User
#-------------------------------------------------------------------------------
setup_user_environment() {
    log_step "Setting up environment for user ${USERNAME}..."

    local user_home="/home/${USERNAME}"
    local bashrc="${user_home}/.bashrc"
    local zshrc="${user_home}/.zshrc"

    # Add fnm to PATH in user's shell config
    for shell_config in "$zshrc" "$bashrc"; do
        if [[ -f "$shell_config" ]]; then
            grep -q "fnm env" "$shell_config" 2>/dev/null || {
                echo "" >> "$shell_config"
                echo "# fnm - Fast Node Manager" >> "$shell_config"
                echo 'export PATH="/home/'"$USERNAME"'/.local/share/fnm:$PATH"' >> "$shell_config"
                echo 'eval "$(fnm env --use-on-cd)"' >> "$shell_config"
            }
        fi
    done

    # Install fnm for the regular user too
    if [[ ! -d "${user_home}/.local/share/fnm" ]]; then
        su - "$USERNAME" -c 'curl -fsSL https://fnm.vercel.app/install | bash' || true
    fi

    log_info "User environment configured"
}

#-------------------------------------------------------------------------------
# 10. Create .env Template
#-------------------------------------------------------------------------------
create_env_template() {
    log_step "Creating .env template..."

    local env_file="/root/.env.goclaw.template"

    if [[ ! -f "$env_file" ]]; then
        cat > "$env_file" << 'EOF'
# GoClaw Environment Variables
# Copy this file to .env and fill in your API keys

OPENAI_API_KEY=your_openai_api_key_here
MINIMAX_API_KEY=your_minimax_api_key_here
TELEGRAM_BOT_TOKEN=your_telegram_bot_token_here
TELEGRAM_CHAT_ID=your_telegram_chat_id_here
EOF
        log_info "Environment template created: ${env_file}"
        log_warn "Copy to .env and fill in your API keys before starting GoClaw"
    else
        log_info "Environment template already exists - skipping"
    fi
}

#-------------------------------------------------------------------------------
# 11. Start Services
#-------------------------------------------------------------------------------
start_services() {
    log_step "Starting services..."

    # Start Redis
    systemctl start redis-server || true

    # Note: GoClaw is not started automatically because it needs API keys
    log_info "Services started (Redis)"
    log_warn "GoClaw not started - configure .env first, then run:"
    log_warn "  docker-compose -f /root/docker-compose.goclaw.yml up -d"
}

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------
print_summary() {
    echo ""
    log_info "=========================================="
    log_info "GoClaw Development Environment Setup Complete"
    log_info "=========================================="
    echo ""
    echo "Installed Components:"
    echo "  ✓ tmux, git, curl, wget, jq"
    echo "  ✓ redis-server"
    echo "  ✓ postgresql-client"
    echo "  ✓ build-essential"
    echo "  ✓ fnm (Node.js version manager)"
    echo "  ✓ Node.js ${NODE_VERSION}"
    echo "  ✓ Claude Code CLI"
    echo "  ✓ Happy-Coder CLI"
    echo "  ✓ OpenAI Codex CLI"
    echo "  ✓ GoClaw (Docker)"
    echo "  ✓ GitHub CLI (gh)"
    echo ""
    echo "Next Steps:"
    echo "  1. Configure GoClaw environment:"
    echo "     cp /root/.env.goclaw.template /root/.env"
    echo "     # Edit /root/.env with your API keys"
    echo ""
    echo "  2. Start GoClaw:"
    echo "     docker-compose -f /root/docker-compose.goclaw.yml up -d"
    echo ""
    echo "  3. Authenticate GitHub CLI:"
    echo "     gh auth login"
    echo ""
    echo "  4. For regular user ($USERNAME):"
    echo "     su - $USERNAME"
    echo "     fnm use ${NODE_VERSION}"
    echo ""
    echo "Quick Commands:"
    echo "  • claude        - Start Claude Code"
    echo "  • happy         - Start Happy-Coder (mobile-enabled)"
    echo "  • happy codex   - Start Codex session"
    echo "  • tmux          - Start terminal multiplexer"
    echo ""
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------
main() {
    check_root
    install_system_packages
    install_fnm
    install_nodejs
    install_claude_code
    install_happy_coder
    install_openai_codex
    install_goclaw
    install_gh_cli
    setup_user_environment
    create_env_template
    start_services
    print_summary
}

main "$@"
