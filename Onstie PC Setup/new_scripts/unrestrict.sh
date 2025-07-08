#!/bin/bash
set -euo pipefail

# Use RESTRICT_USER if set, otherwise default to "participant"
USER="${RESTRICT_USER:-${1:-participant}}"

# Configuration
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
SYSTEM_WHITELIST="/usr/local/etc/contest-restriction/allowed.txt"
IP_CACHE_DIR="/var/cache/contest-restriction"
IP_CACHE_FILE="$IP_CACHE_DIR/resolved-ips.txt"
UPDATE_SCRIPT="/usr/local/bin/update-contest-whitelist"
SYSTEMD_SERVICE="contest-restrict-$USER.service"
CRON_JOB="/etc/cron.d/contest-whitelist-updater"
USB_RULES="/etc/udev/rules.d/99-contest-usb-block.rules"
POLKIT_RULES="/etc/polkit-1/rules.d/99-contest-block-mount.rules"

echo "============================================"
echo "Starting Internet Restriction Removal for user '$USER': $(date)"
echo "============================================"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root." >&2
    exit 1
fi

# Step 1: Check if user exists
echo "============================================"
echo "Step 1: Checking user existence"
echo "============================================"

if ! id "$USER" &>/dev/null; then
    echo "❌ Error: User $USER does not exist!" >&2
    exit 1
fi
USER_ID=$(id -u "$USER")
echo "→ Found user $USER with UID $USER_ID"

# Step 2: Stop and disable systemd service
echo "============================================"
echo "Step 2: Stopping systemd service"
echo "============================================"

echo "→ Stopping and disabling $SYSTEMD_SERVICE..."
systemctl stop "$SYSTEMD_SERVICE" 2>/dev/null || true
systemctl disable "$SYSTEMD_SERVICE" 2>/dev/null || true
rm -f "/etc/systemd/system/$SYSTEMD_SERVICE"
systemctl daemon-reload
echo "✅ Systemd service stopped and removed."

# Step 3: Remove iptables rules
echo "============================================"
echo "Step 3: Removing iptables rules"
echo "============================================"

echo "→ Removing iptables rules for user $USER..."
CHAIN="CONTEST_${USER^^}_OUT"
# Remove the OUTPUT hook
iptables -D OUTPUT -m owner --uid-owner "$USER_ID" -j "$CHAIN" 2>/dev/null || true
ip6tables -D OUTPUT -m owner --uid-owner "$USER_ID" -j "$CHAIN" 2>/dev/null || true

# Flush and delete the chain
if iptables -L "$CHAIN" &>/dev/null 2>&1; then
    iptables -F "$CHAIN"
    iptables -X "$CHAIN"
    echo "→ IPv4 iptables chain removed."
fi

if ip6tables -L "$CHAIN" &>/dev/null 2>&1; then
    ip6tables -F "$CHAIN"
    ip6tables -X "$CHAIN"
    echo "→ IPv6 iptables chain removed."
fi

# Save iptables rules
if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save
fi
echo "✅ Firewall rules removed."

# Step 4: Remove cron job
echo "============================================"
echo "Step 4: Removing scheduled updates"
echo "============================================"

if [ -f "$CRON_JOB" ]; then
    echo "→ Removing cron job..."
    rm -f "$CRON_JOB"
    echo "✅ Cron job removed."
else
    echo "→ No cron job found to remove."
fi

# Step 5: Remove USB and mounting restrictions
echo "============================================"
echo "Step 5: Removing USB and mounting restrictions"
echo "============================================"

# Remove USB rules
if [ -f "$USB_RULES" ]; then
    echo "→ Removing USB restrictions..."
    rm -f "$USB_RULES"
    echo "✅ USB rules removed."
else
    echo "→ No USB rules found to remove."
fi

# Remove polkit rules
if [ -f "$POLKIT_RULES" ]; then
    echo "→ Removing polkit mounting restrictions..."
    rm -f "$POLKIT_RULES"
    echo "✅ Polkit rules removed."
else
    echo "→ No polkit rules found to remove."
fi

# Reload udev
echo "→ Reloading udev rules..."
udevadm control --reload-rules && udevadm trigger
echo "✅ Udev rules reloaded."

# Step 6: Clean up helper scripts and cache
echo "============================================"
echo "Step 6: Cleaning up helper scripts and cache"
echo "============================================"

# Only remove the helper script if no other restricted users exist
if ! ls /etc/systemd/system/contest-restrict-*.service &>/dev/null; then
    echo "→ No other restricted users found, removing helper script..."
    rm -f "$UPDATE_SCRIPT"
    rm -rf "$IP_CACHE_DIR"
    echo "✅ Helper script and cache removed."
else
    echo "→ Other restricted users exist, keeping helper script."
fi

# Step 7: Restore user groups for device access
echo "============================================"
echo "Step 7: Restoring user permissions"
echo "============================================"

echo "→ Adding $USER back to disk and plugdev groups..."
usermod -a -G disk,plugdev "$USER" 2>/dev/null || true
echo "✅ Group memberships restored."

# Final message
echo "============================================"
echo "✅ Internet restrictions successfully removed for user $USER!"
echo "✅ USB storage restrictions removed for user $USER!"
echo "✅ All network access should now be available."
echo "============================================"
echo ""
echo "To verify restrictions are removed:"
echo "1. Log in as $USER"
echo "2. Try to access any website"
echo "3. Try to plug in a USB storage device"
echo "============================================"
