#!/usr/bin/env bash
set -euo pipefail

# ensure root
if (( EUID != 0 )); then
  echo "[ERROR] Must be run as root."
  exit 1
fi

echo "[*] Reverting participant restrictions..."

USER="participant"
UID_PARTICIPANT=$(id -u "$USER")
CHAIN="PARTICIPANT_OUT"
IPSET="participant_whitelist"
CRON_FILE="/etc/cron.d/participant-whitelist"
PKLA_FILE="/etc/polkit-1/localauthority/50-local.d/disable-participant-mount.pkla"
UDEV_RULES="/etc/udev/rules.d/99-usb-block.rules"

# 1) remove iptables OUTPUT hook
echo "[1] Removing iptables hook for $USER"
iptables -t filter -D OUTPUT -m owner --uid-owner "$UID_PARTICIPANT" -j "$CHAIN" 2>/dev/null || true

# 2) flush & delete the chain
if iptables -t filter -L "$CHAIN" &>/dev/null; then
  echo "[2] Flushing and deleting chain $CHAIN"
  iptables -t filter -F "$CHAIN"
  iptables -t filter -X "$CHAIN"
fi

# 3) destroy ipset
if ipset list "$IPSET" &>/dev/null; then
  echo "[3] Destroying ipset $IPSET"
  ipset destroy "$IPSET"
fi

# 4) remove cron job
if [[ -f "$CRON_FILE" ]]; then
  echo "[4] Removing cron job $CRON_FILE"
  rm -f "$CRON_FILE"
fi

# 5) re‑add $USER to disk & plugdev groups
echo "[5] Restoring $USER to disk & plugdev groups"
adduser "$USER" disk    &>/dev/null || true
adduser "$USER" plugdev &>/dev/null || true

# 6) remove Polkit rule
if [[ -f "$PKLA_FILE" ]]; then
  echo "[6] Removing Polkit rule $PKLA_FILE"
  rm -f "$PKLA_FILE"
  systemctl reload polkit.service &>/dev/null || echo "    ! polkit reload failed"
fi

# 7) remove udev rule
if [[ -f "$UDEV_RULES" ]]; then
  echo "[7] Removing udev rule $UDEV_RULES"
  rm -f "$UDEV_RULES"
  udevadm control --reload-rules && udevadm trigger
fi

echo "[*] Done. Participant can now mount devices and has full network access."

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
sudo rsync -aAX /opt/participant_backup/participant_home/ /home/participant/
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

# 8. Set permissions and fix Code::Blocks setup
echo "Setting permissions for participant's home..."
sudo chown -R participant:participant /home/participant
sudo chmod -R u+rwX /home/participant

# Install additional package for ACL support if needed
sudo apt install -y acl

# Make sure participant is part of necessary groups
sudo usermod -aG sudo,adm,dialout,cdrom,floppy,audio,dip,video,plugdev,netdev participant

# Create Code::Blocks projects directory with proper permissions
sudo -u participant mkdir -p /home/participant/cb_projects
sudo chmod -R 755 /home/participant/cb_projects

# Create common Code::Blocks output directories with proper permissions
sudo -u participant mkdir -p /home/participant/cb_projects/bin
sudo -u participant mkdir -p /home/participant/cb_projects/bin/Debug
sudo -u participant mkdir -p /home/participant/cb_projects/bin/Release
sudo chmod -R 755 /home/participant/cb_projects/bin

# Set default umask for participant to ensure new files are executable
if ! grep -q "umask 022" /home/participant/.bashrc; then
    echo "umask 022" | sudo tee -a /home/participant/.bashrc
fi
if ! grep -q "umask 022" /home/participant/.profile; then
    echo "umask 022" | sudo tee -a /home/participant/.profile
fi

# Ensure participant can execute files from anywhere in their home directory
sudo find /home/participant -type f -name "*.out" -exec chmod +x {} \;
sudo find /home/participant -type f -name "*.exe" -exec chmod +x {} \;
sudo find /home/participant -type f -name "*.bin" -exec chmod +x {} \;
sudo find /home/participant -path "*/bin/Debug/*" -type f -exec chmod +x {} \;
sudo find /home/participant -path "*/bin/Release/*" -type f -exec chmod +x {} \;

# Setup ACL to automatically grant execute permissions for new files in bin directories
sudo setfacl -R -d -m u::rwx,g::rx,o::rx /home/participant/cb_projects/bin
sudo setfacl -R -m u::rwx,g::rx,o::rx /home/participant/cb_projects/bin

# Set proper permissions for Code::Blocks configuration directory
sudo -u participant mkdir -p /home/participant/.config/codeblocks
sudo chown -R participant:participant /home/participant/.config/codeblocks
sudo chmod -R u+rwX /home/participant/.config/codeblocks

