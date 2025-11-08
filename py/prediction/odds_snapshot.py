import os, requests, pandas as pd, sqlite3
from datetime import datetime, timezone
from dotenv import load_dotenv

load_dotenv("config/.env")
API = "https://api.the-odds-api.com/v4"
KEY = os.getenv("ODDS_API_KEY")

def fetch_current_odds(markets=("spreads","totals","h2h")):
    params = {
        "apiKey": KEY,
        "regions": "us",
        "markets": ",".join(markets),
        "oddsFormat": "american"
    }
    url = f"{API}/sports/americanfootball_nfl/odds"
    r = requests.get(url, params=params, timeout=30)
    r.raise_for_status()
    return r.json()

def to_rows(json_data, ts):
    rows = []
    for event in json_data:
        eid = event.get("id")
        commence = event.get("commence_time")
        home, away = event.get("home_team"), event.get("away_team")
        for b in event.get("bookmakers", []):
            book = b.get("title")
            for m in b.get("markets", []):
                market = m.get("key")
                for o in m.get("outcomes", []):
                    rows.append({
                        "event_id": eid, "commence_time": commence,
                        "home_team": home, "away_team": away,
                        "book": book, "market": market,
                        "name": o.get("name"),
                        "price": o.get("price"),
                        "point": o.get("point"),
                        "ts_utc": ts
                    })
    return pd.DataFrame(rows)

def main():
    if not KEY:
        raise SystemExit("Missing ODDS_API_KEY in config/.env")
    ts = datetime.now(timezone.utc).isoformat()
    data = fetch_current_odds()
    df = to_rows(data, ts)
    os.makedirs("db", exist_ok=True)
    con = sqlite3.connect("db/nfl.sqlite")
    df.to_sql("odds_snapshots", con, if_exists="append", index=False)
    con.close()
    print(f"Saved {len(df)} rows to db/odds_snapshots @ {ts}")

if __name__ == "__main__":
    main()
