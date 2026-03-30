#!/bin/bash
# Merge .zshrc.pre-oh-my-zsh into .zshrc
# Run this after Oh-My-Zsh installation to restore your custom config

set -e

ZSHRC="$HOME/.zshrc"
ZSHRC_PRE="$HOME/.zshrc.pre-oh-my-zsh"
ZSHRC_BACKUP="$HOME/.zshrc.before-merge"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ ! -f "$ZSHRC_PRE" ]; then
    echo -e "${RED}No .zshrc.pre-oh-my-zsh found${NC}"
    echo "Oh-My-Zsh backup file doesn't exist. Nothing to merge."
    exit 1
fi

echo -e "${GREEN}=========================================="
echo "Merging .zshrc.pre-oh-my-zsh into .zshrc"
echo -e "==========================================${NC}"
echo ""

# Backup current .zshrc
if [ -f "$ZSHRC" ]; then
    echo -e "${YELLOW}Backing up current .zshrc to .zshrc.before-merge...${NC}"
    cp "$ZSHRC" "$ZSHRC_BACKUP"
fi

# Read the pre-oh-my-zsh config
echo -e "${GREEN}Reading custom configuration from .zshrc.pre-oh-my-zsh...${NC}"

# Extract custom config (everything after Oh-My-Zsh initialization)
# We'll append this to the end of the new .zshrc

# Check if there's custom config in the backup
CUSTOM_CONFIG=$(sed -n '/^# User configuration/,/^# End of user configuration/p' "$ZSHRC_PRE" 2>/dev/null)

if [ -z "$CUSTOM_CONFIG" ]; then
    # If no "User configuration" section, just get everything that's not comments
    CUSTOM_CONFIG=$(grep -v '^#' "$ZSHRC_PRE" | grep -v '^[[:space:]]*$' | grep -v '^export PATH=')
fi

# Append custom config to .zshrc
if [ -n "$CUSTOM_CONFIG" ]; then
    echo ""
    echo -e "${GREEN}Found custom configuration to merge:${NC}"
    echo "$CUSTOM_CONFIG" | head -20
    echo ""
    echo -e "${YELLOW}Adding custom configuration to .zshrc...${NC}"

    # Add a separator
    cat >> "$ZSHRC" << 'EOF'

# ============================================
# MERGED FROM .zshrc.pre-oh-my-zsh
# ============================================
EOF

    # Append the custom config
    echo "$CUSTOM_CONFIG" >> "$ZSHRC"

    echo -e "${GREEN}✓ Custom configuration merged successfully${NC}"
else
    echo -e "${YELLOW}No custom configuration found to merge${NC}"
fi

# Restore aliases from backup if they exist
if grep -q "^alias " "$ZSHRC_PRE"; then
    echo ""
    echo -e "${GREEN}Found aliases in backup - restoring...${NC}"

    # Extract aliases
    ALIASES=$(grep "^alias " "$ZSHRC_PRE")

    # Add to .zshrc
    cat >> "$ZSHRC" << 'EOF'

# Aliases from .zshrc.pre-oh-my-zsh
EOF
    echo "$ALIASES" >> "$ZSHRC"

    echo -e "${GREEN}✓ Aliases restored${NC}"
fi

# Restore environment variables from backup if they exist
if grep -q "^export " "$ZSHRC_PRE"; then
    echo ""
    echo -e "${GREEN}Found environment variables in backup - restoring...${NC}"

    # Extract exports (skip PATH to avoid duplicates)
    EXPORTS=$(grep "^export " "$ZSHRC_PRE" | grep -v "export PATH=")

    if [ -n "$EXPORTS" ]; then
        # Add to .zshrc
        cat >> "$ZSHRC" << 'EOF'

# Environment variables from .zshrc.pre-oh-my-zsh
EOF
        echo "$EXPORTS" >> "$ZSHRC"

        echo -e "${GREEN}✓ Environment variables restored${NC}"
    fi
fi

echo ""
echo -e "${GREEN}=========================================="
echo "Merge completed!"
echo -e "==========================================${NC}"
echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "  - Original .zshrc backed up to: .zshrc.before-merge"
echo "  - Custom config merged from: .zshrc.pre-oh-my-zsh"
echo "  - New .zshrc includes Oh-My-Zsh + your custom config"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Review your new .zshrc: cat ~/.zshrc"
echo "  2. Restart your shell: exec zsh"
echo "  3. Or log out and log back in"
echo ""
echo -e "${YELLOW}If something went wrong:${NC}"
echo "  - Restore backup: cp ~/.zshrc.before-merge ~/.zshrc"
echo ""