# Ensure Code::Blocks has proper directory specified for output
CONFIG_FILE="/home/participant/.config/codeblocks/default.conf"
if [ -f "$CONFIG_FILE" ]; then
    sudo -u participant sed -i 's|<default_compiler>.*</default_compiler>|<default_compiler>gnu_gcc_compiler</default_compiler>|' "$CONFIG_FILE"
    sudo -u participant sed -i 's|<output_directory>.*</output_directory>|<output_directory>/home/participant/cb_projects/bin</output_directory>|' "$CONFIG_FILE"
fi

# Set safer default for executed programs in CodeBlocks
sudo -u participant mkdir -p /home/participant/.config/codeblocks/share
sudo chown -R participant:participant /home/participant/.config/codeblocks/share
echo "[General]
terminal_program=xterm
terminal_cmd=xterm -T \$TITLE -e
" | sudo -u participant tee /home/participant/.config/codeblocks/share/terminals.conf > /dev/null

# Add a custom-compiled runner script for Code::Blocks executables
echo '#!/bin/bash
chmod +x "$@"
"$@"
' | sudo tee /usr/local/bin/codeblocks-run > /dev/null
sudo chmod +x /usr/local/bin/codeblocks-run

# Create a helpful alias for participant
if ! grep -q "alias make-executable" /home/participant/.bashrc; then
    echo 'alias make-executable="chmod +x"' | sudo tee -a /home/participant/.bashrc > /dev/null
fi

# Add participant's home directory to PATH for easy execution of compiled programs
if ! grep -q "export PATH=\$PATH:/home/participant" /home/participant/.bashrc; then
    echo 'export PATH=$PATH:/home/participant' >> /home/participant/.bashrc
fi

echo "✅ Permissions and Code::Blocks setup complete. Participant should now be able to compile and run programs."


# Install PAM keyring helper if not present
sudo apt install -y libpam-gnome-keyring

# Add PAM lines if not already present
if ! grep -q "pam_gnome_keyring.so" /etc/pam.d/common-auth; then
    echo "auth optional pam_gnome_keyring.so" | sudo tee -a /etc/pam.d/common-auth
fi

if ! grep -q "pam_gnome_keyring.so auto_start" /etc/pam.d/common-session; then
    echo "session optional pam_gnome_keyring.so auto_start" | sudo tee -a /etc/pam.d/common-session
fi

