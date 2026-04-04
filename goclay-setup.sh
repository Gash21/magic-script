#!/bin/bash
#===============================================================================
# GoClaw Development Environment Setup Script
# Purpose: Install GoClaw, Node.js, Claude Code, and development dependencies
#          with complete pipeline directory structure and helper scripts
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
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$SCRIPT_DIR"

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
check_pass() { printf "  ${GREEN}✅${NC} %s\n" "$1"; }
check_warn() { printf "  ${YELLOW}⚠️${NC}  %s\n" "$1"; }
check_fail() { printf "  ${RED}❌${NC} %s\n" "$1"; }

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

    # Make fnm available immediately in current session
    export PATH="/root/.local/share/fnm:$PATH"

    # Source fnm environment in current shell
    if [[ -f "/root/.local/share/fnm/fnm" ]]; then
        eval "$("/root/.local/share/fnm/fnm" env --shell bash)"

        # Add fnm to .bashrc for future Bash sessions
        grep -q "fnm env" /root/.bashrc 2>/dev/null || {
            echo "" >> /root/.bashrc
            echo "# fnm - Fast Node Manager" >> /root/.bashrc
            echo 'export PATH="/root/.local/share/fnm:$PATH"' >> /root/.bashrc
            echo 'eval "$(fnm env --use-on-cd)"' >> /root/.bashrc
        }

        # Add fnm to .zshrc for future Zsh sessions
        grep -q "fnm env" /root/.zshrc 2>/dev/null || {
            echo "" >> /root/.zshrc
            echo "# fnm - Fast Node Manager" >> /root/.zshrc
            echo 'export PATH="/root/.local/share/fnm:$PATH"' >> /root/.zshrc
            echo 'eval "$(fnm env --use-on-cd)"' >> /root/.zshrc
        }

        log_info "fnm installed and added to .bashrc and .zshrc"
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

    # Ensure fnm is in PATH and sourced
    export PATH="/root/.local/share/fnm:$PATH"

    # Source fnm environment if not already loaded
    if [[ -f "/root/.local/share/fnm/fnm" ]]; then
        eval "$("/root/.local/share/fnm/fnm" env --shell bash)" 2>/dev/null || true
    fi

    if ! command -v fnm &>/dev/null; then
        log_error "fnm not found - cannot install Node.js"
        return 1
    fi

    # Install Node.js 22
    fnm install "${NODE_VERSION}" 2>/dev/null || log_warn "Node.js ${NODE_VERSION} already installed"

    # Use Node.js 22 in current session
    fnm use "${NODE_VERSION}"

    # Set as default for all new sessions
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
    # Use timeout to prevent hanging if fnm use stalls
    timeout 10 fnm use "${NODE_VERSION}" &>/dev/null || {
        # If fnm use fails/stalls, try using eval with fnm env
        eval "$(fnm env --shell=bash)" 2>/dev/null || true
    }

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

    # Allow skipping via env
    if [[ "${HAPPY_INSTALL:-auto}" == "skip" ]]; then
        log_warn "Skipping Happy-Coder installation (HAPPY_INSTALL=skip)"
        return 0
    fi

    # Ensure Node.js is available
    export PATH="/root/.local/share/fnm:$PATH"
    # Use timeout to prevent hanging if fnm use stalls
    timeout 10 fnm use "${NODE_VERSION}" &>/dev/null || {
        # If fnm use fails/stalls, try using eval with fnm env
        eval "$(fnm env --shell=bash)" 2>/dev/null || true
    }

    # Check if already installed (binary or npm package), avoid invoking 'happy'
    GLOBAL_NPM_BIN="$(npm bin -g 2>/dev/null || true)"
    [[ -n "$GLOBAL_NPM_BIN" ]] && export PATH="$GLOBAL_NPM_BIN:$PATH"
    if command -v happy &>/dev/null || npm ls -g --depth=0 happy-coder >/dev/null 2>&1; then
        log_info "Happy-Coder already installed (skipping)"
        return 0
    fi

    # Check if package exists on npm
    log_info "Checking if happy-coder package exists..."
    if ! npm view happy-coder &>/dev/null; then
        log_warn "Package 'happy-coder' not found on npm registry"
        log_warn "Happy-Coder CLI installation skipped"
        log_warn "This is optional - Claude Code will work without it"
        return 0
    fi

    # Install Happy-Coder with timeout (non-interactive)
    log_info "Installing Happy-Coder (this may take a minute)..."
    if CI=true timeout 300 npm install -g happy-coder --silent --no-audit --no-fund --yes --prefer-offline 2>&1; then
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
    else
        log_error "Happy-Coder installation timed out or failed"
        log_warn "Continuing without Happy-Coder (optional)"
        return 0
    fi
}

