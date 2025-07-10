#!/usr/bin/env python3
"""
Contest Environment Unrestrict CLI (Squid Proxy Integration)
"""

import sys
import argparse
import subprocess
import pwd
from ..core.manager import ContestManager
from ..utils.common import check_root, get_project_root

SQUID_WHITELIST = "/etc/squid/whitelist.txt"
SQUID_SERVICE = "squid"


def create_parser():
    """Create the unrestrict argument parser."""
    parser = argparse.ArgumentParser(
        description="Disable internet restrictions for contest environment (Squid proxy mode)",
        prog="contest-unrestrict"
    )
    
    parser.add_argument(
        'user',
        nargs='?',
        default='participant',
        help='Username to unrestrict (default: participant)'
    )
    
    parser.add_argument(
        '--config-dir',
        type=str,
        help='Configuration directory path (default: project root)'
    )
    
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='Enable verbose output'
    )
    
    return parser


def remove_squid_iptables(user):
    uid = pwd.getpwnam(user).pw_uid
    # Remove HTTP/HTTPS redirect rules for this user
    subprocess.run(['iptables', '-t', 'nat', '-D', 'OUTPUT', '-p', 'tcp', '--dport', '80', '-m', 'owner', '--uid-owner', str(uid), '-j', 'REDIRECT', '--to-port', '3128'], check=False)
    subprocess.run(['iptables', '-t', 'nat', '-D', 'OUTPUT', '-p', 'tcp', '--dport', '443', '-m', 'owner', '--uid-owner', str(uid), '-j', 'REDIRECT', '--to-port', '3129'], check=False)
    # Remove block rules for this user
    subprocess.run(['iptables', '-D', 'OUTPUT', '-m', 'owner', '--uid-owner', str(uid), '-j', 'REJECT'], check=False)
    subprocess.run(['ip6tables', '-D', 'OUTPUT', '-m', 'owner', '--uid-owner', str(uid), '-j', 'REJECT'], check=False)
    # Remove DNS block rules if present (customize as needed)
    # subprocess.run(['iptables', '-D', 'OUTPUT', '-p', 'udp', '--dport', '53', '!', '-d', '8.8.8.8', '-m', 'owner', '--uid-owner', str(uid), '-j', 'REJECT'], check=False)
    # subprocess.run(['iptables', '-D', 'OUTPUT', '-p', 'tcp', '--dport', '53', '!', '-d', '8.8.8.8', '-m', 'owner', '--uid-owner', str(uid), '-j', 'REJECT'], check=False)


def clear_squid_whitelist():
    # Optionally clear the whitelist file (or restore to default)
    open(SQUID_WHITELIST, 'w').close()
    subprocess.run(['systemctl', 'reload', SQUID_SERVICE], check=True)


def main():
    """Main unrestrict CLI entry point."""
    parser = create_parser()
    args = parser.parse_args()
    
    check_root()
    
    # Initialize the manager
    config_dir = args.config_dir or get_project_root()
    manager = ContestManager(config_dir=config_dir)
    
    try:
        # Remove iptables rules for the user
        remove_squid_iptables(args.user)
        # Optionally clear Squid whitelist (or leave as is)
        clear_squid_whitelist()
        print(f"Restrictions removed for user '{args.user}'.")
        sys.exit(0)
    except KeyboardInterrupt:
        print("\nUnrestriction cancelled by user")
        sys.exit(1)
    except Exception as e:
        print(f"Unrestriction error: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
