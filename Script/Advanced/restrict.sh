#!/bin/bash

# Run this as root

echo "🔐 Starting system lockdown..."

PARTICIPANT_USER="participant"
PARTICIPANT_UID=$(id -u $PARTICIPANT_USER)

ALLOWED_DOMAINS=(
    "codeforces.com"
    "codechef.com"
    "vjudge.net"
    "atcoder.jp"
    "hackerrank.com"
    "hackerearth.com"
    "topcoder.com"
    "spoj.com"
    "lightoj.com"
    "uva.onlinejudge.org"
    "cses.fi"
    "bapsoj.com"
    "toph.co"
)

LOCAL_PROXY_PORT=3128

echo "🌐 Step 1: Installing required packages..."
apt update
apt install -y squid dnsutils iptables-persistent

echo "🛡️ Step 2: Setting up Squid proxy with whitelisted domains..."
cat > /etc/squid/squid.conf <<EOF
http_port $LOCAL_PROXY_PORT
acl allowed_sites dstdomain ${ALLOWED_DOMAINS[@]/#/.}
http_access allow allowed_sites
http_access deny all
EOF
systemctl restart squid

echo "📡 Step 3: Creating initial /etc/hosts entries..."
cp /etc/hosts /etc/hosts.backup.$(date +%s)
> /etc/hosts
echo "127.0.0.1 localhost" >> /etc/hosts
for domain in "${ALLOWED_DOMAINS[@]}"; do
    IP=$(dig +short "$domain" | grep -E '^[0-9.]+' | head -n 1)
    if [ -n "$IP" ]; then
        echo "$IP $domain" >> /etc/hosts
        echo "[✓] $domain -> $IP"
    else
        echo "[!] Failed to resolve $domain"
    fi
done

echo "⏰ Step 4: Creating hourly auto-refresh for /etc/hosts..."
mkdir -p /usr/local/bin
cat > /usr/local/bin/update-whitelist-hosts.sh <<EOF
#!/bin/bash
echo "[Auto] Refreshing /etc/hosts at \$(date)"
> /etc/hosts
echo "127.0.0.1 localhost" >> /etc/hosts"
EOF

for domain in "${ALLOWED_DOMAINS[@]}"; do
    echo "IP=\$(dig +short $domain | grep -E '^[0-9.]+' | head -n 1)" >> /usr/local/bin/update-whitelist-hosts.sh
    echo "if [ -n \"\$IP\" ]; then echo \"\$IP $domain\" >> /etc/hosts; fi" >> /usr/local/bin/update-whitelist-hosts.sh
done

chmod +x /usr/local/bin/update-whitelist-hosts.sh

cat > /etc/systemd/system/hosts-whitelist.timer <<EOF
[Unit]
Description=Refresh /etc/hosts every hour

[Timer]
OnBootSec=2min
OnUnitActiveSec=1h
Unit=hosts-whitelist.service

[Install]
WantedBy=timers.target
EOF

cat > /etc/systemd/system/hosts-whitelist.service <<EOF
[Unit]
Description=Refresh whitelisted domains in /etc/hosts

[Service]
ExecStart=/usr/local/bin/update-whitelist-hosts.sh
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now hosts-whitelist.timer

echo "🔐 Step 5: Locking down internet access for $PARTICIPANT_USER..."
iptables -A OUTPUT -m owner --uid-owner $PARTICIPANT_UID -p tcp --dport $LOCAL_PROXY_PORT -j ACCEPT
iptables -A OUTPUT -m owner --uid-owner $PARTICIPANT_UID -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -m owner --uid-owner $PARTICIPANT_UID -o lo -j ACCEPT
iptables -A OUTPUT -m owner --uid-owner $PARTICIPANT_UID -j REJECT

echo "💾 Saving firewall rules..."
netfilter-persistent save

echo "🌍 Step 6: Setting proxy environment for participant..."
BASHRC="/home/$PARTICIPANT_USER/.bashrc"
grep -q "http_proxy" "$BASHRC" || {
    echo "export http_proxy=\"http://127.0.0.1:$LOCAL_PROXY_PORT\"" >> "$BASHRC"
    echo "export https_proxy=\"http://127.0.0.1:$LOCAL_PROXY_PORT\"" >> "$BASHRC"
    chown $PARTICIPANT_USER:$PARTICIPANT_USER "$BASHRC"
}

echo "🧱 Step 7: Blocking USB storage devices..."
cat > /etc/udev/rules.d/100-usbblock.rules <<EOF
SUBSYSTEM=="usb", ATTR{bInterfaceClass}=="08", ACTION=="add", RUN+="/bin/sh -c 'echo 0 > /sys\\$DEVPATH/authorized'"
EOF
udevadm control --reload-rules
udevadm trigger

echo "🚫 Step 8: Preventing mounting of external drives via Polkit..."
cat > /etc/polkit-1/localauthority/50-local.d/10-usb-mount.pkla <<EOF
[Disable mounting for participant]
Identity=unix-user:$PARTICIPANT_USER
Action=org.freedesktop.udisks2.filesystem-mount
ResultActive=no
EOF

echo "🔍 Step 9: Detecting non-root partitions to restrict..."
WINDOWS_PARTITIONS=()

while read -r part mountpoint; do
    if [[ "$mountpoint" != "/" && -z "$mountpoint" ]]; then
        WINDOWS_PARTITIONS+=("$part")
    fi
done < <(lsblk -ln -o NAME,MOUNTPOINT | awk '{print "/dev/" $1, $2}')

echo "🛑 Step 10: Unmounting and locking non-Ubuntu partitions..."
for part in "${WINDOWS_PARTITIONS[@]}"; do
    umount "$part" 2>/dev/null
    chmod 000 "$part" 2>/dev/null
    echo "[✓] Restricted access to $part"
done

echo "✅ Lockdown complete. Internet restricted, devices blocked, partitions locked, and firewall rules saved."
