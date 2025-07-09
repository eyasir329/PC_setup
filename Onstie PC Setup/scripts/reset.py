#!/usr/bin/env python3
"""
Contest Environment Reset Script
Resets user account to clean state by restoring from backup.
"""

import os
import sys
import subprocess
import shutil
from pathlib import Path

# Add utils directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'utils'))

from user_manager import create_user_backup
from system_utils import (
    fix_vscode_keyring, fix_codeblocks_permissions, clean_temporary_files,
    fix_user_permissions, create_project_directories, add_user_to_groups
)
from software_installer import verify_essential_software
from common import print_header, print_status, print_error, print_warning, run_command

DEFAULT_USER = "participant"


class ContestReset:
    def __init__(self, user: str):
        self.user = user
        self.user_home = f"/home/{user}"
        self.backup_dir = f"/opt/{user}_backup"
        self.backup_home = f"{self.backup_dir}/{user}_home"
        
    def check_prerequisites(self) -> bool:
        """Check if reset can be performed."""
        print_header("Checking Prerequisites")
        
        # Check if running as root
        if os.geteuid() != 0:
            print_error("This script must be run as root")
            return False
        
        # Check if user exists
        try:
            import pwd
            pwd.getpwnam(self.user)
            print_status(f"User '{self.user}' exists")
        except KeyError:
            print_error(f"User '{self.user}' does not exist")
            return False
        
        # Check if backup exists
        if not os.path.exists(self.backup_home):
            print_error(f"Backup directory {self.backup_home} does not exist")
            print("Please run setup.py first to create a backup")
            return False
        
        print_status(f"Backup found at {self.backup_home}")
        
        # Check if user is logged out
        try:
            result = subprocess.run(['pgrep', '-u', self.user], 
                                  capture_output=True, text=True)
            if result.returncode == 0:
                print_error(f"User '{self.user}' is currently logged in")
                print("Please log them out before resetting")
                return False
        except:
            pass  # pgrep not found or other error, continue
        
        print_status("All prerequisites satisfied")
        return True
    
    def delete_user_home(self) -> bool:
        """Delete current user home directory contents."""
        print_header("Deleting Current User Home")
        
        try:
            # Delete all contents but preserve the directory
            print(f"→ Deleting contents of {self.user_home}...")
            
            # Use Python to safely delete contents
            home_path = Path(self.user_home)
            if home_path.exists():
                for item in home_path.iterdir():
                    if item.is_file() or item.is_symlink():
                        item.unlink()
                    elif item.is_dir():
                        shutil.rmtree(item)
                
                print_status("User home contents deleted successfully")
            else:
                print_warning(f"Home directory {self.user_home} does not exist")
                
            return True
            
        except Exception as e:
            print_error(f"Failed to delete user home: {e}")
            return False
    
    def restore_from_backup(self) -> bool:
        """Restore user home from backup."""
        print_header("Restoring from Backup")
        
        try:
            print(f"→ Restoring from {self.backup_home}...")
            
            # Use rsync to restore backup
            cmd = f"rsync -aAX {self.backup_home}/ {self.user_home}/"
            result = run_command(cmd, shell=True, check=False, capture_output=True)
            
            if result.returncode == 0:
                print_status("Home directory restored successfully")
                return True
            else:
                print_error(f"Failed to restore backup: {result.stderr}")
                return False
                
        except Exception as e:
            print_error(f"Error restoring from backup: {e}")
            return False
    
    def fix_permissions(self) -> bool:
        """Fix file permissions and ownership."""
        print_header("Fixing File Permissions")
        return fix_user_permissions(self.user)
    
    def clean_temporary_files(self) -> bool:
        """Clean temporary and cache files."""
        print_header("Cleaning Temporary Files")
        return clean_temporary_files(self.user)
    
    def verify_software_intact(self) -> bool:
        """Verify essential software is still installed."""
        print_header("Verifying Essential Software")
        
        try:
            # Use the software installer's verification function
            if verify_essential_software():
                print_status("All essential software is intact")
                return True
            else:
                print_error("Some essential software is missing")
                return False
                
        except Exception as e:
            print_error(f"Failed to verify software: {e}")
            return False
    
    def fix_application_issues(self) -> bool:
        """Fix known application issues."""
        print_header("Fixing Application Issues")
        
        try:
            success = True
            
            # Fix VSCode keyring issues
            print("→ Fixing VSCode keyring issues...")
            if not fix_vscode_keyring(self.user):
                print_warning("VSCode keyring fix failed")
                success = False
            
            # Fix CodeBlocks permissions
            print("→ Fixing CodeBlocks permissions...")
            if not fix_codeblocks_permissions(self.user):
                print_warning("CodeBlocks permissions fix failed")
                success = False
            
            if success:
                print_status("Application issues fixed successfully")
            else:
                print_warning("Some application fixes failed")
                
            return success
            
        except Exception as e:
            print_error(f"Failed to fix application issues: {e}")
            return False
    
    def add_user_to_groups(self) -> bool:
        """Add user to necessary groups."""
        print_header("Adding User to Groups")
        return add_user_to_groups(self.user)
    
    def create_project_directories(self) -> bool:
        """Create project directories with proper permissions."""
        print_header("Creating Project Directories")
        return create_project_directories(self.user)
    
    def reset_user_account(self) -> bool:
        """Perform complete user account reset."""
        print_header(f"Resetting User Account '{self.user}'")
        
        success = True
        
        # Step 1: Check prerequisites
        if not self.check_prerequisites():
            return False
        
        # Step 2: Delete user home
        if not self.delete_user_home():
            success = False
        
        # Step 3: Restore from backup
        if not self.restore_from_backup():
            success = False
        
        # Step 4: Fix permissions
        if not self.fix_permissions():
            success = False
        
        # Step 5: Clean temporary files
        if not self.clean_temporary_files():
            success = False
        
        # Step 6: Verify software
        if not self.verify_software_intact():
            success = False
        
        # Step 7: Fix application issues
        if not self.fix_application_issues():
            success = False
        
        # Step 8: Add user to groups
        if not self.add_user_to_groups():
            success = False
        
        # Step 9: Create project directories
        if not self.create_project_directories():
            success = False
        
        # Final result
        if success:
            print_header("✅ User Account Reset Successfully")
            print("The user account has been reset to clean state:")
            print(f"   👤 User: {self.user}")
            print("   🏠 Home directory restored from backup")
            print("   🔧 Permissions and ownership fixed")
            print("   🧹 Temporary files cleaned")
            print("   📦 Essential software verified")
            print("   ⚙️  Application issues fixed")
            print("   📁 Project directories created")
        else:
            print_header("❌ User Account Reset Failed")
            print("Some steps failed during the reset process.")
            print("Please check the errors above and try again.")
        
        return success


def main():
    """Main function."""
    if len(sys.argv) < 2:
        print("Usage: python3 reset.py <username>")
        sys.exit(1)
    
    user = sys.argv[1]
    
    # Create reset instance and perform reset
    reset_manager = ContestReset(user)
    success = reset_manager.reset_user_account()
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
