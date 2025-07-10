#!/usr/bin/env python3
"""
User management utilities for contest environment.
"""

import os
from .common import run_command, user_exists, ensure_user_can_execute


def create_contest_user(user):
    """Create a contest user with minimal privileges."""
    try:
        print(f"→ Setting up user account '{user}'")
        
        # Delete user if exists
        if user_exists(user):
            print(f"→ User '{user}' exists. Deleting...")
            run_command(f"deluser {user} --remove-home", shell=True, check=False)
            print(f"✅ User '{user}' deleted successfully.")
        
        # Create user with minimal groups
        print(f"→ Creating user '{user}' with minimal privileges...")
        run_command(f"useradd -m -s /bin/bash {user} -G audio,video,cdrom,plugdev,users", shell=True)
        
        # Set empty password
        run_command(f"passwd -d {user}", shell=True)
        
        # Ensure user is unlocked
        run_command(f"usermod -U {user}", shell=True)
        
        # Configure autologin
        configure_autologin(user)
        
        # Remove user from privileged groups
        remove_from_privileged_groups(user)
        
        # Ensure user can execute programs
        ensure_user_can_execute(user)
        
        print(f"✅ User '{user}' created successfully with minimal privileges.")
        return True
    except Exception as e:
        print(f"❌ Failed to create contest user: {e}")
        return False


def configure_autologin(user):
    """Configure automatic login for the user."""
    lightdm_conf = "/etc/lightdm/lightdm.conf"
    gdm_conf = "/etc/gdm3/custom.conf"
    
    if os.path.exists(lightdm_conf):
        with open(lightdm_conf, 'a') as f:
            f.write(f"autologin-user={user}\n")
        print("✅ Autologin configured in LightDM.")
    elif os.path.exists(gdm_conf):
        # Configure GDM autologin
        run_command(f"sed -i 's/^#  AutomaticLoginEnable = false/AutomaticLoginEnable = true/' {gdm_conf}", shell=True)
        run_command(f"sed -i 's/^#  AutomaticLogin = .*/AutomaticLogin = {user}/' {gdm_conf}", shell=True)
        print("✅ Autologin configured in GDM3.")
    else:
        print("⚠️ Could not detect supported display manager for autologin setup.")


def remove_from_privileged_groups(user):
    """Remove user from privileged groups."""
    privileged_groups = ["sudo", "netdev", "adm", "disk"]
    for group in privileged_groups:
        run_command(f"gpasswd -d {user} {group}", shell=True, check=False)


def create_user_backup(user):
    """Create backup of user's home directory."""
    print(f"→ Creating backup of user '{user}' home directory...")
    
    backup_dir = f"/opt/{user}_backup"
    user_home = f"/home/{user}"
    backup_home = f"{backup_dir}/{user}_home"
    
    # Create backup directory
    os.makedirs(backup_dir, exist_ok=True)
    
    # Create backup if it doesn't exist
    if not os.path.exists(backup_home):
        run_command(f"rsync -aAX {user_home}/ {backup_home}/", shell=True)
        print(f"✅ Backup created at {backup_home}")
    else:
        print("✅ Backup already exists. Skipping.")


def reset_user_account(user):
    """Reset a user account to clean state by restoring from backup."""
    from pathlib import Path
    import shutil
    import subprocess
    import pwd
    
    print(f"→ Resetting user account '{user}'")
    
    user_home = f"/home/{user}"
    backup_dir = f"/opt/{user}_backup"
    backup_home = f"{backup_dir}/{user}_home"
    
    # Check if user exists
    try:
        pwd.getpwnam(user)
        print(f"→ User '{user}' exists")
    except KeyError:
        print(f"❌ User '{user}' does not exist")
        return False
    
    # Check if backup exists
    if not os.path.exists(backup_home):
        print(f"❌ Backup directory {backup_home} does not exist")
        print("Please run setup first to create a backup")
        return False
    
    # Check if user is logged out
    try:
        result = subprocess.run(['pgrep', '-u', user], 
                              capture_output=True, text=True)
        if result.returncode == 0:
            print(f"❌ User '{user}' is currently logged in")
            print("Please log them out before resetting")
            return False
    except:
        pass  # pgrep not found or other error, continue
    
    try:
        # Delete all contents of home directory
        print(f"→ Deleting contents of {user_home}...")
        home_path = Path(user_home)
        if home_path.exists():
            for item in home_path.iterdir():
                if item.is_file() or item.is_symlink():
                    item.unlink()
                elif item.is_dir():
                    shutil.rmtree(item)
        
        # Restore from backup using rsync
        print(f"→ Restoring from {backup_home}...")
        cmd = f"rsync -aAX {backup_home}/ {user_home}/"
        result = run_command(cmd, shell=True, check=False, capture_output=True)
        
        if result.returncode != 0:
            print(f"❌ Failed to restore backup: {result.stderr}")
            return False
        
        # Fix ownership and permissions
        run_command(f"chown -R {user}:{user} {user_home}", shell=True)
        run_command(f"chmod -R u+rwX,go-w {user_home}", shell=True)
        
        print(f"✅ User '{user}' reset successfully")
        return True
        
    except Exception as e:
        print(f"❌ Failed to reset user account: {e}")
        return False
