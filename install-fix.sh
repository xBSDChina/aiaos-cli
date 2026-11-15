#!/bin/bash

# AIAOS CLI Fix Installation Script
# This script will replace the broken aiaos-cli.el with the fixed version

echo "Installing AIAOS CLI fix..."

# Backup original file
ORIG_FILE="/home/shjiaye8/.emacs.d/aiaos-cli/aiaos-cli.el"
BACKUP_FILE="/home/shjiaye8/.emacs.d/aiaos-cli/aiaos-cli.el.backup.$(date +%Y%m%d_%H%M%S)"

if [ -f "$ORIG_FILE" ]; then
    echo "Backing up original file..."
    cp "$ORIG_FILE" "$BACKUP_FILE"
    echo "Backup created: $BACKUP_FILE"
else
    echo "Warning: Original file not found!"
fi

# Install fixed version
FIXED_FILE="/home/shjiaye8/.emacs.d/aiaos-cli/aiaos-cli-complete-fix.el"

if [ -f "$FIXED_FILE" ]; then
    echo "Installing fixed version..."
    cp "$FIXED_FILE" "$ORIG_FILE"
    echo "Fixed version installed successfully!"
else
    echo "Error: Fixed version not found!"
    exit 1
fi

# Reload in Emacs
echo ""
echo "Please restart Emacs to load the fixed version."
echo "Or use: M-x eval-buffer RET"
echo ""
echo "After restart, test with:"
echo "  M-x aiaos"
echo "  (Enter should send messages)"
echo ""
