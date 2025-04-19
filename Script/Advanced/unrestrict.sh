#!/bin/bash

echo "============================================"
echo "Removing Internet & Storage Restrictions for participant"
echo "============================================"

PARTICIPANT_USER="participant"

echo "1. Removing iptables restrictions..."
sudo iptables -t filter -F OUTPUT
sudo iptables -t nat -F OUTPUT

# Try to remove the custom chain
sudo iptables -D OUTPUT -m owner --uid-owner $(id -u $PARTICIPANT_USER) -j PARTICIPANT_RULES 2>/dev/null
sudo iptables -F PARTICIPANT_RULES 2>/dev/null
sudo iptables -X PARTICIPANT_RULES 2>/dev/null

echo "2. Removing proxy services..."
sudo systemctl stop tinyproxy
sudo systemctl disable tinyproxy

# Restore tinyproxy default config
sudo bash -c "cat > /etc/tinyproxy/tinyproxy.conf" <<EOF
User nobody
Group nogroup
Port 8888
Timeout 600
DefaultErrorFile "/usr/share/tinyproxy/default.html"
StatFile "/usr/share/tinyproxy/stats.html"
LogFile "/var/log/tinyproxy/tinyproxy.log"
LogLevel Info
PidFile "/var/run/tinyproxy/tinyproxy.pid"
MaxClients 100
MinSpareServers 5
MaxSpareServers 20
StartServers 10
MaxRequestsPerChild 0
ViaProxyName "tinyproxy"
ConnectPort 443
ConnectPort 80
EOF

# Delete filter file
sudo rm -f /etc/tinyproxy/filter

echo "3. Removing AppArmor profile..."
sudo rm -f /etc/apparmor.d/user.$PARTICIPANT_USER
sudo apparmor_parser -R /etc/apparmor.d/user.$PARTICIPANT_USER 2>/dev/null

echo "4. Removing storage restrictions..."
sudo rm -f /etc/udev/rules.d/99-block-usb-storage-participant.rules
sudo systemctl stop block-external-storage.service
sudo systemctl disable block-external-storage.service
sudo rm -f /etc/systemd/system/block-external-storage.service

# Unmount restricted directories
sudo umount /media 2>/dev/null
sudo umount /mnt 2>/dev/null

echo "5. Removing maintenance scripts..."
sudo systemctl stop update-allowed-ips.timer
sudo systemctl disable update-allowed-ips.timer
sudo rm -f /etc/systemd/system/update-allowed-ips.timer
sudo rm -f /etc/systemd/system/update-allowed-ips.service
sudo rm -f /usr/local/bin/update-allowed-ips.sh

echo "6. Reloading system services..."
sudo udevadm control --reload-rules
sudo udevadm trigger
sudo systemctl daemon-reload

# Save changes to iptables
sudo netfilter-persistent save

echo "✅ Internet restrictions removed."
echo "✅ Storage restrictions removed."
echo "✅ All maintenance scripts and services removed."
echo "🎯 Restrictions have been removed - a reboot is recommended for full effect."