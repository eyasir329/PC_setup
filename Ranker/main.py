#!/usr/bin/env python3
"""
JKKNIU Programming Club Team Selector
====================================

This tool helps you select teams for programming competitions based on contest rankings.
It calculates points based on ranks and forms balanced teams.
"""

import os
import sys

# Add the scripts directory to the Python path
sys.path.append(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'scripts'))

# Import our modules from the scripts directory
from scripts.file_handler import load_rank_data, save_leaderboard, save_teams, load_saved_points, save_points, clear_data
from scripts.points_calculator import process_rank_data, merge_points
from scripts.team_former import get_rankings, form_teams, print_teams

def fetch_ranks():
    """Placeholder for future rank fetching functionality."""
    print("\nRank fetching feature will be implemented in the future.")
    print("For now, please manually edit the rank.txt file.")

def update_leaderboard():
    """Process the rank.txt file and update the leaderboard."""
    print("\nUpdating leaderboard from rank.txt...")
    
    # Check if rank.txt exists
    if not os.path.exists("rank.txt"):
        print("Error: rank.txt not found. Create this file with contestant usernames.")
        return
    
    # Load rank data
    rank_data = load_rank_data("rank.txt")
    if not rank_data:
        print("No valid contestant data found in rank.txt")
        return
    
    print(f"Loaded {len(rank_data)} contestants from rank.txt")
    
    # Calculate points for current ranks
    new_points = process_rank_data(rank_data)
    
    # Load existing points if any
    existing_points = load_saved_points()
    
    # Merge points
    total_points = merge_points(existing_points, new_points)
    
    # Save updated points
    save_points(total_points)
    
    # Generate and save rankings to leaderboard
    rankings = get_rankings(total_points)
    save_leaderboard(rankings)
    
    print("Leaderboard updated successfully!")

def form_team():
    """Form teams based on current leaderboard."""
    print("\nForming teams based on current leaderboard...")
    
    # Load existing points
    total_points = load_saved_points()
    
    if not total_points:
        print("No points data found. Run 'Update Leaderboard' first.")
        return
    
    try:
        team_size = input("Enter team size (default: 3): ").strip()
        team_size = int(team_size) if team_size else 3
        
        if team_size <= 0:
            print("Team size must be positive.")
            return
    except ValueError:
        print("Invalid team size. Using default size of 3.")
        team_size = 3
    
    # Generate rankings
    rankings = get_rankings(total_points)
    
    # Form teams
    teams = form_teams(rankings, team_size)
    
    # Print teams
    print_teams(teams)
    
    # Save teams to file
    save_teams(teams, team_size)
    
    print(f"{len(teams)} teams formed successfully!")

def reset_system():
    """Clear all data and reset the system."""
    confirm = input("\nAre you sure you want to reset all data? This cannot be undone. (y/n): ")
    if confirm.lower() == 'y':
        clear_data()
        
        # Create empty files
        open("rank.txt", "w").close()
        open("leaderboard.txt", "w").close()
        open("teams.txt", "w").close()
        
        print("All data has been reset. Empty files have been created.")
    else:
        print("Reset cancelled.")

def check_files():
    """Check if required files exist and create them if they don't."""
    # Create data directory if it doesn't exist
    os.makedirs("data", exist_ok=True)
    
    # Create empty files if they don't exist
    if not os.path.exists("rank.txt"):
        open("rank.txt", "w").close()
    
    if not os.path.exists("leaderboard.txt"):
        open("leaderboard.txt", "w").close()
    
    if not os.path.exists("teams.txt"):
        open("teams.txt", "w").close()

def main():
    """Main entry point."""
    print("=============================================")
    print("  JKKNIU Programming Club Team Selector")
    print("=============================================")
    
    # Check if required files exist
    check_files()
    
    # Interactive menu
    while True:
        print("\n============== Programming Club Team Selector ==============")
        print("1. Fetch Ranks (Not implemented yet)")
        print("2. Update Leaderboard")
        print("3. Form Teams")
        print("4. Clear/Reset")
        print("0. Exit")
        
        choice = input("\nEnter your choice: ")
        
        if choice == "1":
            fetch_ranks()
            
        elif choice == "2":
            update_leaderboard()
            
        elif choice == "3":
            form_team()
            
        elif choice == "4":
            reset_system()
            
        elif choice == "0":
            print("Exiting program. Goodbye!")
            break
            
        else:
            print("Invalid choice. Please try again.")

if __name__ == "__main__":
    main()