#-------------------------------------------------------------------------------
# 6. OpenAI Codex CLI
#-------------------------------------------------------------------------------
install_openai_codex() {
    log_step "Installing OpenAI Codex CLI..."

    # Ensure Node.js is available
    export PATH="/root/.local/share/fnm:$PATH"
    # Use timeout to prevent hanging if fnm use stalls
    timeout 10 fnm use "${NODE_VERSION}" &>/dev/null || {
        # If fnm use fails/stalls, try using eval with fnm env
        eval "$(fnm env --shell=bash)" 2>/dev/null || true
    }

    # Check if already installed
    if command -v codex &>/dev/null; then
        local codex_version
        codex_version="$(codex --version 2>/dev/null || echo 'unknown')"
        log_info "OpenAI Codex already installed: ${codex_version}"
        return 0
    fi

    # Check if package exists on npm
    log_info "Checking if @openai/codex package exists..."
    if ! npm view @openai/codex &>/dev/null; then
        log_warn "Package '@openai/codex' not found on npm registry"
        log_warn "OpenAI Codex CLI installation skipped"
        log_warn "This is optional - Claude Code will work without it"
        return 0
    fi

    # Install OpenAI Codex with timeout (non-interactive)
    log_info "Installing OpenAI Codex (this may take a minute)..."
    if CI=true timeout 300 npm install -g @openai/codex --silent --no-audit --no-fund --yes --prefer-offline 2>&1; then
        # Verify installation
        if command -v codex &>/dev/null; then
            log_info "OpenAI Codex CLI installed: $(codex --version)"
        else
            log_error "OpenAI Codex CLI installation failed"
            return 1
        fi
    else
        log_error "OpenAI Codex CLI installation timed out or failed"
        log_warn "Continuing without OpenAI Codex (optional)"
        return 0
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

    # Create docker-compose file for GoClaw in project root
    local compose_file="${PROJECT_ROOT}/docker-compose.goclaw.yml"

    if [[ ! -f "$compose_file" ]]; then
        cat > "$compose_file" << 'EOF'
version: '3.8'
services:
  postgres:
    image: postgres:16-alpine
    container_name: goclaw-postgres
    restart: unless-stopped
    environment:
      - POSTGRES_DB=goclaw
      - POSTGRES_USER=goclaw
      - POSTGRES_PASSWORD=goclaw_password
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U goclaw"]
      interval: 10s
      timeout: 5s
      retries: 5

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
      - GOCLAW_POSTGRES_DSN=postgres://goclaw:goclaw_password@postgres:5432/goclaw?sslmode=disable
    depends_on:
      postgres:
        condition: service_healthy
    env_file:
      - .env

volumes:
  postgres_data:
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

    # Install fnm for the regular user if not already installed
    if [[ ! -d "${user_home}/.local/share/fnm" ]]; then
        log_info "Installing fnm for user ${USERNAME}..."
        su - "$USERNAME" -c 'curl -fsSL https://fnm.vercel.app/install | bash' || true
    fi

    # Add fnm to PATH in user's shell configs (both .bashrc and .zshrc)
    for shell_config in "$zshrc" "$bashrc"; do
        if [[ -f "$shell_config" ]]; then
            grep -q "fnm env" "$shell_config" 2>/dev/null || {
                echo "" >> "$shell_config"
                echo "# fnm - Fast Node Manager" >> "$shell_config"
                echo "export PATH=\"${user_home}/.local/share/fnm:\$PATH\"" >> "$shell_config"
                echo 'eval "$(fnm env --use-on-cd)"' >> "$shell_config"
            }
        fi
    done

    log_info "User environment configured for ${USERNAME}"
}

#-------------------------------------------------------------------------------
# 10. Pipeline Directory Structure
#-------------------------------------------------------------------------------
create_pipeline_structure() {
    log_step "Creating pipeline directory structure..."

    local goclaw_dir="${PROJECT_ROOT}/.goclaw"
    local agent_context_dir="${PROJECT_ROOT}/.agent-context"
    local scripts_dir="${PROJECT_ROOT}/scripts"

    # Create .goclaw directory structure
    mkdir -p "${goclaw_dir}/agents"
    mkdir -p "${goclaw_dir}/worktrees"

    # Create .agent-context directory
    mkdir -p "${agent_context_dir}"
    touch "${agent_context_dir}/.gitkeep"

    # Create scripts directory
    mkdir -p "${scripts_dir}"

    log_info "Pipeline directory structure created"
}

