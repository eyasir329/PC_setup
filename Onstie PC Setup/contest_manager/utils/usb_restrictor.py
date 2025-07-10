#!/usr/bin/env python3
"""
USB Device Restriction Manager
Handles blocking of USB storage devices while allowing keyboards/mice.
"""

import subprocess
import os
import pwd
import grp
import tempfile
from typing import List, Dict
import json


class USBRestrictor:
    def __init__(self, user: str):
        self.user = user
        self.user_uid = self.get_user_uid(user)
        self.user_gid = self.get_user_gid(user)
        
        # Paths for configuration files
        self.udev_rules_path = "/etc/udev/rules.d/99-contest-usb-block.rules"
        self.polkit_rules_path = "/etc/polkit-1/rules.d/99-contest-usb-block.rules"
        
    def get_user_uid(self, user: str) -> int:
        """Get UID for the specified user."""
        try:
            return pwd.getpwnam(user).pw_uid
        except KeyError:
            raise ValueError(f"User '{user}' does not exist")
    
    def get_user_gid(self, user: str) -> int:
        """Get GID for the specified user."""
        try:
            return pwd.getpwnam(user).pw_gid
        except KeyError:
            raise ValueError(f"User '{user}' does not exist")
    
    def run_command(self, cmd: List[str], check: bool = True) -> subprocess.CompletedProcess:
        """Run a command and return the result."""
        try:
            result = subprocess.run(cmd, check=check, capture_output=True, text=True)
            return result
        except subprocess.CalledProcessError as e:
            if check:
                print(f"❌ Command failed: {' '.join(cmd)}")
                print(f"Error: {e.stderr}")
                raise
            return e
    
    def create_udev_rules(self) -> bool:
        """Create udev rules to block USB storage devices."""
        udev_rules = f'''# Contest USB Storage Restriction Rules
# Block USB storage devices for user {self.user}
# Allow keyboards, mice, and other input devices

# Block USB mass storage devices
ACTION=="add", SUBSYSTEM=="block", ATTRS{{removable}}=="1", ENV{{ID_BUS}}=="usb", RUN+="/bin/sh -c 'echo Block USB storage for contest user {self.user}'"
ACTION=="add", SUBSYSTEM=="block", ATTRS{{removable}}=="1", ENV{{ID_BUS}}=="usb", OWNER:="{self.user}", GROUP:="nogroup", MODE:="000"

# Block USB storage class devices
ACTION=="add", SUBSYSTEM=="usb", ATTR{{bInterfaceClass}}=="08", RUN+="/bin/sh -c 'echo Block USB mass storage class'"
ACTION=="add", SUBSYSTEM=="usb", ATTR{{bInterfaceClass}}=="08", OWNER:="{self.user}", GROUP:="nogroup", MODE:="000"

# Block specific USB storage device types
ACTION=="add", SUBSYSTEM=="usb", ENV{{ID_USB_DRIVER}}=="usb-storage", RUN+="/bin/sh -c 'echo Block usb-storage driver'"
ACTION=="add", SUBSYSTEM=="usb", ENV{{ID_USB_DRIVER}}=="usb-storage", OWNER:="{self.user}", GROUP:="nogroup", MODE:="000"

# Allow USB HID devices (keyboards, mice)
ACTION=="add", SUBSYSTEM=="usb", ATTR{{bInterfaceClass}}=="03", RUN+="/bin/sh -c 'echo Allow USB HID device'"

# Allow USB hubs
ACTION=="add", SUBSYSTEM=="usb", ATTR{{bInterfaceClass}}=="09", RUN+="/bin/sh -c 'echo Allow USB hub'"

# Log USB device attempts
ACTION=="add", SUBSYSTEM=="usb", RUN+="/bin/sh -c 'echo \\"USB device: %k %s{{vendor}} %s{{product}}\\" >> /var/log/contest-usb.log'"
'''
        
        try:
            with open(self.udev_rules_path, 'w') as f:
                f.write(udev_rules)
            
            # Set proper permissions
            os.chmod(self.udev_rules_path, 0o644)
            print(f"✅ Created udev rules at {self.udev_rules_path}")
            return True
        except Exception as e:
            print(f"❌ Failed to create udev rules: {e}")
            return False
    
    def create_polkit_rules(self) -> bool:
        """Create polkit rules to prevent USB storage mounting."""
        polkit_rules = f'''// Contest USB Storage Restriction
// Prevent user {self.user} from mounting USB storage devices

polkit.addRule(function(action, subject) {{
    if (action.id == "org.freedesktop.udisks2.filesystem-mount" ||
        action.id == "org.freedesktop.udisks2.filesystem-mount-system" ||
        action.id == "org.freedesktop.udisks2.encrypted-unlock") {{
        
        // Get device path
        var device = action.lookup("device");
        
        // Check if it's a USB device
        if (device && device.indexOf("/dev/sd") == 0) {{
            // Check if user is the contest user
            if (subject.user == "{self.user}") {{
                polkit.log("Blocking USB storage mount attempt by contest user {self.user}");
                return polkit.Result.NO;
            }}
        }}
    }}
    
    // Block USB storage related actions for contest user
    if (subject.user == "{self.user}") {{
        if (action.id.indexOf("org.freedesktop.udisks2") == 0) {{
            var device = action.lookup("device");
            if (device && (device.indexOf("usb") != -1 || device.indexOf("removable") != -1)) {{
                polkit.log("Blocking USB storage action for contest user {self.user}: " + action.id);
                return polkit.Result.NO;
            }}
        }}
    }}
}});
'''
        
        try:
            with open(self.polkit_rules_path, 'w') as f:
                f.write(polkit_rules)
            
            # Set proper permissions
            os.chmod(self.polkit_rules_path, 0o644)
            print(f"✅ Created polkit rules at {self.polkit_rules_path}")
            return True
        except Exception as e:
            print(f"❌ Failed to create polkit rules: {e}")
            return False
    
    def setup_logging(self) -> bool:
        """Setup logging for USB device attempts."""
        try:
            # Create log file with proper permissions
            log_file = "/var/log/contest-usb.log"
            
            # Create log file if it doesn't exist
            if not os.path.exists(log_file):
                with open(log_file, 'w') as f:
                    f.write("# Contest USB Device Access Log\n")
                
                # Set permissions so the contest user can read but not write
                os.chmod(log_file, 0o644)
            
            print(f"✅ USB logging configured at {log_file}")
            return True
        except Exception as e:
            print(f"❌ Failed to setup USB logging: {e}")
            return False
    
    def get_connected_usb_devices(self) -> List[Dict]:
        """Get list of currently connected USB devices."""
        devices = []
        
        try:
            # Use lsusb to get USB device information
            result = self.run_command(['lsusb'], check=False)
            if result.returncode == 0:
                for line in result.stdout.strip().split('\n'):
                    if line.strip():
                        parts = line.split(maxsplit=5)
                        if len(parts) >= 6:
                            device_info = {
                                'bus': parts[1].replace(':', ''),
                                'device': parts[3].replace(':', ''),
                                'id': parts[5].split()[0],
                                'description': ' '.join(parts[5].split()[1:])
                            }
                            devices.append(device_info)
            
            # Get detailed device information
            for device in devices:
                try:
                    # Check if it's a storage device
                    lsusb_detail = self.run_command(['lsusb', '-d', device['id'], '-v'], check=False)
                    if lsusb_detail.returncode == 0:
                        if 'bInterfaceClass         8 Mass Storage' in lsusb_detail.stdout:
                            device['is_storage'] = True
                        elif 'bInterfaceClass         3 Human Interface Device' in lsusb_detail.stdout:
                            device['is_hid'] = True
                        else:
                            device['is_storage'] = False
                            device['is_hid'] = False
                except:
                    device['is_storage'] = False
                    device['is_hid'] = False
            
            return devices
        except Exception as e:
            print(f"❌ Error getting USB devices: {e}")
            return []
    
    def block_existing_usb_storage(self) -> bool:
        """Block any currently connected USB storage devices."""
        print("→ Checking for existing USB storage devices...")
        
        devices = self.get_connected_usb_devices()
        storage_devices = [d for d in devices if d.get('is_storage', False)]
        
        if not storage_devices:
            print("✅ No USB storage devices found")
            return True
        
        print(f"⚠️  Found {len(storage_devices)} USB storage device(s):")
        for device in storage_devices:
            print(f"   - {device['description']} (ID: {device['id']})")
        
        # Try to unmount any mounted USB drives
        try:
            # Get mounted USB drives
            mount_result = self.run_command(['mount'], check=False)
            if mount_result.returncode == 0:
                usb_mounts = []
                for line in mount_result.stdout.split('\n'):
                    if '/dev/sd' in line and 'media' in line:
                        mount_point = line.split()[2]
                        usb_mounts.append(mount_point)
                
                # Unmount USB drives
                for mount_point in usb_mounts:
                    print(f"→ Unmounting {mount_point}...")
                    self.run_command(['umount', mount_point], check=False)
            
            print("✅ Existing USB storage devices handled")
            return True
        except Exception as e:
            print(f"❌ Error handling existing USB storage: {e}")
            return False
    
    def reload_udev_rules(self) -> bool:
        """Reload udev rules to apply changes."""
        try:
            print("→ Reloading udev rules...")
            self.run_command(['udevadm', 'control', '--reload-rules'])
            self.run_command(['udevadm', 'trigger'])
            print("✅ Udev rules reloaded")
            return True
        except Exception as e:
            print(f"❌ Failed to reload udev rules: {e}")
            return False
    
    def restart_polkit(self) -> bool:
        """Restart polkit service to apply new rules."""
        try:
            print("→ Restarting polkit service...")
            self.run_command(['systemctl', 'restart', 'polkit'], check=False)
            print("✅ Polkit service restarted")
            return True
        except Exception as e:
            print(f"❌ Failed to restart polkit: {e}")
            return False
    
    def apply_usb_restrictions(self) -> bool:
        """Apply all USB restrictions."""
        print("🔒 Applying USB storage restrictions...")
        
        success = True
        
        # Create and apply udev rules
        if not self.create_udev_rules():
            success = False
        
        # Create and apply polkit rules
        if not self.create_polkit_rules():
            success = False
        
        # Setup logging
        if not self.setup_logging():
            success = False
        
        # Handle existing USB storage devices
        if not self.block_existing_usb_storage():
            success = False
        
        # Reload services
        if not self.reload_udev_rules():
            success = False
        
        if not self.restart_polkit():
            success = False
        
        if success:
            print("✅ USB storage restrictions applied successfully")
            print("   - USB storage devices are now blocked")
            print("   - USB keyboards and mice will continue to work")
            print("   - Device access attempts will be logged")
        else:
            print("❌ Some USB restriction steps failed")
        
        return success
    
    def remove_usb_restrictions(self) -> bool:
        """Remove all USB restrictions."""
        print("🔓 Removing USB storage restrictions...")
        
        success = True
        
        # Remove udev rules
        try:
            if os.path.exists(self.udev_rules_path):
                os.remove(self.udev_rules_path)
                print(f"✅ Removed udev rules: {self.udev_rules_path}")
        except Exception as e:
            print(f"❌ Failed to remove udev rules: {e}")
            success = False
        
        # Remove polkit rules
        try:
            if os.path.exists(self.polkit_rules_path):
                os.remove(self.polkit_rules_path)
                print(f"✅ Removed polkit rules: {self.polkit_rules_path}")
        except Exception as e:
            print(f"❌ Failed to remove polkit rules: {e}")
            success = False
        
        # Reload services
        if not self.reload_udev_rules():
            success = False
        
        if not self.restart_polkit():
            success = False
        
        if success:
            print("✅ USB storage restrictions removed successfully")
        else:
            print("❌ Some USB restriction removal steps failed")
        
        return success
    
    def get_restriction_status(self) -> Dict:
        """Get current USB restriction status."""
        status = {
            'udev_rules_active': os.path.exists(self.udev_rules_path),
            'polkit_rules_active': os.path.exists(self.polkit_rules_path),
            'connected_devices': self.get_connected_usb_devices()
        }
        
        return status
    
    def show_status(self):
        """Show current USB restriction status."""
        print("📊 USB Restriction Status:")
        
        status = self.get_restriction_status()
        
        print(f"   udev rules: {'✅ Active' if status['udev_rules_active'] else '❌ Inactive'}")
        print(f"   polkit rules: {'✅ Active' if status['polkit_rules_active'] else '❌ Inactive'}")
        
        devices = status['connected_devices']
        if devices:
            print(f"   Connected USB devices: {len(devices)}")
            for device in devices:
                device_type = "🔒 Storage" if device.get('is_storage') else "✅ HID" if device.get('is_hid') else "❓ Other"
                print(f"     - {device_type}: {device['description']}")
        else:
            print("   Connected USB devices: None")


