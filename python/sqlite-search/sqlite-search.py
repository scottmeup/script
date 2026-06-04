import os
import re
import sqlite3
from datetime import datetime
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

def normalize(value):
    if value is None:
        return ""
    return str(value)

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

timestamp = datetime.now().strftime("%Y-%m-%dT%H-%M-%S")
log_filename = f"sqlite-search-{timestamp}.log"
log_file = open(log_filename, "w", encoding="utf-8")

def log_line(text=""):
    log_file.write(text + "\n")

def log_settings():
    log_line("=== SETTINGS ===")
    log_line(f"DB_PATH={db_path}")
    log_line(f"SEARCH_TERMS={terms}")
    log_line(f"REPLACE_TERMS={replace_terms}")
    log_line(f"CASE_SENSITIVE={case_sensitive}")
    log_line(f"SEARCH_VALUES={search_values}")
    log_line(f"SEARCH_COLUMNS={search_columns}")
    log_line(f"SEARCH_TABLES={search_tables}")
    log_line(f"ENABLE_REPLACEMENT={enable_replacement}")
    log_line("")

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

def get_tables(cursor):
    rows = cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").fetchall()
    return [row["name"] for row in rows]

def get_table_info(cursor, table_name):
    return cursor.execute(f"PRAGMA table_info({qident(table_name)})").fetchall()

def get_pk_columns(table_info):
    pk_cols = [row["name"] for row in table_info if row["pk"]]
    pk_cols_sorted = sorted(pk_cols, key=lambda c: next(r["pk"] for r in table_info if r["name"] == c))
    return pk_cols_sorted

def has_rowid_table(cursor, table_name):
    sql_row = cursor.execute(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
        (table_name,)
    ).fetchone()
    if not sql_row or sql_row["sql"] is None:
        return True
    return "WITHOUT ROWID" not in sql_row["sql"].upper()

def get_row_identity(row, rowid_ok, pk_columns):
    if rowid_ok and "__copilot_rowid__" in row.keys():
        return f"rowid={row['__copilot_rowid__']}"
    if pk_columns:
        pairs = []
        for pk in pk_columns:
            pairs.append(f"{pk}={normalize(row[pk])}")
        return "pk=" + ",".join(pairs)
    return "row=unknown"

conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
read_cursor = conn.cursor()
write_cursor = conn.cursor()

table_match_count = 0
column_match_count = 0
value_match_count = 0
rows_updated = 0
fields_updated = 0
bulk_columns_updated = 0
bulk_cells_updated = 0
value_update_count = 0
column_row_log_count = 0
skipped_table_count = 0