#-------------------------------------------------------------------------------
# 11. Agent Configuration (Dynamic JSON-based)
#-------------------------------------------------------------------------------
create_agent_definitions() {
    log_step "Creating dynamic agent configuration..."

    local goclaw_dir="${PROJECT_ROOT}/.goclaw"

    # Create agents-config.json with all agents configured for MiniMax Token Plan
    cat > "${goclaw_dir}/agents-config.json" << 'EOF'
{
  "version": "1.0",
  "default_provider": "minimax-token",
  "agents": {
    "po": {
      "name": "Product Owner",
      "provider": "minimax-token",
      "model": "MiniMax-M2.7",
      "temperature": 0.7,
      "max_tokens": 4000,
      "fallback": null,
      "waves": ["1", "2", "3"]
    },
    "techlead": {
      "name": "Technical Lead",
      "provider": "minimax-token",
      "model": "MiniMax-M2.7",
      "temperature": 0.3,
      "max_tokens": 8000,
      "fallback": null,
      "waves": ["1", "2", "3"]
    },
    "orchestrator": {
      "name": "Orchestrator",
      "provider": "minimax-token",
      "model": "MiniMax-M2.7",
      "temperature": 0.5,
      "max_tokens": 6000,
      "fallback": null,
      "waves": ["1", "2", "3"]
    },
    "be": {
      "name": "Backend",
      "provider": "minimax-token",
      "model": "MiniMax-M2.7",
      "temperature": 0.2,
      "max_tokens": 8000,
      "fallback": null,
      "waves": ["1", "2", "3"]
    },
    "fe": {
      "name": "Frontend",
      "provider": "minimax-token",
      "model": "MiniMax-M2.7",
      "temperature": 0.3,
      "max_tokens": 6000,
      "fallback": null,
      "waves": ["1", "2", "3"]
    },
    "db": {
      "name": "Database",
      "provider": "minimax-token",
      "model": "MiniMax-M2.7",
      "temperature": 0.2,
      "max_tokens": 6000,
      "fallback": null,
      "waves": ["1", "2", "3"]
    },
    "qa": {
      "name": "QA",
      "provider": "minimax-token",
      "model": "MiniMax-M2.5",
      "temperature": 0.4,
      "max_tokens": 8000,
      "fallback": null,
      "waves": ["1", "3"]
    },
    "devops": {
      "name": "DevOps",
      "provider": "minimax-token",
      "model": "MiniMax-M2.5",
      "temperature": 0.3,
      "max_tokens": 6000,
      "fallback": null,
      "waves": ["1", "2", "3"]
    },
    "review": {
      "name": "Review",
      "provider": "minimax-token",
      "model": "MiniMax-M2.5",
      "temperature": 0.2,
      "max_tokens": 4000,
      "fallback": null,
      "waves": ["1", "2", "3"]
    }
  }
}
EOF

    # Create providers-config.json with MiniMax Token Plan, OpenAI, and Anthropic
    cat > "${goclaw_dir}/providers-config.json" << 'EOF'
{
  "version": "1.0",
  "providers": {
    "minimax-token": {
      "name": "MiniMax Token Plan",
      "api_key_env": "MINIMAX_API_KEY",
      "base_url": "https://api.minimax.io/anthropic",
      "auth_header": "x-api-key",
      "auth_type": "anthropic-compatible",
      "models": {
        "MiniMax-M2.7": {
          "name": "MiniMax-M2.7",
          "max_tokens": 128000,
          "input_cost_per_1k": 0.00015,
          "output_cost_per_1k": 0.0006
        },
        "MiniMax-M2.5": {
          "name": "MiniMax-M2.5",
          "max_tokens": 128000,
          "input_cost_per_1k": 0.00012,
          "output_cost_per_1k": 0.00048
        }
      },
      "rate_limit": {
        "requests_per_minute": 20,
        "tokens_per_minute": 30000
      },
      "enabled": true
    },
    "openai": {
      "name": "OpenAI",
      "api_key_env": "OPENAI_API_KEY",
      "base_url": "https://api.openai.com/v1",
      "models": {
        "gpt-4o": {
          "name": "gpt-4o",
          "max_tokens": 128000,
          "input_cost_per_1k": 0.0025,
          "output_cost_per_1k": 0.01
        },
        "gpt-4o-mini": {
          "name": "gpt-4o-mini",
          "max_tokens": 128000,
          "input_cost_per_1k": 0.00015,
          "output_cost_per_1k": 0.0006
        }
      },
      "rate_limit": {
        "requests_per_minute": 500,
        "tokens_per_minute": 150000
      },
      "enabled": false
    },
    "gpt-codex-plus": {
      "name": "GPT Codex Plus",
      "api_key_env": "OPENAI_API_KEY",
      "base_url": "https://api.minimax.io/openai",
      "auth_header": "authorization",
      "auth_type": "bearer-token",
      "models": {
        "gpt-codex-plus": {
          "name": "gpt-codex-plus",
          "max_tokens": 128000,
          "input_cost_per_1k": 0.00015,
          "output_cost_per_1k": 0.0006
        }
      },
      "rate_limit": {
        "requests_per_minute": 100,
        "tokens_per_minute": 100000
      },
      "enabled": false
    },
    "anthropic": {
      "name": "Anthropic",
      "api_key_env": "ANTHROPIC_API_KEY",
      "base_url": "https://api.anthropic.com/v1",
      "models": {
        "claude-3-5-sonnet-20241022": {
          "name": "claude-3-5-sonnet-20241022",
          "max_tokens": 200000,
          "input_cost_per_1k": 0.003,
          "output_cost_per_1k": 0.015
        }
      },
      "rate_limit": {
        "requests_per_minute": 50,
        "tokens_per_minute": 100000
      },
      "enabled": false
    }
  }
}
EOF

    log_info "Dynamic agent configuration created"
    log_info "  - agents-config.json: Per-agent LLM configuration"
    log_info "  - providers-config.json: Provider registry with pricing"
    log_info "  - Default provider: MiniMax (all agents)"
    log_info "  - To add OpenAI/Anthropic: Add API keys to .env and set enabled:true in providers-config.json"
}

