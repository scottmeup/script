import os
import re
import sqlite3
from dotenv import load_dotenv

load_dotenv()

def parse_bool(name, default=False):
    value = os.getenv(name)
    if value is None:
        return default
    value = value.strip().strip('"').strip("'").lower()
    return value in ("1", "true", "yes", "on")

def parse_list(name, default=""):
    value = os.getenv(name, default)
    if not value:
        return []
    return [item.strip() for item in value.split(",")]

def qident(name):
    return '"' + str(name).replace('"', '""') + '"'

db_path = os.getenv("DB_PATH")
terms = parse_list("SEARCH_TERMS")
replace_terms = parse_list("REPLACE_TERMS")
case_sensitive = parse_bool("CASE_SENSITIVE", False)
search_values = parse_bool("SEARCH_VALUES", True)
search_columns = parse_bool("SEARCH_COLUMNS", False)
search_tables = parse_bool("SEARCH_TABLES", False)
enable_replacement = parse_bool("ENABLE_REPLACEMENT", False)

if not db_path:
    raise ValueError("DB_PATH is required")

if not terms:
    raise ValueError("SEARCH_TERMS is required")

flags = 0 if case_sensitive else re.IGNORECASE

compiled_patterns = []
for term in terms:
    try:
        compiled_patterns.append(re.compile(term, flags))
    except re.error:
        compiled_patterns.append(re.compile(re.escape(term), flags))

conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
read_cursor = conn.cursor()
write_cursor = conn.cursor()

def normalize(value):
    if value is None:
        return ""
    return str(value)

def all_match_indices(text):
    matched = []
    for i, pattern in enumerate(compiled_patterns):
        if pattern.search(text):
            matched.append(i)
    return matched

def first_match_index(text):
    for i, pattern in enumerate(compiled_patterns):
        if pattern.search(text):
            return i
    return None

def apply_replacements(text):
    new_text = text
    for i, pattern in enumerate(compiled_patterns):
        replacement = replace_terms[i] if i < len(replace_terms) else ""
        new_text = pattern.sub(replacement, new_text)
    return new_text

def get_tables():
    rows = read_cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").fetchall()
    return [row["name"] for row in rows]

def get_table_info(table_name):
    return read_cursor.execute(f"PRAGMA table_info({qident(table_name)})").fetchall()

def get_pk_columns(table_info):
    pk_cols = [row["name"] for row in table_info if row["pk"]]
    pk_cols_sorted = sorted(pk_cols, key=lambda c: next(r["pk"] for r in table_info if r["name"] == c))
    return pk_cols_sorted

def has_rowid_table(table_name):
    sql_row = read_cursor.execute(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
        (table_name,)
    ).fetchone()
    if not sql_row or sql_row["sql"] is None:
        return True
    return "WITHOUT ROWID" not in sql_row["sql"].upper()

table_match_count = 0
column_match_count = 0
value_match_count = 0
rows_updated = 0
fields_updated = 0
bulk_columns_updated = 0
bulk_cells_updated = 0

tables = get_tables()

for table_name in tables:
    if search_tables:
        table_matches = all_match_indices(table_name)
        for idx in table_matches:
            print(f"[TABLE MATCH] table={table_name} term={terms[idx]}")
            table_match_count += 1

    try:
        table_info = get_table_info(table_name)
        columns = [row["name"] for row in table_info]
        pk_columns = get_pk_columns(table_info)
        rowid_ok = has_rowid_table(table_name)

        matched_columns = {}

        if search_columns:
            for col in columns:
                column_matches = all_match_indices(col)
                for idx in column_matches:
                    print(f"[COLUMN MATCH] table={table_name} column={col} term={terms[idx]}")
                    column_match_count += 1
                first_idx = first_match_index(col)
                if first_idx is not None:
                    matched_columns[col] = first_idx

        if search_values:
            select_columns = []
            if rowid_ok:
                select_columns.append("rowid AS __copilot_rowid__")
            select_columns.extend([qident(c) for c in columns])

            select_sql = f"SELECT {', '.join(select_columns)} FROM {qident(table_name)}"
            rows = read_cursor.execute(select_sql).fetchall()

            for row in rows:
                updates = {}

                for col in columns:
                    original_value = row[col]
                    value_text = normalize(original_value)
                    matches = all_match_indices(value_text)

                    if matches:
                        for idx in matches:
                            print(f"[VALUE MATCH] table={table_name} column={col} term={terms[idx]} value={value_text}")
                            value_match_count += 1

                    if enable_replacement and col not in matched_columns and original_value is not None:
                        new_value = apply_replacements(value_text)
                        if new_value != value_text:
                            updates[col] = new_value

                if enable_replacement and updates:
                    set_clause = ", ".join(f"{qident(col)}=?" for col in updates.keys())
                    params = [updates[col] for col in updates.keys()]

                    if rowid_ok:
                        where_value = row["__copilot_rowid__"]
                        update_sql = f"UPDATE {qident(table_name)} SET {set_clause} WHERE rowid = ?"
                        before_changes = conn.total_changes
                        write_cursor.execute(update_sql, params + [where_value])
                        delta = conn.total_changes - before_changes
                        if delta > 0:
                            rows_updated += 1
                            fields_updated += len(updates)
                    elif pk_columns:
                        where_clause = " AND ".join(f"{qident(pk)}=?" for pk in pk_columns)
                        where_values = [row[pk] for pk in pk_columns]
                        update_sql = f"UPDATE {qident(table_name)} SET {set_clause} WHERE {where_clause}"
                        before_changes = conn.total_changes
                        write_cursor.execute(update_sql, params + where_values)
                        delta = conn.total_changes - before_changes
                        if delta > 0:
                            rows_updated += 1
                            fields_updated += len(updates)

        if enable_replacement and matched_columns:
            row_count = read_cursor.execute(f"SELECT COUNT(*) AS c FROM {qident(table_name)}").fetchone()["c"]

            for col, idx in matched_columns.items():
                replacement = replace_terms[idx] if idx < len(replace_terms) else ""
                try:
                    update_sql = f"UPDATE {qident(table_name)} SET {qident(col)} = ?"
                    before_changes = conn.total_changes
                    write_cursor.execute(update_sql, (replacement,))
                    delta = conn.total_changes - before_changes
                    if delta > 0:
                        bulk_columns_updated += 1
                        bulk_cells_updated += delta
                        print(f"[COLUMN VALUE REPLACEMENT] table={table_name} column={col} term={terms[idx]} replacement={replacement} rows_targeted={row_count} rows_changed={delta}")
                except Exception as e:
