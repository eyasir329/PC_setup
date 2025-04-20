#!/usr/bin/env bash
# unrestrict.sh – reverse participant lockdown
set -euo pipefail

IPSET_NAME="contestwhitelist"
DNSMASQ_DROPIN="/etc/dnsmasq.d/contest.conf"
POLKIT_RULE="/etc/polkit-1/rules.d/10-no-mount-participant.rules"
PART_UID=$(id -u participant)

# 1. Remove iptables rules
iptables -D OUTPUT -m owner --uid-owner "$PART_UID" -p udp --dport 53 -j ACCEPT
iptables -D OUTPUT -m owner --uid-owner "$PART_UID" -m set --match-set "$IPSET_NAME" dst -j ACCEPT
iptables -D OUTPUT -m owner --uid-owner "$PART_UID" -j DROP
netfilter-persistent save                                           # purge rules :contentReference[oaicite:19]{index=19}

# 2. Destroy IP set & persistence
ipset destroy "$IPSET_NAME" || true                                 # remove set :contentReference[oaicite:20]{index=20}
apt-get remove --purge -y ipset-persistent
rm -f /etc/ipset.conf

# 3. Remove dnsmasq config
rm -f "$DNSMASQ_DROPIN"
systemctl restart dnsmasq                                           # default DNS

# 4. Restore systemd-resolved stub
sed -i 's/^DNSStubListener=no/#DNSStubListener=yes/' /etc/systemd/resolved.conf
systemctl restart systemd-resolved                                 # bring back stub :contentReference[oaicite:21]{index=21}

# 5. Remove Polkit rule
rm -f "$POLKIT_RULE"                                                # re‑enable mounts :contentReference[oaicite:22]{index=22}

echo "unrestrict.sh: participant account fully restored."
