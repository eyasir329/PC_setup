#!/usr/bin/env python3
"""
Software installation utilities for contest environment.
"""

import os
from .common import run_command, command_exists, package_installed, install_packages


def install_programming_languages():
    """Install programming languages and compilers."""
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


def install_basic_editors():
    """Install basic code editors."""
    basic_editors = ["micro", "codeblocks"]
    install_packages(basic_editors, "basic code editors")


def install_sublime_text():
    """Install Sublime Text."""
    if command_exists("subl"):
        print("✅ Sublime Text is already installed.")
        return
    
    print("📦 Installing Sublime Text...")
    
    # Install dependencies
    run_command("apt-get install -y apt-transport-https curl gnupg", shell=True)
    
    # Add GPG key
    if not os.path.exists("/etc/apt/trusted.gpg.d/sublimehq-archive.gpg"):
        print("🔑 Adding Sublime Text GPG key...")
        run_command("wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | gpg --dearmor | tee /etc/apt/trusted.gpg.d/sublimehq-archive.gpg > /dev/null", shell=True)
    
    # Add repository
    if not os.path.exists("/etc/apt/sources.list.d/sublime-text.list"):
        print("📝 Adding Sublime Text repository...")
        run_command("echo 'deb https://download.sublimetext.com/ apt/stable/' | tee /etc/apt/sources.list.d/sublime-text.list", shell=True)
    
    # Install
    run_command("apt-get update", shell=True)
    run_command("apt-get install -y sublime-text", shell=True)
    print("✅ Sublime Text installed successfully.")


def install_vscode():
    """Install Visual Studio Code."""
    if command_exists("code"):
        print("✅ Visual Studio Code is already installed.")
        return
    
    print("📦 Installing Visual Studio Code...")
    
    # Install dependencies
    run_command("apt install -y wget gpg apt-transport-https", shell=True)
    
    # Add Microsoft GPG key
    run_command("wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /usr/share/keyrings/microsoft-archive-keyring.gpg > /dev/null", shell=True)
    
    # Add repository
    run_command("echo 'deb [signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/vscode stable main' | tee /etc/apt/sources.list.d/vscode.list > /dev/null", shell=True)
    
    # Install
    run_command("apt update", shell=True)
    run_command("apt install -y code", shell=True)
    print("✅ Visual Studio Code installed successfully.")


def install_vscode_extensions(user):
    """Install VS Code extensions for a user."""
    extensions = [
        "ms-vscode.cpptools",
        "ms-python.python", 
        "redhat.java"
    ]
    
    for ext in extensions:
        print(f"→ Installing extension: {ext}")
        # Use timeout to prevent hanging
        result = run_command(f"timeout 60s sudo -u {user} code --install-extension {ext} --force", 
                           shell=True, check=False, capture_output=True)
        if result.returncode == 0:
            print(f"✅ Extension {ext} installed successfully.")
        else:
            print(f"⚠️ Failed to install {ext} (may be due to network issues)")


def install_grub_customizer():
    """Install GRUB Customizer."""
    if package_installed("grub-customizer"):
        print("✅ GRUB Customizer is already installed.")
        return
    
    print("📦 Installing GRUB Customizer...")
    
    # Add PPA
    ppa_check = run_command("grep -r 'danielrichter2007/grub-customizer' /etc/apt/sources.list /etc/apt/sources.list.d/", 
                           shell=True, check=False, capture_output=True)
    if ppa_check.returncode != 0:
        print("➕ Adding PPA for GRUB Customizer...")
        run_command("add-apt-repository -y ppa:danielrichter2007/grub-customizer", shell=True)
        run_command("apt update", shell=True)
    
    # Install
    run_command("apt install -y grub-customizer", shell=True)
    print("✅ GRUB Customizer installed successfully.")


def install_browsers():
    """Install web browsers."""
    install_firefox()
    install_chrome()


def install_firefox():
    """Install Firefox."""
    if command_exists("firefox"):
        print("✅ Firefox is already installed.")
        return
    
    print("📦 Installing Firefox...")
    result = run_command("apt install -y firefox", shell=True, check=False)
    if result.returncode == 0:
        print("✅ Firefox installed successfully using APT.")
    else:
        print("⚠️ APT install failed. Trying snap...")
        run_command("snap install firefox", shell=True)
        print("✅ Firefox installed successfully using Snap.")


def install_chrome():
    """Install Google Chrome."""
    if command_exists("google-chrome"):
        print("✅ Google Chrome is already installed.")
        return
    
    print("📦 Installing Google Chrome...")
    
    # Download Chrome
    tmp_deb = "/tmp/google-chrome.deb"
    run_command(f"wget -O {tmp_deb} https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb", shell=True)
    
    # Install
    result = run_command(f"dpkg -i {tmp_deb}", shell=True, check=False)
    if result.returncode != 0:
        print("⚠️ Resolving dependencies...")
        run_command("apt-get install -f -y", shell=True)
        run_command(f"dpkg -i {tmp_deb}", shell=True)
    
    # Clean up
    os.remove(tmp_deb)
    print("✅ Google Chrome installed successfully.")


def verify_essential_software() -> bool:
    """Verify that essential software is still installed."""
    print("→ Verifying essential software...")
    
    essential_packages = [
        "python3",
        "git", 
        "vim",
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
