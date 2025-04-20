#!/usr/bin/env bash
# unrestrict.sh – Undo restrictions for 'participant'

set -euo pipefail

IPSET_NAME="contestwhitelist"
DNSMASQ_CONF="/etc/dnsmasq.d/contest.conf"
POLKIT_RULE="/etc/polkit-1/rules.d/10-no-mount-participant.rules"
PART_UID=$(id -u participant)

echo "[*] Removing iptables rules..."
sudo iptables -D OUTPUT -m owner --uid-owner "$PART_UID" -p udp --dport 53 -j ACCEPT || true
sudo iptables -D OUTPUT -m owner --uid-owner "$PART_UID" -m set --match-set "$IPSET_NAME" dst -j ACCEPT || true
sudo iptables -D OUTPUT -m owner --uid-owner "$PART_UID" -j DROP || true
sudo netfilter-persistent save

echo "[*] Deleting ipset and config..."
sudo ipset destroy "$IPSET_NAME" || true
sudo rm -f /etc/ipset.conf
sudo apt remove --purge -y ipset-persistent || true

echo "[*] Restoring DNS resolver..."
sudo rm -f "$DNSMASQ_CONF"
sudo systemctl restart dnsmasq
sudo sed -i 's/^DNSStubListener=no/#DNSStubListener=yes/' /etc/systemd/resolved.conf || true
sudo systemctl restart systemd-resolved || true

echo "[*] Removing Polkit restriction..."
sudo rm -f "$POLKIT_RULE"

echo "[✓] Restrictions for 'participant' have been removed."
