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

