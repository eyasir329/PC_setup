#!/bin/bash

echo "============================================"
echo "Reverting Internet Access and Storage Device Restrictions"
echo "============================================"

# Define the participant's username
PARTICIPANT_USER="participant"

# Remove Squid configuration
echo "Removing Squid configuration for domain-based access control..."
sudo rm -f /etc/squid/squid.conf

# Reinstall the original Squid configuration
echo "Restoring the original Squid configuration..."
sudo cp /etc/squid/squid.conf.bak /etc/squid/squid.conf

# Restart Squid to apply the original config
sudo systemctl restart squid

# Remove the udev rule for blocking storage devices for participant
echo "Removing udev rule for blocking storage devices for participant..."
sudo rm -f /etc/udev/rules.d/99-block-storage-participant.rules

# Reload udev rules to apply the changes
sudo udevadm control --reload-rules

# Remove Squid package if no longer needed
echo "Uninstalling Squid..."
sudo apt-get remove --purge squid -y
sudo apt-get autoremove -y

echo "============================================"
echo "✅ Internet access and storage device restrictions have been reverted."
echo "============================================"

