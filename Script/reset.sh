#!/bin/bash

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


echo "============================================"
echo "✅ Participant account has been reset successfully."
echo "============================================"