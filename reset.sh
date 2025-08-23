#!/usr/bin/env bash
set -euo pipefail

# ================================
# Reset User Environment Script
# - Restores /home from backup
# - Removes contest restrictions (same as unrestrict, noninteractive)
# ================================

DEFAULT_USER="participant"
USER="${1:-$DEFAULT_USER}"

CONFIG_DIR="/usr/local/etc/contest-restriction"
WHITELIST_FILE="$CONFIG_DIR/whitelist.txt"
DEPENDENCIES_FILE="$CONFIG_DIR/dependencies.txt"
HELPER_SCRIPT="/usr/local/bin/update-contest-whitelist"
CHAIN_PREFIX="CONTEST"
CONTEST_SERVICE="contest-restrict-$USER"

BACKUP_DIR="/opt/${USER}_backup/${USER}_home"

echo "============================================"
echo " Resetting $USER account to default..."
echo " Started at: $(date)"
echo "============================================"

[[ $EUID -eq 0 ]] || { echo "❌ Must run as root"; exit 1; }
id "$USER" &>/dev/null || { echo "❌ User '$USER' does not exist."; exit 1; }

# 1) Ensure backup exists (auto-create if missing)
if [[ ! -d "$BACKUP_DIR" ]]; then
  echo "⚠️  Backup not found at $BACKUP_DIR."
  echo "→ Creating initial backup before reset..."
  mkdir -p "$BACKUP_DIR"
  rsync -aAX --info=progress2 "/home/$USER/" "$BACKUP_DIR/"
  echo "✅ Initial backup created successfully."
fi

# 2) Ensure user is logged out
if pgrep -u "$USER" >/dev/null; then
  echo "❌ $USER is currently logged in. Please log them out before resetting."
  exit 1
fi

