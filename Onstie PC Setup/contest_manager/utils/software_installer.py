#!/usr/bin/env python3
"""
Software installation utilities for contest environment.
"""

import os
from .common import run_command, command_exists, package_installed, install_packages


def install_programming_languages():
    """Install programming languages and compilers."""
    try:
        dev_packages = [
            "build-essential",
            "gdb", 
            "gcc",
            "g++",
            "python3",
            "python3-pip",
            "openjdk-17-jdk"
        ]
        
        print("→ Updating package lists...")
        run_command("apt update", shell=True)
        
        install_packages(dev_packages, "programming languages and compilers")
        print("✅ Programming languages and development tools installed.")
        return True
    except Exception as e:
        print(f"❌ Failed to install programming languages: {e}")
        return False


def install_basic_editors():
    """Install basic code editors."""
    try:
        basic_editors = ["micro", "codeblocks"]
        install_packages(basic_editors, "basic code editors")
        return True
    except Exception as e:
        print(f"❌ Failed to install basic editors: {e}")
        return False


def install_sublime_text():
    """Install Sublime Text."""
    try:
        if command_exists("subl"):
            print("✅ Sublime Text is already installed.")
            return True
        print("📦 Installing Sublime Text...")
        run_command("apt-get install -y apt-transport-https curl gnupg", shell=True)
        if not os.path.exists("/etc/apt/trusted.gpg.d/sublimehq-archive.gpg"):
            print("🔑 Adding Sublime Text GPG key...")
            run_command("wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | gpg --dearmor | tee /etc/apt/trusted.gpg.d/sublimehq-archive.gpg > /dev/null", shell=True)
        if not os.path.exists("/etc/apt/sources.list.d/sublime-text.list"):
            print("📝 Adding Sublime Text repository...")
            run_command("echo 'deb https://download.sublimetext.com/ apt/stable/' | tee /etc/apt/sources.list.d/sublime-text.list", shell=True)
        run_command("apt-get update", shell=True)
        run_command("apt-get install -y sublime-text", shell=True)
        print("✅ Sublime Text installed successfully.")
        return True
    except Exception as e:
        print(f"❌ Failed to install Sublime Text: {e}")
        return False


def install_vscode():
    """Install Visual Studio Code."""
    try:
        if command_exists("code"):
            print("✅ Visual Studio Code is already installed.")
            return True
        print("📦 Installing Visual Studio Code...")
        run_command("apt install -y wget gpg apt-transport-https", shell=True)
        run_command("wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /usr/share/keyrings/microsoft-archive-keyring.gpg > /dev/null", shell=True)
        run_command("echo 'deb [signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/vscode stable main' | tee /etc/apt/sources.list.d/vscode.list > /dev/null", shell=True)
        run_command("apt update", shell=True)
        run_command("apt install -y code", shell=True)
        print("✅ Visual Studio Code installed successfully.")
        return True
    except Exception as e:
        print(f"❌ Failed to install Visual Studio Code: {e}")
        return False


def install_vscode_extensions(user):
    """Install VS Code extensions for a user."""
    try:
        extensions = [
            "ms-vscode.cpptools",
            "ms-python.python", 
            "redhat.java"
        ]
        all_ok = True
        user_data_dir = f"/home/{user}/.config/Code"
        for ext in extensions:
            # Check if extension is already installed (more robust)
            check_cmd = f"sudo -u {user} code --user-data-dir={user_data_dir} --list-extensions | grep -Fxq '{ext}'"
            check_result = run_command(check_cmd, shell=True, check=False, capture_output=True)
            if check_result.returncode == 0:
                print(f"✅ Extension {ext} is already installed.")
                continue
            print(f"→ Installing extension: {ext}")
            result = run_command(f"timeout 60s sudo -u {user} code --user-data-dir={user_data_dir} --install-extension {ext} --force", shell=True, check=False, capture_output=True)
            if result.returncode == 0:
                print(f"✅ Extension {ext} installed successfully.")
            else:
                print(f"⚠️ Failed to install {ext} (may be due to network issues)")
                all_ok = False
        return all_ok
    except Exception as e:
        print(f"❌ Failed to install VS Code extensions: {e}")
        return False


def install_grub_customizer():
    """Install GRUB Customizer."""
    try:
        if package_installed("grub-customizer"):
            print("✅ GRUB Customizer is already installed.")
            return True
        print("📦 Installing GRUB Customizer...")
        ppa_check = run_command("grep -r 'danielrichter2007/grub-customizer' /etc/apt/sources.list /etc/apt/sources.list.d/", shell=True, check=False, capture_output=True)
        if ppa_check.returncode != 0:
            print("➕ Adding PPA for GRUB Customizer...")
            run_command("add-apt-repository -y ppa:danielrichter2007/grub-customizer", shell=True)
            run_command("apt update", shell=True)
        run_command("apt install -y grub-customizer", shell=True)
        print("✅ GRUB Customizer installed successfully.")
        return True
    except Exception as e:
        print(f"❌ Failed to install GRUB Customizer: {e}")
        return False


def install_browsers():
    """Install web browsers."""
    try:
        ok1 = install_firefox()
        ok2 = install_chrome()
        return ok1 and ok2
    except Exception as e:
        print(f"❌ Failed to install browsers: {e}")
        return False


def install_firefox():
    """Install Firefox."""
    try:
        if command_exists("firefox"):
            print("✅ Firefox is already installed.")
            return True
        print("📦 Installing Firefox...")
        result = run_command("apt install -y firefox", shell=True, check=False)
        if result.returncode == 0:
            print("✅ Firefox installed successfully using APT.")
            return True
        else:
            print("⚠️ APT install failed. Trying snap...")
            run_command("snap install firefox", shell=True)
            print("✅ Firefox installed successfully using Snap.")
            return True
    except Exception as e:
        print(f"❌ Failed to install Firefox: {e}")
        return False


def install_chrome():
    """Install Google Chrome."""
    try:
        if command_exists("google-chrome"):
            print("✅ Google Chrome is already installed.")
            return True
        print("📦 Installing Google Chrome...")
        tmp_deb = "/tmp/google-chrome.deb"
        run_command(f"wget -O {tmp_deb} https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb", shell=True)
        result = run_command(f"dpkg -i {tmp_deb}", shell=True, check=False)
        if result.returncode != 0:
            print("⚠️ Resolving dependencies...")
            run_command("apt-get install -f -y", shell=True)
            run_command(f"dpkg -i {tmp_deb}", shell=True)
        os.remove(tmp_deb)
        print("✅ Google Chrome installed successfully.")
        return True
    except Exception as e:
        print(f"❌ Failed to install Google Chrome: {e}")
        return False


def verify_essential_software() -> bool:
    """Verify that essential software is still installed."""
    print("→ Verifying essential software...")
    
    essential_packages = [
        "python3",
        "git", 
        "gcc",
        "g++",
        "build-essential",
        "openjdk-17-jdk",
        "codeblocks",
        "code"  # VS Code
    ]
    
    missing_packages = []
    
    for package in essential_packages:
        if not package_installed(package):
            missing_packages.append(package)
    
    # Also check for browsers
    browsers = ["google-chrome-stable", "firefox"]
    browser_found = False
    for browser in browsers:
        if package_installed(browser):
            browser_found = True
            break
    
    if not browser_found:
        missing_packages.append("browser (Chrome or Firefox)")
    
    if missing_packages:
        print(f"❌ Missing essential software: {', '.join(missing_packages)}")
        return False
    else:
        print("✅ All essential software is intact")
        return True
