#!/usr/bin/env python3

import math
from typing import List, Tuple, Dict

def calculate_points(rank: int) -> int:
    """
    Calculate points for a given rank using the formula: ceil(1800 / (rank + 5))
    
    Args:
        rank: The contestant's rank
        
    Returns:
        The calculated points
    """
    return math.ceil(1600.0 / (rank + 7))

def process_rank_data(rank_data: List[Tuple[str, int]]) -> Dict[str, int]:
    """
    Calculate points for each contestant based on their ranks
    
    Args:
        rank_data: List of (username, rank) tuples
        
    Returns:
        Dictionary mapping usernames to points
    """
    points = {}
    for username, rank in rank_data:
        points[username] = calculate_points(rank)
    
    return points

def merge_points(existing_points: Dict[str, int], new_points: Dict[str, int]) -> Dict[str, int]:
    """
    Merge new points into existing points, accumulating them
    
    Args:
        existing_points: Existing points dictionary
        new_points: New points dictionary
        
    Returns:
        Updated points dictionary
    """
    merged = existing_points.copy()
    
    for username, points in new_points.items():
        if username in merged:
            merged[username] += points
        else:
            merged[username] = points
    
    return merged