#-------------------------------------------------------------------------------
# 12. Pipeline State Files
#-------------------------------------------------------------------------------
create_pipeline_state() {
    log_step "Creating pipeline state files..."

    local goclaw_dir="${PROJECT_ROOT}/.goclaw"

    # Create pipeline-state.json
    cat > "${goclaw_dir}/pipeline-state.json" << 'EOF'
{
  "version": "1.0",
  "status": "idle",
  "current_sprint": null,
  "agents": {
    "po": "idle",
    "techlead": "idle",
    "orchestrator": "idle",
    "be": "idle",
    "fe": "idle",
    "db": "idle",
    "qa": "idle",
    "devops": "idle",
    "review": "idle"
  },
  "circuit_breaker": {
    "trips": 0,
    "max_retries": 3
  }
}
EOF

    # Create agent-responsibilities.json
    cat > "${goclaw_dir}/agent-responsibilities.json" << 'EOF'
{
  "version": "1.0",
  "agents": {
    "po": {
      "name": "Product Owner",
      "waves": ["1", "2", "3"],
      "responsibilities": [
        "Gather requirements",
        "Write PRD",
        "Create user stories",
        "Prioritize backlog",
        "Accept completed work"
      ]
    },
    "techlead": {
      "name": "Technical Lead",
      "waves": ["1", "2", "3"],
      "responsibilities": [
        "Review technical feasibility",
        "Architecture decisions",
        "Coordinate agents",
        "Code review"
      ]
    },
    "orchestrator": {
      "name": "Orchestrator",
      "waves": ["1", "2", "3"],
      "responsibilities": [
        "Coordinate all agents",
        "Manage dependencies",
        "Monitor circuit breaker",
        "Handle failures"
      ]
    },
    "be": {
      "name": "Backend",
      "waves": ["1", "2", "3"],
      "responsibilities": [
        "Implement business logic",
        "Consume schema (read-only)",
        "Create API endpoints",
        "Write tests"
      ]
    },
    "fe": {
      "name": "Frontend",
      "waves": ["1", "2", "3"],
      "responsibilities": [
        "Implement UI",
        "Use codegen for types",
        "Consume API",
        "Write frontend tests"
      ]
    },
    "db": {
      "name": "Database",
      "waves": ["1", "2", "3"],
      "responsibilities": [
        "Own schema modifications",
        "Write migrations",
        "Optimize queries",
        "Document schema"
      ]
    },
    "qa": {
      "name": "QA",
      "waves": ["1", "3"],
      "responsibilities": [
        "Wave 1: Write test specs",
        "Wave 3: Execute tests",
        "File bug reports",
        "Measure coverage"
      ]
    },
    "devops": {
      "name": "DevOps",
      "waves": ["1", "2", "3"],
      "responsibilities": [
        "Set up CI/CD",
        "Configure infrastructure",
        "Manage deployments",
        "Set up monitoring"
      ]
    },
    "review": {
      "name": "Review",
      "waves": ["1", "2", "3"],
      "responsibilities": [
        "Review code changes",
        "Check security",
        "Ensure best practices",
        "Approve/reject PRs"
      ]
    }
  },
  "rules": {
    "database_ownership": "DB agent owns all schema modifications",
    "backend_db_access": "BE consumes schema read-only via codegen",
    "frontend_types": "FE uses codegen for types, no direct schema access",
    "qa_wave2_idle": "QA agent is idle during Wave 2",
    "review_continuous": "Review agent reviews all changes continuously"
  }
}
EOF

    log_info "Pipeline state files created"
}

#-------------------------------------------------------------------------------
# 13. Environment File Template
#-------------------------------------------------------------------------------
create_env_template() {
    log_step "Creating environment file template..."

    local env_example="${PROJECT_ROOT}/.env.example"

    cat > "$env_example" << 'EOF'
# === LLM PROVIDERS ===
MINIMAX_API_KEY=           # Required: MiniMax Token Plan key (default provider)
OPENAI_API_KEY=            # Optional: OpenAI API key (for OpenAI models)
ANTHROPIC_API_KEY=         # Optional: Anthropic API key (for Claude models)

# === CONFIGURATION ===
DEFAULT_PROVIDER=minimax-token   # Default LLM provider (minimax-token, openai, anthropic)
CONFIG_HOT_RELOAD=true     # Reload config without restarting GoClaw

# === COMMUNICATION ===
TELEGRAM_BOT_TOKEN=       # BotFather token
TELEGRAM_CHAT_ID=         # Your personal chat ID

# === GITHUB ===
GITHUB_TOKEN=             # Fine-grained PAT: repo + issues + PRs + discussions
GITHUB_REPO=              # e.g. username/repo-name

# === INFRASTRUCTURE ===
REDIS_URL=redis://localhost:6379
GOCLAW_PORT=18789
GOCLAW_POSTGRES_DSN=postgres://goclaw:goclaw_password@localhost:5432/goclaw?sslmode=disable

# === PIPELINE CONFIG ===
MAX_SPRINT_HOURS=4
MAX_AGENT_RETRIES=3
AUTO_MERGE=true
STAGING_URL=
EOF

    # Add .env to .gitignore
    local gitignore="${PROJECT_ROOT}/.gitignore"
    if [[ -f "$gitignore" ]]; then
        grep -q "^\.env$" "$gitignore" || echo ".env" >> "$gitignore"
    fi

    log_info "Environment template created: .env.example"
}

