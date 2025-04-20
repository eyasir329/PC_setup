#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

echo "Removing all participant restrictions..."

# Stop and disable the auto-discovery service
echo "Stopping domain discovery service..."
systemctl stop domain-discovery 2>/dev/null || true
systemctl disable domain-discovery 2>/dev/null || true
[ -f "/etc/systemd/system/domain-discovery.service" ] && rm -f /etc/systemd/system/domain-discovery.service
[ -f "/usr/local/bin/auto_domain_discovery.sh" ] && rm -f /usr/local/bin/auto_domain_discovery.sh

# Stop and disable squid proxy
echo "Stopping Squid proxy service..."
systemctl stop squid
if [ -f "/etc/squid/squid.conf.backup" ]; then
  mv /etc/squid/squid.conf.backup /etc/squid/squid.conf
  echo "Restored original Squid configuration"
else
  echo "No Squid backup found, leaving current config in place"
fi

# Remove proxy configuration for participant
echo "Removing participant proxy settings..."
[ -f "/usr/local/bin/set-participant-proxy.sh" ] && rm -f /usr/local/bin/set-participant-proxy.sh

# Check if participant user exists before trying to modify their settings
if id "participant" &>/dev/null; then
  echo "Resetting proxy settings for participant user..."
  if [ -f "/home/participant/.config/autostart/proxy-settings.desktop" ]; then
    rm -f /home/participant/.config/autostart/proxy-settings.desktop
  fi
  
  # Reset participant's proxy settings to direct connection
  sudo -u participant gsettings set org.gnome.system.proxy mode 'none' 2>/dev/null || true
else
  echo "Participant user not found, skipping user-specific settings"
fi

# Remove iptables rules
echo "Removing iptables redirection rules..."
iptables -t nat -F  # Clear all nat rules
netfilter-persistent save
echo "Firewall rules cleared"

# Remove USB storage restrictions
echo "Removing USB storage restrictions..."
if [ -f "/etc/udev/rules.d/99-block-participant-usb.rules" ]; then
  rm -f /etc/udev/rules.d/99-block-participant-usb.rules
  udevadm control --reload-rules
  echo "USB storage restrictions removed"
fi

# Remove mounting restrictions policy
echo "Removing mounting restrictions..."
if [ -f "/etc/polkit-1/localauthority/50-local.d/restrict-mounting.pkla" ]; then
  rm -f /etc/polkit-1/localauthority/50-local.d/restrict-mounting.pkla
  echo "Mounting restrictions removed"
fi

# Clean up other files
echo "Cleaning up remaining files..."
[ -f "/etc/squid/whitelist.txt" ] && rm -f /etc/squid/whitelist.txt
[ -d "/var/log/domain-discovery" ] && rm -rf /var/log/domain-discovery

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