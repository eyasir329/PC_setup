#!/usr/bin/env python3
"""
Contest Environment Unrestirctor
Removes all restrictions applied by the contest environment restrictor:
- Restores full internet access
- Allows USB storage devices
- Removes monitoring services
- Cleans up system configurations
"""

import os
import sys
import argparse
import subprocess
from typing import Dict

# Add utils directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'utils'))

from network_restrictor import NetworkRestrictor
from usb_restrictor import USBRestrictor
from common import print_header, print_status, print_error, print_warning


class ContestUnrestrictor:
    def __init__(self, user: str, config_dir: str = None):
        self.user = user
        self.config_dir = config_dir or os.path.dirname(os.path.dirname(__file__))
        self.cache_file = os.path.join(self.config_dir, '.dependency_cache.json')
        
        # Initialize components
        self.network_restrictor = NetworkRestrictor(user)
        self.usb_restrictor = USBRestrictor(user)
        
    def check_root_privileges(self) -> bool:
        """Check if running as root."""
        if os.geteuid() != 0:
            print_error("This script must be run as root to modify system settings")
            return False
        return True
    
    def check_user_exists(self) -> bool:
        """Check if the specified user exists."""
        try:
            import pwd
            pwd.getpwnam(self.user)
            return True
        except KeyError:
            print_error(f"User '{self.user}' does not exist")
            return False
    
    def remove_network_restrictions(self) -> bool:
        """Remove network restrictions."""
        print_header("Removing Network Restrictions")
        
        try:
            success = self.network_restrictor.remove_restrictions()
            if success:
                print_status("Network restrictions removed successfully")
            else:
                print_error("Failed to remove some network restrictions")
            return success
        except Exception as e:
            print_error(f"Error removing network restrictions: {e}")
            return False
    
    def remove_usb_restrictions(self) -> bool:
        """Remove USB storage restrictions."""
        print_header("Removing USB Storage Restrictions")
        
        try:
            success = self.usb_restrictor.remove_usb_restrictions()
            if success:
                print_status("USB storage restrictions removed successfully")
            else:
                print_error("Failed to remove some USB restrictions")
            return success
        except Exception as e:
            print_error(f"Error removing USB restrictions: {e}")
            return False
    
    def remove_monitoring_services(self) -> bool:
        """Remove systemd monitoring services."""
        print_header("Removing Monitoring Services")
        
        try:
            services_to_remove = [
                'contest-monitor.timer',
                'contest-monitor.service'
            ]
            
            success = True
            
            for service in services_to_remove:
                try:
                    # Stop the service
                    print(f"→ Stopping {service}...")
                    subprocess.run(['systemctl', 'stop', service], 
                                 check=False, capture_output=True)
                    
                    # Disable the service
                    print(f"→ Disabling {service}...")
                    subprocess.run(['systemctl', 'disable', service], 
                                 check=False, capture_output=True)
                    
                    # Remove service file
                    service_file = f'/etc/systemd/system/{service}'
                    if os.path.exists(service_file):
                        os.remove(service_file)
                        print(f"✅ Removed {service_file}")
                    else:
                        print(f"✅ {service} was not active")
                
                except Exception as e:
                    print_warning(f"Failed to remove {service}: {e}")
                    success = False
            
            # Reload systemd daemon
            try:
                print("→ Reloading systemd daemon...")
                subprocess.run(['systemctl', 'daemon-reload'], check=True)
                print_status("Systemd daemon reloaded")
            except Exception as e:
                print_warning(f"Failed to reload systemd daemon: {e}")
                success = False
            
            if success:
                print_status("Monitoring services removed successfully")
            else:
                print_warning("Some monitoring services may not have been fully removed")
            
            return success
            
        except Exception as e:
            print_error(f"Error removing monitoring services: {e}")
            return False
    
    def clean_cache_files(self) -> bool:
        """Clean up cache and temporary files."""
        print_header("Cleaning Cache Files")
        
        try:
            files_to_remove = [
                self.cache_file,
                os.path.join(self.config_dir, f'{self.user}_domains_cache.txt'),
                os.path.join(self.config_dir, f'{self.user}_ip_cache.txt'),
                '/var/log/contest-usb.log'
            ]
            
            removed_count = 0
            
            for file_path in files_to_remove:
                try:
                    if os.path.exists(file_path):
                        os.remove(file_path)
                        print(f"✅ Removed {file_path}")
                        removed_count += 1
                    else:
                        print(f"   {file_path} (not found)")
                except Exception as e:
                    print_warning(f"Failed to remove {file_path}: {e}")
            
            print_status(f"Cleaned {removed_count} cache files")
            return True
            
        except Exception as e:
            print_error(f"Error cleaning cache files: {e}")
            return False
    
    def remove_update_scripts(self) -> bool:
        """Remove IP update scripts."""
        print_header("Removing Update Scripts")
        
        try:
            scripts_to_remove = [
                f'/usr/local/bin/update-contest-whitelist-{self.user}',
                '/usr/local/bin/update-contest-whitelist'
            ]
            
            removed_count = 0
            
            for script_path in scripts_to_remove:
                try:
                    if os.path.exists(script_path):
                        os.remove(script_path)
                        print(f"✅ Removed {script_path}")
                        removed_count += 1
                    else:
                        print(f"   {script_path} (not found)")
                except Exception as e:
                    print_warning(f"Failed to remove {script_path}: {e}")
            
            print_status(f"Removed {removed_count} update scripts")
            return True
            
        except Exception as e:
            print_error(f"Error removing update scripts: {e}")
            return False
    
    def check_restriction_status(self) -> Dict:
        """Check current restriction status."""
        try:
            network_active = self.network_restrictor.is_active()
            usb_status = self.usb_restrictor.get_restriction_status()
            
            return {
                'network_active': network_active,
                'usb_active': usb_status['udev_rules_active'] or usb_status['polkit_rules_active'],
                'monitoring_active': self.check_monitoring_active(),
                'user': self.user
            }
        except Exception as e:
            print_warning(f"Error checking restriction status: {e}")
            return {
                'network_active': False,
                'usb_active': False,
                'monitoring_active': False,
                'user': self.user
            }
    
    def check_monitoring_active(self) -> bool:
        """Check if monitoring services are active."""
        try:
            result = subprocess.run(['systemctl', 'is-active', 'contest-monitor.timer'], 
                                  capture_output=True, text=True)
            return result.returncode == 0 and 'active' in result.stdout
        except:
            return False
    
    def show_status(self):
        """Show current restriction status."""
        print_header("Contest Environment Status")
        
        status = self.check_restriction_status()
        
        print(f"User: {status['user']}")
        print(f"Network restrictions: {'✅ Active' if status['network_active'] else '❌ Inactive'}")
        print(f"USB restrictions: {'✅ Active' if status['usb_active'] else '❌ Inactive'}")
        print(f"Monitoring services: {'✅ Active' if status['monitoring_active'] else '❌ Inactive'}")
        
        if status['network_active'] or status['usb_active'] or status['monitoring_active']:
            print("\n⚠️  Some restrictions are still active")
            print("   Run with --remove to remove all restrictions")
        else:
            print("\n✅ No restrictions are currently active")
        
        # Show detailed status if available
        if status['network_active']:
            print("\n📊 Network Status:")
            self.network_restrictor.show_status()
        
        if status['usb_active']:
            print("\n📊 USB Status:")
            self.usb_restrictor.show_status()
    
    def remove_all_restrictions(self, force: bool = False) -> bool:
        """Remove all restrictions."""
        print_header("Removing All Contest Environment Restrictions")
        
        # Check prerequisites
        if not self.check_root_privileges():
            return False
        
        if not self.check_user_exists():
            return False
        
        # Check if restrictions are active
        status = self.check_restriction_status()
        
        if not force and not any([status['network_active'], status['usb_active'], status['monitoring_active']]):
            print_warning("No restrictions appear to be active for this user")
            print("Use --force to clean up any remaining configuration files")
            return True
        
        success = True
        
        # Remove network restrictions
        if not self.remove_network_restrictions():
            success = False
        
        # Remove USB restrictions
        if not self.remove_usb_restrictions():
            success = False
        
        # Remove monitoring services
        if not self.remove_monitoring_services():
            success = False
        
        # Remove update scripts
        if not self.remove_update_scripts():
            success = False
        
        # Clean cache files
        if not self.clean_cache_files():
            success = False
        
        # Final status
        if success:
            print_header("✅ Contest Environment Restrictions Removed Successfully")
            print("All restrictions have been removed:")
            print("   🌐 Internet access fully restored")
            print("   🔓 USB storage devices allowed")
            print("   📊 Monitoring services stopped and removed")
            print("   🧹 Cache files cleaned up")
            print(f"   👤 User '{self.user}' is now unrestricted")
        else:
            print_header("❌ Some Restrictions Failed to Remove")
            print("Please check the errors above and try manual cleanup if needed.")
            print("You may need to:")
            print("   - Manually remove iptables rules")
            print("   - Remove udev/polkit rules")
            print("   - Stop systemd services")
        
        return success
    
    def verify_removal(self) -> bool:
        """Verify that all restrictions have been removed."""
        print_header("Verifying Restriction Removal")
        
        status = self.check_restriction_status()
        
        issues = []
        
        if status['network_active']:
            issues.append("Network restrictions still active")
        
        if status['usb_active']:
            issues.append("USB restrictions still active")
        
        if status['monitoring_active']:
            issues.append("Monitoring services still active")
        
        if issues:
            print_error("Verification failed:")
            for issue in issues:
                print(f"   - {issue}")
            return False
        else:
            print_status("Verification successful - all restrictions removed")
            return True


