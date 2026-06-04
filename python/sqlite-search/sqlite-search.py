import os
import re
import sqlite3
from dotenv import load_dotenv

load_dotenv()

db_path = os.getenv("DB_PATH")
terms = os.getenv("SEARCH_TERMS").split(",")
replace_terms = os.getenv("REPLACE_TERMS").split(",")
case_sensitive = os.getenv("CASE_SENSITIVE", "false").lower() == "true"

search_values = os.getenv("SEARCH_VALUES", "true").lower() == "true"
search_columns = os.getenv("SEARCH_COLUMNS", "false").lower() == "true"
search_tables = os.getenv("SEARCH_TABLES", "false").lower() == "true"

enable_replacement = os.getenv("ENABLE_REPLACEMENT", "false").lower() == "true"

flags = 0 if case_sensitive else re.IGNORECASE

compiled_patterns = []
for term in terms:
    try:
        compiled_patterns.append(re.compile(term, flags))
    except re.error:
        compiled_patterns.append(re.compile(re.escape(term), flags))

conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
cursor = conn.cursor()

def normalize(v):
    if v is None:
        return ""
    return str(v)

def find_matches(text):
    matches = []
    for i, pattern in enumerate(compiled_patterns):
        if pattern.search(text):
            matches.append((i, pattern))
    return matches

def apply_replacements(text):
    new_text = text
    for i, pattern in enumerate(compiled_patterns):
        replacement = replace_terms[i] if i < len(replace_terms) else ""
        new_text = pattern.sub(replacement, new_text)
    return new_text

tables = cursor.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()

total_matches = 0

for table in tables:
    table_name = table["name"]

    if search_tables:
        matches = find_matches(table_name)
        for idx, _ in matches:
            print(f"[TABLE MATCH] table={table_name} term={terms[idx]}")
            total_matches += 1

    try:
        columns_info = cursor.execute(f"PRAGMA table_info('{table_name}')").fetchall()
        columns = [col["name"] for col in columns_info]

        if search_columns:
            for col in columns:
                matches = find_matches(col)
                for idx, _ in matches:
                    print(f"[COLUMN MATCH] table={table_name} column={col} term={terms[idx]}")
                    total_matches += 1

        if search_values:
            rows = cursor.execute(f"SELECT rowid, * FROM '{table_name}'")

            for row in rows:
                rowid = row["rowid"] if "rowid" in row.keys() else None

                updates = {}

                for col in columns:
                    value = normalize(row[col])
                    matches = find_matches(value)

                    if matches:
                        for idx, pattern in matches:
                            print(f"[VALUE MATCH] table={table_name} column={col} rowid={rowid} term={terms[idx]}")
                            total_matches += 1

                        if enable_replacement:
                            new_value = apply_replacements(value)
                            if new_value != value:
                                updates[col] = new_value

                if enable_replacement and updates:
                    set_clause = ", ".join([f"{c}=?" for c in updates.keys()])
                    params = list(updates.values())

                    if rowid is not None:
                        cursor.execute(
                            f"UPDATE '{table_name}' SET {set_clause} WHERE rowid=?",
                            params + [rowid]
                        )

    except Exception:
        continue

if enable_replacement:
    conn.commit()

conn.close()

print(f"Total matches: {total_matches}")