try:
    log_settings()
    log_line("=== MATCHES AND MODIFICATIONS ===")

    tables = get_tables(read_cursor)

    for table_name in tables:
        if search_tables:
            table_matches = all_match_indices(table_name)
            for idx in table_matches:
                msg = f"[TABLE MATCH] table={table_name} term={terms[idx]}"
                print(msg)
                log_line(msg)
                table_match_count += 1

        try:
            table_info = get_table_info(read_cursor, table_name)
            columns = [row["name"] for row in table_info]
            pk_columns = get_pk_columns(table_info)
            rowid_ok = has_rowid_table(read_cursor, table_name)

            matched_columns = {}
            matched_column_first_idx = {}

            if search_columns:
                for col in columns:
                    column_matches = all_match_indices(col)
                    if column_matches:
                        matched_columns[col] = column_matches
                        matched_column_first_idx[col] = first_match_index(col)
                    for idx in column_matches:
                        msg = f"[COLUMN MATCH] table={table_name} column={col} term={terms[idx]}"
                        print(msg)
                        log_line(msg)
                        column_match_count += 1

            if search_values or (search_columns and matched_columns):
                select_columns = []
                if rowid_ok:
                    select_columns.append("rowid AS __copilot_rowid__")
                select_columns.extend([qident(c) for c in columns])

                select_sql = f"SELECT {', '.join(select_columns)} FROM {qident(table_name)}"
                rows = read_cursor.execute(select_sql).fetchall()

                for row in rows:
                    row_identity = get_row_identity(row, rowid_ok, pk_columns)
                    updates = {}

                    for col in columns:
                        original_value = row[col]
                        value_text = normalize(original_value)

                        if search_columns and col in matched_columns:
                            replacement_idx = matched_column_first_idx[col]
                            replacement_value = replace_terms[replacement_idx] if replacement_idx is not None and replacement_idx < len(replace_terms) else ""
                            for idx in matched_columns[col]:
                                if enable_replacement:
                                    msg = f"[COLUMN MATCH ROW] table={table_name} column={col} {row_identity} term={terms[idx]} field_contents={value_text!r} new_field_contents={replacement_value!r}"
                                else:
                                    msg = f"[COLUMN MATCH ROW] table={table_name} column={col} {row_identity} term={terms[idx]} field_contents={value_text!r}"
                                log_line(msg)
                                column_row_log_count += 1

                        if search_values:
                            matches = all_match_indices(value_text)
                            if matches:
                                if enable_replacement:
                                    if col in matched_columns:
                                        replacement_idx = matched_column_first_idx[col]
                                        projected_new_value = replace_terms[replacement_idx] if replacement_idx is not None and replacement_idx < len(replace_terms) else ""
                                    else:
                                        projected_new_value = apply_replacements(value_text)
                                else:
                                    projected_new_value = None

                                for idx in matches:
                                    if enable_replacement:
                                        msg = f"[VALUE MATCH] table={table_name} column={col} {row_identity} term={terms[idx]} field_contents={value_text!r} new_field_contents={projected_new_value!r}"
                                    else:
                                        msg = f"[VALUE MATCH] table={table_name} column={col} {row_identity} term={terms[idx]} field_contents={value_text!r}"
                                    print(msg)
                                    log_line(msg)
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
                                value_update_count += len(updates)
                                for updated_col, new_value in updates.items():
                                    mod_msg = f"[VALUE UPDATE] table={table_name} column={updated_col} {row_identity} old_field_contents={normalize(row[updated_col])!r} new_field_contents={new_value!r}"
                                    print(mod_msg)
                                    log_line(mod_msg)

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
                                value_update_count += len(updates)
                                for updated_col, new_value in updates.items():
                                    mod_msg = f"[VALUE UPDATE] table={table_name} column={updated_col} {row_identity} old_field_contents={normalize(row[updated_col])!r} new_field_contents={new_value!r}"
                                    print(mod_msg)
                                    log_line(mod_msg)

            if enable_replacement and matched_columns:
                for col, match_indices in matched_columns.items():
                    replacement_idx = matched_column_first_idx[col]
                    replacement = replace_terms[replacement_idx] if replacement_idx is not None and replacement_idx < len(replace_terms) else ""
                    try:
                        update_sql = f"UPDATE {qident(table_name)} SET {qident(col)} = ?"
                        before_changes = conn.total_changes
                        write_cursor.execute(update_sql, (replacement,))
                        delta = conn.total_changes - before_changes
                        if delta > 0:
                            bulk_columns_updated += 1
                            bulk_cells_updated += delta
                            mod_msg = f"[COLUMN VALUE REPLACEMENT] table={table_name} column={col} replacement_term={terms[replacement_idx]} replacement_value={replacement!r} rows_changed={delta}"
                            print(mod_msg)
                            log_line(mod_msg)
                    except Exception as e:
                        err_msg = f"[SKIP COLUMN VALUE REPLACEMENT] table={table_name} column={col} error={e}"
                        print(err_msg)
                        log_line(err_msg)

        except Exception as e:
            skipped_table_count += 1
            err_msg = f"[SKIP] table={table_name} error={e}"
            print(err_msg)
            log_line(err_msg)

    if enable_replacement:
        conn.commit()

    total_matches = table_match_count + column_match_count + value_match_count

    log_line("")
    log_line("=== SUMMARY ===")
    log_line(f"Table matches: {table_match_count}")
    log_line(f"Column matches: {column_match_count}")
    log_line(f"Column match row details logged: {column_row_log_count}")
    log_line(f"Value matches: {value_match_count}")
    log_line(f"Total matches: {total_matches}")
    log_line(f"Replacement enabled: {enable_replacement}")
    log_line(f"Rows updated: {rows_updated}")
    log_line(f"Fields updated: {fields_updated}")
    log_line(f"Value updates logged: {value_update_count}")
    log_line(f"Bulk columns updated: {bulk_columns_updated}")
    log_line(f"Bulk cells updated: {bulk_cells_updated}")
    log_line(f"Skipped tables: {skipped_table_count}")
    log_line(f"SQLite total changes: {conn.total_changes}")
    log_line(f"Log file: {log_filename}")

    print()
    print(f"Table matches: {table_match_count}")
    print(f"Column matches: {column_match_count}")
    print(f"Column match row details logged: {column_row_log_count}")
    print(f"Value matches: {value_match_count}")
    print(f"Total matches: {total_matches}")
    print(f"Replacement enabled: {enable_replacement}")
    print(f"Rows updated: {rows_updated}")
    print(f"Fields updated: {fields_updated}")
    print(f"Value updates logged: {value_update_count}")
    print(f"Bulk columns updated: {bulk_columns_updated}")
    print(f"Bulk cells updated: {bulk_cells_updated}")
    print(f"Skipped tables: {skipped_table_count}")
    print(f"SQLite total changes: {conn.total_changes}")
    print(f"Log file: {log_filename}")

finally:
    conn.close()
    log_file.close()