#!/usr/bin/env python3
"""
Contest Environment Manager - Main Control Hub
Professional Python implementation of the contest management system
"""

import sys
import os
import argparse
import subprocess
from pathlib import Path

# Configuration
DEFAULT_USER = "participant"
SCRIPT_DIR = Path(__file__).parent  # Scripts are in the same directory now
WHITELIST_FILE = Path(__file__).parent.parent / "whitelist.txt"  # Go up one level to project root

def check_root():
    """Check if running as root"""
    if os.geteuid() != 0:
        print("Error: This command must be run as root")
        sys.exit(1)

def show_usage():
    """Display usage information"""
    usage = """
Contest Environment Manager - Professional Python Implementation

Commands:
  setup [USER]        Set up lab PC with all required software and user account (default: participant)
  reset [USER]        Reset user account to clean state (default: participant)
  restrict [USER]     Enable internet restrictions for specified user (default: participant)
  unrestrict [USER]   Disable internet restrictions for specified user (default: participant)
  status [USER]       Show current restriction status for specified user (default: participant)
  add DOMAIN          Add domain to whitelist
  remove DOMAIN       Remove domain from whitelist
  list                List currently whitelisted domains
  dependencies        Show resolved dependencies for whitelisted domains
  help                Show this help message

Examples:
  sudo python3 manager.py setup                   # Set up lab PC from scratch for participant
  sudo python3 manager.py setup contestant        # Set up lab PC for user "contestant"
  sudo python3 manager.py restrict                # Restrict default user (participant)
  sudo python3 manager.py unrestrict              # Remove restrictions for participant
  sudo python3 manager.py status                  # Check status for participant
  sudo python3 manager.py reset                   # Reset participant account to clean state
  sudo python3 manager.py add codeforces.com      # Add domain to whitelist
  sudo python3 manager.py remove codeforces.com   # Remove domain from whitelist
  sudo python3 manager.py list                    # List whitelisted domains
  sudo python3 manager.py dependencies            # Show resolved dependencies
"""
    print(usage)

def run_script(script_name, *args):
    """Run a script from the scripts directory"""
    script_path = SCRIPT_DIR / script_name
    
    if not script_path.exists():
        print(f"Error: Script {script_name} not found at {script_path}")
        sys.exit(1)
    
    try:
        # Run the script with Python
        cmd = [sys.executable, str(script_path)] + list(args)
        result = subprocess.run(cmd, check=True)
        return result.returncode
    except subprocess.CalledProcessError as e:
        print(f"Error running {script_name}: {e}")
        sys.exit(e.returncode)
    except Exception as e:
        print(f"Unexpected error running {script_name}: {e}")
        sys.exit(1)

def load_whitelist():
    """Load whitelist domains from file."""
    try:
        if not WHITELIST_FILE.exists():
            return set()
        
        with open(WHITELIST_FILE, 'r') as f:
            domains = set()
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    domains.add(line)
            return domains
    except Exception as e:
        print(f"Error loading whitelist: {e}")
        return set()


def save_whitelist(domains):
    """Save whitelist domains to file."""
    try:
        with open(WHITELIST_FILE, 'w') as f:
            for domain in sorted(domains):
                f.write(f"{domain}\n")
        return True
    except Exception as e:
        print(f"Error saving whitelist: {e}")
        return False


def add_domain(domain):
    """Add a domain to the whitelist."""
    # Basic domain validation
    if not domain or '.' not in domain:
        print(f"Error: Invalid domain format '{domain}'")
        return False
    
    # Remove protocol if present
    domain = domain.replace('http://', '').replace('https://', '')
    domain = domain.split('/')[0]  # Remove path
    domain = domain.lower()
    
    domains = load_whitelist()
    
    if domain in domains:
        print(f"Domain '{domain}' is already in the whitelist")
        return True
    
    domains.add(domain)
    
    if save_whitelist(domains):
        print(f"✅ Added '{domain}' to whitelist")
        print(f"   Total domains: {len(domains)}")
        return True
    else:
        print(f"❌ Failed to add '{domain}' to whitelist")
        return False


def remove_domain(domain):
    """Remove a domain from the whitelist."""
    domain = domain.replace('http://', '').replace('https://', '')
    domain = domain.split('/')[0]  # Remove path
    domain = domain.lower()
    
    domains = load_whitelist()
    
    if domain not in domains:
        print(f"Domain '{domain}' is not in the whitelist")
        return True
    
    domains.remove(domain)
    
    if save_whitelist(domains):
        print(f"✅ Removed '{domain}' from whitelist")
        print(f"   Total domains: {len(domains)}")
        return True
    else:
        print(f"❌ Failed to remove '{domain}' from whitelist")
        return False


def list_domains():
    """List all domains in the whitelist."""
    domains = load_whitelist()
    
    if not domains:
        print("No domains in whitelist")
        return
    
    print(f"Whitelisted domains ({len(domains)} total):")
    print("=" * 50)
    for domain in sorted(domains):
        print(f"  {domain}")
    print("=" * 50)

