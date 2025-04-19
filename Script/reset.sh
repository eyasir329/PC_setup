#!/bin/bash

echo "============================================"
echo "Removing Internet Access and Storage Device Restrictions"
echo "============================================"

# Define the participant's username
PARTICIPANT_USER="participant"

# Remove iptables rules for the participant user
echo "Removing iptables rules for participant..."
sudo iptables -D OUTPUT -m owner --uid-owner $PARTICIPANT_USER -j DROP
sudo iptables -D OUTPUT -m owner --uid-owner $PARTICIPANT_USER -d 127.0.0.1 -j ACCEPT

# Flush all iptables rules and set default policies to ACCEPT (reverting to default behavior)
echo "Restoring default iptables policies..."
sudo iptables -F OUTPUT
sudo iptables -P OUTPUT ACCEPT

# Resolve and allow access for all previously allowed domains (using dnsmasq)
ALLOWED_DOMAINS=(
    "codeforces.com" "codechef.com" "vjudge.net" "atcoder.jp"
    "hackerrank.com" "hackerearth.com" "topcoder.com"
    "spoj.com" "lightoj.com" "uva.onlinejudge.org"
    "cses.fi" "bapsoj.com" "toph.co"
)

for domain in "${ALLOWED_DOMAINS[@]}"; do
    echo "→ Resolving $domain using local DNS..."

    # Resolve domain via local DNS (dnsmasq)
    IP_LIST_IPV4=$(dig +short $domain)
    
    if [ -z "$IP_LIST_IPV4" ]; then
        echo "❌ Could not resolve $domain — skipping."
        continue
    fi

    # Allow access for each resolved IPv4 address
    for ip in $IP_LIST_IPV4; do
        echo "→ Allowing participant to access $domain (IPv4: $ip)..."
        sudo iptables -A OUTPUT -m owner --uid-owner $PARTICIPANT_USER -d "$ip" -j ACCEPT
    done

    echo "✅ Allowed $domain (IPv4: $IP_LIST_IPV4)"
done

# Remove the udev rule blocking storage devices for the participant
echo "Removing udev storage device blocking rule for participant..."
sudo rm -f /etc/udev/rules.d/99-block-storage-participant.rules
sudo udevadm control --reload-rules

# Save the changes to iptables
echo "Saving iptables rules after removing restrictions..."
sudo netfilter-persistent save
sudo netfilter-persistent reload

echo "============================================"
echo "✅ Internet access and storage device restrictions removed for participant."
echo "============================================"

echo "============================================"
echo "Resetting participant account to default..."
echo "============================================"

# 1. Ensure backup exists
if [ ! -d /opt/participant_backup ]; then
    echo "❌ Backup directory /opt/participant_backup does not exist. Cannot reset!"
    exit 1
fi

# 2. Ensure participant is logged out
if pgrep -u participant > /dev/null; then
    echo "❌ Participant is currently logged in. Please log them out before resetting."
    exit 1
fi

