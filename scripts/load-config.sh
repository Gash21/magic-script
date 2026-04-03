#!/bin/bash
#===============================================================================
# Configuration Loader for GoClaw Dynamic Agent Configuration
# Purpose: Validate, load, and manage agent configuration
#===============================================================================

set -euo pipefail

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly AGENTS_CONFIG="$PROJECT_ROOT/.goclaw/agents-config.json"
readonly PROVIDERS_CONFIG="$PROJECT_ROOT/.goclaw/providers-config.json"

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
log_fail() { printf "${RED}[✗]${NC} %s\n" "$1"; }

#-------------------------------------------------------------------------------
# Usage
#-------------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: $0 <command> [options]

Commands:
  validate           Validate configuration files
  load               Load and display configuration
  get-provider <agent>   Get provider for a specific agent
  export-env          Export environment variables for GoClaw
  switch-provider <agent> <provider> [fallback]
                      Switch provider for an agent
  reload              Trigger GoClaw configuration reload
  list-providers      List all available providers
  list-agents         List all agents and their providers

Options:
  -h, --help          Show this help message

Examples:
  $0 validate
  $0 get-provider po
  $0 switch-provider techlead openai
  $0 switch-provider po minimax --fallback openai
  $0 export-env > /tmp/goclaw-env.sh
EOF
}

#-------------------------------------------------------------------------------
# Validation Functions
#-------------------------------------------------------------------------------
validate_json() {
    local file="$1"
    local name="$2"

    if [[ ! -f "$file" ]]; then
        log_error "Configuration file not found: $file"
        return 1
    fi

    if ! jq empty "$file" &>/dev/null; then
        log_error "$name is not valid JSON"
        return 1
    fi

    log_success "$name is valid JSON"
    return 0
}

validate_agents_config() {
    log_info "Validating agents configuration..."

    # Check file exists
    if [[ ! -f "$AGENTS_CONFIG" ]]; then
        log_error "agents-config.json not found"
        return 1
    fi

    # Validate JSON
    if ! validate_json "$AGENTS_CONFIG" "agents-config.json"; then
        return 1
    fi

    # Check required fields
    local version
    version=$(jq -r '.version' "$AGENTS_CONFIG")
    if [[ "$version" != "1.0" ]]; then
        log_error "Unsupported version: $version"
        return 1
    fi

    # Check agents
    local agent_count
    agent_count=$(jq '.agents | length' "$AGENTS_CONFIG")
    if [[ "$agent_count" -eq 0 ]]; then
        log_error "No agents defined"
        return 1
    fi

    log_success "Found $agent_count agents"

    # Validate each agent
    jq -r '.agents | to_entries[] | .key' "$AGENTS_CONFIG" | while read -r agent_id; do
        local provider
        provider=$(jq -r ".agents.$agent_id.provider" "$AGENTS_CONFIG")
        local model
        model=$(jq -r ".agents.$agent_id.model" "$AGENTS_CONFIG")

        # Check if provider exists in providers-config.json
        if ! jq -e ".providers[\"$provider\"]" "$PROVIDERS_CONFIG" &>/dev/null; then
            log_warn "Agent '$agent_id' uses unknown provider: $provider"
        fi

        log_success "  ✓ $agent_id: $provider/$model"
    done

    return 0
}

validate_providers_config() {
    log_info "Validating providers configuration..."

    # Check file exists
    if [[ ! -f "$PROVIDERS_CONFIG" ]]; then
        log_error "providers-config.json not found"
        return 1
    fi

    # Validate JSON
    if ! validate_json "$PROVIDERS_CONFIG" "providers-config.json"; then
        return 1
    fi

    # Check providers
    local provider_count
    provider_count=$(jq '.providers | length' "$PROVIDERS_CONFIG")
    if [[ "$provider_count" -eq 0 ]]; then
        log_error "No providers defined"
        return 1
    fi

    log_success "Found $provider_count providers"

    # Validate each provider
    jq -r '.providers | to_entries[] | .key' "$PROVIDERS_CONFIG" | while read -r provider_id; do
        local name
        name=$(jq -r ".providers[\"$provider_id\"].name" "$PROVIDERS_CONFIG")
        local enabled
        enabled=$(jq -r ".providers[\"$provider_id\"].enabled" "$PROVIDERS_CONFIG")

        if [[ "$enabled" == "true" ]]; then
            log_success "  ✓ $name ($provider_id) - ENABLED"
        else
            log_warn "  ⚠ $name ($provider_id) - DISABLED"
        fi
    done

    return 0
}

