import os
import sqlite3
from dotenv import load_dotenv

load_dotenv()

db_path = os.getenv("DB_PATH")
terms = os.getenv("SEARCH_TERMS").split(",")
case_sensitive = os.getenv("CASE_SENSITIVE", "false").lower() == "true"

conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
cursor = conn.cursor()

def normalize(value):
    if value is None:
        return ""
    return str(value)

def match(value):
    text = normalize(value)
    if not case_sensitive:
        text = text.lower()
    for term in terms:
        t = term if case_sensitive else term.lower()
        if t in text:
            return True, term
    return False, None

tables = cursor.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()

results = []

for table in tables:
    table_name = table["name"]
    try:
        columns_info = cursor.execute(f"PRAGMA table_info('{table_name}')").fetchall()
        columns = [col["name"] for col in columns_info]

        rows = cursor.execute(f"SELECT rowid, * FROM '{table_name}'")

        for row in rows:
            rowid = row["rowid"] if "rowid" in row.keys() else None
            for col in columns:
                value = row[col]
                found, term = match(value)
                if found:
                    results.append({
                        "table": table_name,
                        "column": col,
                        "rowid": rowid,
                        "matched_term": term,
                        "value": normalize(value)
                    })
    except Exception:
        continue

for r in results:
    print(f"[MATCH] table={r['table']} column={r['column']} rowid={r['rowid']} term={r['matched_term']}")
    print(f"         value={r['value']}")
    print()

print(f"Total matches: {len(results)}")