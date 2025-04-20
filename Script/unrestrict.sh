#!/bin/bash

# IUPC Participant Unrestrictions Script
# This script removes the restrictions set by restrict.sh

# Exit on any error
set -e

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Constants
PARTICIPANT_USER="participant"
PARTICIPANT_UID=$(id -u $PARTICIPANT_USER 2>/dev/null || echo "")
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if restrictions are active
if [ ! -f /etc/iupc-restrictions-active ]; then
    echo "Restrictions do not appear to be active. Continuing anyway..."
fi

echo "=== Removing IUPC restrictions ==="

# ==========================================
# REMOVE INTERNET RESTRICTIONS
# ==========================================
echo "Removing internet restrictions..."

# Remove iptables rules
iptables -t mangle -D OUTPUT -m owner --uid-owner $PARTICIPANT_UID -j PARTICIPANT_RULES 2>/dev/null || true
iptables -t mangle -F PARTICIPANT_RULES 2>/dev/null || true
iptables -t mangle -X PARTICIPANT_RULES 2>/dev/null || true

# Also clean up IPv6 rules if they exist
if command_exists ip6tables; then
    ip6tables -t mangle -D OUTPUT -m owner --uid-owner $PARTICIPANT_UID -j PARTICIPANT_RULES 2>/dev/null || true
    ip6tables -t mangle -F PARTICIPANT_RULES 2>/dev/null || true
    ip6tables -t mangle -X PARTICIPANT_RULES 2>/dev/null || true
fi

# Save the iptables rules
if command_exists netfilter-persistent; then
    netfilter-persistent save
else
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    [ -x "$(command -v ip6tables-save)" ] && ip6tables-save > /etc/iptables/rules.v6
fi

# ==========================================
# REMOVE STORAGE DEVICE RESTRICTIONS
# ==========================================
echo "Removing storage device restrictions..."

# Remove udev rules
if [ -f /etc/udev/rules.d/99-iupc-restrictions.rules ]; then
    rm -f /etc/udev/rules.d/99-iupc-restrictions.rules
    udevadm control --reload-rules
    udevadm trigger
fi

# Remove AppArmor profile
if [ -f /etc/apparmor.d/usr.local.bin.participant-restricted ]; then
    if command_exists apparmor_parser; then
        apparmor_parser -R /etc/apparmor.d/usr.local.bin.participant-restricted 2>/dev/null || true
    fi
    rm -f /etc/apparmor.d/usr.local.bin.participant-restricted
fi

# Remove PAM configuration
if [ -f /usr/local/bin/apply-aa-profile ]; then
    rm -f /usr/local/bin/apply-aa-profile
    sed -i '/participant-restricted/d' /etc/pam.d/common-session 2>/dev/null || true
fi

# Restore fstab if backup exists
if [ -f /etc/fstab.backup ]; then
    cp /etc/fstab.backup /etc/fstab
    echo "Restored original fstab configuration"
else
    echo "No fstab backup found, manually restoring defaults"
    sed -i 's/defaults,noauto/defaults/g' /etc/fstab
fi

# ==========================================
# REMOVE SYSTEMD SERVICES
# ==========================================
echo "Removing systemd services..."

# Stop and disable services
systemctl stop iupc-restrictions.service 2>/dev/null || true
systemctl stop iupc-restrictions.timer 2>/dev/null || true
systemctl disable iupc-restrictions.service 2>/dev/null || true
systemctl disable iupc-restrictions.timer 2>/dev/null || true

# Remove service files
rm -f /etc/systemd/system/iupc-restrictions.service
rm -f /etc/systemd/system/iupc-restrictions.timer

# Reload systemd
systemctl daemon-reload

# Remove the marker file
rm -f /etc/iupc-restrictions-active

# ==========================================
# VERIFY RESTRICTIONS REMOVED
# ==========================================
echo "Verifying restrictions have been removed..."

# Test DNS access (should work now)
if command_exists host; then
    su - $PARTICIPANT_USER -c "host facebook.com" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "✓ DNS blocking successfully removed"
    else
        echo "✗ DNS blocking may still be active. Manual verification required."
    fi
fi

echo "=== IUPC restrictions removal complete ==="
echo "Restrictions have been removed for user: $PARTICIPANT_USER"
echo ""
echo "To re-apply restrictions, run: $SCRIPT_DIR/restrict.sh"