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

def emit(text=""):
    print(text)
    log_file.write(text + "\n")

def log_only(text=""):
    log_file.write(text + "\n")

def log_settings():
    emit("=== SETTINGS ===")
    emit(f"DB_PATH={db_path}")
    emit(f"SEARCH_TERMS={terms}")
    emit(f"REPLACE_TERMS={replace_terms}")
    emit(f"CASE_SENSITIVE={case_sensitive}")
    emit(f"SEARCH_VALUES={search_values}")
    emit(f"SEARCH_COLUMNS={search_columns}")
    emit(f"SEARCH_TABLES={search_tables}")
    emit(f"ENABLE_REPLACEMENT={enable_replacement}")
    emit("")

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

def build_where_clause_and_params(row, rowid_ok, pk_columns):
    if rowid_ok and "__copilot_rowid__" in row.keys():
        return "rowid = ?", [row["__copilot_rowid__"]]
    if pk_columns:
        return " AND ".join(f"{qident(pk)}=?" for pk in pk_columns), [row[pk] for pk in pk_columns]
    return None, None

def fetch_current_value(cursor, table_name, column_name, row, rowid_ok, pk_columns):
    where_clause, where_params = build_where_clause_and_params(row, rowid_ok, pk_columns)
    if where_clause is None:
        return False, None, "No row identifier available for verification"
    sql = f"SELECT {qident(column_name)} AS v FROM {qident(table_name)} WHERE {where_clause}"
    result = cursor.execute(sql, where_params).fetchone()
    if result is None:
        return False, None, "Verification select found no row"
    return True, result["v"], None

def update_and_verify_cell(conn, read_cursor, write_cursor, table_name, column_name, row, rowid_ok, pk_columns, old_value, new_value):
    where_clause, where_params = build_where_clause_and_params(row, rowid_ok, pk_columns)
    if where_clause is None:
        return False, False, False, "No row identifier available for update"

    if old_value == new_value:
        return True, False, False, None

    try:
        before_ok, before_db_value, before_err = fetch_current_value(read_cursor, table_name, column_name, row, rowid_ok, pk_columns)
        if not before_ok:
            return False, False, False, before_err
        if before_db_value != old_value:
            return False, False, False, f"Pre-update verification mismatch old_db_value={before_db_value!r} expected_old_value={old_value!r}"

        sql = f"UPDATE {qident(table_name)} SET {qident(column_name)} = ? WHERE {where_clause}"
        write_cursor.execute(sql, [new_value] + where_params)

        after_ok, after_db_value, after_err = fetch_current_value(read_cursor, table_name, column_name, row, rowid_ok, pk_columns)
        if not after_ok:
            return False, False, False, after_err
        if after_db_value == new_value:
            return True, True, True, None
        if after_db_value == old_value:
            return True, False, False, f"Post-update verification shows unchanged value={after_db_value!r}"
        return True, False, False, f"Post-update verification mismatch actual_value={after_db_value!r} expected_new_value={new_value!r}"
    except Exception as e:
        return False, False, False, str(e)

conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
read_cursor = conn.cursor()
write_cursor = conn.cursor()

table_match_count = 0
column_match_count = 0
value_match_count = 0
column_match_row_detail_count = 0

value_change_count = 0
value_no_change_count = 0
value_failed_change_count = 0

column_change_count = 0
column_no_change_count = 0
column_failed_change_count = 0

skipped_table_count = 0

