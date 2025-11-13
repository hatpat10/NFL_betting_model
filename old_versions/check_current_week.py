"""
Quick diagnostic: Check what weeks are available in database
"""

import duckdb
import yaml

# Load config
with open('config/config.yaml', 'r') as f:
    config = yaml.safe_load(f)

DB_PATH = f"{config['directories']['base']}/data/nfl_data.duckdb"

con = duckdb.connect(DB_PATH, read_only=True)

# Check 2025 schedule
print("ðŸ“… 2025 NFL SCHEDULE IN DATABASE\n")
print("=" * 60)

weeks = con.execute("""
    SELECT 
        week,
        COUNT(*) as total_games,
        SUM(CASE WHEN home_score IS NOT NULL THEN 1 ELSE 0 END) as completed,
        SUM(CASE WHEN home_score IS NULL THEN 1 ELSE 0 END) as upcoming
    FROM games
    WHERE season = 2025
    GROUP BY week
    ORDER BY week
""").df()

print(weeks.to_string(index=False))

print("\n" + "=" * 60)

# Get current week recommendation
if len(weeks) > 0:
    last_week_with_games = weeks['week'].max()
    completed_weeks = weeks[weeks['completed'] > 0]['week'].max() if (weeks['completed'] > 0).any() else 0
    
    print(f"\nðŸ“Š Analysis:")
    print(f"   Last week in database: Week {last_week_with_games}")
    print(f"   Last completed week: Week {completed_weeks}")
    print(f"   Recommended prediction week: Week {completed_weeks + 1}")
    
    # Check team features availability
    features_available = con.execute(f"""
        SELECT COUNT(DISTINCT team_abbr) as teams
        FROM team_features
        WHERE season = 2025 AND week = {completed_weeks + 1}
    """).fetchone()[0]
    
    print(f"   Teams with features for Week {completed_weeks + 1}: {features_available}/32")
    
    if features_available < 32:
        print(f"\n   âš ï¸  Not all teams have features yet for Week {completed_weeks + 1}")
        print(f"      (This is normal if Week {completed_weeks} just finished)")

con.close()

print("\nðŸ’¡ Update config.yaml current_week to the recommended week above.\n")
