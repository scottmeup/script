#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

POLICY_PATH=""
CANDIDATE_PATH=""
COMMIT_MESSAGE=""
ACCEPT=false
DOCUMENTATION_VALIDATED=false
DEPLOYMENT_SUCCEEDED=false
SELF_TEST=false
TRACE_PATH=""
PROJECT_DIR=""
BACKUP_DIR=""
PRIOR_FETCH_URL=""
PRIOR_PUSH_URL=""
REMOTE_CHANGED=false
CANONICAL_INSTALLED=false
PRIOR_HANDOVER_BACKUP=""
COMMIT_CREATED=false
CREATED_COMMIT=""
GIT_BIN=""
SSH_ADD_BIN=""
SHA256_BIN=""
STAT_BIN=""
DATE_BIN=""
CP_BIN=""
MV_BIN=""
MKDIR_BIN=""
RM_BIN=""
CHOWN_BIN=""
CHMOD_BIN=""
GREP_BIN=""
AWK_BIN=""
PYTHON_BIN=""

usage() {
    printf '%s\n' "Usage: $0 --policy PATH --candidate PATH --message TEXT [--accept] [--documentation-validated] [--deployment-succeeded]"
    printf '%s\n' "       $0 --self-test"
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

command_path() {
    result="$(command -v "$1" 2>/dev/null || true)"
    [[ -n "$result" && -x "$result" ]] || fail "Required executable is unavailable: $1"
    printf '%s\n' "$result"
}

require_git_tools() {
    GIT_BIN="$(command_path git)"
    SHA256_BIN="$(command_path sha256sum)"
    STAT_BIN="$(command_path stat)"
    DATE_BIN="$(command_path date)"
    CP_BIN="$(command_path cp)"
    MV_BIN="$(command_path mv)"
    MKDIR_BIN="$(command_path mkdir)"
    RM_BIN="$(command_path rm)"
    CHOWN_BIN="$(command_path chown)"
    CHMOD_BIN="$(command_path chmod)"
    GREP_BIN="$(command_path grep)"
    AWK_BIN="$(command_path awk)"
    if [[ "$GIT_AUTH_METHOD" == ssh-agent ]]; then
        SSH_ADD_BIN="$(command_path ssh-add)"
    fi
}

normalize_size() {
    "$PYTHON_BIN" - "$1" <<'PY'
import re
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
text = text.replace("\r\n", "\n").replace("\r", "\n")
text = re.sub(r"<br\s*/?>", "\n", text, flags=re.I)
text = re.sub(r"\s+", " ", text).strip()
print(len(text))
PY
}

section_concepts() {
    "$PYTHON_BIN" - "$1" <<'PY'
import re
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
concepts = []
for line in text.replace("\r\n", "\n").replace("\r", "\n").splitlines():
    value = line.strip()
    match = re.match(r"^(?:SECTION|SUBSECTION|ITEM-ID|STATUS|NEXT-ACTION)\s*:\s*(.+)$", value, re.I)
    if match:
        normalized = re.sub(r"\s+", " ", match.group(1)).strip().casefold()
        if normalized and normalized not in concepts:
            concepts.append(normalized)
for concept in concepts:
    print(concept)
PY
}

validate_candidate() {
    [[ -f "$CANDIDATE_PATH" && -r "$CANDIDATE_PATH" ]] || fail "Candidate is missing or unreadable: $CANDIDATE_PATH"
    [[ -s "$CANDIDATE_PATH" ]] || fail "Candidate is empty"
    grep -Fq "$POLICY_PATH" "$CANDIDATE_PATH" || fail "Candidate does not identify the exact policy path"
    grep -Eiq 'read.{0,120}handover-policy\.env' "$CANDIDATE_PATH" || fail "Candidate does not instruct subsequent work to read the policy"
    case "$HANDOVER_FORMAT" in
        plain-text)
            [[ "$HANDOVER_CANONICAL_PATH" == *.txt ]] || fail "Plain-text handover path must end in .txt"
            ;;
        markdown)
            [[ "$HANDOVER_CANONICAL_PATH" == *.md ]] || fail "Markdown handover path must end in .md"
            ;;
        *)
            fail "Unsupported HANDOVER_FORMAT: $HANDOVER_FORMAT"
            ;;
    esac
    if [[ -f "$HANDOVER_CANONICAL_PATH" ]]; then
        baseline_size="$(normalize_size "$HANDOVER_CANONICAL_PATH")"
        candidate_size="$(normalize_size "$CANDIDATE_PATH")"
        minimum_size=$((baseline_size * 85 / 100))
        [[ "$candidate_size" -ge "$minimum_size" ]] || fail "Candidate is below the 85 percent normalized-size safeguard"
        mapfile -t baseline_concepts < <(section_concepts "$HANDOVER_CANONICAL_PATH")
        mapfile -t candidate_concepts < <(section_concepts "$CANDIDATE_PATH")
        if [[ ${#baseline_concepts[@]} -gt 0 ]]; then
            matched=0
            for concept in "${baseline_concepts[@]}"; do
                for candidate_concept in "${candidate_concepts[@]}"; do
                    if [[ "$candidate_concept" == "$concept" ]]; then
                        matched=$((matched + 1))
                        break
                    fi
                done
            done
            required=$(( (${#baseline_concepts[@]} * 90 + 99) / 100 ))
            [[ "$matched" -ge "$required" ]] || fail "Candidate is below the 90 percent section-concept safeguard"
        fi
    fi
}

validate_authority() {
    case "$HANDOVER_AUTHORITY_MODE" in
        explicit-user-acceptance)
            [[ "$ACCEPT" == true ]] || fail "--accept is required by HANDOVER_AUTHORITY_MODE"
            ;;
        successful-documentation-validation)
            [[ "$DOCUMENTATION_VALIDATED" == true ]] || fail "--documentation-validated is required by HANDOVER_AUTHORITY_MODE"
            ;;
        successful-deployment)
            [[ "$DEPLOYMENT_SUCCEEDED" == true ]] || fail "--deployment-succeeded is required by HANDOVER_AUTHORITY_MODE"
            ;;
        *)
            fail "Unsupported HANDOVER_AUTHORITY_MODE: $HANDOVER_AUTHORITY_MODE"
            ;;
    esac
}

validate_policy() {
    required=(
        HANDOVER_POLICY_VERSION
        HANDOVER_HISTORY_MODE
        HANDOVER_CANONICAL_PATH
        HANDOVER_FORMAT
        HANDOVER_HISTORY_DIR
        HANDOVER_AUTHORITY_MODE
        GIT_REPOSITORY_PATH
        GIT_REMOTE_NAME
        GIT_REMOTE_URL
        GIT_BRANCH
        GIT_PUSH_AFTER_ACCEPTED_UPDATE
        GIT_AUTH_METHOD
        REMOTE_PUSH_FAILURE_MODE
    )
    for key in "${required[@]}"; do
        [[ -v "$key" ]] || fail "Required policy key is missing: $key"
    done
    [[ "$HANDOVER_POLICY_VERSION" == 1 ]] || fail "Unsupported HANDOVER_POLICY_VERSION: $HANDOVER_POLICY_VERSION"
    case "$HANDOVER_HISTORY_MODE" in
        git-local|git-remote|timestamped-backups) ;;
        *) fail "Unsupported HANDOVER_HISTORY_MODE: $HANDOVER_HISTORY_MODE" ;;
    esac
    case "$GIT_PUSH_AFTER_ACCEPTED_UPDATE" in
        true|false) ;;
        *) fail "GIT_PUSH_AFTER_ACCEPTED_UPDATE must be true or false" ;;
    esac
    case "$GIT_AUTH_METHOD" in
        ssh-agent|ssh-key-file|https-credential-helper|none) ;;
        *) fail "Unsupported GIT_AUTH_METHOD: $GIT_AUTH_METHOD" ;;
    esac
    case "$REMOTE_PUSH_FAILURE_MODE" in
        preserve-local-mark-remote-unresolved|fail-keep-local) ;;
        *) fail "Unsupported REMOTE_PUSH_FAILURE_MODE: $REMOTE_PUSH_FAILURE_MODE" ;;
    esac
    PROJECT_DIR="$(dirname -- "$POLICY_PATH")"
    [[ "$(readlink -m "$HANDOVER_CANONICAL_PATH")" == "$PROJECT_DIR"/* ]] || fail "Canonical handover must be inside the policy directory"
    if [[ "$HANDOVER_HISTORY_MODE" == timestamped-backups ]]; then
        [[ -n "$HANDOVER_HISTORY_DIR" ]] || fail "HANDOVER_HISTORY_DIR is required for timestamped-backups"
    else
        [[ -n "$GIT_REPOSITORY_PATH" ]] || fail "GIT_REPOSITORY_PATH is required for Git history modes"
        [[ -n "$GIT_BRANCH" ]] || fail "GIT_BRANCH is required for Git history modes"
        repository_root="$(readlink -m "$GIT_REPOSITORY_PATH")"
        [[ "$PROJECT_DIR" == "$repository_root" || "$PROJECT_DIR" == "$repository_root"/* ]] || fail "Policy directory must be inside GIT_REPOSITORY_PATH"
        PROJECT_RELATIVE="${PROJECT_DIR#"$repository_root"/}"
        if [[ "$PROJECT_DIR" == "$repository_root" ]]; then
            PROJECT_RELATIVE="."
        fi
    fi
    if [[ "$HANDOVER_HISTORY_MODE" == git-remote ]]; then
        [[ -n "$GIT_REMOTE_NAME" && -n "$GIT_REMOTE_URL" ]] || fail "Remote name and URL are required for git-remote"
    fi
}

load_policy() {
    declare -A seen=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" ]] || continue
        [[ "$line" != \#* ]] || continue
        [[ "$line" == *=* ]] || fail "Malformed policy line"
        key="${line%%=*}"
        value="${line#*=}"
        [[ "$key" =~ ^[A-Z0-9_]+$ ]] || fail "Malformed policy key: $key"
        [[ -z "${seen[$key]:-}" ]] || fail "Duplicate policy key: $key"
        seen[$key]=1
        printf -v "$key" '%s' "$value"
        export "$key"
    done < "$POLICY_PATH"
}

validate_git_repository() {
    "$GIT_BIN" -C "$GIT_REPOSITORY_PATH" rev-parse --is-inside-work-tree | "$GREP_BIN" -qx true || fail "Not a Git working tree"
    [[ "$("$GIT_BIN" -C "$GIT_REPOSITORY_PATH" rev-parse --show-toplevel)" == "$(readlink -m "$GIT_REPOSITORY_PATH")" ]] || fail "Repository root mismatch"
    [[ "$("$GIT_BIN" -C "$GIT_REPOSITORY_PATH" branch --show-current)" == "$GIT_BRANCH" ]] || fail "Current branch does not match GIT_BRANCH"
    preexisting_staged="$("$GIT_BIN" -C "$GIT_REPOSITORY_PATH" diff --cached --name-only)"
    [[ -z "$preexisting_staged" ]] || fail "Pre-existing staged changes must be committed or unstaged first"
    if [[ "$PROJECT_RELATIVE" != . ]]; then
        unrelated="$("$GIT_BIN" -C "$GIT_REPOSITORY_PATH" status --porcelain --untracked-files=all | "$AWK_BIN" -v prefix="$PROJECT_RELATIVE/" 'substr($0,4,length(prefix)) != prefix {print}')"
        [[ -z "$unrelated" ]] || fail "Unrelated repository changes exist outside the project directory"
    fi
}

validate_authentication() {
    case "$GIT_AUTH_METHOD" in
        ssh-agent)
            [[ -n "$SSH_ADD_BIN" ]] || fail "ssh-add is unavailable"
            [[ -n "${SSH_AUTH_SOCK:-}" && -S "$SSH_AUTH_SOCK" ]] || fail "SSH agent socket is unavailable"
            "$SSH_ADD_BIN" -l >/dev/null 2>&1 || fail "SSH agent has no usable identities"
            ;;
        ssh-key-file)
            [[ -n "${GIT_SSH_COMMAND:-}" ]] || fail "GIT_SSH_COMMAND must identify the externally managed SSH key"
            ;;
        https-credential-helper)
            [[ -n "$("$GIT_BIN" -C "$GIT_REPOSITORY_PATH" config --get credential.helper || true)" ]] || fail "No Git credential helper is configured"
            ;;
        none) ;;
    esac
}

configure_and_validate_remote() {
    "$GIT_BIN" -C "$GIT_REPOSITORY_PATH" remote get-url "$GIT_REMOTE_NAME" >/dev/null 2>&1 || fail "Configured remote does not exist"
    PRIOR_FETCH_URL="$("$GIT_BIN" -C "$GIT_REPOSITORY_PATH" remote get-url "$GIT_REMOTE_NAME")"
    PRIOR_PUSH_URL="$("$GIT_BIN" -C "$GIT_REPOSITORY_PATH" remote get-url --push "$GIT_REMOTE_NAME")"
    if [[ "$PRIOR_FETCH_URL" != "$GIT_REMOTE_URL" || "$PRIOR_PUSH_URL" != "$GIT_REMOTE_URL" ]]; then
        "$GIT_BIN" -C "$GIT_REPOSITORY_PATH" remote set-url "$GIT_REMOTE_NAME" "$GIT_REMOTE_URL"
        "$GIT_BIN" -C "$GIT_REPOSITORY_PATH" remote set-url --push "$GIT_REMOTE_NAME" "$GIT_REMOTE_URL"
        REMOTE_CHANGED=true
    fi
    [[ "$("$GIT_BIN" -C "$GIT_REPOSITORY_PATH" remote get-url "$GIT_REMOTE_NAME")" == "$GIT_REMOTE_URL" ]] || fail "Fetch URL validation failed"
    [[ "$("$GIT_BIN" -C "$GIT_REPOSITORY_PATH" remote get-url --push "$GIT_REMOTE_NAME")" == "$GIT_REMOTE_URL" ]] || fail "Push URL validation failed"
    validate_authentication
    "$GIT_BIN" -C "$GIT_REPOSITORY_PATH" ls-remote --exit-code "$GIT_REMOTE_NAME" "refs/heads/$GIT_BRANCH" >/dev/null || fail "Remote authentication, reachability, or branch validation failed"
    "$GIT_BIN" -C "$GIT_REPOSITORY_PATH" fetch --prune "$GIT_REMOTE_NAME" "$GIT_BRANCH"
    "$GIT_BIN" -C "$GIT_REPOSITORY_PATH" show-ref --verify --quiet "refs/remotes/$GIT_REMOTE_NAME/$GIT_BRANCH" || fail "Remote branch is unavailable after fetch"
    local_head="$("$GIT_BIN" -C "$GIT_REPOSITORY_PATH" rev-parse "$GIT_BRANCH")"
    remote_head="$("$GIT_BIN" -C "$GIT_REPOSITORY_PATH" rev-parse "$GIT_REMOTE_NAME/$GIT_BRANCH")"
    merge_base="$("$GIT_BIN" -C "$GIT_REPOSITORY_PATH" merge-base "$GIT_BRANCH" "$GIT_REMOTE_NAME/$GIT_BRANCH")"
    [[ "$local_head" == "$remote_head" || "$merge_base" == "$remote_head" ]] || fail "Local branch is behind or diverged from the remote branch"
}

create_backup() {
    if [[ "$HANDOVER_HISTORY_MODE" == timestamped-backups ]]; then
        BACKUP_DIR="$(readlink -m "$HANDOVER_HISTORY_DIR")/$TIMESTAMP"
    else
        BACKUP_DIR="$PROJECT_DIR/.handover-backups/$TIMESTAMP"
    fi
    "$MKDIR_BIN" -p "$BACKUP_DIR"
    if [[ -f "$HANDOVER_CANONICAL_PATH" ]]; then
        PRIOR_HANDOVER_BACKUP="$BACKUP_DIR/$(basename -- "$HANDOVER_CANONICAL_PATH")"
        "$CP_BIN" -p "$HANDOVER_CANONICAL_PATH" "$PRIOR_HANDOVER_BACKUP"
    fi
    "$CP_BIN" -p "$POLICY_PATH" "$BACKUP_DIR/handover-policy.env"
}

install_candidate() {
    temporary="$PROJECT_DIR/.handover-candidate.$$"
    "$CP_BIN" "$CANDIDATE_PATH" "$temporary"
    "$MV_BIN" -f "$temporary" "$HANDOVER_CANONICAL_PATH"
    CANONICAL_INSTALLED=true
    candidate_sha="$("$SHA256_BIN" "$CANDIDATE_PATH" | "$AWK_BIN" '{print $1}')"
    installed_sha="$("$SHA256_BIN" "$HANDOVER_CANONICAL_PATH" | "$AWK_BIN" '{print $1}')"
    [[ "$candidate_sha" == "$installed_sha" ]] || fail "Installed handover differs from the candidate"
}

commit_project() {
    trace_relative="${TRACE_PATH#"$(readlink -m "$GIT_REPOSITORY_PATH")"/}"
    backup_relative="${BACKUP_DIR#"$(readlink -m "$GIT_REPOSITORY_PATH")"/}"
    candidate_relative="${CANDIDATE_PATH#"$(readlink -m "$GIT_REPOSITORY_PATH")"/}"
    candidate_exclusion=()
    if [[ "$candidate_relative" != "$CANDIDATE_PATH" ]]; then
        candidate_exclusion=(":(exclude)$candidate_relative")
    fi
    if [[ "$PROJECT_RELATIVE" == . ]]; then
        "$GIT_BIN" -C "$GIT_REPOSITORY_PATH" add --all -- . ":(exclude)$trace_relative" ":(exclude)$backup_relative/**" "${candidate_exclusion[@]}"
    else
        "$GIT_BIN" -C "$GIT_REPOSITORY_PATH" add -- "$PROJECT_RELATIVE" ":(exclude)$trace_relative" ":(exclude)$backup_relative/**" "${candidate_exclusion[@]}"
    fi
    "$GIT_BIN" -C "$GIT_REPOSITORY_PATH" diff --cached --quiet && fail "No accepted project changes are staged"
    if [[ "$PROJECT_RELATIVE" != . ]]; then
        "$GIT_BIN" -C "$GIT_REPOSITORY_PATH" diff --cached --name-only | "$AWK_BIN" -v prefix="$PROJECT_RELATIVE/" 'index($0,prefix) != 1 {exit 1}' || fail "Staged changes escaped the project directory"
    fi
    "$GIT_BIN" -C "$GIT_REPOSITORY_PATH" commit -m "$COMMIT_MESSAGE"
    CREATED_COMMIT="$("$GIT_BIN" -C "$GIT_REPOSITORY_PATH" rev-parse HEAD)"
    COMMIT_CREATED=true
}

push_and_verify() {
    [[ "$GIT_PUSH_AFTER_ACCEPTED_UPDATE" == true ]] || return 0
    if ! "$GIT_BIN" -C "$GIT_REPOSITORY_PATH" push "$GIT_REMOTE_NAME" "$GIT_BRANCH"; then
        printf 'REMOTE_SYNC_UNRESOLVED commit=%s\n' "$CREATED_COMMIT" >&2
        case "$REMOTE_PUSH_FAILURE_MODE" in
            preserve-local-mark-remote-unresolved|fail-keep-local)
                REMOTE_CHANGED=false
                exit 2
                ;;
        esac
    fi
    "$GIT_BIN" -C "$GIT_REPOSITORY_PATH" fetch "$GIT_REMOTE_NAME" "$GIT_BRANCH"
    verified="$("$GIT_BIN" -C "$GIT_REPOSITORY_PATH" rev-parse "$GIT_REMOTE_NAME/$GIT_BRANCH")"
    [[ "$verified" == "$CREATED_COMMIT" ]] || fail "Remote does not contain the exact local commit"
}

finish() {
    status=$?
    set +e
    if [[ $status -ne 0 ]]; then
        if [[ "$CANONICAL_INSTALLED" == true ]]; then
            if [[ -n "$PRIOR_HANDOVER_BACKUP" && -f "$PRIOR_HANDOVER_BACKUP" ]]; then
                "$CP_BIN" -p "$PRIOR_HANDOVER_BACKUP" "$HANDOVER_CANONICAL_PATH" 2>/dev/null || true
            else
                "$RM_BIN" -f "$HANDOVER_CANONICAL_PATH" 2>/dev/null || true
            fi
        fi
        if [[ "$REMOTE_CHANGED" == true && -n "$GIT_BIN" && -n "$PRIOR_FETCH_URL" && -n "$PRIOR_PUSH_URL" ]]; then
            "$GIT_BIN" -C "$GIT_REPOSITORY_PATH" remote set-url "$GIT_REMOTE_NAME" "$PRIOR_FETCH_URL" 2>/dev/null || true
            "$GIT_BIN" -C "$GIT_REPOSITORY_PATH" remote set-url --push "$GIT_REMOTE_NAME" "$PRIOR_PUSH_URL" 2>/dev/null || true
        fi
    fi
    exit "$status"
}

self_test() {
    root="$(mktemp -d)"
    trap 'rm -rf "$root"' RETURN
    policy="$root/handover-policy.env"
    canonical="$root/PROJECT-HANDOVER.txt"
    candidate="$root/candidate.txt"
    printf '%s\n' "SECTION: ALPHA" "Read $policy before subsequent work" > "$canonical"
    printf '%s\n' "SECTION: ALPHA" "SECTION: BETA" "Read $policy before subsequent work" > "$candidate"
    POLICY_PATH="$policy"
    CANDIDATE_PATH="$candidate"
    PROJECT_DIR="$root"
    HANDOVER_FORMAT=plain-text
    HANDOVER_CANONICAL_PATH="$canonical"
    PYTHON_BIN="$(command -v python3)"
    validate_candidate
    printf '%s\n' "SECTION: BETA" "Read $policy before subsequent work" > "$candidate"
    if (validate_candidate) >/dev/null 2>&1; then
        fail "Negative self-test accepted a truncated candidate"
    fi
    printf 'SELF_TEST=PASS\n'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --policy)
            [[ $# -ge 2 ]] || fail "--policy requires a value"
            POLICY_PATH="$(readlink -m "$2")"
            shift 2
            ;;
        --candidate)
            [[ $# -ge 2 ]] || fail "--candidate requires a value"
            CANDIDATE_PATH="$(readlink -m "$2")"
            shift 2
            ;;
        --message)
            [[ $# -ge 2 ]] || fail "--message requires a value"
            COMMIT_MESSAGE="$2"
            shift 2
            ;;
        --accept)
            ACCEPT=true
            shift
            ;;
        --documentation-validated)
            DOCUMENTATION_VALIDATED=true
            shift
            ;;
        --deployment-succeeded)
            DEPLOYMENT_SUCCEEDED=true
            shift
            ;;
        --self-test)
            SELF_TEST=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

PYTHON_BIN="$(command_path python3)"

if [[ "$SELF_TEST" == true ]]; then
    self_test
    exit 0
fi

[[ -n "$POLICY_PATH" ]] || fail "--policy is required"
[[ -n "$CANDIDATE_PATH" ]] || fail "--candidate is required"
[[ -n "$COMMIT_MESSAGE" ]] || fail "--message is required"
[[ -f "$POLICY_PATH" && -r "$POLICY_PATH" ]] || fail "Policy is missing or unreadable: $POLICY_PATH"

PROJECT_DIR="$(dirname -- "$POLICY_PATH")"
TRACE_PATH="$PROJECT_DIR/handover-update.trace"
exec 9>>"$TRACE_PATH"
export BASH_XTRACEFD=9
export PS4='+ $(date -Ins) ${FUNCNAME[0]:-main}: '
set -x
trap finish EXIT INT TERM HUP

load_policy
validate_policy
validate_authority
validate_candidate

SHA256_BIN="$(command_path sha256sum)"
STAT_BIN="$(command_path stat)"
DATE_BIN="$(command_path date)"
CP_BIN="$(command_path cp)"
MV_BIN="$(command_path mv)"
MKDIR_BIN="$(command_path mkdir)"
RM_BIN="$(command_path rm)"
CHOWN_BIN="$(command_path chown)"
CHMOD_BIN="$(command_path chmod)"
AWK_BIN="$(command_path awk)"
TIMESTAMP="$("$DATE_BIN" -u +%Y%m%dT%H%M%SZ)"

case "$HANDOVER_HISTORY_MODE" in
    timestamped-backups)
        create_backup
        install_candidate
        ;;
    git-local)
        require_git_tools
        validate_git_repository
        create_backup
        install_candidate
        commit_project
        ;;
    git-remote)
        require_git_tools
        validate_git_repository
        configure_and_validate_remote
        create_backup
        install_candidate
        commit_project
        push_and_verify
        ;;
esac

CANONICAL_INSTALLED=false
REMOTE_CHANGED=false
printf 'HANDOVER_PATH=%s\n' "$HANDOVER_CANONICAL_PATH"
printf 'BACKUP_DIR=%s\n' "$BACKUP_DIR"
printf 'TRACE_FILE=%s\n' "$TRACE_PATH"
if [[ "$COMMIT_CREATED" == true ]]; then
    printf 'LOCAL_COMMIT=%s\n' "$CREATED_COMMIT"
fi
