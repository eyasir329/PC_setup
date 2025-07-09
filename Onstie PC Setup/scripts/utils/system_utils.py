#!/usr/bin/env python3
"""
System utilities for contest environment.
"""

import os
import shutil
from .common import run_command, print_status, print_error, print_warning


def disable_system_updates():
    """Disable automatic system updates."""
    print("→ Disabling automatic system updates...")
    
    # Stop update services
    services = ["apt-daily.service", "apt-daily-upgrade.service"]
    for service in services:
        run_command(f"systemctl stop {service}", shell=True, check=False)
        run_command(f"systemctl disable {service}", shell=True, check=False)
    
    print("✅ Automatic system updates disabled.")


def cleanup_system():
    """Clean up system packages."""
    print("→ Cleaning up system...")
    
    run_command("apt autoremove -y", shell=True)
    run_command("apt autoclean", shell=True)
    
    print("✅ System cleanup completed.")


def clean_temporary_files(user: str) -> bool:
    """Clean temporary and cache files for a user."""
    print("→ Cleaning temporary files...")
    
    try:
        user_home = f"/home/{user}"
        
        temp_patterns = [
            "*.tmp", "*.bak", "*.*~", "*.swp", "*.swo"
        ]
        
        # Clean temporary files
        for pattern in temp_patterns:
            cmd = f"find {user_home} -name '{pattern}' -type f -delete"
            run_command(cmd, shell=True, check=False)
        
        # Clean cache directories
        cache_dirs = [
            f"{user_home}/.cache",
            f"{user_home}/.local/share/Trash",
            f"{user_home}/.config/Code/logs",
            f"{user_home}/.config/Code/CachedData"
        ]
        
        for cache_dir in cache_dirs:
            if os.path.exists(cache_dir):
                print(f"→ Cleaning {cache_dir}...")
                shutil.rmtree(cache_dir, ignore_errors=True)
                os.makedirs(cache_dir, exist_ok=True)
                run_command(f"chown -R {user}:{user} {cache_dir}", shell=True)
        
        print("✅ Temporary files cleaned successfully")
        return True
        
    except Exception as e:
        print_error(f"Failed to clean temporary files: {e}")
        return False


def fix_user_permissions(user: str) -> bool:
    """Fix file permissions and ownership for a user."""
    print("→ Fixing file permissions...")
    
    try:
        user_home = f"/home/{user}"
        
        # Fix ownership
        print(f"→ Setting ownership to {user}:{user}...")
        run_command(f"chown -R {user}:{user} {user_home}", shell=True)
        
        # Fix permissions
        print(f"→ Setting proper permissions...")
        run_command(f"chmod -R u+rwX {user_home}", shell=True)
        
        print("✅ File permissions fixed successfully")
        return True
        
    except Exception as e:
        print_error(f"Failed to fix permissions: {e}")
        return False


def create_project_directories(user: str) -> bool:
    """Create project directories with proper permissions."""
    print("→ Creating project directories...")
    
    try:
        user_home = f"/home/{user}"
        
        # Create CodeBlocks projects directory
        cb_projects = f"{user_home}/cb_projects"
        os.makedirs(cb_projects, exist_ok=True)
        
        # Create subdirectories
        for subdir in ["bin", "bin/Debug", "bin/Release"]:
            path = f"{cb_projects}/{subdir}"
            os.makedirs(path, exist_ok=True)
        
        # Set permissions
        run_command(f"chown -R {user}:{user} {cb_projects}", shell=True)
        run_command(f"chmod -R 755 {cb_projects}", shell=True)
        
        # Create Desktop directory if it doesn't exist
        desktop_dir = f"{user_home}/Desktop"
        os.makedirs(desktop_dir, exist_ok=True)
        run_command(f"chown {user}:{user} {desktop_dir}", shell=True)
        
        print("✅ Project directories created successfully")
        return True
        
    except Exception as e:
        print_error(f"Failed to create project directories: {e}")
        return False


def add_user_to_groups(user: str) -> bool:
    """Add user to necessary groups."""
    print("→ Adding user to groups...")
    
    try:
        # Add to necessary groups (not sudo for security)
        groups = ["adm", "dialout", "cdrom", "floppy", "audio", "dip", "video", "plugdev", "netdev"]
        
        for group in groups:
            try:
                run_command(f"usermod -aG {group} {user}", shell=True, check=False)
            except:
                pass  # Group might not exist, continue
        
        print("✅ User added to necessary groups")
        return True
        
    except Exception as e:
        print_error(f"Failed to add user to groups: {e}")
        return False


def fix_vscode_keyring(user):
    """Fix VS Code keyring issues."""
    print("→ Fixing VS Code keyring issues...")
    
    # Install keyring support
    run_command("apt install -y libpam-gnome-keyring", shell=True)
    
    # Configure PAM
    auth_file = "/etc/pam.d/common-auth"
    session_file = "/etc/pam.d/common-session"
    
    # Add keyring auth if not present
    with open(auth_file, 'r') as f:
        content = f.read()
    if "pam_gnome_keyring.so" not in content:
        with open(auth_file, 'a') as f:
            f.write("auth optional pam_gnome_keyring.so\n")
    
    # Add keyring session if not present
    with open(session_file, 'r') as f:
        content = f.read()
    if "pam_gnome_keyring.so auto_start" not in content:
        with open(session_file, 'a') as f:
            f.write("session optional pam_gnome_keyring.so auto_start\n")
    
    # Clear existing keyring files
    keyring_dir = f"/home/{user}/.local/share/keyrings"
    if os.path.exists(keyring_dir):
        shutil.rmtree(keyring_dir)
    
    print("✅ VS Code keyring issues fixed.")


def fix_codeblocks_permissions(user):
    """Fix CodeBlocks permissions and setup."""
    print("→ Fixing CodeBlocks permissions...")
    
    # Install ACL support
    run_command("apt install -y acl", shell=True)
    
    # Set up CodeBlocks directories
    home_dir = f"/home/{user}"
    cb_projects = f"{home_dir}/cb_projects"
    cb_bin = f"{cb_projects}/bin"
    
    # Create directories as user
    run_command(f"sudo -u {user} mkdir -p {cb_projects}/bin/Debug", shell=True)
    run_command(f"sudo -u {user} mkdir -p {cb_projects}/bin/Release", shell=True)
    
    # Set permissions
    run_command(f"chown -R {user}:{user} {home_dir}", shell=True)
    run_command(f"chmod -R u+rwX {home_dir}", shell=True)
    
    # Set ACL for execute permissions
    run_command(f"setfacl -R -d -m u::rwx,g::rx,o::rx {cb_bin}", shell=True)
    run_command(f"setfacl -R -m u::rwx,g::rx,o::rx {cb_bin}", shell=True)
    
    # Find and make executable any existing compiled programs
    run_command(f"find {cb_bin} -type f -exec chmod +x {{}} \\;", shell=True, check=False)
    
    print("✅ CodeBlocks permissions fixed.")
