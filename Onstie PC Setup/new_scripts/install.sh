#!/usr/bin/env bash
set -euo pipefail

# MDPC Contest Network Manager Installer
echo "===================================="
echo " MDPC Contest Network Manager Setup "
echo "===================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
  echo "Error: This installer must be run as root"
  echo "Please run: sudo bash install.sh"
  exit 1
fi

# Get script directory (works even if script is run from another directory)
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Create installation directory
mkdir -p /usr/local/share/mdpc/

# Copy scripts to installation directory
cp "$SCRIPT_DIR/mdpc" /usr/local/share/mdpc/
cp "$SCRIPT_DIR/mdpc-restrict.sh" /usr/local/share/mdpc/
cp "$SCRIPT_DIR/mdpc-unrestrict.sh" /usr/local/share/mdpc/
cp "$SCRIPT_DIR/mdpc-setup.sh" /usr/local/share/mdpc/
cp "$SCRIPT_DIR/mdpc-reset.sh" /usr/local/share/mdpc/

# Set correct permissions
chmod 755 /usr/local/share/mdpc/mdpc
chmod 755 /usr/local/share/mdpc/mdpc-restrict.sh
chmod 755 /usr/local/share/mdpc/mdpc-unrestrict.sh
chmod 755 /usr/local/share/mdpc/mdpc-setup.sh
chmod 755 /usr/local/share/mdpc/mdpc-reset.sh

# Create symlink in /usr/local/bin for system-wide access
ln -sf /usr/local/share/mdpc/mdpc /usr/local/bin/mdpc

echo "Installation complete!"
echo "You can now use the 'mdpc' command to manage restrictions."
echo
echo "Example commands:"
echo "  sudo mdpc setup           # Set up lab PC from scratch"
echo "  sudo mdpc reset           # Reset participant account"
echo "  sudo mdpc restrict        # Restrict participant user"
echo "  sudo mdpc add example.com # Add domain to whitelist"
echo "  sudo mdpc status          # Check restriction status"
echo "  sudo mdpc help            # Show all available commands"
