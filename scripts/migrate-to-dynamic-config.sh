#!/bin/bash
#===============================================================================
# Migration Script: Convert Static Agent Definitions to Dynamic Configuration
# Purpose: Migrate from static .md files to JSON-based configuration
#===============================================================================

set -euo pipefail

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly GOCRAW_DIR="$PROJECT_ROOT/.goclaw"
readonly AGENTS_DIR="$GOCRAW_DIR/agents"
readonly BACKUP_DIR="$GOCRAW_DIR/.backup_$(date +%Y%m%d_%H%M%S)"
readonly AGENTS_CONFIG="$GOCRAW_DIR/agents-config.json"
readonly PROVIDERS_CONFIG="$GOCRAW_DIR/providers-config.json"

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
log_step()  { printf "${BLUE}[STEP]${NC} %s\n" "$1"; }

#-------------------------------------------------------------------------------
# Pre-flight Checks
#-------------------------------------------------------------------------------
pre_flight_checks() {
    log_step "Running pre-flight checks..."

    # Check if running in correct directory
    if [[ ! -d "$GOCRAW_DIR" ]]; then
        log_error "GoClaw directory not found: $GOCRAW_DIR"
        log_error "Are you in the project root?"
        exit 1
    fi

    # Check if agents directory exists
    if [[ ! -d "$AGENTS_DIR" ]]; then
        log_warn "No agents directory found (fresh installation?)"
        log_info "No migration needed - JSON configs will be created by setup script"
        exit 0
    fi

    # Check if already migrated (JSON configs exist)
    if [[ -f "$AGENTS_CONFIG" ]] && [[ -f "$PROVIDERS_CONFIG" ]]; then
        log_warn "Dynamic configuration already exists!"
        echo ""
        read -p "Continue and overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Migration cancelled"
            exit 0
        fi
    fi

    log_success "Pre-flight checks passed"
}

#-------------------------------------------------------------------------------
# Backup
#-------------------------------------------------------------------------------
create_backup() {
    log_step "Creating backup..."

    mkdir -p "$BACKUP_DIR"

    # Backup agents directory
    if [[ -d "$AGENTS_DIR" ]]; then
        cp -r "$AGENTS_DIR" "$BACKUP_DIR/agents"
        log_success "Backed up agents directory to: $BACKUP_DIR/agents"
    fi

    # Backup any existing JSON configs
    if [[ -f "$AGENTS_CONFIG" ]]; then
        cp "$AGENTS_CONFIG" "$BACKUP_DIR/agents-config.json"
        log_info "Backed up existing agents-config.json"
    fi

    if [[ -f "$PROVIDERS_CONFIG" ]]; then
        cp "$PROVIDERS_CONFIG" "$BACKUP_DIR/providers-config.json"
        log_info "Backed up existing providers-config.json"
    fi

    log_success "Backup created at: $BACKUP_DIR"
}

#-------------------------------------------------------------------------------
# Extract Agent Information
#-------------------------------------------------------------------------------
extract_agent_info() {
    local agent_file="$1"
    local agent_name
    local waves=()

    # Extract agent name from file
    agent_name=$(basename "$agent_file" .md)

    # Extract wave information from file content
    if grep -q "Wave 1" "$agent_file"; then
        waves+=("1")
    fi
    if grep -q "Wave 2" "$agent_file"; then
        waves+=("2")
    fi
    if grep -q "Wave 3" "$agent_file"; then
        waves+=("3")
    fi

    # Special case for QA agent (idle in Wave 2)
    if [[ "$agent_name" == "qa-agent" ]]; then
        waves=("1" "3")
    fi

    # Return waves as JSON array
    printf '%s\n' "$(printf '%s,' "${waves[@]}" | sed 's/$/\[/')" | sed 's/,/]/", "/g')"
}