validate() {
    log_info "=========================================="
    log_info "Validating Configuration"
    log_info "=========================================="
    echo ""

    local all_valid=true

    validate_agents_config || all_valid=false
    echo ""
    validate_providers_config || all_valid=false

    echo ""
    if [[ "$all_valid" == "true" ]]; then
        log_success "✓ All validation checks passed"
        return 0
    else
        log_fail "✗ Validation failed"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Configuration Loading
#-------------------------------------------------------------------------------
load_config() {
    log_info "Loading configuration..."

    if [[ ! -f "$AGENTS_CONFIG" ]] || [[ ! -f "$PROVIDERS_CONFIG" ]]; then
        log_error "Configuration files not found"
        return 1
    fi

    # Display configuration summary
    local default_provider
    default_provider=$(jq -r '.default_provider' "$AGENTS_CONFIG")
    log_info "Default Provider: $default_provider"
    echo ""

    log_info "Agent Configuration:"
    jq -r '.agents | to_entries[] | "\(.key): \(.value.provider)/\(.value.model)"' "$AGENTS_CONFIG" | while read -r line; do
        log_info "  $line"
    done

    return 0
}

#-------------------------------------------------------------------------------
# Provider Resolution
#-------------------------------------------------------------------------------
get_provider() {
    local agent_id="$1"

    if [[ -z "$agent_id" ]]; then
        log_error "Agent ID required"
        return 1
    fi

    if ! jq -e ".agents.$agent_id" "$AGENTS_CONFIG" &>/dev/null; then
        log_error "Agent not found: $agent_id"
        return 1
    fi

    local provider
    provider=$(jq -r ".agents.$agent_id.provider" "$AGENTS_CONFIG")
    local model
    model=$(jq -r ".agents.$agent_id.model" "$AGENTS_CONFIG")

    echo "$provider/$model"
    return 0
}

list_providers() {
    log_info "Available Providers:"
    echo ""

    jq -r '.providers | to_entries[] |
        "Provider: \(.value.name) (\(.key))
  Enabled: \(.value.enabled)
  API Key: \(.value.api_key_env)
  Models: \(.value.models | length) available"' "$PROVIDERS_CONFIG"

    echo ""
    log_info "Provider Details:"
    jq -r '.providers | to_entries[] |
        if .value.enabled == true then
          "  ✓ \(.value.name) (\(.key))"
        else
          "    \(.value.name) (\(.key)) - DISABLED"
        end' "$PROVIDERS_CONFIG"
}

list_agents() {
    log_info "Agent Configuration:"
    echo ""

    jq -r '.agents | to_entries[] |
        "Agent: \(.value.name) (\(.key))
  Provider: \(.value.provider)
  Model: \(.value.model)
  Temperature: \(.value.temperature)
  Max Tokens: \(.value.max_tokens)
  Fallback: \(.value.fallback // "none")
  Waves: \(.value.waves | join(", "))"' "$AGENTS_CONFIG"
}

#-------------------------------------------------------------------------------
# Environment Export
#-------------------------------------------------------------------------------
export_env() {
    log_info "Exporting environment variables..."

    # Export default provider
    local default_provider
    default_provider=$(jq -r '.default_provider' "$AGENTS_CONFIG")
    echo "export GOCLAW_DEFAULT_PROVIDER=$default_provider"

    # Export provider API keys (only for enabled providers)
    jq -r '.providers | to_entries[] | select(.value.enabled == true) | .value.api_key_env' "$PROVIDERS_CONFIG" | while read -r env_var; do
        # Check if env var is set
        if [[ -n "${!env_var:-}" ]]; then
            echo "export GOCLAW_$(echo $env_var | tr '[:lower:]' '[:upper:]')=${!env_var}"
        else
            log_warn "  ⚠ $env_var not set"
        fi
    done

    # Export config hot-reload setting
    local hot_reload="${CONFIG_HOT_RELOAD:-true}"
    echo "export GOCLAW_CONFIG_HOT_RELOAD=$hot_reload"

    return 0
}

#-------------------------------------------------------------------------------
# Provider Switching
#-------------------------------------------------------------------------------
switch_provider() {
    local agent_id="$1"
    local new_provider="$2"
    local fallback="${3:-}"

    if [[ -z "$agent_id" ]] || [[ -z "$new_provider" ]]; then
        log_error "Usage: $0 switch-provider <agent> <provider> [fallback]"
        return 1
    fi

    # Validate agent exists
    if ! jq -e ".agents.$agent_id" "$AGENTS_CONFIG" &>/dev/null; then
        log_error "Agent not found: $agent_id"
        return 1
    fi

    # Validate provider exists
    if ! jq -e ".providers[\"$new_provider\"]" "$PROVIDERS_CONFIG" &>/dev/null; then
        log_error "Provider not found: $new_provider"
        return 1
    fi

    # Validate provider is enabled
    local enabled
    enabled=$(jq -r ".providers[\"$new_provider\"].enabled" "$PROVIDERS_CONFIG")
    if [[ "$enabled" != "true" ]]; then
        log_error "Provider is not enabled: $new_provider"
        log_error "Add API key to .env and set 'enabled': true in providers-config.json"
        return 1
    fi

    # Backup current config
    cp "$AGENTS_CONFIG" "${AGENTS_CONFIG}.backup"

    # Update provider
    local temp_config
    temp_config=$(jq ".agents.$agent_id.provider = \"$new_provider\"" "$AGENTS_CONFIG")

    # Update fallback if provided
    if [[ -n "$fallback" ]]; then
        if ! jq -e ".providers[\"$fallback\"]" "$PROVIDERS_CONFIG" &>/dev/null; then
            log_error "Fallback provider not found: $fallback"
            return 1
        fi
        temp_config=$(echo "$temp_config" | jq ".agents.$agent_id.fallback = \"$fallback\"")
    fi

    # Write new config
    echo "$temp_config" > "$AGENTS_CONFIG"

    log_success "Switched $agent_id to $new_provider"

    if [[ -n "$fallback" ]]; then
        log_info "Fallback: $fallback"
    fi

    # Trigger reload if requested
    if [[ "${AUTO_RELOAD:-true}" == "true" ]]; then
        log_info "Triggering GoClaw reload..."
        reload
    fi

    return 0
}

#-------------------------------------------------------------------------------
# GoClaw Integration
#-------------------------------------------------------------------------------
reload() {
    log_info "Reloading GoClaw configuration..."

    # Check if GoClaw is running
    if ! docker ps --filter 'name=goclaw-pipeline' --format '{{.Names}}' | grep -q goclaw-pipeline; then
        log_warn "GoClaw is not running"
        return 0
    fi

    # Call reload endpoint
    local response
    response=$(curl -s -X POST http://localhost:18789/api/config/reload 2>&1)

    if [[ $? -eq 0 ]]; then
        log_success "Configuration reloaded successfully"
        return 0
    else
        log_error "Failed to reload configuration"
        log_error "Response: $response"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------
main() {
    local command="${1:-}"
    shift || true

    case "$command" in
        validate)
            validate
            ;;
        load)
            load_config
            ;;
        get-provider)
            get_provider "$@"
            ;;
        export-env)
            export_env
            ;;
        switch-provider)
            switch_provider "$@"
            ;;
        reload)
            reload
            ;;
        list-providers)
            list_providers
            ;;
        list-agents)
            list_agents
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            usage
            exit 1
            ;;
    esac
}

main "$@"
