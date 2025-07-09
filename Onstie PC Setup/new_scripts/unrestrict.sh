#!/usr/bin/env bash
set -euo pipefail

# Contest Environment Unrestriction Script
# This script removes all internet and USB storage restrictions for contest participants
# reversing the changes made by restrict.sh

# Configuration
DEFAULT_USER="participant"
RESTRICT_USER="${1:-$DEFAULT_USER}"
CONFIG_DIR="/usr/local/etc/contest-restriction"
WHITELIST_FILE="$CONFIG_DIR/whitelist.txt"
DEPENDENCIES_FILE="$CONFIG_DIR/dependencies.txt"
HELPER_SCRIPT="/usr/local/bin/update-contest-whitelist"
CHAIN_PREFIX="CONTEST"
CONTEST_SERVICE="contest-restrict-$RESTRICT_USER"

echo "============================================"
echo "Contest Environment Unrestriction - User: '$RESTRICT_USER'"
echo "Starting at: $(date)"
echo "============================================"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
  echo "❌ Error: This script must be run as root"
  echo "   Reason: Required to remove system-level restrictions"
  exit 1
fi

# Ensure the user exists
if ! id "$RESTRICT_USER" &>/dev/null; then
  echo "❌ Error: User '$RESTRICT_USER' does not exist"
  exit 1
fi

echo "============================================"
echo "Step 1: Remove Systemd Services"
echo "============================================"

echo "→ Stopping and disabling systemd services..."

# Stop and disable timer
if systemctl is-active --quiet "$CONTEST_SERVICE.timer"; then
  echo "→ Stopping systemd timer: $CONTEST_SERVICE.timer"
  systemctl stop "$CONTEST_SERVICE.timer"
  if [[ $? -eq 0 ]]; then
    echo "✅ Timer stopped successfully"
  else
    echo "❌ Failed to stop timer" >&2
  fi
fi

if systemctl is-enabled --quiet "$CONTEST_SERVICE.timer"; then
  echo "→ Disabling systemd timer: $CONTEST_SERVICE.timer"
  systemctl disable "$CONTEST_SERVICE.timer"
  if [[ $? -eq 0 ]]; then
    echo "✅ Timer disabled successfully"
  else
    echo "❌ Failed to disable timer" >&2
  fi
fi

# Stop and disable service
if systemctl is-active --quiet "$CONTEST_SERVICE.service"; then
  echo "→ Stopping systemd service: $CONTEST_SERVICE.service"
  systemctl stop "$CONTEST_SERVICE.service"
  if [[ $? -eq 0 ]]; then
    echo "✅ Service stopped successfully"
  else
    echo "❌ Failed to stop service" >&2
  fi
fi

if systemctl is-enabled --quiet "$CONTEST_SERVICE.service"; then
  echo "→ Disabling systemd service: $CONTEST_SERVICE.service"
  systemctl disable "$CONTEST_SERVICE.service"
  if [[ $? -eq 0 ]]; then
    echo "✅ Service disabled successfully"
  else
    echo "❌ Failed to disable service" >&2
  fi
fi

# Remove systemd files
echo "→ Removing systemd service files..."
if [[ -f "/etc/systemd/system/$CONTEST_SERVICE.service" ]]; then
  rm -f "/etc/systemd/system/$CONTEST_SERVICE.service"
  echo "✅ Service file removed"
fi

if [[ -f "/etc/systemd/system/$CONTEST_SERVICE.timer" ]]; then
  rm -f "/etc/systemd/system/$CONTEST_SERVICE.timer"
  echo "✅ Timer file removed"
fi

# Reload systemd daemon
echo "→ Reloading systemd daemon..."
systemctl daemon-reload
if [[ $? -eq 0 ]]; then
  echo "✅ Systemd daemon reloaded"
else
  echo "❌ Failed to reload systemd daemon" >&2
fi

echo "============================================"
echo "Step 2: Remove Firewall Rules"
echo "============================================"

echo "→ Removing iptables network restrictions..."

# Configure user-specific chains
CHAIN_IN="${CHAIN_PREFIX}_${RESTRICT_USER^^}_IN"
CHAIN_OUT="${CHAIN_PREFIX}_${RESTRICT_USER^^}_OUT"

echo "→ Removing user-specific firewall rules..."

# Get the UID for the user
USER_UID=$(id -u "$RESTRICT_USER" 2>/dev/null || echo "")

if [[ -n "$USER_UID" ]]; then
  # Remove user-specific jump rules from main chains
  echo "→ Removing jump rules for user $RESTRICT_USER (UID: $USER_UID)"
  iptables -D OUTPUT -m owner --uid-owner "$USER_UID" -j "$CHAIN_OUT" 2>/dev/null || true
  iptables -D INPUT -m owner --uid-owner "$USER_UID" -j "$CHAIN_IN" 2>/dev/null || true
  echo "✅ User-specific jump rules removed"
else
  echo "⚠️  Could not determine UID for user $RESTRICT_USER"
fi

# Flush and delete the custom chains
echo "→ Removing custom iptables chains: $CHAIN_IN, $CHAIN_OUT"

if iptables -L "$CHAIN_OUT" &>/dev/null; then
  echo "→ Flushing chain: $CHAIN_OUT"
  iptables -F "$CHAIN_OUT" 2>/dev/null || true
  echo "→ Deleting chain: $CHAIN_OUT"
  iptables -X "$CHAIN_OUT" 2>/dev/null || true
  echo "✅ Output chain removed"
else
  echo "✅ Output chain was not present"
fi

