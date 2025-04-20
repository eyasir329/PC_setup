#!/usr/bin/env bash
# restrict.sh – per-user contest lockdown for "participant"

set -euo pipefail

# 1. Variables
DOMAINS=(
  codeforces.com
  codechef.com
  vjudge.net
  atcoder.jp
  hackerrank.com
  hackerearth.com
  topcoder.com
  spoj.com
  lightoj.com
  uva.onlinejudge.org
  cses.fi
  bapsoj.com
  toph.co
)
IPSET_NAME="contestwhitelist"
DNSMASQ_DROPIN="/etc/dnsmasq.d/contest.conf"
POLKIT_RULE="/etc/polkit-1/rules.d/10-no-mount-participant.rules"
PART_UID=$(id -u participant)  # resolves participant’s UID at runtime

# 2. Disable systemd‑resolved stub listener so dnsmasq can bind port 53
if grep -q '^#DNSStubListener=' /etc/systemd/resolved.conf; then
  sed -i 's/^#DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
else
  sed -i '/^\[Resolve\]/a DNSStubListener=no' /etc/systemd/resolved.conf
fi
systemctl restart systemd-resolved                      # persist stub‑listener off :contentReference[oaicite:0]{index=0}

# 3. Install prerequisites
apt update
DEBIAN_FRONTEND=noninteractive apt install -y \
  dnsmasq \
  ipset \
  iptables-persistent \
  ipset-persistent \
  netfilter-persistent

# 4. Create & persist IP set
ipset create "$IPSET_NAME" hash:ip -exist                # pre‑create set :contentReference[oaicite:1]{index=1}
ipset save > /etc/ipset.conf                             # for restore by ipset-persistent :contentReference[oaicite:2]{index=2}

# 5. Configure dnsmasq drop‑in for dynamic whitelisting
cat > "$DNSMASQ_DROPIN" <<EOF
# contest domains → add resolved IPs to $IPSET_NAME
EOF
for d in "${DOMAINS[@]}"; do
  echo "ipset=/${d}/${IPSET_NAME}" >> "$DNSMASQ_DROPIN"   # dnsmasq --ipset syntax :contentReference[oaicite:3]{index=3}
done
systemctl restart dnsmasq                                # reload with IP‑set directives :contentReference[oaicite:4]{index=4}

# 6. Apply iptables rules for participant
iptables -I OUTPUT -m owner --uid-owner "$PART_UID" -p udp --dport 53 -j ACCEPT
iptables -I OUTPUT -m owner --uid-owner "$PART_UID" -m set --match-set "$IPSET_NAME" dst -j ACCEPT
iptables -I OUTPUT -m owner --uid-owner "$PART_UID" -j DROP
netfilter-persistent save                                 # save to /etc/iptables/rules.v4 :contentReference[oaicite:5]{index=5}

# 7. Deny mounting via Polkit for participant
cat > "$POLKIT_RULE" <<'EOF'
// Deny participant any udisks2 mount action
polkit.addRule(function(action, subject) {
  if (subject.user == "participant" &&
     (action.id == "org.freedesktop.udisks2.filesystem-mount" ||
      action.id == "org.freedesktop.udisks2.filesystem-mount-system" ||
      action.id == "org.freedesktop.udisks2.filesystem-mount-other-seat")) {
    return polkit.Result.NO;
  }
});
EOF                                                        # Polkit JS rule :contentReference[oaicite:6]{index=6}

echo "restrict.sh: lockdown in place (participant only sees whitelisted domains, cannot mount disks)."
