#!/usr/bin/env bash
# restrict.sh – Lock down 'participant' user for contest use only

set -euo pipefail

# Variables
DOMAINS=(
  codeforces.com codechef.com vjudge.net atcoder.jp hackerrank.com
  hackerearth.com topcoder.com spoj.com lightoj.com
  uva.onlinejudge.org cses.fi bapsoj.com toph.co
)
IPSET_NAME="contestwhitelist"
DNSMASQ_CONF="/etc/dnsmasq.d/contest.conf"
POLKIT_RULE="/etc/polkit-1/rules.d/10-no-mount-participant.rules"
PART_UID=$(id -u participant)

echo "[*] Disabling systemd-resolved stub listener..."
sudo sed -i 's/^#DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf || \
  sudo sed -i '/^\[Resolve\]/a DNSStubListener=no' /etc/systemd/resolved.conf
sudo systemctl restart systemd-resolved || true

echo "[*] Installing required packages..."
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
  dnsmasq ipset ipset-persistent iptables-persistent netfilter-persistent

echo "[*] Creating ipset '$IPSET_NAME'..."
sudo ipset create "$IPSET_NAME" hash:ip -exist
sudo ipset save > /etc/ipset.conf

echo "[*] Writing dnsmasq domain whitelist..."
{
  echo "# Domains to whitelist via ipset"
  for domain in "${DOMAINS[@]}"; do
    echo "ipset=/$domain/$IPSET_NAME"
  done
} | sudo tee "$DNSMASQ_CONF" > /dev/null

echo "[*] Restarting dnsmasq..."
sudo systemctl restart dnsmasq

echo "[*] Adding iptables rules for user 'participant'..."
sudo iptables -I OUTPUT -m owner --uid-owner "$PART_UID" -p udp --dport 53 -j ACCEPT
sudo iptables -I OUTPUT -m owner --uid-owner "$PART_UID" -m set --match-set "$IPSET_NAME" dst -j ACCEPT
sudo iptables -I OUTPUT -m owner --uid-owner "$PART_UID" -j DROP
sudo netfilter-persistent save

echo "[*] Creating Polkit rule to block mount for 'participant'..."
sudo tee "$POLKIT_RULE" > /dev/null <<EOF
// Deny participant from mounting external storage
polkit.addRule(function(action, subject) {
  if (subject.user == "participant" &&
     action.id.startsWith("org.freedesktop.udisks2.filesystem-mount")) {
    return polkit.Result.NO;
  }
});
EOF

echo "[✓] Restriction applied to 'participant' successfully."
