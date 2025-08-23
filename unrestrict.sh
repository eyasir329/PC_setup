#!/usr/bin/env bash
set -euo pipefail

# Contest Environment Unrestriction Script
# Removes all restrictions applied by restrict.sh
# Restores full internet + USB access for the participant user

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
echo "Started at: $(date)"
echo "============================================"

[[ $EUID -eq 0 ]] || { echo "❌ Must run as root"; exit 1; }
id "$RESTRICT_USER" >/dev/null 2>&1 || { echo "❌ User '$RESTRICT_USER' not found"; exit 1; }

# --- Step 1: Remove systemd persistence --------------------------------------
echo "→ Stopping and disabling systemd unit/timer..."
systemctl stop "$CONTEST_SERVICE.service" 2>/dev/null || true
systemctl stop "$CONTEST_SERVICE.timer" 2>/dev/null || true
systemctl disable "$CONTEST_SERVICE.service" 2>/dev/null || true
systemctl disable "$CONTEST_SERVICE.timer" 2>/dev/null || true
systemctl mask "$CONTEST_SERVICE.service" 2>/dev/null || true
systemctl mask "$CONTEST_SERVICE.timer" 2>/dev/null || true

echo "→ Removing systemd service files..."
rm -f "/etc/systemd/system/$CONTEST_SERVICE.service" "/etc/systemd/system/$CONTEST_SERVICE.timer" 2>/dev/null || true
systemctl daemon-reload
systemctl reset-failed

echo "✅ Systemd unit/timer removed"

# --- Step 2: Remove firewall rules -------------------------------------------
CHAIN_OUT="${CHAIN_PREFIX}_${RESTRICT_USER^^}_OUT"
USER_UID=$(id -u "$RESTRICT_USER")

echo "→ Removing firewall rules for UID $USER_UID..."
# Remove OUTPUT hooks (repeat until absent)
while iptables  -C OUTPUT -m owner --uid-owner "$USER_UID" -j "$CHAIN_OUT" 2>/dev/null; do
  iptables  -D OUTPUT -m owner --uid-owner "$USER_UID" -j "$CHAIN_OUT" || true
done
while ip6tables -C OUTPUT -m owner --uid-owner "$USER_UID" -j "$CHAIN_OUT" 2>/dev/null; do
  ip6tables -D OUTPUT -m owner --uid-owner "$USER_UID" -j "$CHAIN_OUT" || true
done

# Flush/delete the per-user chains
iptables  -F "$CHAIN_OUT" 2>/dev/null || true
iptables  -X "$CHAIN_OUT" 2>/dev/null || true
ip6tables -F "$CHAIN_OUT" 2>/dev/null || true
ip6tables -X "$CHAIN_OUT" 2>/dev/null || true

echo "✅ Firewall rules and chains removed"

# --- Step 3: Remove USB restrictions ----------------------------------------
echo "→ Removing USB restrictions..."
rm -f /etc/modprobe.d/contest-usb-storage-blacklist.conf 2>/dev/null || true
rm -f /etc/polkit-1/rules.d/99-contest-block-mount.rules 2>/dev/null || true
rm -f /etc/udev/rules.d/99-contest-block-usb.rules 2>/dev/null || true

modprobe usb_storage 2>/dev/null || true
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger 2>/dev/null || true

echo "✅ USB restrictions removed"

# --- Step 4: Cleanup caches --------------------------------------------------
echo "→ Cleaning caches..."
rm -f "$CONFIG_DIR/${RESTRICT_USER}_domains_cache.txt" "$CONFIG_DIR/${RESTRICT_USER}_ip_cache.txt" 2>/dev/null || true

# Ask about global config removal
echo ""
echo "Whitelist file:   $WHITELIST_FILE"
echo "Dependencies:     $DEPENDENCIES_FILE"
echo "Helper script:    $HELPER_SCRIPT"
read -p "Do you want to remove global config + helper too? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
  rm -f "$WHITELIST_FILE" "$DEPENDENCIES_FILE" "$HELPER_SCRIPT" 2>/dev/null || true
  rmdir "$CONFIG_DIR" 2>/dev/null || true
  echo "✅ Global config + helper removed"
else
  echo "✅ Global config preserved"
fi

# --- Step 5: Verification ----------------------------------------------------
echo "============================================"
iptables -L | grep -q "$CHAIN_PREFIX" && echo "⚠️ IPv4 chains still exist" || echo "✅ No IPv4 chains"
ip6tables -L | grep -q "$CHAIN_PREFIX" && echo "⚠️ IPv6 chains still exist" || echo "✅ No IPv6 chains"
systemctl list-units --all | grep -q "$CONTEST_SERVICE" && echo "⚠️ Systemd entries remain" || echo "✅ No systemd entries"
[[ -f /etc/modprobe.d/contest-usb-storage-blacklist.conf ]] && echo "⚠️ USB blacklist remains" || echo "✅ No USB blacklist"
[[ -f /etc/polkit-1/rules.d/99-contest-block-mount.rules ]] && echo "⚠️ Polkit block remains" || echo "✅ No Polkit restrictions"
[[ -f /etc/udev/rules.d/99-contest-block-usb.rules ]] && echo "⚠️ Udev USB rule remains" || echo "✅ No Udev USB rule"
echo "============================================"
echo "✅ Contest Environment Unrestriction Complete"
echo "User:        $RESTRICT_USER"
echo "Completed at: $(date)"
echo "============================================"