try:
    log_settings()
    emit("=== MATCHES AND MODIFICATIONS ===")

    tables = get_tables(read_cursor)

    for table_name in tables:
        if search_tables:
            table_matches = all_match_indices(table_name)
            for idx in table_matches:
                emit(f"[TABLE MATCH] table={table_name} term={terms[idx]}")
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
                        emit(f"[COLUMN MATCH] table={table_name} column={col} term={terms[idx]}")
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

                    for col in columns:
                        original_value = row[col]
                        value_text = normalize(original_value)

                        if search_columns and col in matched_columns:
                            replacement_idx = matched_column_first_idx[col]
                            replacement_value = replace_terms[replacement_idx] if replacement_idx is not None and replacement_idx < len(replace_terms) else ""
                            for idx in matched_columns[col]:
                                if enable_replacement:
                                    emit(f"[COLUMN MATCH ROW] table={table_name} column={col} {row_identity} term={terms[idx]} field_contents={value_text!r} new_field_contents={replacement_value!r}")
                                else:
                                    emit(f"[COLUMN MATCH ROW] table={table_name} column={col} {row_identity} term={terms[idx]} field_contents={value_text!r}")
                                column_match_row_detail_count += 1

                            if enable_replacement:
                                ok, attempted, changed, err = update_and_verify_cell(
                                    conn,
                                    read_cursor,
                                    write_cursor,
                                    table_name,
                                    col,
                                    row,
                                    rowid_ok,
                                    pk_columns,
                                    original_value,
                                    replacement_value
                                )
                                if ok and attempted and changed:
                                    emit(f"[COLUMN VALUE UPDATE] table={table_name} column={col} {row_identity} old_field_contents={value_text!r} new_field_contents={replacement_value!r}")
                                    column_change_count += 1
                                elif ok and not attempted and not changed:
                                    emit(f"[COLUMN VALUE NO CHANGE] table={table_name} column={col} {row_identity} field_contents={value_text!r} new_field_contents={replacement_value!r}")
                                    column_no_change_count += 1
                                else:
                                    emit(f"[COLUMN VALUE UPDATE FAILED] table={table_name} column={col} {row_identity} old_field_contents={value_text!r} attempted_new_field_contents={replacement_value!r} error={err}")
                                    column_failed_change_count += 1

                            continue

                        if search_values:
                            matches = all_match_indices(value_text)
                            if matches:
                                projected_new_value = None
                                if enable_replacement and original_value is not None:
                                    projected_new_value = apply_replacements(value_text)

                                for idx in matches:
                                    if enable_replacement and original_value is not None:
                                        emit(f"[VALUE MATCH] table={table_name} column={col} {row_identity} term={terms[idx]} field_contents={value_text!r} new_field_contents={projected_new_value!r}")
                                    else:
                                        emit(f"[VALUE MATCH] table={table_name} column={col} {row_identity} term={terms[idx]} field_contents={value_text!r}")
                                    value_match_count += 1

                                if enable_replacement and original_value is not None:
                                    ok, attempted, changed, err = update_and_verify_cell(
                                        conn,
                                        read_cursor,
                                        write_cursor,
                                        table_name,
                                        col,
                                        row,
                                        rowid_ok,
                                        pk_columns,
                                        original_value,
                                        projected_new_value
                                    )
                                    if ok and attempted and changed:
                                        emit(f"[VALUE UPDATE] table={table_name} column={col} {row_identity} old_field_contents={value_text!r} new_field_contents={projected_new_value!r}")
                                        value_change_count += 1
                                    elif ok and not attempted and not changed:
                                        emit(f"[VALUE NO CHANGE] table={table_name} column={col} {row_identity} field_contents={value_text!r} new_field_contents={projected_new_value!r}")
                                        value_no_change_count += 1
                                    else:
                                        emit(f"[VALUE UPDATE FAILED] table={table_name} column={col} {row_identity} old_field_contents={value_text!r} attempted_new_field_contents={projected_new_value!r} error={err}")
                                        value_failed_change_count += 1

        except Exception as e:
            skipped_table_count += 1
            emit(f"[SKIP] table={table_name} error={e}")

    if enable_replacement:
        conn.commit()

    total_matches = table_match_count + column_match_count + value_match_count
    total_actual_changes = value_change_count + column_change_count
    total_no_change = value_no_change_count + column_no_change_count
    total_failed_changes = value_failed_change_count + column_failed_change_count

    emit("")
    emit("=== SUMMARY ===")
    emit(f"Table matches: {table_match_count}")
    emit(f"Column matches: {column_match_count}")
    emit(f"Column match row details logged: {column_match_row_detail_count}")
    emit(f"Value matches: {value_match_count}")
    emit(f"Total matches: {total_matches}")
    emit(f"Replacement enabled: {enable_replacement}")
    emit(f"Value changes applied: {value_change_count}")
    emit(f"Value no-change replacements: {value_no_change_count}")
    emit(f"Value failed changes: {value_failed_change_count}")
    emit(f"Column-wide changes applied: {column_change_count}")
    emit(f"Column-wide no-change replacements: {column_no_change_count}")
    emit(f"Column-wide failed changes: {column_failed_change_count}")
    emit(f"Total actual changes applied: {total_actual_changes}")
    emit(f"Total no-change replacements: {total_no_change}")
    emit(f"Total failed changes: {total_failed_changes}")
    emit(f"Skipped tables: {skipped_table_count}")
    emit(f"SQLite total changes: {conn.total_changes}")
    emit(f"Log file: {log_filename}")

finally:
    conn.close()
    log_file.close()