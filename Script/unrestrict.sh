#!/usr/bin/env bash
# unrestrict.sh – reverse the participant lockdown

set -euo pipefail

IPSET_NAME="contestwhitelist"
DNSMASQ_DROPIN="/etc/dnsmasq.d/contest.conf"
POLKIT_RULE="/etc/polkit-1/rules.d/10-no-mount-participant.rules"
PART_UID=$(id -u participant)

# 1. Remove iptables rules
iptables -D OUTPUT -m owner --uid-owner "$PART_UID" -p udp --dport 53 -j ACCEPT
iptables -D OUTPUT -m owner --uid-owner "$PART_UID" -m set --match-set "$IPSET_NAME" dst -j ACCEPT
iptables -D OUTPUT -m owner --uid-owner "$PART_UID" -j DROP
netfilter-persistent save                                 # persist removal :contentReference[oaicite:12]{index=12}

# 2. Tear down IP set & persistence
ipset destroy "$IPSET_NAME" || true                        # drop the set :contentReference[oaicite:13]{index=13}
apt-get remove --purge -y ipset-persistent                 # remove persist packages
rm -f /etc/ipset.conf

# 3. Remove dnsmasq drop‑in
rm -f "$DNSMASQ_DROPIN"                                    # delete dynamic whitelist config
systemctl restart dnsmasq                                  # reload default DNS paths

# 4. Restore systemd‑resolved stub listener
sed -i 's/^DNSStubListener=no/#DNSStubListener=yes/' /etc/systemd/resolved.conf
systemctl restart systemd-resolved                         # restore stub resolver

# 5. Remove Polkit rule
rm -f "$POLKIT_RULE"                                       # participant can mount again

echo "unrestrict.sh: participant account fully restored."
