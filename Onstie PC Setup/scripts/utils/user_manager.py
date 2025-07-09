#!/usr/bin/env python3
"""
User management utilities for contest environment.
"""

import os
from .common import run_command, user_exists, ensure_user_can_execute


def create_contest_user(user):
    """Create a contest user with minimal privileges."""
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
