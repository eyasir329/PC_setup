#!/bin/bash

PARTICIPANT_USER="participant"
PARTICIPANT_UID=$(id -u $PARTICIPANT_USER)

echo "🔓 Starting system unlock..."

echo "🧹 Step 1: Removing Squid proxy..."
systemctl stop squid
apt purge -y squid
rm -f /etc/squid/squid.conf

echo "📡 Step 2: Restoring /etc/hosts..."
if ls /etc/hosts.backup.* 1>/dev/null 2>&1; then
    LATEST_BACKUP=$(ls -t /etc/hosts.backup.* | head -n 1)
    cp "$LATEST_BACKUP" /etc/hosts
    echo "[✓] Restored from $LATEST_BACKUP"
else
    echo "[!] No backup hosts file found, skipping restore"
fi

echo "🔥 Step 3: Removing iptables restrictions..."
iptables -D OUTPUT -m owner --uid-owner $PARTICIPANT_UID -p tcp --dport 3128 -j ACCEPT 2>/dev/null
iptables -D OUTPUT -m owner --uid-owner $PARTICIPANT_UID -p udp --dport 53 -j ACCEPT 2>/dev/null
iptables -D OUTPUT -m owner --uid-owner $PARTICIPANT_UID -o lo -j ACCEPT 2>/dev/null
iptables -D OUTPUT -m owner --uid-owner $PARTICIPANT_UID -j REJECT 2>/dev/null
netfilter-persistent save

echo "🌍 Step 4: Removing proxy environment variables..."
sed -i '/http_proxy/d' "/home/$PARTICIPANT_USER/.bashrc"
sed -i '/https_proxy/d' "/home/$PARTICIPANT_USER/.bashrc"
chown $PARTICIPANT_USER:$PARTICIPANT_USER "/home/$PARTICIPANT_USER/.bashrc"

echo "🔌 Step 5: Re-enabling USB devices..."
rm -f /etc/udev/rules.d/100-usbblock.rules
udevadm control --reload-rules
udevadm trigger

echo "💽 Step 6: Re-enabling external device mounting for participant..."
rm -f /etc/polkit-1/localauthority/50-local.d/10-usb-mount.pkla

echo "🧯 Step 7: Unlocking restricted partitions..."
for part in $(lsblk -ln -o NAME | grep -v "$(df / | tail -1 | awk '{print $1}' | sed 's|/dev/||')"); do
    chmod 666 "/dev/$part" 2>/dev/null
done

echo "⏰ Step 8: Disabling /etc/hosts refresh timer..."
systemctl disable --now hosts-whitelist.timer 2>/dev/null
rm -f /etc/systemd/system/hosts-whitelist.timer
rm -f /etc/systemd/system/hosts-whitelist.service
rm -f /usr/local/bin/update-whitelist-hosts.sh
systemctl daemon-reload

echo "✅ System successfully unrestricted."
