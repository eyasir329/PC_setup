#!/bin/bash

# Use SETUP_USER if set, otherwise default to "participant"
USER="${SETUP_USER:-participant}"

echo "============================================"
echo "Starting Lab PC Setup for user '$USER': $(date)"
echo "============================================"

echo "============================================"
echo "Step 1: Recreate '$USER' account with minimal privileges"
echo "============================================"

# Delete user if exists (keep home for safety)
if id "$USER" &>/dev/null; then
    echo "→ '$USER' exists. Deleting account..."
    sudo deluser "$USER" --remove-home || true
    echo "✅ '$USER' removed."
fi

# Create user with minimal groups (desktop only)
sudo useradd -m -s /bin/bash "$USER" -G audio,video,cdrom,plugdev

# --- Password options ---
# Option 1: Fixed password (uncomment line below)
# echo "$USER:contest123" | sudo chpasswd
# Option 2: Prompt you to set password manually
sudo passwd "$USER"

# Ensure account is unlocked
sudo usermod -U "$USER"

# Verify groups
echo "→ Checking groups for '$USER'..."
CURRENT_GROUPS=$(groups "$USER" | cut -d: -f2)
echo "✅ Groups: $CURRENT_GROUPS"

# Remove dangerous groups if present
for group in sudo netdev adm disk; do
    if groups "$USER" | grep -q "\b$group\b"; then
        echo "⚠️ Removing $group group..."
        sudo gpasswd -d "$USER" "$group" 2>/dev/null || true
    fi
done

echo "============================================"
echo "Step 2: Install Development Tools and Utilities"
echo "============================================"

DEV_PACKAGES=(
    build-essential
    gdb
    gcc
    g++
    python3
    python3-pip
    openjdk-17-jdk
    neovim
    git
    micro
    codeblocks
    curl
    wget
    neofetch
    hollywood
)

for pkg in "${DEV_PACKAGES[@]}"; do
    if dpkg -s "$pkg" &>/dev/null; then
        echo "✅ $pkg already installed."
    else
        echo "📦 Installing $pkg..."
        sudo apt-get install -y "$pkg"
    fi
done

echo "📦 Installing GRUB Customizer..."
if ! grep -q "danielrichter2007/grub-customizer" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
    sudo add-apt-repository -y ppa:danielrichter2007/grub-customizer
    sudo apt-get update
fi
sudo apt-get install -y grub-customizer

echo "============================================"
echo "Step 3: Install Sublime Text"
echo "============================================"

if ! command -v subl &>/dev/null; then
    sudo apt-get install -y apt-transport-https curl gnupg
    wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg \
        | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/sublimehq-archive.gpg > /dev/null
    echo "deb https://download.sublimetext.com/ apt/stable/" \
        | sudo tee /etc/apt/sources.list.d/sublime-text.list
    sudo apt-get update
    sudo apt-get install -y sublime-text
else
    echo "✅ Sublime Text already installed."
fi

echo "============================================"
echo "Step 4: Install Google Chrome"
echo "============================================"

if ! command -v google-chrome &>/dev/null; then
    TMP_DEB="/tmp/google-chrome.deb"
    wget -O "$TMP_DEB" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    sudo dpkg -i "$TMP_DEB" || sudo apt-get install -f -y
    rm -f "$TMP_DEB"
else
    echo "✅ Google Chrome already installed."
fi

echo "============================================"
echo "Step 5: Install Firefox"
echo "============================================"

if ! command -v firefox &>/dev/null; then
    sudo apt-get install -y firefox || sudo snap install firefox
else
    echo "✅ Firefox already installed."
fi

echo "Step 6: Install Visual Studio Code"
echo "============================================"

if ! command -v code &>/dev/null; then
    sudo apt-get install -y wget gpg apt-transport-https
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | \
        gpg --dearmor | sudo tee /usr/share/keyrings/microsoft-archive-keyring.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/vscode stable main" \
        | sudo tee /etc/apt/sources.list.d/vscode.list
    sudo apt-get update
    sudo apt-get install -y code
else
    echo "✅ VS Code already installed."
fi

echo "============================================"
echo "Step 7: Install VS Code Extensions"
echo "============================================"

EXTENSIONS=( "ms-vscode.cpptools" "ms-python.python" "redhat.java" )

for ext in "${EXTENSIONS[@]}"; do
    if ! sudo -u "$USER" code --list-extensions 2>/dev/null | grep -q "$ext"; then
        echo "→ Installing $ext..."
        timeout 60s sudo -u "$USER" code --install-extension "$ext" --force || true
    else
        echo "✅ $ext already installed."
    fi
done

echo "============================================"
echo "Step 8: Fix VS Code Keyring Popup"
echo "============================================"

sudo apt-get install -y libpam-gnome-keyring
grep -q "pam_gnome_keyring.so" /etc/pam.d/common-auth || echo "auth optional pam_gnome_keyring.so" | sudo tee -a /etc/pam.d/common-auth
grep -q "pam_gnome_keyring.so auto_start" /etc/pam.d/common-session || echo "session optional pam_gnome_keyring.so auto_start" | sudo tee -a /etc/pam.d/common-session
sudo -u "$USER" rm -f "/home/$USER/.local/share/keyrings/*"

echo "============================================"
echo "Step 9: Set Permissions for $USER"
echo "============================================"

sudo apt-get install -y acl
sudo chown -R "$USER:$USER" "/home/$USER"
sudo chmod -R u+rwX "/home/$USER"

echo "============================================"
echo "Step 10: Disable Automatic Updates"
echo "============================================"

sudo systemctl stop apt-daily.service apt-daily-upgrade.service
sudo systemctl disable apt-daily.service apt-daily-upgrade.service

echo "============================================"
echo "Step 11: Clean Up"
echo "============================================"

sudo apt-get autoremove -y

echo "============================================"
echo "Step 12: Backup $USER's Home"
echo "============================================"

BACKUP_DIR="/opt/${USER}_backup"
SOURCE_DIR="/home/$USER"
TARGET_DIR="$BACKUP_DIR/${USER}_home"

# Ensure backup directory exists
sudo mkdir -p "$BACKUP_DIR"

# Check if backup already exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "→ No backup found. Creating initial backup..."
    sudo rsync -aAX --info=progress2 "$SOURCE_DIR/" "$TARGET_DIR/"
    if [ $? -eq 0 ]; then
        echo "✅ Backup created successfully at $TARGET_DIR"
    else
        echo "❌ Backup failed! Please check disk space and permissions." >&2
        exit 1
    fi
else
    echo "✅ Backup already exists at $TARGET_DIR. Skipping."
    echo "💡 If you want to refresh the backup, run with '--force-backup'."
fi

# Optional: Handle --force-backup
if [[ "${FORCE_BACKUP:-}" == "1" ]]; then
    echo "→ Force backup enabled. Refreshing backup..."
    sudo rsync -aAX --delete --info=progress2 "$SOURCE_DIR/" "$TARGET_DIR/"
    echo "✅ Backup refreshed."
fi

echo "============================================"
echo "✅ Lab PC Setup Completed!"
echo "============================================"