def show_dependencies():
    """Show resolved dependencies for whitelisted domains."""
    import json
    import os
    import time
    
    # Path to the dependency cache file (use same directory as whitelist)
    cache_file = WHITELIST_FILE.parent / '.dependency_cache.json'
    
    # Load whitelist domains
    domains = load_whitelist()
    
    if not domains:
        print("No domains in whitelist")
        return
    
    # Check if cache file exists
    if not cache_file.exists():
        print("No dependency cache found.")
        print("Run 'sudo python3 manager.py restrict' first to analyze dependencies.")
        return
    
    try:
        with open(cache_file, 'r') as f:
            cache = json.load(f)
    except Exception as e:
        print(f"Error loading dependency cache: {e}")
        return
    
    if not cache:
        print("Dependency cache is empty.")
        print("Run 'sudo python3 manager.py restrict' first to analyze dependencies.")
        return
    
    # Get cache file modification time
    cache_mtime = os.path.getmtime(cache_file)
    cache_time = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(cache_mtime))
    
    # Count total dependencies
    all_dependencies = set()
    analyzed_count = 0
    for domain in domains:
        if domain in cache:
            analyzed_count += 1
            all_dependencies.update(cache[domain])
    
    print(f"Resolved Dependencies ({len(all_dependencies)} total)")
    print("=" * 60)
    print(f"Based on {len(domains)} whitelisted domains")
    print(f"Analyzed: {analyzed_count}/{len(domains)} domains")
    print(f"Cache updated: {cache_time}")
    print()
    
    # Show dependencies per domain
    for domain in sorted(domains):
        if domain in cache:
            deps = cache[domain]
            if deps:
                print(f"📊 {domain} → {len(deps)} dependencies:")
                for dep in sorted(deps):
                    print(f"   • {dep}")
                print()
            else:
                print(f"📊 {domain} → No dependencies found")
                print()
        else:
            print(f"📊 {domain} → Not analyzed yet")
            print()
    
    # Show all unique dependencies
    if all_dependencies:
        print("🔗 All Unique Dependencies:")
        print("-" * 30)
        for dep in sorted(all_dependencies):
            print(f"   • {dep}")
        
        print("-" * 30)
        print(f"Total: {len(all_dependencies)} unique dependencies")
        print()
        print("💡 These dependencies will be automatically allowed when restrictions are active.")
    
    # Show refresh hint if not all domains analyzed
    if analyzed_count < len(domains):
        print()
        print("🔄 Some domains haven't been analyzed yet.")
        print("   Run 'sudo python3 manager.py restrict' to analyze all domains.")
        print("   Use 'sudo python3 restrict.py --user USER --apply --force-refresh' to re-analyze all domains.")

def main():
    """Main function to route commands"""
    # Parse arguments to handle --config-dir
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('--config-dir', help='Configuration directory path')
    parser.add_argument('command', nargs='?', help='Command to execute')
    parser.add_argument('args', nargs='*', help='Additional arguments')
    
    args, unknown = parser.parse_known_args()
    
    # Update paths if config-dir is provided
    global WHITELIST_FILE
    if args.config_dir:
        WHITELIST_FILE = Path(args.config_dir) / "whitelist.txt"
    
    # Handle --help or help command
    if '--help' in sys.argv or '-h' in sys.argv or args.command == 'help':
        show_usage()
        sys.exit(0)
    
    # Get command and arguments
    if args.command:
        command = args.command
        cmd_args = args.args + unknown
    else:
        if len(sys.argv) < 2:
            show_usage()
            sys.exit(1)
        command = sys.argv[1]
        cmd_args = sys.argv[2:]
    
    # Route commands to appropriate scripts
    if command == "setup":
        check_root()
        user = cmd_args[0] if cmd_args else DEFAULT_USER
        run_script("setup.py", user)
    
    elif command == "reset":
        check_root()
        user = cmd_args[0] if cmd_args else DEFAULT_USER
        run_script("reset.py", user)
    
    elif command == "restrict":
        check_root()
        user = cmd_args[0] if cmd_args else DEFAULT_USER
        script_args = ["--user", user, "--apply"]
        if args.config_dir:
            script_args.extend(["--config-dir", args.config_dir])
        run_script("restrict.py", *script_args)
    
    elif command == "unrestrict":
        check_root()
        user = cmd_args[0] if cmd_args else DEFAULT_USER
        script_args = ["--user", user, "--remove"]
        if args.config_dir:
            script_args.extend(["--config-dir", args.config_dir])
        run_script("unrestrict.py", *script_args)
    
    elif command == "status":
        user = cmd_args[0] if cmd_args else DEFAULT_USER
        script_args = ["--user", user, "--status"]
        if args.config_dir:
            script_args.extend(["--config-dir", args.config_dir])
        run_script("restrict.py", *script_args)
    
    elif command == "help":
        show_usage()
    
    elif command == "add":
        check_root()
        if not cmd_args:
            print("Error: Missing domain name")
            print("Usage: sudo python3 manager.py add example.com")
            sys.exit(1)
        success = add_domain(cmd_args[0])
        sys.exit(0 if success else 1)
    
    elif command == "remove":
        check_root()
        if not cmd_args:
            print("Error: Missing domain name")
            print("Usage: sudo python3 manager.py remove example.com")
            sys.exit(1)
        success = remove_domain(cmd_args[0])
        sys.exit(0 if success else 1)
    
    elif command == "list":
        list_domains()
        sys.exit(0)
    
    elif command == "dependencies":
        show_dependencies()
        sys.exit(0)
    
    else:
        print(f"Error: Unknown command '{command}'")
        show_usage()
        sys.exit(1)

if __name__ == "__main__":
    main()