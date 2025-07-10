#!/usr/bin/env python3
"""
Contest Environment Manager - Main CLI Entry Point
"""

import sys
import os
import argparse
from pathlib import Path

from ..core.manager import ContestManager
from ..utils.common import check_root, get_project_root


def create_parser():
    """Create the main argument parser."""
    parser = argparse.ArgumentParser(
        description="Contest Environment Manager - Professional Python Implementation",
        prog="contest-manager",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  sudo contest-manager setup                   # Set up lab PC from scratch for participant
  sudo contest-manager setup contestant        # Set up lab PC for user "contestant"
  sudo contest-manager restrict                # Restrict default user (participant)
  sudo contest-manager unrestrict              # Remove restrictions for participant
  sudo contest-manager status                  # Check status for participant
  sudo contest-manager reset                   # Reset participant account to clean state
  sudo contest-manager add codeforces.com      # Add domain to whitelist
  sudo contest-manager remove codeforces.com   # Remove domain from whitelist
  sudo contest-manager list                    # List whitelisted domains
  sudo contest-manager dependencies            # Show resolved dependencies
        """
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
    
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # Setup command
    setup_parser = subparsers.add_parser('setup', help='Set up lab PC with all required software')
    setup_parser.add_argument('user', nargs='?', default='participant', help='Username (default: participant)')
    
    # Reset command
    reset_parser = subparsers.add_parser('reset', help='Reset user account to clean state')
    reset_parser.add_argument('user', nargs='?', default='participant', help='Username (default: participant)')
    
    # Restrict command
    restrict_parser = subparsers.add_parser('restrict', help='Enable internet restrictions')
    restrict_parser.add_argument('user', nargs='?', default='participant', help='Username (default: participant)')
    
    # Unrestrict command
    unrestrict_parser = subparsers.add_parser('unrestrict', help='Disable internet restrictions')
    unrestrict_parser.add_argument('user', nargs='?', default='participant', help='Username (default: participant)')
    
    # Status command
    status_parser = subparsers.add_parser('status', help='Show current restriction status')
    status_parser.add_argument('user', nargs='?', default='participant', help='Username (default: participant)')
    
    # Whitelist management commands
    add_parser = subparsers.add_parser('add', help='Add domain to whitelist')
    add_parser.add_argument('domain', help='Domain to add (e.g., example.com)')
    
    remove_parser = subparsers.add_parser('remove', help='Remove domain from whitelist')
    remove_parser.add_argument('domain', help='Domain to remove')
    
    list_parser = subparsers.add_parser('list', help='List currently whitelisted domains')
    
    deps_parser = subparsers.add_parser('dependencies', help='Show resolved dependencies for whitelisted domains')
    
    return parser


def main():
    """Main CLI entry point."""
    parser = create_parser()
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
    
    # Initialize the manager
    config_dir = args.config_dir or get_project_root()
    manager = ContestManager(config_dir=config_dir)
    
    try:
        # Route commands
        if args.command == "setup":
            check_root()
            success = manager.setup_user(args.user)
            sys.exit(0 if success else 1)
        
        elif args.command == "reset":
            check_root()
            success = manager.reset_user(args.user)
            sys.exit(0 if success else 1)
        
        elif args.command == "restrict":
            check_root()
            success = manager.apply_restrictions(args.user)
            sys.exit(0 if success else 1)
        
        elif args.command == "unrestrict":
            check_root()
            success = manager.remove_restrictions(args.user)
            sys.exit(0 if success else 1)
        
        elif args.command == "status":
            success = manager.show_status(args.user)
            sys.exit(0 if success else 1)
        
        elif args.command == "add":
            check_root()
            success = manager.add_domain(args.domain)
            sys.exit(0 if success else 1)
        
        elif args.command == "remove":
            check_root()
            success = manager.remove_domain(args.domain)
            sys.exit(0 if success else 1)
        
        elif args.command == "list":
            manager.show_domains()
            sys.exit(0)
        
        elif args.command == "dependencies":
            manager.show_dependencies()
            sys.exit(0)
        
        else:
            parser.print_help()
            sys.exit(1)
    
    except KeyboardInterrupt:
        print("\nOperation cancelled by user")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
