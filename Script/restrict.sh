#!/usr/bin/env bash
# restrict.sh – per-user contest lockdown for "participant"
set -euo pipefail

# 1. Variables
DOMAINS=(codeforces.com codechef.com vjudge.net atcoder.jp hackerrank.com hackerearth.com topcoder.com spoj.com lightoj.com uva.onlinejudge.org cses.fi bapsoj.com toph.co)
IPSET_NAME="contestwhitelist"
DNSMASQ_DROPIN="/etc/dnsmasq.d/contest.conf"
POLKIT_RULE="/etc/polkit-1/rules.d/10-no-mount-participant.rules"
PART_UID=$(id -u participant)

# 2. Disable systemd-resolved stub listener
if grep -q '^#DNSStubListener=' /etc/systemd/resolved.conf; then
  sed -i 's/^#DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
else
  sed -i '/^\[Resolve\]/a DNSStubListener=no' /etc/systemd/resolved.conf
fi
systemctl restart systemd-resolved                                 # free port 53 :contentReference[oaicite:13]{index=13}

# 3. Install packages
apt update
DEBIAN_FRONTEND=noninteractive apt install -y dnsmasq ipset iptables-persistent ipset-persistent netfilter-persistent

# 4. Prepare IP set
ipset create "$IPSET_NAME" hash:ip -exist                           # create if missing :contentReference[oaicite:14]{index=14}
ipset save > /etc/ipset.conf                                        # persist :contentReference[oaicite:15]{index=15}

# 5. Configure dnsmasq for dynamic whitelisting
cat > "$DNSMASQ_DROPIN" <<EOF
# contest domains → populate $IPSET_NAME
EOF
for d in "${DOMAINS[@]}"; do
  echo "ipset=/${d}/${IPSET_NAME}" >> "$DNSMASQ_DROPIN"             # dnsmasq ipset syntax :contentReference[oaicite:16]{index=16}
done
systemctl restart dnsmasq                                           # load directives

# 6. Apply per-UID firewall
iptables -I OUTPUT -m owner --uid-owner "$PART_UID" -p udp --dport 53 -j ACCEPT
iptables -I OUTPUT -m owner --uid-owner "$PART_UID" -m set --match-set "$IPSET_NAME" dst -j ACCEPT
iptables -I OUTPUT -m owner --uid-owner "$PART_UID" -j DROP
netfilter-persistent save                                          # save rules :contentReference[oaicite:17]{index=17}

# 7. Polkit rule to block mounts
cat > "$POLKIT_RULE" <<'EOF'
// Deny participant any udisks2 mount action
polkit.addRule(function(action, subject) {
  if (subject.user == "participant" &&
     (action.id.startsWith("org.freedesktop.udisks2.filesystem-mount"))) {
    return polkit.Result.NO;
  }
});
EOF                                                                 # deny mounts :contentReference[oaicite:18]{index=18}

echo "restrict.sh: lockdown applied successfully."
