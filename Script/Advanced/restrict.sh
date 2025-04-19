#!/bin/bash

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

