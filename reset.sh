#!/usr/bin/env bash
set -euo pipefail

# ================================
# Reset User Environment Script
# ================================

DEFAULT_USER="participant"
USER="${RESET_USER:-$DEFAULT_USER}"

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

# 1. Check if user exists
if ! id "$USER" &>/dev/null; then
  echo "❌ User '$USER' does not exist."
  exit 1
fi

# 2. Ensure backup exists (auto-create if missing)
if [ ! -d "$BACKUP_DIR" ]; then
    echo "⚠️  Backup not found at $BACKUP_DIR."
    echo "→ Creating initial backup before reset..."
    sudo mkdir -p "$BACKUP_DIR"
    sudo rsync -aAX --info=progress2 "/home/$USER/" "$BACKUP_DIR/"
    echo "✅ Initial backup created successfully."
fi

# 3. Ensure user is logged out
if pgrep -u "$USER" > /dev/null; then
  echo "❌ $USER is currently logged in. Please log them out before resetting."
  exit 1
fi

# 4. Delete current user home (safe glob expansion)
echo "→ Deleting contents of /home/$USER ..."
shopt -s nullglob
sudo rm -rf /home/"$USER"/* || true
shopt -u nullglob

# 5. Restore backup
echo "→ Restoring from backup..."
sudo rsync -aAX "$BACKUP_DIR/" "/home/$USER/"
echo "✅ Home directory restored."

# 6. Fix ownership
echo "→ Fixing permissions..."
sudo chown -R "$USER:$USER" "/home/$USER"
echo "✅ Permissions fixed."

# 7. Clean temp/config/cache
echo "→ Cleaning sensitive files..."
find "/home/$USER/" -type f \( -name "*.tmp" -o -name "*.bak" -o -name "*.*~" \) -delete
sudo rm -rf "/home/$USER/.cache"/* || true
sudo rm -rf "/home/$USER/.local/share"/* || true
sudo rm -rf "/home/$USER/.config"/* || true

# ================================
# Contest Restriction Cleanup
# ================================
echo "→ Cleaning up contest restrictions..."

# Stop & disable systemd services
systemctl stop "$CONTEST_SERVICE.service" 2>/dev/null || true
systemctl stop "$CONTEST_SERVICE.timer" 2>/dev/null || true
systemctl disable "$CONTEST_SERVICE.service" 2>/dev/null || true
systemctl disable "$CONTEST_SERVICE.timer" 2>/dev/null || true
rm -f "/etc/systemd/system/$CONTEST_SERVICE.service" "/etc/systemd/system/$CONTEST_SERVICE.timer" 2>/dev/null || true
systemctl daemon-reload

# Remove firewall rules
CHAIN_OUT="${CHAIN_PREFIX}_${USER^^}_OUT"
iptables  -D OUTPUT -m owner --uid-owner "$(id -u "$USER")" -j "$CHAIN_OUT" 2>/dev/null || true
ip6tables -D OUTPUT -m owner --uid-owner "$(id -u "$USER")" -j "$CHAIN_OUT" 2>/dev/null || true
iptables  -F "$CHAIN_OUT" 2>/dev/null || true
iptables  -X "$CHAIN_OUT" 2>/dev/null || true
ip6tables -F "$CHAIN_OUT" 2>/dev/null || true
ip6tables -X "$CHAIN_OUT" 2>/dev/null || true

# Remove USB restrictions
rm -f /etc/modprobe.d/contest-usb-storage-blacklist.conf 2>/dev/null || true
rm -f /etc/polkit-1/rules.d/99-contest-block-mount.rules 2>/dev/null || true
modprobe usb_storage 2>/dev/null || true
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger 2>/dev/null || true

# Cleanup caches
rm -f "$CONFIG_DIR/${USER}_domains_cache.txt" "$CONFIG_DIR/${USER}_ip_cache.txt" 2>/dev/null || true

# Re-create whitelist if missing
if [[ ! -f "$WHITELIST_FILE" ]]; then
  echo "hackerrank.com" > "$WHITELIST_FILE"
  echo "✅ Created default whitelist: hackerrank.com"
fi

echo "✅ Contest restrictions cleaned/reset."

# ================================
# Development Environment Setup
# ================================

# 8. Verify essential software
echo "→ Verifying essential software..."
REQUIRED_PKGS=(python3 git vim gcc build-essential openjdk-17-jdk codeblocks sublime-text google-chrome-stable firefox code)
for pkg in "${REQUIRED_PKGS[@]}"; do
    if dpkg -s "$pkg" &>/dev/null; then
        echo "✅ $pkg installed"
    else
        echo "⚠️  Missing: $pkg"
    fi
done

# 9. Code::Blocks setup
echo "→ Configuring Code::Blocks..."
sudo -u "$USER" mkdir -p "/home/$USER/cb_projects/bin/Debug" "/home/$USER/cb_projects/bin/Release"
sudo chmod -R 755 "/home/$USER/cb_projects"
for file in "/home/$USER/.bashrc" "/home/$USER/.profile"; do
  if ! grep -qxF "umask 022" "$file"; then
      echo "umask 022" | sudo tee -a "$file" >/dev/null
  fi
done
sudo find "/home/$USER/cb_projects/bin" -type f -exec chmod +x {} \;
sudo setfacl -R -d -m u::rwx,g::rx,o::rx "/home/$USER/cb_projects/bin"
sudo -u "$USER" mkdir -p "/home/$USER/.config/codeblocks/share"
cat <<EOF | sudo -u "$USER" tee "/home/$USER/.config/codeblocks/share/terminals.conf" >/dev/null
[General]
terminal_program=xterm
terminal_cmd=xterm -T \$TITLE -e
EOF
cat <<'EOF' | sudo tee /usr/local/bin/codeblocks-run >/dev/null
#!/bin/bash
chmod +x "$@"
"$@"
EOF
sudo chmod +x /usr/local/bin/codeblocks-run
if ! grep -qxF "alias make-executable=\"chmod +x\"" "/home/$USER/.bashrc"; then
  echo 'alias make-executable="chmod +x"' | sudo tee -a "/home/$USER/.bashrc" >/dev/null
fi
if ! grep -qxF "export PATH=\$PATH:/home/$USER" "/home/$USER/.bashrc"; then
  echo "export PATH=\$PATH:/home/$USER" | sudo tee -a "/home/$USER/.bashrc"
fi
echo "✅ Code::Blocks setup complete."

# 10. Keyring / PAM
echo "→ Configuring keyring..."
sudo apt install -y libpam-gnome-keyring
for file in /etc/pam.d/common-auth /etc/pam.d/common-session; do
  case "$file" in
    *auth*)
      if ! grep -qxF "auth optional pam_gnome_keyring.so" "$file"; then
        echo "auth optional pam_gnome_keyring.so" | sudo tee -a "$file"
      fi
      ;;
    *session*)
      if ! grep -qxF "session optional pam_gnome_keyring.so auto_start" "$file"; then
        echo "session optional pam_gnome_keyring.so auto_start" | sudo tee -a "$file"
      fi
      ;;
  esac
done
sudo -u "$USER" rm -f "/home/$USER/.local/share/keyrings/"*
echo "✅ Keyring configuration complete."

# 11. VS Code extensions
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