# 3. Delete current participant home
echo "Deleting current home directory files (except backup files)..."
sudo rm -rf /home/participant/*
if [ $? -ne 0 ]; then
    echo "❌ Failed to delete /home/participant/"
    exit 1
fi

# 4. Restore backup
echo "Restoring from backup..."
sudo rsync -aAX /opt/participant_backup/ /home/participant/
if [ $? -eq 0 ]; then
    echo "✅ Home directory restored."
else
    echo "❌ Error restoring from backup!"
    exit 1
fi

# 5. Fix ownership
echo "Fixing permissions..."
sudo chown -R participant:participant /home/participant
if [ $? -eq 0 ]; then
    echo "✅ Permissions fixed."
else
    echo "❌ Failed to fix permissions."
    exit 1
fi

# 6. Clean sensitive files
echo "Cleaning sensitive files (templates, code, etc.)..."
find /home/participant/ -type f -name "*.tmp" -exec rm -f {} \;
find /home/participant/ -type f -name "*.bak" -exec rm -f {} \;
find /home/participant/ -type f -name "*.*~" -exec rm -f {} \;

echo "Cleaning up config/cache folders..."
sudo rm -rf /home/participant/.cache/*
sudo rm -rf /home/participant/.local/share/*
sudo rm -rf /home/participant/.config/*

# 7. Verify essential software is intact
echo "Verifying that no essential software has been removed..."
sudo apt list --installed | grep -E "python3|git|vim|gcc|build-essential|openjdk-17-jdk|codeblocks|sublime-text|google-chrome-stable|firefox|code" > /dev/null
if [ $? -eq 0 ]; then
    echo "✅ Essential software is intact."
else
    echo "❌ Some essential software is missing or has been removed."
    exit 1
fi

# 8. Set permissions
echo "Setting permissions for participant's home..."
sudo chown -R participant:participant /home/participant
sudo chmod -R u+rwX /home/participant

# 9. Install VS Code Extensions and Browser Add-ons
echo "============================================"
echo "Starting Installing VS Code Extensions"
echo "============================================"

echo "→ Installing VS Code extensions for 'participant'..."

EXTENSIONS=(
    "ms-vscode.cpptools"
    "ms-python.python"
    "redhat.java"
)

for ext in "${EXTENSIONS[@]}"; do
    echo "→ Installing extension: $ext for participant"
    sudo -u participant code --install-extension "$ext" --force
    if [ $? -eq 0 ]; then
        echo "✅ Installed $ext successfully."
    else
        echo "❌ Failed to install $ext." >&2
        exit 1
    fi
done

echo "============================================"
echo "✅ VS Code extensions installed."
echo "============================================"


echo "============================================"
echo "Starting Internet Access and Storage Device Restriction"
echo "============================================"

# Define the participant's username
PARTICIPANT_USER="participant"

# List of allowed domains
ALLOWED_DOMAINS=(
    "codeforces.com" "codechef.com" "vjudge.net" "atcoder.jp"
    "hackerrank.com" "hackerearth.com" "topcoder.com"
    "spoj.com" "lightoj.com" "uva.onlinejudge.org"
    "cses.fi" "bapsoj.com" "toph.co"
)

# Flush existing OUTPUT chain rules and set default policy to DROP
# Only apply this to the participant user by using the --uid-owner option
echo "Flushing existing iptables rules and setting default policy to DROP..."
sudo iptables -F OUTPUT
sudo iptables -P OUTPUT ACCEPT  # Allow all users to use the network by default

# Set the policy to DROP for the participant user
echo "Applying DROP policy for participant..."
sudo iptables -A OUTPUT -m owner --uid-owner $PARTICIPANT_USER -j DROP

# Allow localhost communication (e.g., localhost) for the participant
echo "Allowing localhost communication for the participant..."
sudo iptables -A OUTPUT -m owner --uid-owner $PARTICIPANT_USER -d 127.0.0.1 -j ACCEPT

# Resolve and allow access for specific allowed domains (using dnsmasq)
for domain in "${ALLOWED_DOMAINS[@]}"; do
    echo "→ Resolving $domain using local DNS..."

    # Resolve domain via local DNS (dnsmasq)
    IP_LIST_IPV4=$(dig +short $domain)
    
    if [ -z "$IP_LIST_IPV4" ]; then
        echo "❌ Could not resolve $domain — skipping."
        continue
    fi

    # Allow access for each resolved IPv4 address
    for ip in $IP_LIST_IPV4; do
        echo "→ Allowing participant to access $domain (IPv4: $ip)..."
        sudo iptables -A OUTPUT -m owner --uid-owner $PARTICIPANT_USER -d "$ip" -j ACCEPT
    done

    echo "✅ Allowed $domain (IPv4: $IP_LIST_IPV4)"
done

# Block storage devices (USB, SSD, CD, etc.), but allow keyboard and mouse for participant only
echo "Blocking access to storage devices (USB, SSD, CD, etc.) for participant..."
echo 'SUBSYSTEM=="block", ACTION=="add", ATTRS{idVendor}!="0781", ATTRS{idProduct}!="5591", RUN+="/usr/bin/logger Storage device blocked for participant"' | sudo tee /etc/udev/rules.d/99-block-storage-participant.rules
sudo udevadm control --reload-rules

# Save iptables rules to ensure persistence after reboot
echo "Saving iptables rules to ensure persistence after reboot..."
sudo apt-get install iptables-persistent
sudo netfilter-persistent save
sudo netfilter-persistent reload

echo "============================================"
echo "✅ Internet access and storage device restrictions applied for participant."
echo "============================================"


echo "============================================"
echo "✅ Participant account has been reset successfully."
echo "============================================"

