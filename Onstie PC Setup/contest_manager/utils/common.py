#!/usr/bin/env python3
"""
Common utility functions for contest environment manager.
"""

import subprocess
import sys
import shutil
import pwd
import os
from pathlib import Path


def run_command(cmd, shell=False, check=True, capture_output=False):
    """Run a command and handle errors."""
    try:
        if shell:
            result = subprocess.run(cmd, shell=True, check=check, 
                                  capture_output=capture_output, text=True)
        else:
            result = subprocess.run(cmd, check=check, capture_output=capture_output, text=True)
        return result
    except subprocess.CalledProcessError as e:
        print(f"❌ Command failed: {e.cmd}")
        if capture_output:
            print(f"Error output: {e.stderr}")
        if check:
            sys.exit(1)
        return e


def print_step(step_num, description):
    """Print a formatted step header."""
    print("=" * 50)
    print(f"Step {step_num}: {description}")
    print("=" * 50)


def print_header(text):
    """Print a formatted header."""
    print("\n" + "=" * 60)
    print(f"  {text}")
    print("=" * 60)


def print_status(text):
    """Print a status message."""
    print(f"✅ {text}")


def print_error(text):
    """Print an error message."""
    print(f"❌ {text}")


def print_warning(text):
    """Print a warning message."""
    print(f"⚠️  {text}")


def user_exists(username):
    """Check if a user exists."""
    try:
        pwd.getpwnam(username)
        return True
    except KeyError:
        return False


def package_installed(package_name):
    """Check if a package is installed."""
    result = run_command(f"dpkg -s {package_name}", shell=True, check=False, capture_output=True)
    return result.returncode == 0


def command_exists(command):
    """Check if a command exists."""
    return shutil.which(command) is not None


def install_packages(packages, description="packages"):
    """Install a list of packages."""
    print(f"→ Installing {description}...")
    
    for package in packages:
        if package_installed(package):
            print(f"✅ {package} is already installed.")
        else:
            print(f"📦 Installing {package}...")
            run_command(f"apt install -y {package}", shell=True)
            print(f"✅ {package} installed successfully.")


def ensure_user_can_execute(user):
    """Ensure user can execute programs they create."""
    home_dir = f"/home/{user}"
    
    # Set proper ownership and permissions
    run_command(f"chown -R {user}:{user} {home_dir}", shell=True)
    run_command(f"chmod -R u+rwx {home_dir}", shell=True)
    
    # Add execute permissions for user's programs
    run_command(f"find {home_dir} -type f -name '*.out' -exec chmod +x {{}} \\;", shell=True, check=False)
    run_command(f"find {home_dir} -type f -name '*.exe' -exec chmod +x {{}} \\;", shell=True, check=False)
    
    # Set umask for future files
    bashrc = f"{home_dir}/.bashrc"
    profile = f"{home_dir}/.profile"
    
    umask_line = "umask 022"
    for file_path in [bashrc, profile]:
        try:
            with open(file_path, 'r') as f:
                content = f.read()
            if umask_line not in content:
                with open(file_path, 'a') as f:
                    f.write(f"\n{umask_line}\n")
        except FileNotFoundError:
            with open(file_path, 'w') as f:
                f.write(f"{umask_line}\n")
    
    print(f"✅ User '{user}' can now execute programs they create.")


def get_project_root() -> str:
    """Get the project root directory."""
    # Try to find the project root by looking for setup.py or pyproject.toml
    current_dir = Path(__file__).parent
    while current_dir != current_dir.parent:
        if (current_dir / "setup.py").exists() or (current_dir / "pyproject.toml").exists():
            return str(current_dir)
        current_dir = current_dir.parent
    
    # Fallback to /etc/contest-manager
    return "/etc/contest-manager"


def check_root():
    """Check if running as root."""
    if os.geteuid() != 0:
        print("❌ Error: This command must be run as root")
        sys.exit(1)