#-------------------------------------------------------------------------------
# 14. Helper Scripts
#-------------------------------------------------------------------------------
create_helper_scripts() {
    log_step "Creating helper scripts..."

    local scripts_dir="${PROJECT_ROOT}/scripts"

    # start-pipeline.sh
    cat > "${scripts_dir}/start-pipeline.sh" << 'EOF'
#!/bin/bash
# Start Pipeline - Start GoClaw and Redis services

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.goclaw.yml"

# Remove obsolete 'version' warning if present (compose v2 ignores it)
sed -i.bak '/^version:/d' "$COMPOSE_FILE" 2>/dev/null || true

echo "Starting pipeline services..."

# Start Redis if available
if command -v systemctl &>/dev/null; then
  if ! systemctl is-active --quiet redis-server; then
      echo "Starting Redis..."
      sudo systemctl start redis-server || true
  else
      echo "Redis already running"
  fi
fi

# Start Postgres + GoClaw
set +e
docker compose -f "$COMPOSE_FILE" up -d
compose_up_exit=$?
set -e

if [ $compose_up_exit -ne 0 ]; then
  echo "docker compose up failed (code $compose_up_exit). Checking container status..."
  docker ps --all --filter 'name=goclaw-pipeline'
  echo "Tailing last 100 lines of goclaw logs..."
  docker logs --tail=100 goclaw-pipeline 2>&1 || true
  exit $compose_up_exit
fi

# Auto-migrate database inside container
echo "Running GoClaw DB migrations..."
if ! docker compose -f "$COMPOSE_FILE" exec -T goclaw goclaw upgrade --status >/dev/null 2>&1; then
  echo "Schema dirty or mismatched. Forcing baseline to 0 and re-upgrading..."
  docker compose -f "$COMPOSE_FILE" exec -T goclaw goclaw migrate force 0 || true
fi

docker compose -f "$COMPOSE_FILE" exec -T goclaw goclaw upgrade || {
  echo "Upgrade failed. Showing container logs:"
  docker logs --tail=200 goclaw-pipeline || true
  exit 1
}

# Show status
echo ""
echo "=========================================="
echo "Pipeline Services Status"
echo "=========================================="
if command -v systemctl &>/dev/null; then
  echo "Redis: $(systemctl is-active redis-server)"
fi
echo "GoClaw: $(docker ps --filter 'name=goclaw-pipeline' --format '{{.Status}}')"
echo ""
echo "GoClaw Dashboard: http://localhost:18789"
echo "=========================================="
EOF

    # stop-pipeline.sh
    cat > "${scripts_dir}/stop-pipeline.sh" << 'EOF'
#!/bin/bash
# Stop Pipeline - Stop GoClaw and optionally Redis

set -euo pipefail

echo "Stopping pipeline services..."

# Stop GoClaw
echo "Stopping GoClaw..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
docker compose -f "${PROJECT_ROOT}/docker-compose.goclaw.yml" down

# Ask about Redis
read -p "Stop Redis too? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Stopping Redis..."
    sudo systemctl stop redis-server
else
    echo "Redis left running"
fi

# Clean up worktrees
read -p "Clean up git worktrees? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleaning up worktrees..."
    git worktree list | grep agent | awk '{print $1}' | xargs -r git worktree remove
    echo "Worktrees cleaned"
fi
EOF

    # status.sh
    cat > "${scripts_dir}/status.sh" << 'EOF'
#!/bin/bash
# Pipeline Status - Show all running agents and pipeline state

set -euo pipefail

echo "=========================================="
echo "Pipeline Status"
echo "=========================================="
echo ""

# Redis status
echo "Redis:"
if systemctl is-active --quiet redis-server; then
    echo "  Status: Running ✓"
else
    echo "  Status: Stopped ✗"
fi
echo ""

# GoClaw status
echo "GoClaw:"
if docker ps --filter 'name=goclaw-pipeline' --format '{{.Names}}' | grep -q goclaw-pipeline; then
    echo "  Status: Running ✓"
    echo "  Port: 18789"
    echo "  URL: http://localhost:18789"
else
    echo "  Status: Stopped ✗"
fi
echo ""

# Pipeline state
echo "Pipeline State:"
if [ -f .goclaw/pipeline-state.json ]; then
    jq '.' .goclaw/pipeline-state.json 2>/dev/null || cat .goclaw/pipeline-state.json
else
    echo "  No pipeline state found"
fi
echo ""

# Git worktrees
echo "Git Worktrees:"
git worktree list 2>/dev/null || echo "  No worktrees found"
echo ""

# GitHub issues (if gh is authenticated)
echo "GitHub Issues (if authenticated):"
if gh auth status &>/dev/null; then
    gh issue list --state open 2>/dev/null || echo "  No issues found"
else
    echo "  GitHub CLI not authenticated"
fi
echo ""
EOF

    # sprint.sh
    cat > "${scripts_dir}/sprint.sh" << 'EOF'
#!/bin/bash
# Sprint Trigger - Trigger a new sprint with PRD

set -euo pipefail

# Check for .env file
if [ ! -f .env ]; then
    echo "Error: .env file not found!"
    echo "Please create .env from .env.example and fill in your API keys."
    exit 1
fi

# Source .env
set -a
source .env
set +a

# Validate required vars
required_vars=("OPENAI_API_KEY" "TELEGRAM_BOT_TOKEN" "TELEGRAM_CHAT_ID")
missing_vars=()

for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
        missing_vars+=("$var")
    fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
    echo "Error: Missing required environment variables:"
    printf '  - %s\n' "${missing_vars[@]}"
    exit 1
fi

# Get PRD
if [ $# -eq 0 ]; then
    echo "Enter PRD (Ctrl+D when done):"
    prd=$(cat)
else
    prd="$*"
fi

if [ -z "$prd" ]; then
    echo "Error: PRD cannot be empty"
    exit 1
fi

# Trigger sprint
echo "Triggering sprint..."
echo "PRD: $prd"
echo ""

# POST to GoClaw API
curl -X POST http://localhost:${GOCLAW_PORT:-18789}/api/sprint \
  -H "Content-Type: application/json" \
  -d "{\"prd\": \"$prd\"}" \
  2>/dev/null || echo "Failed to trigger sprint - is GoClaw running?"

echo ""
echo "Sprint triggered! Check Telegram for notifications."
EOF

    # tmux-layout.sh
    cat > "${scripts_dir}/tmux-layout.sh" << 'EOF'
#!/bin/bash
# Tmux Layout - Launch pipeline monitoring tmux session

SESSION_NAME="pipeline"

# Check if session already exists
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "Session '$SESSION_NAME' already exists. Attaching..."
    tmux attach-session -t "$SESSION_NAME"
    exit 0
fi

echo "Creating tmux session: $SESSION_NAME"

# Create session and windows
tmux new-session -d -s "$SESSION_NAME" -n "monitor"

# Window 1: Monitor (2 panes)
tmux split-window -t "$SESSION_NAME:monitor" -h
tmux select-pane -t "$SESSION_NAME:monitor.0"
tmux send-keys -t "$SESSION_NAME:monitor.0" "watch -n 2 'cat .goclaw/pipeline-state.json | jq .'" C-m
tmux select-pane -t "$SESSION_NAME:monitor.1"
tmux send-keys -t "$SESSION_NAME:monitor.1" "docker logs -f goclaw-pipeline" C-m

# Window 2: Agents (4 panes)
tmux new-window -t "$SESSION_NAME" -n "agents"
tmux split-window -t "$SESSION_NAME:agents" -h
tmux split-window -t "$SESSION_NAME:agents" -v
tmux select-pane -t "$SESSION_NAME:agents.0"
tmux split-window -t "$SESSION_NAME:agents.0" -v
tmux select-pane -t "$SESSION_NAME:agents.3"
tmux split-window -t "$SESSION_NAME:agents.3" -v

# Label agent panes
tmux send-keys -t "$SESSION_NAME:agents.0" "# BE agent logs" C-m
tmux send-keys -t "$SESSION_NAME:agents.1" "# FE agent logs" C-m
tmux send-keys -t "$SESSION_NAME:agents.2" "# DB agent logs" C-m
tmux send-keys -t "$SESSION_NAME:agents.3" "# QA agent logs" C-m

# Window 3: Git
tmux new-window -t "$SESSION_NAME" -n "git"
tmux send-keys -t "$SESSION_NAME:git" "watch -n 5 'git worktree list && echo \"---\" && git branch -a | grep agent'" C-m

# Window 4: Shell
tmux new-window -t "$SESSION_NAME" -n "shell"
tmux send-keys -t "$SESSION_NAME:shell" "# Free shell for manual commands" C-m

# Select first window
tmux select-window -t "$SESSION_NAME:monitor"

echo "Session '$SESSION_NAME' created!"
echo "Windows: monitor, agents, git, shell"
echo "Attach with: tmux attach-session -t $SESSION_NAME"

# Attach to session
tmux attach-session -t "$SESSION_NAME"
EOF

    # Make all scripts executable
    chmod +x "${scripts_dir}"/*.sh

    log_info "Helper scripts created and made executable"
}

#-------------------------------------------------------------------------------
# 15. VS Code Dev Container
#-------------------------------------------------------------------------------
create_devcontainer() {
    log_step "Creating VS Code Dev Container configuration..."

    local devcontainer_dir="${PROJECT_ROOT}/.devcontainer"
    mkdir -p "$devcontainer_dir"

    # Create devcontainer.json
    cat > "${devcontainer_dir}/devcontainer.json" << 'EOF'
{
  "name": "GoClaw Pipeline Development",
  "dockerComposeFile": "docker-compose.yml",
  "service": "app",
  "workspaceFolder": "/workspace",

  // Features to add to the dev container
  "features": {
    "ghcr.io/devcontainers/features/node:1": {
      "version": "22",
      "nodeGypDependencies": true,
      "nvmInstallPath": "/usr/local/share/nvm"
    },
    "ghcr.io/devcontainers/features/docker-in-docker:2": {
      "version": "latest",
      "moby": true,
      "dockerDashComposeVersion": "v2.23.0"
    },
    "ghcr.io/devcontainers/features/common-utils:2": {
      "installZsh": true,
      "installOhMyZsh": true,
      "upgradePackages": true,
      "username": "vscode",
      "userUid": "automatic",
      "userGid": "automatic"
    },
    "ghcr.io/devcontainers/features/git:1": {
      "version": "latest",
      "ppa": true
    }
  },

  // Use 'forwardPorts' to make a list of ports inside the container available locally
  "forwardPorts": [18789, 6379],

  // Port attributes
  "portsAttributes": {
    "18789": {
      "label": "GoClaw API",
      "onAutoForward": "notify"
    },
    "6379": {
      "label": "Redis",
      "onAutoForward": "silent"
    }
  },

  // Use 'postCreateCommand' to run commands after the container is created
  "postCreateCommand": "bash .devcontainer/post-create.sh",

  // Configure tool-specific properties
  "customizations": {
    "vscode": {
      "extensions": [
        "ms-azuretools.vscode-docker",
        "dbaeumer.vscode-eslint",
        "esbenp.prettier-vscode",
        "ms-vscode.vscode-typescript-next",
        "GitHub.copilot",
        "GitHub.vscode-pull-request-github",
        "ms-vscode.live-server",
        "humao.rest-client",
        "tomoki1207.pdf",
        "zh9528.format-code-in-markdown",
        "eamodio.gitlens",
        "streetsidesoftware.code-spell-checker",
        "VisualStudioExptTeam.vscodeintellicode"
      ],
      "settings": {
        "terminal.integrated.profiles.linux": {
          "zsh": {
            "path": "/bin/zsh"
          }
        },
        "terminal.integrated.defaultProfile.linux": "zsh",
        "editor.formatOnSave": true,
        "editor.defaultFormatter": "esbenp.prettier-vscode",
        "editor.codeActionsOnSave": {
          "source.fixAll.eslint": "explicit"
        }
      }
    }
  },

  // Uncomment to connect as root instead
  "remoteUser": "vscode",

  // Mounts
  "mounts": [
    "source=${localWorkspaceFolder}/.goclaw,target=/workspace/.goclaw,type=bind,consistency=cached",
    "source=${localWorkspaceFolder}/.agent-context,target=/workspace/.agent-context,type=bind,consistency=cached",
    "source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind"
  ],

  // Run arguments
  "runArgs": [
    "--cap-add=SYS_PTRACE",
    "--security-opt", "seccomp=unconfined"
  ],

  // Lifecycle scripts
  "onCreateCommand": "echo '🚀 Creating GoClaw development container...'",
  "updateContentCommand": "echo '📦 Updating dependencies...'",
  "postAttachCommand": "echo '✅ Container ready! Run ./scripts/start-pipeline.sh to start services'"
}
EOF

    # Create Dockerfile for the app service
    cat > "${devcontainer_dir}/Dockerfile" << 'EOF'
FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Install basic tools
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get install -y \
    curl \
    wget \
    git \
    tmux \
    jq \
    redis-tools \
    postgresql-client \
    build-essential \
    unzip \
    vim \
    zsh \
    && rm -rf /var/lib/apt/lists/*

# Install fnm (Fast Node Manager)
RUN curl -fsSL https://fnm.vercel.app/install | bash
ENV PATH="/root/.local/share/fnm:${PATH}"
RUN fnm install 22 && fnm use 22 && fnm default 22

# Install global npm packages
RUN npm install -g \
    @anthropic-ai/claude-code \
    happy-coder \
    @openai/codex

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh

# Set up workspace directory
WORKDIR /workspace

# Set default shell to zsh
SHELL ["/bin/zsh", "-c"]
CMD ["/bin/zsh"]
EOF

    # Create docker-compose.yml for dev container
    cat > "${devcontainer_dir}/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    volumes:
      - ../..:/workspaces/goclaw-pipeline:cached
    command: sleep infinity
    network_mode: service:goclaw

  goclaw:
    image: ghcr.io/nextlevelbuilder/goclaw:full
    container_name: goclaw-pipeline
    restart: unless-stopped
    ports:
      - "18789:18789"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - GOCLAW_OPENAI_API_KEY=${OPENAI_API_KEY:-}
      - GOCLAW_MINIMAX_API_KEY=${MINIMAX_API_KEY:-}
      - GOCLAW_TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN:-}
      - GOCLAW_TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID:-}
    env_file:
      - ../.env

  redis:
    image: redis:7-alpine
    container_name: goclaw-redis
    restart: unless-stopped
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data

volumes:
  redis-data:
EOF

    # Create post-create script
    cat > "${devcontainer_dir}/post-create.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

echo "🎯 Running post-create setup..."

# Ensure fnm is in PATH
export PATH="${HOME}/.local/share/fnm:${PATH}"

# Verify installations
echo "✅ Node version: $(node --version)"
echo "✅ npm version: $(npm --version)"
echo "✅ Claude Code: $(claude --version || echo 'not installed')"
echo "✅ Happy-Coder: $(happy --version || echo 'not installed')"
echo "✅ Codex: $(codex --version || echo 'not installed')"
echo "✅ Docker: $(docker --version)"
echo "✅ GitHub CLI: $(gh --version | head -n1 || echo 'not installed')"

# Copy .env.example if .env doesn't exist
if [ ! -f .env ] && [ -f .env.example ]; then
    echo ""
    echo "⚠️  Creating .env from .env.example - please add your API keys!"
    cp .env.example .env
fi

echo ""
echo "✅ Dev container setup complete!"
echo ""
echo "Next steps:"
echo "  1. Edit .env with your API keys"
echo "  2. Run: ./scripts/start-pipeline.sh"
echo "  3. Open a new terminal and run: ./scripts/tmux-layout.sh"
echo ""
EOF

    chmod +x "${devcontainer_dir}/post-create.sh"

    # Create .devcontainer gitignore
    cat > "${devcontainer_dir}/.gitignore" << 'EOF'
# Ignore local environment overrides
.env.local

# Ignore any local workspace config
*.code-workspace
EOF

    log_info "VS Code Dev Container configuration created"
    log_info "Press F1 in VS Code and select 'Dev Containers: Reopen in Container'"
}

#-------------------------------------------------------------------------------
# 16. Start Services
#-------------------------------------------------------------------------------
start_services() {
    log_step "Starting services..."

    # Start Redis
    systemctl start redis-server || true

    # Note: GoClaw is not started automatically because it needs API keys
    log_info "Services started (Redis)"
    log_warn "GoClaw not started - configure .env first, then run:"
    log_warn "  ./scripts/start-pipeline.sh"
}

#-------------------------------------------------------------------------------
# 16. Final Verification
#-------------------------------------------------------------------------------
verify_installation() {
    echo ""
    log_info "=========================================="
    log_info "Verifying Installation"
    log_info "=========================================="
    echo ""

    local all_good=true

    # Check tmux
    if command -v tmux &>/dev/null; then
        check_pass "tmux ($(tmux -V | awk '{print $2}'))"
    else
        check_fail "tmux not installed"
        all_good=false
    fi

    # Check node
    if command -v node &>/dev/null; then
        local node_ver="$(node --version)"
        if [[ "$node_ver" =~ v2[2-9] ]]; then
            check_pass "node ($node_ver)"
        else
            check_warn "node ($node_ver) - should be v22+"
        fi
    else
        check_fail "node not installed"
        all_good=false
    fi

    # Check claude
    if command -v claude &>/dev/null; then
        check_pass "claude (installed)"
    else
        check_fail "claude not installed"
        all_good=false
    fi

    # Check happy
    if command -v happy &>/dev/null; then
        check_pass "happy-coder (installed)"
    else
        check_fail "happy-coder not installed"
        all_good=false
    fi

    # Check codex
    if command -v codex &>/dev/null; then
        check_pass "codex (installed)"
    else
        check_fail "codex not installed"
        all_good=false
    fi

    # Check docker
    if command -v docker &>/dev/null && docker info &>/dev/null; then
        check_pass "docker (running)"
    else
        check_fail "docker not running"
        all_good=false
    fi

    # Check goclaw image
    if docker images | grep -q "nextlevelbuilder/goclaw"; then
        check_pass "goclaw (image pulled)"
    else
        check_fail "goclaw image not found"
        all_good=false
    fi

    # Check gh
    if command -v gh &>/dev/null; then
        if gh auth status &>/dev/null; then
            check_pass "gh (authenticated)"
        else
            check_warn "gh (needs authentication)"
        fi
    else
        check_fail "gh not installed"
        all_good=false
    fi

    # Check redis
    if systemctl is-active --quiet redis-server; then
        check_pass "redis (running)"
    else
        check_fail "redis not running"
        all_good=false
    fi

    # Check .env.example
    if [ -f .env.example ]; then
        check_pass ".env.example exists"
    else
        check_fail ".env.example not found"
        all_good=false
    fi

    # Check scripts
    if [ -d scripts ] && [ -x scripts/start-pipeline.sh ]; then
        check_pass "scripts (executable)"
    else
        check_fail "scripts not executable"
        all_good=false
    fi

    # Check .gitignore
    if [ -f .gitignore ] && grep -q "^\.env$" .gitignore; then
        check_pass ".gitignore has .env"
    else
        check_warn ".gitignore missing .env"
    fi

    # Check VS Code Dev Container
    if [ -d .devcontainer ] && [ -f .devcontainer/devcontainer.json ]; then
        check_pass "VS Code Dev Container (configured)"
    else
        check_warn "VS Code Dev Container (not found)"
    fi

    echo ""
    if [ "$all_good" = true ]; then
        log_info "✅ All checks passed!"
    else
        log_warn "⚠️  Some checks failed - review above"
    fi
}

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------
print_summary() {
    echo ""
    log_info "=========================================="
    log_info "PIPELINE SETUP COMPLETE"
    log_info "=========================================="
    echo ""
    echo "NEXT STEPS:"
    echo ""
    echo "1. Configure environment:"
    echo "   cp .env.example .env"
    echo "   # Edit .env with your API keys"
    echo ""
    echo "2a. Start the pipeline (native):"
    echo "   ./scripts/start-pipeline.sh"
    echo ""
    echo "2b. OR use VS Code Dev Container:"
    echo "   Press F1 → 'Dev Containers: Reopen in Container'"
    echo ""
    echo "3. Launch monitoring dashboard:"
    echo "   ./scripts/tmux-layout.sh"
    echo ""
    echo "4. Trigger a sprint:"
    echo "   ./scripts/sprint.sh \"Your PRD here\""
    echo ""
    echo "=========================================="
    echo ""
    log_info "Quick command to launch tmux layout:"
    echo ""
    echo "  ./scripts/tmux-layout.sh"
    echo ""
    log_info "VS Code Dev Container ready:"
    echo ""
    echo "  Press F1 → 'Dev Containers: Reopen in Container'"
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
    create_pipeline_structure
    create_agent_definitions
    create_pipeline_state
    create_env_template
    create_helper_scripts
    create_devcontainer
    start_services
    verify_installation
    print_summary
}

main "$@"
