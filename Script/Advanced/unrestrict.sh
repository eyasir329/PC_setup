#!/bin/bash

echo "============================================"
echo "Removing Internet Access and Storage Device Restriction for participant"
echo "============================================"

PARTICIPANT_USER="participant"
SQUID_CONF_FILE="/etc/squid/squid.conf"
SQUID_ALLOWED_DOMAINS_FILE="/etc/squid/allowed_domains.txt"
UDEV_RULE_FILE="/etc/udev/rules.d/99-block-usb-storage-participant.rules"

# 1. Stop and disable all services
echo "1. Stopping and removing services..."
# Stop and disable the participant network service
sudo systemctl stop participant-network.service 2>/dev/null
sudo systemctl disable participant-network.service 2>/dev/null
sudo rm -f /etc/systemd/system/participant-network.service

# Stop and disable the apply namespace service
sudo systemctl stop apply-participant-namespace.service 2>/dev/null
sudo systemctl disable apply-participant-namespace.service 2>/dev/null
sudo rm -f /etc/systemd/system/apply-participant-namespace.service

# 2. Remove the network namespace and scripts
echo "2. Removing network namespace and configuration scripts..."
sudo ip netns del participant_ns 2>/dev/null
sudo rm -f /usr/local/bin/setup-participant-net.sh
sudo rm -f /usr/local/bin/mark-participant-login.sh
sudo rm -f /usr/local/bin/apply-participant-ns.sh
sudo rm -f /usr/local/bin/participant-firewall.sh
sudo rm -f /home/$PARTICIPANT_USER/.participant_net.sh

# 3. Clean up PAM configuration
echo "3. Removing PAM configuration..."
for service in login gdm lightdm sddm common-session; do
    if [ -f "/etc/pam.d/$service" ]; then
        sudo sed -i '/mark-participant-login.sh/d' "/etc/pam.d/$service"
    fi
done

# Remove the line from participant's profile
if [ -f "/home/$PARTICIPANT_USER/.profile" ]; then
    sudo sed -i '/source ~\/.participant_net.sh/d' /home/$PARTICIPANT_USER/.profile
fi

# 4. Remove Squid configuration
echo "4. Removing Squid proxy configuration..."
sudo systemctl stop squid
sudo systemctl disable squid

# Restore original Squid configuration
if [ -f "${SQUID_CONF_FILE}.backup" ]; then
    sudo cp "${SQUID_CONF_FILE}.backup" "$SQUID_CONF_FILE"
    sudo rm -f "${SQUID_CONF_FILE}.backup"
else
    echo "No Squid backup found. Proceeding with default configuration removal."
fi

# Remove allowed domains file
sudo rm -f $SQUID_ALLOWED_DOMAINS_FILE

# Remove SSL cert directory
sudo rm -rf /var/lib/squid/ssl_cert

# 5. Clean up firewall rules
echo "5. Cleaning up iptables rules..."
# Clean NAT table
sudo iptables -t nat -F PREROUTING
sudo iptables -t nat -D POSTROUTING -s 10.0.0.0/24 -j MASQUERADE 2>/dev/null

# Reset default policies in case they were changed
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT

# 6. Remove virtual interfaces
echo "6. Removing virtual interfaces..."
sudo ip link delete veth0 2>/dev/null

# 7. Remove AppArmor profile
echo "7. Removing AppArmor profile for $PARTICIPANT_USER..."
sudo rm -f /etc/apparmor.d/user.$PARTICIPANT_USER
sudo apparmor_parser -R /etc/apparmor.d/user.$PARTICIPANT_USER 2>/dev/null

# 8. Remove udev rules for USB storage
echo "8. Removing USB storage restrictions..."
sudo rm -f $UDEV_RULE_FILE

# 9. Remove mount units and restrictions
echo "9. Removing mount restrictions..."
sudo systemctl stop media.mount 2>/dev/null
sudo systemctl disable media.mount 2>/dev/null
sudo rm -f /etc/systemd/system/media.mount

# 10. Remove fstab entries
echo "10. Cleaning fstab entries..."
sudo sed -i '/Restrict access to external drives/d' /etc/fstab
sudo sed -i '/tmpfs.*\/media.*tmpfs/d' /etc/fstab
sudo sed -i '/tmpfs.*\/mnt.*tmpfs/d' /etc/fstab

# 11. Remove sudoers entry
echo "11. Removing sudoers configuration..."
sudo rm -f /etc/sudoers.d/participant-netns

# 12. Clean up log directories
echo "12. Cleaning up log files..."
sudo rm -rf /var/log/participant-net
sudo rm -rf /run/participant-net

# 13. Apply all changes
echo "13. Applying changes..."
sudo udevadm control --reload-rules
sudo udevadm trigger
sudo systemctl daemon-reload

echo "✅ Network namespace isolation removed."
echo "✅ Squid proxy configuration restored."
echo "✅ PAM configuration restored."
echo "✅ Storage access restrictions removed."
echo "✅ All user restrictions have been lifted for $PARTICIPANT_USER."
echo "🎯 System restored to normal operation. Please reboot to ensure all changes take effect."