#!/bin/bash
#===============================================================================
# Provider Switcher for GoClaw Dynamic Agent Configuration
# Purpose: Change LLM provider for agents at runtime
#===============================================================================

set -euo pipefail

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOAD_CONFIG="$SCRIPT_DIR/load-config.sh"

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
log_success() { printf "${GREEN}[✓]${NC} %s\n" "$1"; }

#-------------------------------------------------------------------------------
# Usage
#-------------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: $0 <agent> <provider> [fallback]

Change LLM provider for a specific agent at runtime.

Arguments:
  agent      Agent ID (e.g., po, techlead, be, fe, db, qa, devops, review, orchestrator)
  provider   New provider ID (e.g., minimax, openai, anthropic)
  fallback   Optional fallback provider (e.g., --fallback openai)

Options:
  -h, --help     Show this help message
  --no-reload    Don't trigger GoClaw reload after switching

Environment Variables:
  AUTO_RELOAD    Set to 'false' to skip automatic reload (default: true)

Examples:
  # Switch techlead to OpenAI
  $0 techlead openai

  # Switch po to MiniMax with OpenAI fallback
  $0 po minimax --fallback openai

  # Switch be to Anthropic without triggering reload
  $0 be anthropic --no-reload

Notes:
  - Provider must be enabled in providers-config.json
  - API key must be set in .env file
  - Changes take effect immediately (with hot reload) or after GoClaw restart

EOF
}

#-------------------------------------------------------------------------------
# Pre-flight Checks
#-------------------------------------------------------------------------------
pre_flight_checks() {
    # Check if load-config.sh exists
    if [[ ! -f "$LOAD_CONFIG" ]]; then
        log_error "Configuration loader not found: $LOAD_CONFIG"
        return 1
    fi

    # Check if it's executable
    if [[ ! -x "$LOAD_CONFIG" ]]; then
        log_error "Configuration loader is not executable: $LOAD_CONFIG"
        log_info "Run: chmod +x $LOAD_CONFIG"
        return 1
    fi

    return 0
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------
main() {
    local agent=""
    local provider=""
    local fallback=""
    local no_reload=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help|help)
                usage
                exit 0
                ;;
            --no-reload)
                no_reload=true
                shift
                ;;
            --fallback)
                fallback="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                echo ""
                usage
                exit 1
                ;;
            *)
                if [[ -z "$agent" ]]; then
                    agent="$1"
                elif [[ -z "$provider" ]]; then
                    provider="$1"
                else
                    log_error "Too many arguments"
                    echo ""
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$agent" ]] || [[ -z "$provider" ]]; then
        log_error "Missing required arguments"
        echo ""
        usage
        exit 1
    fi

    # Run pre-flight checks
    if ! pre_flight_checks; then
        exit 1
    fi

    # Show current configuration
    log_info "Current configuration for '$agent':"
    if ! current=$("$LOAD_CONFIG" get-provider "$agent" 2>&1); then
        log_error "Failed to get current provider for '$agent'"
        log_error "$current"
        exit 1
    fi
    log_info "  Provider: $current"
    echo ""

    # Build command arguments
    local cmd_args=("$agent" "$provider")
    if [[ -n "$fallback" ]]; then
        cmd_args+=(--fallback "$fallback")
    fi

    # Set AUTO_RELOAD environment variable
    if [[ "$no_reload" == true ]]; then
        export AUTO_RELOAD=false
    else
        export AUTO_RELOAD=true
    fi

    # Execute switch-provider via load-config.sh
    log_info "Switching '$agent' to '$provider'..."
    echo ""

    if ! "$LOAD_CONFIG" switch-provider "${cmd_args[@]}"; then
        log_error "Failed to switch provider"
        exit 1
    fi

    echo ""
    log_success "Provider switch completed successfully"

    # Show new configuration
    log_info "New configuration for '$agent':"
    if ! new_config=$("$LOAD_CONFIG" get-provider "$agent" 2>&1); then
        log_warn "Failed to verify new configuration"
    else
        log_info "  Provider: $new_config"
    fi

    # Remind about validation
    echo ""
    log_info "To validate all configurations, run:"
    echo "  $LOAD_CONFIG validate"
}

main "$@"