def main():
    parser = argparse.ArgumentParser(
        description="Contest Environment Unrestirctor",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  sudo python3 unrestrict.py --user alice --remove
  sudo python3 unrestrict.py --user alice --status
  sudo python3 unrestrict.py --user alice --remove --force
  sudo python3 unrestrict.py --user alice --verify
        """
    )
    
    parser.add_argument('--user', required=True, help='Username to remove restrictions for')
    parser.add_argument('--remove', action='store_true', help='Remove all restrictions')
    parser.add_argument('--status', action='store_true', help='Show current restriction status')
    parser.add_argument('--verify', action='store_true', help='Verify that restrictions have been removed')
    parser.add_argument('--force', action='store_true', help='Force removal even if restrictions appear inactive')
    parser.add_argument('--config-dir', help='Configuration directory path')
    
    args = parser.parse_args()
    
    # Create unrestrictor instance
    unrestrictor = ContestUnrestrictor(args.user, args.config_dir)
    
    # Execute requested action
    if args.remove:
        success = unrestrictor.remove_all_restrictions(force=args.force)
        sys.exit(0 if success else 1)
    
    elif args.status:
        unrestrictor.show_status()
        sys.exit(0)
    
    elif args.verify:
        success = unrestrictor.verify_removal()
        sys.exit(0 if success else 1)
    
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()