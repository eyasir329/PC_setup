#!/usr/bin/env python3

from typing import List, Tuple, Dict
import os
import json

def load_rank_data(rank_file: str = "rank.txt") -> List[Tuple[str, int]]:
    """
    Load contestant ranks from a file.
    
    Args:
        rank_file: Path to the file containing usernames in rank order
        
    Returns:
        List of (username, rank) tuples
    """
    try:
        results = []
        with open(rank_file, 'r') as file:
            for rank, line in enumerate(file, start=1):
                username = line.strip()
                if username and not username.startswith('#'):  # Skip comments and empty lines
                    results.append((username, rank))
        return results
    except FileNotFoundError:
        print(f"Rank file '{rank_file}' not found.")
        return []

def save_leaderboard(rankings: List[Tuple[str, int]], output_file: str = "leaderboard.txt") -> None:
    """
    Save rankings to a leaderboard file.
    
    Args:
        rankings: List of (username, points) tuples sorted by points (descending)
        output_file: Path to the output file
    """
    with open(output_file, 'w') as file:
        file.write("Final Rankings\n")
        file.write("=============\n\n")
        file.write(f"{'Rank':<6} {'Username':<30} {'Total Points':<12}\n")
        file.write("-" * 50 + "\n")
        
        for i, (username, points) in enumerate(rankings, start=1):
            file.write(f"{i:<6} {username:<30} {points:<12}\n")
            
    print(f"Leaderboard saved to {output_file}")

def save_teams(teams: List[List[Tuple[str, int]]], team_size: int, output_file: str = "teams.txt") -> None:
    """
    Save team allocations to a file.
    
    Args:
        teams: List of teams, where each team is a list of (username, points) tuples
        team_size: Size of each team
        output_file: Path to the output file
    """
    with open(output_file, 'w') as file:
        file.write(f"Teams (size {team_size})\n")
        file.write("=" * 50 + "\n\n")
        
        for i, team in enumerate(teams, start=65):  # Start with 'A'
            team_name = f"Team {chr(i)}"
            file.write(f"\n{team_name}:\n")
            file.write("-" * 40 + "\n")
            file.write(f"{'Username':<30} {'Total Points':<12}\n")
            file.write("-" * 40 + "\n")
            
            for username, points in team:
                file.write(f"{username:<30} {points:<12}\n")
            
            file.write("\n")
    
    print(f"Team allocations saved to {output_file}")

def load_saved_points(file_path: str = "data/total_points.json") -> Dict[str, int]:
    """
    Load previously saved points from a JSON file.
    
    Args:
        file_path: Path to the JSON file containing saved points
        
    Returns:
        Dictionary mapping usernames to total points
    """
    try:
        with open(file_path, 'r') as file:
            return json.load(file)
    except FileNotFoundError:
        return {}

def save_points(total_points: Dict[str, int], file_path: str = "data/total_points.json") -> None:
    """
    Save total points to a JSON file.
    
    Args:
        total_points: Dictionary mapping usernames to total points
        file_path: Path to the JSON file to save to
    """
    # Ensure data directory exists
    os.makedirs(os.path.dirname(file_path), exist_ok=True)
    
    with open(file_path, 'w') as file:
        json.dump(total_points, file, indent=2)
    
    print(f"Points data saved successfully.")

def clear_data(leaderboard_file: str = "leaderboard.txt", 
               points_file: str = "data/total_points.json", 
               teams_file: str = "teams.txt") -> None:
    """
    Clear all saved data.
    
    Args:
        leaderboard_file: Path to the leaderboard file
        points_file: Path to the points data file
        teams_file: Path to the teams file
    """
    # Clear leaderboard
    with open(leaderboard_file, 'w') as file:
        file.write("No contest data available yet.\n")
    
    # Clear teams file
    with open(teams_file, 'w') as file:
        file.write("No contest data available yet.\n")
    
    # Delete points file
    try:
        os.remove(points_file)
    except FileNotFoundError:
        pass
    
    print("All data has been cleared. The system has been reset.")