# 3) Wipe home contents (safe glob)
echo "→ Deleting contents of /home/$USER ..."
shopt -s nullglob
rm -rf /home/"$USER"/* || true
shopt -u nullglob

# 4) Restore backup
echo "→ Restoring from backup..."
rsync -aAX "$BACKUP_DIR/" "/home/$USER/"
echo "✅ Home directory restored."

# 5) Fix ownership
echo "→ Fixing permissions..."
chown -R "$USER:$USER" "/home/$USER"
echo "✅ Permissions fixed."

# 6) Clean temp/config/cache (optional)
echo "→ Cleaning sensitive files..."
find "/home/$USER/" -type f \( -name "*.tmp" -o -name "*.bak" -o -name "*.*~" \) -delete || true
rm -rf "/home/$USER/.cache"/* "/home/$USER/.local/share"/* "/home/$USER/.config"/* 2>/dev/null || true

# ================================
# Contest Restriction Cleanup (noninteractive)
# ================================
echo "→ Cleaning up contest restrictions..."

# Stop & disable systemd services + mask
systemctl stop "$CONTEST_SERVICE.service" 2>/dev/null || true
systemctl stop "$CONTEST_SERVICE.timer" 2>/dev/null || true
systemctl disable "$CONTEST_SERVICE.service" 2>/dev/null || true
systemctl disable "$CONTEST_SERVICE.timer" 2>/dev/null || true
systemctl mask "$CONTEST_SERVICE.service" 2>/dev/null || true
systemctl mask "$CONTEST_SERVICE.timer" 2>/dev/null || true
rm -f "/etc/systemd/system/$CONTEST_SERVICE.service" "/etc/systemd/system/$CONTEST_SERVICE.timer" 2>/dev/null || true
systemctl daemon-reload

# Remove firewall rules (only per-user hooks and chain)
CHAIN_OUT="${CHAIN_PREFIX}_${USER^^}_OUT"
USER_UID="$(id -u "$USER")"

while iptables  -C OUTPUT -m owner --uid-owner "$USER_UID" -j "$CHAIN_OUT" 2>/dev/null; do
  iptables  -D OUTPUT -m owner --uid-owner "$USER_UID" -j "$CHAIN_OUT" || true
done
while ip6tables -C OUTPUT -m owner --uid-owner "$USER_UID" -j "$CHAIN_OUT" 2>/dev/null; do
  ip6tables -D OUTPUT -m owner --uid-owner "$USER_UID" -j "$CHAIN_OUT" || true
done

iptables  -F "$CHAIN_OUT" 2>/dev/null || true
iptables  -X "$CHAIN_OUT" 2>/dev/null || true
ip6tables -F "$CHAIN_OUT" 2>/dev/null || true
ip6tables -X "$CHAIN_OUT" 2>/dev/null || true

# Remove USB restrictions (kernel + polkit + udev)
rm -f /etc/modprobe.d/contest-usb-storage-blacklist.conf 2>/dev/null || true
rm -f /etc/polkit-1/rules.d/99-contest-block-mount.rules 2>/dev/null || true
rm -f /etc/udev/rules.d/99-contest-block-usb.rules 2>/dev/null || true
modprobe usb_storage 2>/dev/null || true
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger 2>/dev/null || true

# Cleanup caches
rm -f "$CONFIG_DIR/${USER}_domains_cache.txt" "$CONFIG_DIR/${USER}_ip_cache.txt" 2>/dev/null || true

# Re-create whitelist if missing (helpful for future re-restrict)
if [[ ! -f "$WHITELIST_FILE" ]]; then
  mkdir -p "$CONFIG_DIR"
  echo "hackerrank.com" > "$WHITELIST_FILE"
  echo "✅ Created default whitelist: hackerrank.com"
fi

echo "✅ Contest restrictions cleaned/reset."

# ================================
# Development Environment Setup (unchanged, but safer)
# ================================
echo "→ Verifying essential software..."
REQUIRED_PKGS=(python3 git vim gcc build-essential openjdk-17-jdk codeblocks sublime-text google-chrome-stable firefox code)
for pkg in "${REQUIRED_PKGS[@]}"; do
  if dpkg -s "$pkg" &>/dev/null; then
    echo "✅ $pkg installed"
  else
    echo "⚠️  Missing: $pkg"
  fi
done

# Code::Blocks setup
echo "→ Configuring Code::Blocks..."
sudo -u "$USER" mkdir -p "/home/$USER/cb_projects/bin/Debug" "/home/$USER/cb_projects/bin/Release"
chmod -R 755 "/home/$USER/cb_projects"
for file in "/home/$USER/.bashrc" "/home/$USER/.profile"; do
  grep -qxF "umask 022" "$file" || echo "umask 022" >> "$file"
done
find "/home/$USER/cb_projects/bin" -type f -exec chmod +x {} \; || true
setfacl -R -d -m u::rwx,g::rx,o::rx "/home/$USER/cb_projects/bin" 2>/dev/null || true
sudo -u "$USER" mkdir -p "/home/$USER/.config/codeblocks/share"
cat <<EOF | sudo -u "$USER" tee "/home/$USER/.config/codeblocks/share/terminals.conf" >/dev/null
[General]
terminal_program=xterm
terminal_cmd=xterm -T \$TITLE -e
EOF
cat <<'EOF' >/usr/local/bin/codeblocks-run
#!/bin/bash
chmod +x "$@"
"$@"
EOF
chmod +x /usr/local/bin/codeblocks-run
grep -qxF 'alias make-executable="chmod +x"' "/home/$USER/.bashrc" || echo 'alias make-executable="chmod +x"' >> "/home/$USER/.bashrc"
grep -qxF "export PATH=\$PATH:/home/$USER" "/home/$USER/.bashrc" || echo "export PATH=\$PATH:/home/$USER" >> "/home/$USER/.bashrc"
echo "✅ Code::Blocks setup complete."

# Keyring / PAM
echo "→ Configuring keyring..."
apt-get update -qq || true
apt-get install -y libpam-gnome-keyring || true
for file in /etc/pam.d/common-auth /etc/pam.d/common-session; do
  case "$file" in
    *auth*)    grep -qxF "auth optional pam_gnome_keyring.so" "$file" || echo "auth optional pam_gnome_keyring.so" >> "$file" ;;
    *session*) grep -qxF "session optional pam_gnome_keyring.so auto_start" "$file" || echo "session optional pam_gnome_keyring.so auto_start" >> "$file" ;;
  esac
done
sudo -u "$USER" rm -f "/home/$USER/.local/share/keyrings/"* 2>/dev/null || true
echo "✅ Keyring configuration complete."

# VS Code extensions
echo "→ Installing VS Code extensions..."
if command -v code &>/dev/null; then
  EXTENSIONS=(ms-vscode.cpptools ms-python.python redhat.java)
  for ext in "${EXTENSIONS[@]}"; do
    if sudo -u "$USER" code --list-extensions | grep -q "$ext"; then
      echo "✅ $ext already installed."
    else
      sudo -u "$USER" code --install-extension "$ext" --force || echo "⚠️ Failed to install $ext"
    fi
  done
else
  echo "⚠️ VS Code not installed, skipping extensions."
fi

echo "============================================"
echo "✅ $USER account has been reset successfully."
echo " Finished at: $(date)"
echo "============================================"
