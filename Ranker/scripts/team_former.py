#!/usr/bin/env python3

from typing import List, Tuple, Dict

def get_rankings(total_points: Dict[str, int]) -> List[Tuple[str, int]]:
    """
    Get contestant rankings based on total points.
    
    Args:
        total_points: Dictionary mapping usernames to total points
        
    Returns:
        List of (username, points) tuples sorted by points (descending)
    """
    rankings = [(username, points) for username, points in total_points.items()]
    return sorted(rankings, key=lambda x: x[1], reverse=True)

def form_teams(rankings: List[Tuple[str, int]], team_size: int = 3) -> List[List[Tuple[str, int]]]:
    """
    Form teams based on rankings.
    
    Args:
        rankings: List of (username, points) tuples sorted by points (descending)
        team_size: Number of members in each team
        
    Returns:
        List of teams, where each team is a list of (username, points) tuples
    """
    teams = []
    
    # Form teams by taking contestants in order
    for i in range(0, len(rankings), team_size):
        team = rankings[i:i + team_size]
        teams.append(team)
    
    return teams

def print_teams(teams: List[List[Tuple[str, int]]]) -> None:
    """
    Print teams to the console.
    
    Args:
        teams: List of teams, where each team is a list of (username, points) tuples
    """
    print(f"\nTeams (size {len(teams[0]) if teams else 0}):")
    print("=" * 50)
    
    for i, team in enumerate(teams, start=65):  # Start with 'A'
        team_name = f"Team {chr(i)}"
        print(f"\n{team_name}:")
        print("-" * 40)
        print(f"{'Username':<20} {'Total Points':<12}")
        print("-" * 40)
        
        for username, points in team:
            print(f"{username:<20} {points:<12}")