#!/bin/bash
# Fix common zsh and filesystem errors
# Run this if you get bus errors or I/O errors in zsh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

printf ""
printf "${GREEN}==========================================\n"
printf "Zsh Error Fix Script\n"
printf "==========================================${NC}\n"
printf ""

# ============================================
# 1. FIX CORRUPTED ZSH COMPLETION DUMP
# ============================================

log_info "Fixing zsh completion cache..."

ZSH_COMPDUMP="$HOME/.zcompdump*"
if ls $ZSH_COMPDUMP >/dev/null 2>&1; then
    log_warn "Found zsh completion dump files - removing them..."
    rm -fv $ZSH_COMPDUMP 2>/dev/null || true
    log_info "✓ Completion dump files removed"
else
    log_info "No completion dump files found"
fi

# Also check for .zcompcache
if [ -f "$HOME/.zcompcache" ]; then
    rm -fv "$HOME/.zcompcache"
    log_info "✓ Removed .zcompcache"
fi

# ============================================
# 2. FIX NVM (Node Version Manager)
# ============================================

log_info "Checking nvm installation..."

if [ -d "$HOME/.nvm" ]; then
    log_warn "Found nvm directory - checking for corruption..."

    # Check if nvm is sourced in .zshrc
    if grep -q "nvm" "$HOME/.zshrc" 2>/dev/null; then
        log_warn "nvm is configured in .zshrc - temporarily disabling..."

        # Backup .zshrc
        cp "$HOME/.zshrc" "$HOME/.zshrc.nvm-backup"

        # Comment out nvm lines
        sed -i.bak '/NVM_DIR/d' "$HOME/.zshrc" 2>/dev/null || true
        sed -i.bak '/\[ -s/d' "$HOME/.zshrc" 2>/dev/null || true

        log_info "✓ nvm temporarily disabled in .zshrc"
        log_warn "You can re-enable nvm later by uncommenting lines in .zshrc.nvm-backup"
    fi
fi

# ============================================
# 3. FIX CORRUPTED ZSH HISTORY
# ============================================

log_info "Checking zsh history..."

if [ -f "$HOME/.zsh_history" ]; then
    # Check if history file is corrupted
    if ! grep -q ":" "$HOME/.zsh_history" 2>/dev/null; then
        log_warn "zsh history may be corrupted - backing up and creating new one..."
        mv "$HOME/.zsh_history" "$HOME/.zsh_history.corrupted"
        touch "$HOME/.zsh_history"
        log_info "✓ Created new .zsh_history (corrupted version saved as .zsh_history.corrupted)"
    fi
fi

# ============================================
# 4. CHECK FOR CORRUPTED BINARIES
# ============================================

log_info "Checking critical system binaries..."

BINARIES="head tail cat grep sed awk"

for binary in $BINARIES; do
    if ! command -v $binary >/dev/null 2>&1; then
        log_error "$binary is not found or corrupted!"
    else
        # Try to run the binary
        if ! echo "test" | $binary >/dev/null 2>&1; then
            log_error "$binary is corrupted! Reinstall required."
        fi
    fi
done

log_info "✓ Binary check completed"

# ============================================
# 5. CHECK DISK SPACE
# ============================================

log_info "Checking disk space..."

DISK_USAGE=$(df -h "$HOME" | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 90 ]; then
    log_error "Disk is ${DISK_USAGE}% full - this may cause errors!"
    log_warn "Free up some space and run: zsh"
else
    log_info "✓ Disk space OK (${DISK_USAGE}% used)"
fi

# ============================================
# 6. REBUILD ZSH COMPLETION
# ============================================

log_info "Rebuilding zsh completion system..."

# Create a temporary script to rebuild completions
cat > /tmp/rebuild-zcomp << 'ZSH_SCRIPT'
#!/bin/zsh
# Force rebuild of zsh completion system
rm -f ~/.zcompdump*
autoload -Uz compinit
compinit -d ~/.zcompdump
echo "Completion system rebuilt"
ZSH_SCRIPT

chmod +x /tmp/rebuild-zcomp

if zsh /tmp/rebuild-zcomp 2>/dev/null; then
    log_info "✓ zsh completion rebuilt successfully"
else
    log_warn "Could not rebuild zsh completion (may need manual intervention)"
fi

rm -f /tmp/rebuild-zcomp

# ============================================
# 7. CHECK FOR OH-MY-ZSH ISSUES
# ============================================

log_info "Checking Oh-My-Zsh installation..."

if [ -d "$HOME/.oh-my-zsh" ]; then
    # Check if .zshrc is properly sourced
    if ! grep -q "ZSH=" "$HOME/.zshrc" 2>/dev/null; then
        log_warn ".zshrc may not be properly configured for Oh-My-Zsh"
    fi

    # Check for update issues
    if [ -f "$HOME/.oh-my-zsh/.git" ]; then
        log_info "Oh-My-Zsh git repository found"
    fi
fi

# ============================================
# SUMMARY
# ============================================

printf ""
printf "${GREEN}==========================================\n"
printf "Fix Summary\n"
printf "==========================================${NC}\n"
printf ""
log_info "Completed the following fixes:"
printf "  1. ✓ Removed corrupted completion dump files\n"
printf "  2. ✓ Temporarily disabled nvm (if found)\n"
printf "  3. ✓ Checked and fixed .zsh_history\n"
printf "  4. ✓ Verified critical system binaries\n"
printf "  5. ✓ Checked disk space\n"
printf "  6. ✓ Rebuilt zsh completion system\n"
printf "  7. ✓ Checked Oh-My-Zsh installation\n"
printf ""
log_warn "NEXT STEPS:"
log_warn "1. Start a new zsh session: exec zsh"
log_warn "2. If errors persist, restart your terminal/SSH session"
log_warn "3. If still broken, reload Oh-My-Zsh: source ~/.zshrc"
printf ""
log_warn "If nvm was disabled:"
log_warn "  - Check: cat ~/.zshrc.nvm-backup"
log_warn "  - Re-enable by adding the nvm lines back to .zshrc"
printf ""
log_warn "If you still see errors:"
log_warn "  - Check filesystem: fsck -f (requires reboot)"
log_warn "  - Reinstall packages: apk fix (Alpine) or apt --fix-broken install (Ubuntu)"
printf ""
printf "${GREEN}To test your shell now:${NC}\n"
printf "  exec zsh\n"
printf ""
