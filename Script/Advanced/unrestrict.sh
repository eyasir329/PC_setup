#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

echo "Removing all participant restrictions..."

# Stop and disable the auto-discovery service
echo "Stopping domain discovery service..."
systemctl stop domain-discovery
systemctl disable domain-discovery
rm -f /etc/systemd/system/domain-discovery.service
rm -f /usr/local/bin/auto_domain_discovery.sh

# Stop and disable squid proxy
echo "Stopping Squid proxy service..."
systemctl stop squid
if [ -f "/etc/squid/squid.conf.backup" ]; then
  mv /etc/squid/squid.conf.backup /etc/squid/squid.conf
fi

# Remove proxy configuration for participant
echo "Removing participant proxy settings..."
rm -f /usr/local/bin/set-participant-proxy.sh
if [ -f "/home/participant/.config/autostart/proxy-settings.desktop" ]; then
  rm -f /home/participant/.config/autostart/proxy-settings.desktop
fi

# Reset participant's proxy settings to direct connection
sudo -u participant gsettings set org.gnome.system.proxy mode 'none'

# Remove iptables rules
echo "Removing iptables redirection rules..."
iptables -t nat -F
netfilter-persistent save

# Remove USB storage restrictions
echo "Removing USB storage restrictions..."
rm -f /etc/udev/rules.d/99-block-participant-usb.rules
udevadm control --reload-rules

# Remove mounting restrictions policy
echo "Removing mounting restrictions..."
rm -f /etc/polkit-1/localauthority/50-local.d/restrict-mounting.pkla

# Clean up other files
echo "Cleaning up remaining files..."
rm -f /etc/squid/whitelist.txt
rm -rf /var/log/domain-discovery

# Restore permissions on mounted partitions
echo "Restoring partition access..."
partitions=$(lsblk -ln -o NAME,MOUNTPOINT | grep -v 'loop\|sr' | awk '$2 != "" && $2 != "/" && $2 != "/boot" && $2 != "swap" {print $2}')

for mount_point in $partitions; do
    if [ -d "$mount_point" ]; then
        echo "Restoring permissions for $mount_point..."
        chmod 755 "$mount_point"
    fi
done

# Restart relevant services
echo "Restarting services..."
systemctl daemon-reload

echo "=============================================================="
echo "ALL RESTRICTIONS SUCCESSFULLY REMOVED!"
echo "=============================================================="
echo ""
echo "SUMMARY:"
echo "1. Proxy service stopped and configuration removed"
echo "2. Auto-discovery service disabled and removed"
echo "3. All iptables redirection rules cleared"
echo "4. USB storage access restored for participant"
echo "5. Mounting privileges restored for participant" 
echo "6. Access to all partitions restored"
echo ""
echo "A system reboot is recommended to ensure all changes take effect."
echo "=============================================================="