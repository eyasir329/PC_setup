#!/usr/bin/env python3
"""
Contest Environment Manager Installer
Installs all dependencies, copies files, and sets up the contest environment manager system.
"""

import os
import sys
import subprocess
import shutil
import stat
import pwd
import grp
from pathlib import Path
import argparse

class ContestManagerInstaller:
    def __init__(self, install_prefix="/usr/local"):
        self.install_prefix = install_prefix
        self.bin_dir = f"{install_prefix}/bin"
        self.lib_dir = f"{install_prefix}/lib/contest-manager"
        self.config_dir = "/etc/contest-manager"
        self.current_dir = os.path.dirname(os.path.abspath(__file__))
        
        # Files to install
        self.python_files = [
            "scripts/manager.py",
            "scripts/setup.py",
            "scripts/reset.py", 
            "scripts/restrict.py",
            "scripts/unrestrict.py",
            "scripts/utils/user_manager.py",
            "scripts/utils/software_installer.py",
            "scripts/utils/system_utils.py",
            "scripts/utils/common.py",
            "scripts/utils/network_restrictor.py",
            "scripts/utils/usb_restrictor.py",
            "scripts/utils/dependency_analyzer.py"
        ]
        
        self.config_files = [
            "whitelist.txt",
            "requirements.txt"
        ]
        
        # Load requirements from files
        self.system_packages = self.load_system_requirements()
        self.python_packages = self.load_python_requirements()

    def load_system_requirements(self):
        """Load system packages from system-requirements.txt"""
        packages = []
        requirements_file = os.path.join(self.current_dir, "system-requirements.txt")
        
        try:
            with open(requirements_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#'):
                        packages.append(line)
        except FileNotFoundError:
            self.print_warning(f"System requirements file not found: {requirements_file}")
            # Fallback to basic packages
            packages = [
                "python3", "python3-pip", "python3-dev", "iptables",
                "udev", "systemd", "dnsutils", "usbutils", "util-linux",
                "chromium-browser", "chromium-chromedriver", "netfilter-persistent"
            ]
        
        return packages

    def load_python_requirements(self):
        """Load Python packages from requirements.txt"""
        packages = []
        requirements_file = os.path.join(self.current_dir, "requirements.txt")
        
        try:
            with open(requirements_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#'):
                        packages.append(line)
        except FileNotFoundError:
            self.print_warning(f"Python requirements file not found: {requirements_file}")
            # Fallback to basic packages
            packages = [
                "selenium>=4.0.0", "requests>=2.25.0", "dnspython>=2.1.0", "psutil>=5.8.0"
            ]
        
        return packages

    def print_header(self, text):
        """Print a formatted header."""
        print(f"\n{'='*60}")
        print(f"  {text}")
        print(f"{'='*60}")

    def print_status(self, text):
        """Print a status message."""
        print(f"✅ {text}")

    def print_error(self, text):
        """Print an error message."""
        print(f"❌ {text}")

    def print_warning(self, text):
        """Print a warning message."""
        print(f"⚠️  {text}")

    def check_root(self):
        """Check if running as root."""
        if os.geteuid() != 0:
            self.print_error("This installer must be run as root (use sudo)")
            sys.exit(1)

    def detect_package_manager(self):
        """Detect the system package manager."""
        managers = {
            'apt': ['apt-get', 'apt'],
            'yum': ['yum'],
            'dnf': ['dnf'],
            'pacman': ['pacman'],
            'zypper': ['zypper']
        }
        
        for manager, commands in managers.items():
            for cmd in commands:
                try:
                    subprocess.run(['which', cmd], check=True, capture_output=True)
                    return manager, cmd
                except subprocess.CalledProcessError:
                    continue
        
        return None, None

    def install_system_packages(self):
        """Install system packages using the detected package manager."""
        self.print_header("Installing System Dependencies")
        
        pkg_manager, cmd = self.detect_package_manager()
        
        if not pkg_manager:
            self.print_error("Could not detect package manager. Please install packages manually:")
            for pkg in self.system_packages:
                print(f"  - {pkg}")
            return False
        
        print(f"Using package manager: {pkg_manager}")
        
        # Update package database
        if pkg_manager == 'apt':
            try:
                subprocess.run(['apt', 'update'], check=True)
                self.print_status("Package database updated")
            except subprocess.CalledProcessError:
                self.print_warning("Failed to update package database")
        
        # Install packages
        failed_packages = []
        for package in self.system_packages:
            try:
                print(f"Installing {package}...")
                if pkg_manager == 'apt':
                    subprocess.run(['apt', 'install', '-y', package], check=True, capture_output=True)
                elif pkg_manager in ['yum', 'dnf']:
                    subprocess.run([cmd, 'install', '-y', package], check=True, capture_output=True)
                elif pkg_manager == 'pacman':
                    subprocess.run(['pacman', '-S', '--noconfirm', package], check=True, capture_output=True)
                elif pkg_manager == 'zypper':
                    subprocess.run(['zypper', 'install', '-y', package], check=True, capture_output=True)
                
                self.print_status(f"Installed {package}")
                
            except subprocess.CalledProcessError as e:
                self.print_warning(f"Failed to install {package}: {e}")
                failed_packages.append(package)
        
        if failed_packages:
            self.print_warning(f"Failed to install: {', '.join(failed_packages)}")
            self.print_warning("Please install these packages manually")
        
        return len(failed_packages) == 0

    def install_python_packages(self):
        """Install Python packages using pip."""
        self.print_header("Installing Python Dependencies")
        
        try:
            # Upgrade pip first
            subprocess.run([sys.executable, '-m', 'pip', 'install', '--upgrade', 'pip'], check=True)
            self.print_status("Upgraded pip")
            
            # Install packages
            for package in self.python_packages:
                print(f"Installing {package}...")
                subprocess.run([sys.executable, '-m', 'pip', 'install', package], check=True)
                self.print_status(f"Installed {package}")
            
            return True
            
        except subprocess.CalledProcessError as e:
            self.print_error(f"Failed to install Python packages: {e}")
            return False

    def create_directories(self):
        """Create necessary directories."""
        self.print_header("Creating Directories")
        
        directories = [
            self.bin_dir,
            self.lib_dir,
            f"{self.lib_dir}/scripts",
            f"{self.lib_dir}/scripts/utils",
            self.config_dir
        ]
        
        for directory in directories:
            try:
                os.makedirs(directory, exist_ok=True)
                os.chmod(directory, 0o755)
                self.print_status(f"Created directory: {directory}")
            except Exception as e:
                self.print_error(f"Failed to create directory {directory}: {e}")
                return False
        
        return True

    def copy_files(self):
        """Copy all necessary files to their destinations."""
        self.print_header("Copying Files")
        
        # Copy Python files
        for file_path in self.python_files:
            src = os.path.join(self.current_dir, file_path)
            if file_path == "scripts/manager.py":
                dst = os.path.join(self.lib_dir, "manager.py")  # Place manager.py in lib root
            else:
                # Remove 'scripts/' prefix for destination path
                dst_path = file_path.replace("scripts/", "", 1)
                dst = os.path.join(self.lib_dir, dst_path)
            
            try:
                # Create destination directory if it doesn't exist
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                
                # Copy file
                shutil.copy2(src, dst)
                os.chmod(dst, 0o755)
                self.print_status(f"Copied {file_path}")
                
            except Exception as e:
                self.print_error(f"Failed to copy {file_path}: {e}")
                return False
        
        # Copy config files
        for file_path in self.config_files:
            src = os.path.join(self.current_dir, file_path)
            dst = os.path.join(self.config_dir, file_path)
            
            try:
                # Don't overwrite existing config files
                if not os.path.exists(dst):
                    shutil.copy2(src, dst)
                    os.chmod(dst, 0o644)
                    self.print_status(f"Copied {file_path}")
                else:
                    self.print_warning(f"Config file {file_path} already exists, skipping")
                    
            except Exception as e:
                self.print_error(f"Failed to copy {file_path}: {e}")
                return False
        
        return True

    def create_wrapper_script(self):
        """Create a wrapper script for the contest manager."""
        self.print_header("Creating Wrapper Script")
        
        wrapper_content = f"""#!/bin/bash
# Contest Environment Manager Wrapper Script
# This script provides easy access to the contest manager from anywhere

INSTALL_DIR="{self.lib_dir}"
CONFIG_DIR="{self.config_dir}"

# Check if running as root for restricted operations
if [[ "$1" == "restrict" || "$1" == "unrestrict" || "$1" == "setup" || "$1" == "reset" ]]; then
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This operation requires root privileges. Use sudo."
        exit 1
    fi
fi

# Execute the manager with proper paths
exec python3 "$INSTALL_DIR/manager.py" --config-dir "$CONFIG_DIR" "$@"
"""
        
        wrapper_path = os.path.join(self.bin_dir, "contest-manager")
        
        try:
            with open(wrapper_path, 'w') as f:
                f.write(wrapper_content)
            
            # Make executable
            os.chmod(wrapper_path, 0o755)
            self.print_status(f"Created wrapper script: {wrapper_path}")
            
            return True
            
        except Exception as e:
            self.print_error(f"Failed to create wrapper script: {e}")
            return False

    def create_desktop_entry(self):
        """Create a desktop entry for GUI access."""
        self.print_header("Creating Desktop Entry")
        
        desktop_content = f"""[Desktop Entry]
Version=1.0
Type=Application
Name=Contest Environment Manager
Comment=Manage contest environment restrictions and settings
Exec=gnome-terminal -- sudo contest-manager
Icon=security-high
Terminal=true
Categories=System;Security;
StartupNotify=true
"""
        
        desktop_path = "/usr/share/applications/contest-manager.desktop"
        
        try:
            with open(desktop_path, 'w') as f:
                f.write(desktop_content)
            
            os.chmod(desktop_path, 0o644)
            self.print_status(f"Created desktop entry: {desktop_path}")
            
            return True
            
        except Exception as e:
            self.print_error(f"Failed to create desktop entry: {e}")
            return False

    def setup_sudoers(self):
        """Setup sudoers configuration for contest manager."""
        self.print_header("Setting Up Sudoers Configuration")
        
        sudoers_content = f"""# Contest Environment Manager Sudoers Configuration
# Allow contest-manager group to run contest management commands

# Create contest-manager group if it doesn't exist
%contest-manager ALL=(root) NOPASSWD: {self.bin_dir}/contest-manager restrict *
%contest-manager ALL=(root) NOPASSWD: {self.bin_dir}/contest-manager unrestrict *
%contest-manager ALL=(root) NOPASSWD: {self.bin_dir}/contest-manager setup *
%contest-manager ALL=(root) NOPASSWD: {self.bin_dir}/contest-manager reset *
%contest-manager ALL=(root) NOPASSWD: {self.bin_dir}/contest-manager status *
"""
        
        sudoers_path = "/etc/sudoers.d/contest-manager"
        
        try:
            with open(sudoers_path, 'w') as f:
                f.write(sudoers_content)
            
            os.chmod(sudoers_path, 0o440)
            
            # Create contest-manager group
            try:
                grp.getgrnam('contest-manager')
                self.print_status("Group 'contest-manager' already exists")
            except KeyError:
                subprocess.run(['groupadd', 'contest-manager'], check=True)
                self.print_status("Created group 'contest-manager'")
            
            self.print_status("Configured sudoers for contest-manager")
            self.print_warning("Add users to 'contest-manager' group: sudo usermod -a -G contest-manager <username>")
            
            return True
            
        except Exception as e:
            self.print_error(f"Failed to setup sudoers: {e}")
            return False

    def verify_installation(self):
        """Verify the installation was successful."""
        self.print_header("Verifying Installation")
        
        checks = [
            (f"{self.bin_dir}/contest-manager", "Wrapper script"),
            (f"{self.lib_dir}/manager.py", "Main manager script"),
            (f"{self.config_dir}/whitelist.txt", "Whitelist configuration"),
            ("/usr/share/applications/contest-manager.desktop", "Desktop entry")
        ]
        
        all_good = True
        for path, description in checks:
            if os.path.exists(path):
                self.print_status(f"{description}: {path}")
            else:
                self.print_error(f"Missing {description}: {path}")
                all_good = False
        
        # Test the command
        try:
            result = subprocess.run(['contest-manager', '--help'], 
                                  capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                self.print_status("Command 'contest-manager --help' works")
            else:
                self.print_error("Command 'contest-manager --help' failed")
                all_good = False
        except Exception as e:
            self.print_error(f"Failed to test command: {e}")
            all_good = False
        
        return all_good

    def show_usage_info(self):
        """Show usage information after installation."""
        self.print_header("Installation Complete!")
        
        print("""
🎉 Contest Environment Manager has been successfully installed!

📍 Installation Locations:
   • Executable: /usr/local/bin/contest-manager
   • Library: /usr/local/lib/contest-manager/
   • Configuration: /etc/contest-manager/
   • Desktop Entry: /usr/share/applications/contest-manager.desktop

🚀 Usage:
   • Run: contest-manager --help
   • Setup contest environment: sudo contest-manager setup --user <username>
   • Apply restrictions: sudo contest-manager restrict --user <username>
   • Remove restrictions: sudo contest-manager unrestrict --user <username>
   • Check status: contest-manager status --user <username>
   • Manage whitelist: contest-manager whitelist add <site>

👥 User Management:
   • Add users to contest-manager group: sudo usermod -a -G contest-manager <username>
   • Users in this group can run contest management commands

📝 Configuration:
   • Edit whitelist: sudo nano /etc/contest-manager/whitelist.txt
   • View logs: journalctl -u contest-monitor.service

🔧 Troubleshooting:
   • Check dependencies: contest-manager --help
   • View system status: sudo systemctl status contest-monitor.timer
   • Manual cleanup: sudo contest-manager unrestrict --user <username>

For more information, visit the documentation or run: contest-manager --help
""")

    def install(self, skip_system=False, skip_python=False):
        """Run the complete installation process."""
        self.print_header("Contest Environment Manager Installer")
        
        # Check prerequisites
        self.check_root()
        
        success = True
        
        # Install system packages
        if not skip_system:
            if not self.install_system_packages():
                success = False
        else:
            self.print_warning("Skipping system package installation")
        
        # Install Python packages
        if not skip_python:
            if not self.install_python_packages():
                success = False
        else:
            self.print_warning("Skipping Python package installation")
        
        # Create directories
        if not self.create_directories():
            success = False
        
        # Copy files
        if not self.copy_files():
            success = False
        
        # Create wrapper script
        if not self.create_wrapper_script():
            success = False
        
        # Create desktop entry
        if not self.create_desktop_entry():
            success = False
        
        # Setup sudoers
        if not self.setup_sudoers():
            success = False
        
        # Verify installation
        if not self.verify_installation():
            success = False
        
        if success:
            self.show_usage_info()
        else:
            self.print_error("Installation completed with some errors. Please check the messages above.")
        
        return success

    def uninstall(self):
        """Uninstall the contest environment manager."""
        self.print_header("Uninstalling Contest Environment Manager")
        
        # Check if running as root
        self.check_root()
        
        # Remove files and directories
        paths_to_remove = [
            f"{self.bin_dir}/contest-manager",
            self.lib_dir,
            "/usr/share/applications/contest-manager.desktop",
            "/etc/sudoers.d/contest-manager"
        ]
        
        for path in paths_to_remove:
            try:
                if os.path.exists(path):
                    if os.path.isdir(path):
                        shutil.rmtree(path)
                    else:
                        os.remove(path)
                    self.print_status(f"Removed: {path}")
                else:
                    self.print_warning(f"Not found: {path}")
            except Exception as e:
                self.print_error(f"Failed to remove {path}: {e}")
        
        # Remove contest-manager group
        try:
            grp.getgrnam('contest-manager')
            subprocess.run(['groupdel', 'contest-manager'], check=True)
            self.print_status("Removed group 'contest-manager'")
        except KeyError:
            self.print_warning("Group 'contest-manager' not found")
        except subprocess.CalledProcessError:
            self.print_warning("Failed to remove group 'contest-manager'")
        
        # Note about config files
        self.print_warning(f"Configuration files in {self.config_dir} were not removed")
        self.print_warning("Remove them manually if desired")
        
        self.print_status("Uninstallation complete")

def main():
    parser = argparse.ArgumentParser(
        description="Contest Environment Manager Installer",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument('--install', action='store_true', help='Install the contest manager')
    parser.add_argument('--uninstall', action='store_true', help='Uninstall the contest manager')
    parser.add_argument('--prefix', default='/usr/local', help='Installation prefix (default: /usr/local)')
    parser.add_argument('--skip-system', action='store_true', help='Skip system package installation')
    parser.add_argument('--skip-python', action='store_true', help='Skip Python package installation')
    
    args = parser.parse_args()
    
    if not args.install and not args.uninstall:
        parser.print_help()
        sys.exit(1)
    
    installer = ContestManagerInstaller(args.prefix)
    
    if args.install:
        success = installer.install(skip_system=args.skip_system, skip_python=args.skip_python)
        sys.exit(0 if success else 1)
    
    elif args.uninstall:
        installer.uninstall()
        sys.exit(0)

if __name__ == "__main__":
    main()
