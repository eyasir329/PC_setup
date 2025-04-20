#!/bin/bash

# Run this as root
echo "🔓 Starting system unrestriction..."

PARTICIPANT_USER="participant"
PARTICIPANT_UID=$(id -u $PARTICIPANT_USER)
LOCAL_PROXY_PORT=3128
BASHRC="/home/$PARTICIPANT_USER/.bashrc"

# -------------------------------
# 1. Restore original /etc/hosts
# -------------------------------
BACKUP_HOST=$(ls -t /etc/hosts.backup.* 2>/dev/null | head -n 1)
if [ -f "$BACKUP_HOST" ]; then
    cp "$BACKUP_HOST" /etc/hosts
    echo "✅ Restored /etc/hosts from backup: $BACKUP_HOST"
else
    echo "⚠️  No /etc/hosts backup found."
fi

# -----------------------------------
# 2. Remove proxy from participant’s bashrc
# -----------------------------------
if grep -q "http_proxy" "$BASHRC"; then
    sed -i '/http_proxy/d' "$BASHRC"
    sed -i '/https_proxy/d' "$BASHRC"
    echo "✅ Removed proxy settings from $BASHRC"
fi

# -------------------------
# 3. Remove iptables rules
# -------------------------
iptables -D OUTPUT -m owner --uid-owner $PARTICIPANT_UID -p tcp --dport $LOCAL_PROXY_PORT -j ACCEPT 2>/dev/null
iptables -D OUTPUT -m owner --uid-owner $PARTICIPANT_UID -p udp --dport 53 -j ACCEPT 2>/dev/null
iptables -D OUTPUT -m owner --uid-owner $PARTICIPANT_UID -o lo -j ACCEPT 2>/dev/null
iptables -D OUTPUT -m owner --uid-owner $PARTICIPANT_UID -j REJECT 2>/dev/null
netfilter-persistent save
echo "✅ iptables rules removed and saved."

# -------------------------------
# 4. Remove Squid proxy config
# -------------------------------
systemctl stop squid
systemctl disable squid
rm -f /etc/squid/squid.conf
echo "✅ Squid proxy disabled and config removed."

# ---------------------------------------------------
# 5. Remove systemd timer and script for /etc/hosts
# ---------------------------------------------------
systemctl stop hosts-whitelist.timer
systemctl disable hosts-whitelist.timer
rm -f /etc/systemd/system/hosts-whitelist.{timer,service}
rm -f /usr/local/bin/update-whitelist-hosts.sh
systemctl daemon-reload
echo "✅ Removed hosts whitelist timer and updater script."

# -----------------------------
# 6. Re-enable USB permissions
# -----------------------------
UDEV_RULE="/etc/udev/rules.d/100-usbblock.rules"
if [ -f "$UDEV_RULE" ]; then
    rm -f "$UDEV_RULE"
    udevadm control --reload-rules
    udevadm trigger
    echo "✅ USB block rule removed."
fi

# -------------------------------
# 7. Remove Polkit block for USB
# -------------------------------
POLKIT_RULE="/etc/polkit-1/localauthority/50-local.d/10-usb-mount.pkla"
if [ -f "$POLKIT_RULE" ]; then
    rm -f "$POLKIT_RULE"
    echo "✅ Polkit USB mount rule removed."
fi

# ----------------------------------------------------
# 8. Re-enable access to non-root internal partitions
# ----------------------------------------------------
echo "🔄 Restoring access to internal partitions..."
while read -r part mountpoint; do
    if [[ "$mountpoint" != "/" && -z "$mountpoint" ]]; then
        chmod 666 "$part" 2>/dev/null
        echo "✅ Re-permissioned $part"
    fi
done < <(lsblk -ln -o NAME,MOUNTPOINT | awk '{print "/dev/" $1, $2}')

# -----------------------
# 9. Final confirmation
# -----------------------
echo "✅ System is unrestricted. All restrictions have been lifted."
