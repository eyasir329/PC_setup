#!/usr/bin/env bash
set -euo pipefail

# Contest Environment Manager Installer
echo "===================================="
echo " Contest Environment Manager Setup "
echo "===================================="

# Get command name from argument or default to 'cmanager'
COMMAND_NAME="${1:-cmanager}"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
  echo "Error: This installer must be run as root"
  echo "Please run: sudo bash install.sh [command_name]"
  exit 1
fi

echo "Installing with command name: $COMMAND_NAME"

# Get script directory (works even if script is run from another directory)
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Create installation directory
mkdir -p /usr/local/share/contest-manager/

# Copy scripts to installation directory
cp "$SCRIPT_DIR/cmanager" /usr/local/share/contest-manager/
cp "$SCRIPT_DIR/restrict.sh" /usr/local/share/contest-manager/
cp "$SCRIPT_DIR/unrestrict.sh" /usr/local/share/contest-manager/
cp "$SCRIPT_DIR/setup.sh" /usr/local/share/contest-manager/
cp "$SCRIPT_DIR/reset.sh" /usr/local/share/contest-manager/
cp "$SCRIPT_DIR/discover-dependencies.sh" /usr/local/share/contest-manager/

# Copy whitelist file if it exists
if [ -f "$SCRIPT_DIR/whitelist.txt" ]; then
  echo "Copying whitelist.txt file..."
  mkdir -p /usr/local/etc/contest-restriction/
  cp "$SCRIPT_DIR/whitelist.txt" /usr/local/etc/contest-restriction/whitelist.txt
  chmod 644 /usr/local/etc/contest-restriction/whitelist.txt
else
  echo "Warning: whitelist.txt not found in $SCRIPT_DIR"
  echo "You will need to create it manually or run 'cmanager add domain.com' to add domains"
fi

# Set correct permissions
chmod 755 /usr/local/share/contest-manager/cmanager
chmod 755 /usr/local/share/contest-manager/restrict.sh
chmod 755 /usr/local/share/contest-manager/unrestrict.sh
chmod 755 /usr/local/share/contest-manager/setup.sh
chmod 755 /usr/local/share/contest-manager/reset.sh
chmod 755 /usr/local/share/contest-manager/discover-dependencies.sh

# Create symlink in /usr/local/bin for system-wide access
ln -sf /usr/local/share/contest-manager/cmanager "/usr/local/bin/$COMMAND_NAME"

echo "Installation complete!"
echo "You can now use the '$COMMAND_NAME' command to manage restrictions."
echo
echo "Example commands:"
echo "  sudo $COMMAND_NAME setup           # Set up lab PC from scratch"
echo "  sudo $COMMAND_NAME discover        # Discover contest site dependencies"
echo "  sudo $COMMAND_NAME restrict        # Restrict participant user"
echo "  sudo $COMMAND_NAME unrestrict      # Remove all restrictions"
echo "  sudo $COMMAND_NAME reset           # Reset participant account"
echo "  sudo $COMMAND_NAME add example.com # Add domain to whitelist"
echo "  sudo $COMMAND_NAME status          # Check restriction status"
echo "  sudo $COMMAND_NAME help            # Show all available commands"