#-------------------------------------------------------------------------------
# Create Migration
#-------------------------------------------------------------------------------
create_migration() {
    log_step "Creating dynamic configuration..."

    # Check if JSON configs already exist (from setup script)
    if [[ -f "$AGENTS_CONFIG" ]] && [[ -f "$PROVIDERS_CONFIG" ]]; then
        log_info "JSON configuration files already exist (created by setup script)"
        log_info "Migration complete!"
        return 0
    fi

    # Note: The setup script (goclay-setup.sh) now creates these JSON files
    # So this migration script is mainly for existing installations

    log_info "For new installations, JSON configs are created automatically by setup script"
    log_info "For existing installations, please re-run setup script:"
    echo ""
    echo "  sudo ./goclay-setup.sh"
    echo ""

    # Create placeholder configs if they don't exist
    if [[ ! -f "$AGENTS_CONFIG" ]]; then
        log_warn "agents-config.json not found - re-run setup script"
    fi

    if [[ ! -f "$PROVIDERS_CONFIG" ]]; then
        log_warn "providers-config.json not found - re-run setup script"
    fi
}

#-------------------------------------------------------------------------------
# Rollback
#-------------------------------------------------------------------------------
rollback() {
    log_step "Rolling back migration..."

    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_error "No backup found to rollback from!"
        exit 1
    fi

    # Restore agents directory
    if [[ -d "$BACKUP_DIR/agents" ]]; then
        rm -rf "$AGENTS_DIR"
        cp -r "$BACKUP_DIR/agents" "$AGENTS_DIR"
        log_success "Restored agents directory from backup"
    fi

    # Restore JSON configs if they existed
    if [[ -f "$BACKUP_DIR/agents-config.json" ]]; then
        cp "$BACKUP_DIR/agents-config.json" "$AGENTS_CONFIG"
        log_info "Restored agents-config.json"
    fi

    if [[ -f "$BACKUP_DIR/providers-config.json" ]]; then
        cp "$BACKUP_DIR/providers-config.json" "$PROVIDERS_CONFIG"
        log_info "Restored providers-config.json"
    fi

    # Remove JSON configs created by migration (if not in backup)
    if [[ ! -f "$BACKUP_DIR/agents-config.json" ]] && [[ -f "$AGENTS_CONFIG" ]]; then
        rm -f "$AGENTS_CONFIG"
        log_info "Removed agents-config.json"
    fi

    if [[ ! -f "$BACKUP_DIR/providers-config.json" ]] && [[ -f "$PROVIDERS_CONFIG" ]]; then
        rm -f "$PROVIDERS_CONFIG"
        log_info "Removed providers-config.json"
    fi

    log_success "Rollback complete"
}

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------
print_summary() {
    echo ""
    log_info "=========================================="
    log_info "Migration Summary"
    log_info "=========================================="
    echo ""
    echo "Configuration Files:"
    echo "  agents-config.json:    Agent LLM configuration"
    echo "  providers-config.json:  Provider registry"
    echo ""
    echo "Next Steps:"
    echo "  1. Validate configuration:"
    echo "     ./scripts/load-config.sh validate"
    echo ""
    echo "  2. Test provider resolution:"
    echo "     ./scripts/load-config.sh get-provider po"
    echo ""
    echo "  3. Add OpenAI/Anthropic (optional):"
    echo "     - Add API keys to .env"
    echo "     - Set 'enabled': true in providers-config.json"
    echo ""
    echo "  4. Rollback if needed:"
    echo "     $0 rollback"
    echo ""
    echo "Backup Location: $BACKUP_DIR"
    echo ""
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------
main() {
    local command="${1:-migrate}"
    shift || true

    case "$command" in
        migrate)
            pre_flight_checks
            create_backup
            create_migration
            print_summary
            ;;
        rollback)
            rollback
            ;;
        *)
            echo "Usage: $0 {migrate|rollback}"
            echo ""
            echo "Commands:"
            echo "  migrate  - Migrate from static .md files to JSON configuration"
            echo "  rollback - Rollback to static .md files"
            exit 1
            ;;
    esac
}

main "$@"