if iptables -L "$CHAIN_IN" &>/dev/null; then
  echo "→ Flushing chain: $CHAIN_IN"
  iptables -F "$CHAIN_IN" 2>/dev/null || true
  echo "→ Deleting chain: $CHAIN_IN"
  iptables -X "$CHAIN_IN" 2>/dev/null || true
  echo "✅ Input chain removed"
else
  echo "✅ Input chain was not present"
fi

echo "============================================"
echo "Step 3: Remove USB Storage Restrictions"
echo "============================================"

echo "→ Removing USB storage device restrictions..."

# Remove udev rules
if [[ -f "/etc/udev/rules.d/99-contest-block-usb.rules" ]]; then
  echo "→ Removing udev rules..."
  rm -f "/etc/udev/rules.d/99-contest-block-usb.rules"
  echo "✅ USB storage udev rules removed"
else
  echo "✅ USB storage udev rules were not present"
fi

# Remove polkit rules
if [[ -f "/etc/polkit-1/rules.d/99-contest-block-mount.rules" ]]; then
  echo "→ Removing polkit rules..."
  rm -f "/etc/polkit-1/rules.d/99-contest-block-mount.rules"
  echo "✅ Polkit mount blocking rules removed"
else
  echo "✅ Polkit mount blocking rules were not present"
fi

# Reload udev rules
echo "→ Reloading udev rules..."
udevadm control --reload-rules
udevadm trigger

if [[ $? -eq 0 ]]; then
  echo "✅ USB storage restrictions removed successfully"
else
  echo "❌ Failed to reload udev rules" >&2
fi

echo "============================================"
echo "Step 4: Clean Up Configuration Files"
echo "============================================"

echo "→ Cleaning up user-specific configuration files..."

# Remove user-specific cache files
USER_DOMAIN_CACHE="$CONFIG_DIR/${RESTRICT_USER}_domains_cache.txt"
USER_IP_CACHE="$CONFIG_DIR/${RESTRICT_USER}_ip_cache.txt"

if [[ -f "$USER_DOMAIN_CACHE" ]]; then
  echo "→ Removing domain cache: $USER_DOMAIN_CACHE"
  rm -f "$USER_DOMAIN_CACHE"
  echo "✅ Domain cache removed"
fi

if [[ -f "$USER_IP_CACHE" ]]; then
  echo "→ Removing IP cache: $USER_IP_CACHE"
  rm -f "$USER_IP_CACHE"
  echo "✅ IP cache removed"
fi

# Ask user if they want to remove global configuration
echo ""
echo "→ Global configuration files:"
echo "   • Whitelist: $WHITELIST_FILE"
echo "   • Dependencies: $DEPENDENCIES_FILE"
echo "   • Helper script: $HELPER_SCRIPT"

read -p "Do you want to remove global configuration files? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "→ Removing global configuration files..."
  
  if [[ -f "$WHITELIST_FILE" ]]; then
    rm -f "$WHITELIST_FILE"
    echo "✅ Whitelist file removed"
  fi
  
  if [[ -f "$DEPENDENCIES_FILE" ]]; then
    rm -f "$DEPENDENCIES_FILE"
    echo "✅ Dependencies file removed"
  fi
  
  if [[ -f "$HELPER_SCRIPT" ]]; then
    rm -f "$HELPER_SCRIPT"
    echo "✅ Helper script removed"
  fi
  
  # Remove config directory if empty
  if [[ -d "$CONFIG_DIR" ]] && [[ -z "$(ls -A "$CONFIG_DIR" 2>/dev/null)" ]]; then
    rmdir "$CONFIG_DIR"
    echo "✅ Configuration directory removed"
  fi
else
  echo "✅ Global configuration files preserved"
fi

echo "============================================"
echo "Step 5: Verify Removal"
echo "============================================"

echo "→ Verifying that all restrictions have been removed..."

# Check for remaining iptables rules
echo "→ Checking for remaining iptables rules..."
if iptables -L | grep -q "$CHAIN_PREFIX.*$RESTRICT_USER" 2>/dev/null; then
  echo "⚠️  Warning: Some iptables rules may still exist"
else
  echo "✅ No iptables rules found"
fi

# Check for remaining systemd services
echo "→ Checking for remaining systemd services..."
if systemctl list-units --all | grep -q "$CONTEST_SERVICE" 2>/dev/null; then
  echo "⚠️  Warning: Some systemd services may still exist"
else
  echo "✅ No systemd services found"
fi

# Check for remaining udev/polkit rules
echo "→ Checking for remaining USB restrictions..."
remaining_rules=0

if [[ -f "/etc/udev/rules.d/99-contest-block-usb.rules" ]]; then
  echo "⚠️  Warning: USB udev rules still exist"
  remaining_rules=1
fi

if [[ -f "/etc/polkit-1/rules.d/99-contest-block-mount.rules" ]]; then
  echo "⚠️  Warning: Polkit mount rules still exist"
  remaining_rules=1
fi

if [[ $remaining_rules -eq 0 ]]; then
  echo "✅ No USB restrictions found"
fi

echo "============================================"
echo "✅ Contest Environment Unrestriction Complete!"
echo "============================================"

echo "Summary:"
echo "→ User: '$RESTRICT_USER'"
echo "→ Internet access: Fully restored (no restrictions)"
echo "→ USB storage devices: Fully accessible"
echo "→ Firewall rules: Removed"
echo "→ Background services: Stopped and disabled"
echo "→ Completed at: $(date)"

echo ""
echo "💡 Next steps:"
echo "   • User '$RESTRICT_USER' now has full internet access"
echo "   • USB storage devices can be used normally"
echo "   • To re-apply restrictions, run: sudo cmanager restrict $RESTRICT_USER"
echo "   • To check current status, run: sudo cmanager status $RESTRICT_USER"

echo "============================================"