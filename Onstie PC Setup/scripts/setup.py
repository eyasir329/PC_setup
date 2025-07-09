#!/usr/bin/env python3
"""
Contest Environment Setup Script
Sets up lab PC with required software and user account for contest environments.
"""

import sys
import os
import subprocess

# Add utils directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'utils'))

from user_manager import create_contest_user, create_user_backup
from software_installer import (
    install_programming_languages, install_basic_editors, 
    install_sublime_text, install_vscode, install_vscode_extensions,
    install_grub_customizer, install_browsers, verify_essential_software
)
from system_utils import (
    disable_system_updates, cleanup_system, fix_vscode_keyring, fix_codeblocks_permissions,
    clean_temporary_files, fix_user_permissions, create_project_directories, add_user_to_groups
)
from common import print_step

DEFAULT_USER = "participant"


def main():
    """Main setup function."""
    if len(sys.argv) < 2:
        print("Usage: python3 setup.py <username>")
        sys.exit(1)
    
    user = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_USER
    
    print("=" * 60)
    print(f"Contest Environment Setup for user '{user}'")
    print(f"Starting at: {subprocess.check_output('date', shell=True).decode().strip()}")
    print("=" * 60)
    
    # Check if running as root
    if os.geteuid() != 0:
        print("❌ This script must be run as root")
        sys.exit(1)
    
    try:
        # Step 1: Setup user account
        print_step(1, f"Setting up user account '{user}'")
        create_contest_user(user)
        
        # Step 2: Install programming languages
        print_step(2, "Installing programming languages")
        install_programming_languages()
        
        # Step 3: Install code editors
        print_step(3, "Installing code editors")
        install_basic_editors()
        install_sublime_text()
        install_vscode()
        
        # Step 4: Install VS Code extensions
        print_step(4, "Installing VS Code extensions")
        install_vscode_extensions(user)
        
        # Step 5: Install GRUB Customizer
        print_step(5, "Installing GRUB Customizer")
        install_grub_customizer()
        
        # Step 6: Install browsers
        print_step(6, "Installing browsers")
        install_browsers()
        
        # Step 7: Disable system updates
        print_step(7, "Disabling system updates")
        disable_system_updates()
        
        # Step 8: System cleanup
        print_step(8, "System cleanup")
        cleanup_system()
        
        # Fix known issues
        print_step(9, "Fixing known issues")
        fix_vscode_keyring(user)
        fix_codeblocks_permissions(user)
        
        # Clean temporary files
        print_step(10, "Cleaning temporary files")
        clean_temporary_files(user)
        
        # Fix user permissions
        print_step(11, "Fixing user permissions")
        fix_user_permissions(user)
        
        # Create project directories
        print_step(12, "Creating project directories")
        create_project_directories(user)
        
        # Add user to groups
        print_step(13, "Adding user to groups")
        add_user_to_groups(user)
        
        # Verify essential software
        print_step(14, "Verifying essential software")
        verify_essential_software()
        
        # Create backup
        print_step(15, "Creating user backup")
        create_user_backup(user)
        
        print("=" * 60)
        print("✅ Contest Environment Setup Completed Successfully!")
        print("=" * 60)
        
    except Exception as e:
        print(f"❌ Setup failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