# Clear existing keyring files
sudo -u participant rm -f /home/participant/.local/share/keyrings/*

# Pre-create a blank keyring if needed (interactive part not scriptable without security compromise)
echo "✅ Keyring configuration fixed. You may still need to run VS Code once under participant to complete silent keyring setup."


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
    # Check if the extension is already installed
    if sudo -u participant code --list-extensions | grep -q "$ext"; then
        echo "✅ Extension $ext is already installed. Skipping installation."
    else
        echo "→ Installing extension: $ext for participant"
        sudo -u participant code --install-extension "$ext" --force
        if [ $? -eq 0 ]; then
            echo "✅ Installed $ext successfully."
        else
            echo "❌ Failed to install $ext." >&2
            exit 1
        fi
    fi
done

echo "============================================"
echo "✅ VS Code extensions installed."
echo "============================================"


set -euo pipefail

# --- auto‑install missing tools ---
declare -A PKG_FOR_CMD=(
  [ipset]=ipset
  [iptables]=iptables
  [udevadm]=udev
  [dig]=dnsutils
)
missing=()
for cmd in "${!PKG_FOR_CMD[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    missing+=("${PKG_FOR_CMD[$cmd]}")
  fi
done
if (( ${#missing[@]} )); then
  echo "[*] Installing missing packages: ${missing[*]}"
  apt update
  DEBIAN_FRONTEND=noninteractive apt install -y "${missing[@]}"
fi
# --- end auto‑install ---

# ensure root
if (( EUID != 0 )); then
  echo "[ERROR] Must be run as root."
  exit 1
fi

export PATH=$PATH:/usr/local/sbin:/usr/sbin:/sbin
echo "[*] Starting participant network & device lockdown..."

DOMAINS=(
  codeforces.com codechef.com vjudge.net atcoder.jp
  hackerrank.com hackerearth.com topcoder.com
  spoj.com lightoj.com uva.onlinejudge.org
  cses.fi bapsoj.com toph.co
)
IPSET="participant_whitelist"
CHAIN="PARTICIPANT_OUT"
USER="participant"
UID_PARTICIPANT=$(id -u "$USER")

# 1) create or flush ipset
if ipset list "$IPSET" &>/dev/null; then
  echo "[1] Flushing ipset $IPSET"
  ipset flush "$IPSET"
else
  echo "[1] Creating ipset $IPSET"
  ipset create "$IPSET" hash:ip family inet hashsize 1024
fi

# 2) resolve domains → add to ipset
echo "[2] Resolving domains into $IPSET"
for d in "${DOMAINS[@]}"; do
  echo "   → $d"
  mapfile -t ips < <(
    dig +short A "$d" 2>/dev/null \
      | grep -Eo '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
      | sort -u
  )
  if (( ${#ips[@]} == 0 )); then
    echo "      [!] no A records, skipping"
    continue
  fi
  for ip in "${ips[@]}"; do
    echo "      · $ip"
    ipset add "$IPSET" "$ip" \
      || echo "      [!] failed to add $ip"
  done
done

# 3) rebuild iptables chain
echo "[3] Rebuilding iptables chain $CHAIN"
# 3a) delete old OUTPUT hook
iptables -t filter -D OUTPUT -m owner --uid-owner "$UID_PARTICIPANT" -j "$CHAIN" 2>/dev/null || true
# 3b) if chain exists, flush & delete
if iptables -t filter -L "$CHAIN" &>/dev/null; then
  iptables -t filter -F "$CHAIN"
  iptables -t filter -X "$CHAIN"
fi
# 3c) create fresh chain
iptables -t filter -N "$CHAIN"

# hook new chain into OUTPUT
iptables -t filter -I OUTPUT -m owner --uid-owner "$UID_PARTICIPANT" -j "$CHAIN"

# 4) allow DNS
echo "[4] Allowing DNS"
iptables -A "$CHAIN" -p udp --dport 53 -j ACCEPT
iptables -A "$CHAIN" -p tcp --dport 53 -j ACCEPT

# 5) allow HTTP/HTTPS → whitelisted IPs
echo "[5] Allowing HTTP/HTTPS"
iptables -A "$CHAIN" -p tcp -m multiport --dports 80,443 \
         -m set --match-set "$IPSET" dst -j ACCEPT

# 6) allow established
echo "[6] Allowing ESTABLISHED,RELATED"
iptables -A "$CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 7) drop all else
echo "[7] Dropping everything else"
iptables -A "$CHAIN" -j REJECT

# 8) cron job
CRON_FILE="/etc/cron.d/participant-whitelist"
CRON_LINE="*/15 * * * * root bash /media/shazid/Files/MDPC/Script/restrict.sh >/dev/null 2>&1"
echo "[8] Ensuring cron job"
if ! grep -Fxq "$CRON_LINE" "$CRON_FILE" 2>/dev/null; then
  cat <<EOF >"$CRON_FILE"
# Refresh whitelist every 15 minutes
$CRON_LINE
EOF
  echo "    · installed"
else
  echo "    · already present"
fi

# 9) strip participant from disk/plugdev
echo "[9] Removing $USER from disk & plugdev groups"
deluser "$USER" disk    &>/dev/null || true
deluser "$USER" plugdev &>/dev/null || true

# 10) block mounts via Polkit
PKLA_DIR=/etc/polkit-1/localauthority/50-local.d
PKLA_FILE=$PKLA_DIR/disable-participant-mount.pkla
echo "[10] Writing Polkit rule to disable all mounts"
mkdir -p "$PKLA_DIR"
cat <<EOF > "$PKLA_FILE"
[Disable all mounts for participant]
Identity=unix-user:$USER
Action=org.freedesktop.udisks2.filesystem-mount
Action=org.freedesktop.udisks2.filesystem-mount-system
Action=org.freedesktop.udisks2.filesystem-unmount
Action=org.freedesktop.udisks2.eject
Action=org.freedesktop.udisks2.power-off-drive
ResultAny=no
ResultActive=no
ResultInactive=no
EOF
systemctl reload polkit.service &>/dev/null || echo "    ! polkit reload failed"

# 11) enforce USB‐only device‐node lockdown via udev
UDEV_RULES=/etc/udev/rules.d/99-usb-block.rules
echo "[11] Writing udev rule to lock USB block devices"
cat <<EOF > "$UDEV_RULES"
# all USB disks/partitions become root:root, mode 0000
SUBSYSTEM=="block", ENV{ID_BUS}=="usb", KERNEL=="sd[b-z]|mmcblk[0-9]*", OWNER="root", GROUP="root", MODE="0000"
EOF
udevadm control --reload-rules && udevadm trigger

echo "[*] Done."

echo "============================================"
echo "✅ Participant account has been reset successfully."
echo "============================================"