def apply_usb_restrictions(username: str) -> bool:
    """Apply USB restrictions for a user.
    
    Args:
        username: The username to apply restrictions for
        
    Returns:
        True if successful, False otherwise
    """
    try:
        # Create USB restrictor instance
        restrictor = USBRestrictor(username)
        
        # Apply restrictions
        success = restrictor.apply_usb_restrictions()
        
        if success:
            print(f"✅ USB restrictions applied for user '{username}'")
        else:
            print(f"❌ Failed to apply USB restrictions for user '{username}'")
            
        return success
        
    except Exception as e:
        print(f"❌ Failed to apply USB restrictions: {e}")
        return False


def remove_usb_restrictions(username: str) -> bool:
    """Remove USB restrictions for a user.
    
    Args:
        username: The username to remove restrictions for
        
    Returns:
        True if successful, False otherwise
    """
    try:
        # Create USB restrictor instance
        restrictor = USBRestrictor(username)
        
        # Remove restrictions
        success = restrictor.remove_usb_restrictions()
        
        if success:
            print(f"✅ USB restrictions removed for user '{username}'")
        else:
            print(f"❌ Failed to remove USB restrictions for user '{username}'")
            
        return success
        
    except Exception as e:
        print(f"❌ Failed to remove USB restrictions: {e}")
        return False
