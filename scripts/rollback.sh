#!/usr/bin/env bash
# ==============================================================================
# GBA Furniture — Safe Manual Rollback Script
#
# Usage:
#   ./scripts/rollback.sh <RELEASE_ID> [VERIFY_URL]
#
# Process:
#   1. Strictly Validates Release ID, URL & Canonical Realpath Guards
#      (Error-checked symlink scan; allows overrides ONLY in TEST_MODE=1)
#   2. Acquires Shared Host-Side OS-Held Lock (/home/alibhatt/.gba-deploy.lock)
#      via nonblocking flock on a canonical regular file with stable fd &
#      separate atomic owner metadata
#   3. Parses Pre-Cutover Manifest as Strict JSON (Rejecting Malformed JSON &
#      Duplicate Keys) and Validates release_id, docroot, Exact Backup Paths,
#      DB-Required Flag, SHA256 Hashes, and DB Identities Before Any Mutation
#   4. Creates and Verifies an Exclusive Pre-Rollback Snapshot/Recovery Tree
#      (and Pre-Rollback Database Snapshot if DB Exists) Before Mutating Docroot
#   5. Atomically Restores Previous Docroot Files & Database with Trap-Driven
#      Recovery Covering Every Partial rsync/chmod/DB/file/health/manifest
#      Failure (Restores Previously Live Files and Pre-Rollback DB State;
#      Preserves Recovery Evidence if Restoration Fails)
#   6. Enforces Post-Rollback HTTP 200 and Fatal-Error/Content Health Checks on
#      EVERY Rollback Endpoint Including /index.php
#   7. Atomically Records Rollback Audit Manifest via Same-Directory Temp File,
#      fsync, Strict JSON Validation & Rename (Zero Credentials Logged)
# ==============================================================================

set -euo pipefail

export COPYFILE_DISABLE=1
export LC_ALL=C

if [ "${GBA_SIG_DFL_PID:-}" != "$$" ] && command -v python3 >/dev/null 2>&1; then
  if python3 -c 'import signal, sys; sys.exit(0 if any(signal.getsignal(s) == signal.SIG_IGN for s in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM)) else 1)' 2>/dev/null; then
    export GBA_SIG_DFL_PID="$$"
    exec python3 -c 'import os, signal, sys
for s in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
    signal.signal(s, signal.SIG_DFL)
os.execv(sys.argv[1], sys.argv[1:])' "$0" "$@"
  fi
fi

RELEASE_ID="${1:-}"
VERIFY_URL="${2:-https://gbafurniture.com}"

if [ -z "${RELEASE_ID}" ]; then
  echo "Usage: $0 <RELEASE_ID> [VERIFY_URL]" >&2
  exit 1
fi

if [[ ! "${RELEASE_ID}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || [[ "${RELEASE_ID}" == *".."* ]]; then
  echo "CRITICAL ERROR: Invalid RELEASE_ID '${RELEASE_ID}'. Must match ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ without '..'" >&2
  exit 1
fi

# Strip trailing slash and strictly validate VERIFY_URL
VERIFY_URL="${VERIFY_URL%/}"
if [ -z "${VERIFY_URL}" ] || [[ ! "${VERIFY_URL}" =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]{1,5})?(/[a-zA-Z0-9._/-]*)?$ ]]; then
  echo "CRITICAL ERROR: Invalid VERIFY_URL '${VERIFY_URL}'. Must match ^https?://[a-zA-Z0-9.-]+(:[0-9]{1,5})?(/[a-zA-Z0-9._/-]*)?$" >&2
  exit 1
fi

# ==============================================================================
# 1. Canonical Realpath Guards & Error-Checked Symlink Scan
# ==============================================================================
EXPECTED_DOCROOT="/home/alibhatt/web/gbafurniture.com"
EXPECTED_BACKUP_ROOT="/home/alibhatt/backups/gbafurniture"
EXPECTED_LOCK_DIR="/home/alibhatt/.gba-deploy.lock"

if [ "${TEST_MODE:-0}" = "1" ]; then
  RAW_DOCROOT="${GBA_DOCROOT_OVERRIDE:-${EXPECTED_DOCROOT}}"
  RAW_BACKUP_ROOT="${GBA_BACKUP_OVERRIDE:-${EXPECTED_BACKUP_ROOT}}"
  RAW_LOCK_DIR="${GBA_LOCK_OVERRIDE:-$(dirname "${RAW_DOCROOT%/}")/.gba-deploy.lock}"
else
  if [ -n "${GBA_DOCROOT_OVERRIDE:-}" ] || [ -n "${GBA_BACKUP_OVERRIDE:-}" ] || [ -n "${GBA_RELEASES_OVERRIDE:-}" ] || [ -n "${GBA_SANDBOX_OVERRIDE:-}" ] || [ -n "${GBA_LOCK_OVERRIDE:-}" ] || [ -n "${GBA_STAGE_ROOT_OVERRIDE:-}" ]; then
    echo "CRITICAL ERROR: Path overrides (GBA_*_OVERRIDE) are strictly forbidden when TEST_MODE != 1!" >&2
    exit 1
  fi
  RAW_DOCROOT="${EXPECTED_DOCROOT}"
  RAW_BACKUP_ROOT="${EXPECTED_BACKUP_ROOT}"
  RAW_LOCK_DIR="${EXPECTED_LOCK_DIR}"
fi

assert_no_symlinks_in_tree() {
  local target_dir="$1"
  local label="${2:-directory}"
  if [ -L "${target_dir}" ]; then
    echo "CRITICAL ERROR: ${label} '${target_dir}' is a symlink!" >&2
    return 1
  fi
  if [ ! -d "${target_dir}" ]; then
    echo "CRITICAL ERROR: ${label} '${target_dir}' is not a valid directory!" >&2
    return 1
  fi
  local find_out=""
  local find_rc=0
  find_out="$(find "${target_dir}" -type l -print 2>&1)" || find_rc=$?
  if [ "${find_rc}" -ne 0 ]; then
    echo "CRITICAL ERROR: Symlink scan failed (exit ${find_rc}) inside ${label} '${target_dir}': ${find_out}" >&2
    return 1
  fi
  if [ -n "${find_out}" ]; then
    local first_link="${find_out%%$'\n'*}"
    echo "CRITICAL ERROR: Symlink detected inside ${label} '${target_dir}': ${first_link}" >&2
    return 1
  fi
  return 0
}

guard_and_canonicalize_dir() {
  local raw_path="$1"
  local label="$2"
  local create_if_missing="${3:-0}"
  local scan_tree="${4:-1}"

  if [ -z "${raw_path}" ] || [[ "${raw_path}" != /* ]]; then
    echo "CRITICAL ERROR: ${label} '${raw_path}' must be an absolute path." >&2
    return 1
  fi

  if [ "${raw_path}" != "/" ]; then
    raw_path="${raw_path%/}"
  fi

  if [[ "${raw_path}" =~ (^|/)\.\.?(/|$) ]] || [[ "${raw_path}" == *"//"* ]]; then
    echo "CRITICAL ERROR: ${label} '${raw_path}' contains non-canonical dot or empty segments." >&2
    return 1
  fi

  if [ -L "${raw_path}" ]; then
    echo "CRITICAL ERROR: ${label} '${raw_path}' is a symlink! Symlinks are strictly rejected." >&2
    return 1
  fi

  if [ -e "${raw_path}" ] && [ ! -d "${raw_path}" ]; then
    echo "CRITICAL ERROR: ${label} '${raw_path}' exists and is not a directory!" >&2
    return 1
  fi

  local current=""
  local IFS='/'
  read -r -a parts <<< "${raw_path}"
  for part in "${parts[@]}"; do
    if [ -z "${part}" ]; then
      continue
    fi
    current="${current}/${part}"
    if [ -L "${current}" ]; then
      if [ "${TEST_MODE:-0}" = "1" ] && [ "$(uname -s)" = "Darwin" ] && [[ "${current}" =~ ^/(var|tmp|etc)$ ]]; then
        continue
      fi
      echo "CRITICAL ERROR: ${label} ancestor '${current}' is a symlink! Symlinks are strictly rejected." >&2
      return 1
    fi
    if [ -e "${current}" ] && [ ! -d "${current}" ]; then
      echo "CRITICAL ERROR: ${label} ancestor '${current}' exists and is not a directory!" >&2
      return 1
    fi
  done

  local canonical
  if [ -d "${raw_path}" ]; then
    canonical="$(cd -P -- "${raw_path}" && pwd -P)" || return 1
  else
    if [ "${create_if_missing}" != "1" ]; then
      echo "CRITICAL ERROR: Required directory for ${label} does not exist: '${raw_path}'" >&2
      return 1
    fi
    local ancestor="${raw_path}"
    local suffix=""
    while [ ! -d "${ancestor}" ]; do
      suffix="/$(basename "${ancestor}")${suffix}"
      ancestor="$(dirname "${ancestor}")"
    done
    local canon_ancestor
    canon_ancestor="$(cd -P -- "${ancestor}" && pwd -P)" || return 1
    canonical="${canon_ancestor%/}${suffix}"
  fi

  if [ "${TEST_MODE:-0}" != "1" ]; then
    if [ "${canonical}" != "${raw_path}" ]; then
      echo "CRITICAL ERROR: Canonical realpath '${canonical}' does not match '${raw_path}' for ${label}!" >&2
      return 1
    fi
  else
    local expected_test_canon="${raw_path}"
    if [ "$(uname -s)" = "Darwin" ] && [[ "${raw_path}" =~ ^/(var|tmp|etc)(/|$) ]]; then
      expected_test_canon="/private${raw_path}"
    fi
    if [ "${canonical}" != "${expected_test_canon}" ]; then
      echo "CRITICAL ERROR: Canonical realpath '${canonical}' does not match '${expected_test_canon}' for ${label} (symlink detected)!" >&2
      return 1
    fi
  fi

  if [ -d "${canonical}" ] && [ "${scan_tree}" = "1" ]; then
    assert_no_symlinks_in_tree "${canonical}" "${label}" || return 1
  fi

  printf '%s\n' "${canonical}"
}

paths_overlap() {
  local p1="$1"
  local p2="$2"
  if [ "${p1}" = "${p2}" ] || [[ "${p1}" == "${p2}/"* ]] || [[ "${p2}" == "${p1}/"* ]]; then
    return 0
  fi
  return 1
}

validate_sql_identifier() {
  local ident="$1"
  local label="${2:-SQL identifier}"
  if [ -z "${ident}" ] || [[ ! "${ident}" =~ ^[a-zA-Z0-9_$]{1,64}$ ]]; then
    echo "CRITICAL ERROR: Invalid ${label} '${ident}'. Must strictly match ^[a-zA-Z0-9_\$]{1,64}$" >&2
    return 1
  fi
}

quote_sql_ident() {
  local ident="$1"
  local label="${2:-SQL identifier}"
  validate_sql_identifier "${ident}" "${label}" || return 1
  local escaped="${ident//\`/\`\`}"
  printf '`%s`' "${escaped}"
}

compute_sha256() {
  local target="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${target}" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${target}" | awk '{print $1}'
  else
    openssl dgst -sha256 "${target}" | awk '{print $NF}'
  fi
}

compute_tree_digest() {
  local target_dir="$1"
  python3 - "${target_dir}" <<'PYEOF'
import hashlib, os, sys
root = sys.argv[1]
if not os.path.isdir(root) or os.path.islink(root):
    print("INVALID")
    sys.exit(0)
entries = []
for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
    dirnames.sort()
    filenames.sort()
    rel_dir = os.path.relpath(dirpath, root).replace(os.sep, "/")
    if rel_dir != ".":
        entries.append(f"D:{rel_dir}")
    for fn in filenames:
        full = os.path.join(dirpath, fn)
        rel = os.path.relpath(full, root).replace(os.sep, "/")
        if os.path.islink(full):
            entries.append(f"L:{rel}:{os.readlink(full)}")
        elif os.path.isfile(full):
            h = hashlib.sha256()
            with open(full, "rb") as f:
                for chunk in iter(lambda: f.read(65536), b""):
                    h.update(chunk)
            entries.append(f"F:{rel}:{h.hexdigest()}")
        else:
            entries.append(f"O:{rel}")
digest = hashlib.sha256("\n".join(entries).encode("utf-8")).hexdigest()
print(f"{digest}:{len(entries)}")
PYEOF
}

write_json_manifest_atomically() {
  local target_path="$1"
  local is_final="${2:-0}"
  local raw_json=""
  raw_json="$(cat)"
  python3 - "${target_path}" "${is_final}" "${TEST_FAIL_FINAL_MANIFEST_WRITE:-0}" "${raw_json}" <<'PYEOF'
import json, os, sys, tempfile

target_path, is_final_str, fail_final_str, raw_input = sys.argv[1:5]
is_final = is_final_str == "1"
fail_final = fail_final_str == "1"

if os.path.islink(target_path):
    sys.stderr.write(f"CRITICAL ERROR: Target manifest '{target_path}' is a symlink!\n")
    sys.exit(1)

parent_dir = os.path.dirname(target_path)
if not os.path.isdir(parent_dir) or os.path.islink(parent_dir):
    sys.stderr.write(f"CRITICAL ERROR: Manifest parent directory '{parent_dir}' is invalid or a symlink!\n")
    sys.exit(1)

def reject_duplicates(pairs):
    obj = {}
    for k, v in pairs:
        if k in obj:
            raise ValueError(f"Duplicate JSON key '{k}'")
        obj[k] = v
    return obj

def reject_constants(val):
    raise ValueError(f"Invalid JSON constant '{val}'")

try:
    parsed = json.loads(raw_input, object_pairs_hook=reject_duplicates, parse_constant=reject_constants)
except Exception as exc:
    sys.stderr.write(f"CRITICAL ERROR: Candidate manifest content is not valid strict JSON: {exc}\n")
    sys.exit(1)

if not isinstance(parsed, dict):
    sys.stderr.write("CRITICAL ERROR: Candidate manifest root must be a JSON object!\n")
    sys.exit(1)

formatted = (json.dumps(parsed, indent=2) + "\n").encode("utf-8")

fd, tmp_path = tempfile.mkstemp(prefix="." + os.path.basename(target_path) + ".tmp.", dir=parent_dir)
try:
    os.fchmod(fd, 0o600)
    os.write(fd, formatted)
    os.fsync(fd)
    os.close(fd)
    fd = -1

    if is_final and fail_final:
        raise RuntimeError("Simulated final manifest write failure before atomic replace")

    with open(tmp_path, "r", encoding="utf-8") as vf:
        verified = json.loads(vf.read(), object_pairs_hook=reject_duplicates, parse_constant=reject_constants)
    if not isinstance(verified, dict) or verified != parsed:
        raise ValueError("On-disk temporary manifest verification mismatch")

    os.replace(tmp_path, target_path)
    try:
        dir_fd = os.open(parent_dir, os.O_RDONLY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    except Exception:
        pass
except Exception as exc:
    if fd >= 0:
        try:
            os.close(fd)
        except Exception:
            pass
    try:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
    except Exception:
        pass
    sys.stderr.write(f"CRITICAL ERROR: Atomic manifest write failed for '{target_path}': {exc}\n")
    sys.exit(1)
PYEOF
}

DOCROOT="$(guard_and_canonicalize_dir "${RAW_DOCROOT}" "DOCROOT" "1")"
BACKUP_ROOT="$(guard_and_canonicalize_dir "${RAW_BACKUP_ROOT}" "BACKUP_ROOT" "0")"
LOCK_PARENT="$(guard_and_canonicalize_dir "$(dirname "${RAW_LOCK_DIR%/}")" "LOCK_PARENT" "1" "0")"
LOCK_DIR="${LOCK_PARENT}/$(basename "${RAW_LOCK_DIR%/}")"
LOCK_FILE="${LOCK_DIR}"
LOCK_META_FILE="${LOCK_FILE}.meta"

if [ "${TEST_MODE:-0}" != "1" ]; then
  if [ "${DOCROOT}" != "${EXPECTED_DOCROOT}" ] || [ "${BACKUP_ROOT}" != "${EXPECTED_BACKUP_ROOT}" ] || [ "${LOCK_DIR}" != "${EXPECTED_LOCK_DIR}" ]; then
    echo "CRITICAL ERROR: Canonical path guard failed! DOCROOT='${DOCROOT}', BACKUP_ROOT='${BACKUP_ROOT}'" >&2
    exit 1
  fi
fi

if paths_overlap "${DOCROOT}" "${BACKUP_ROOT}"; then
  echo "CRITICAL ERROR: BACKUP_ROOT '${BACKUP_ROOT}' cannot overlap with DOCROOT '${DOCROOT}'!" >&2
  exit 1
fi

mkdir -p -- "${DOCROOT}"

# ==============================================================================
# 2. Shared Host-Side OS-Held Lock & Pre-Rollback Recovery Trap State
# ==============================================================================
LOCK_ACQUIRED=0
LOCK_META_OWNED=0
LOCK_OWNER_TOKEN="$$:$(date -u +%s):${RANDOM}"
STAGE_DIR=""
STAGE_DIR_OWNED=0
TMP_MYCNF=""
HEALTH_TMP=""

PRE_ROLLBACK_DIGEST=""
PRE_ROLLBACK_HAD_FILES=0
PRE_ROLLBACK_RECOVERY_DIR=""
PRE_ROLLBACK_RECOVERY_DIR_OWNED=0
PRE_ROLLBACK_FILES_TAR=""
PRE_ROLLBACK_FILES_TAR_OWNED=0
PRE_ROLLBACK_RECOVERY_TREE=""
PRE_ROLLBACK_RECOVERY_TREE_OWNED=0
PRE_ROLLBACK_DB_EXISTED=0
PRE_ROLLBACK_DB_DUMP=""
PRE_ROLLBACK_DB_DUMP_OWNED=0
PRE_ROLLBACK_ORIG_MANIFEST=""
PRE_ROLLBACK_ORIG_MANIFEST_OWNED=0
PRE_ROLLBACK_ORIG_RB_MANIFEST=""
PRE_ROLLBACK_ORIG_RB_MANIFEST_OWNED=0
HAD_PRIOR_ROLLBACK_MANIFEST=0

ROLLBACK_MUTATION_STARTED=0
DOCROOT_MUTATION_STARTED=0
DB_MUTATION_STARTED=0
ROLLBACK_COMPLETED=0
RESTORE_ATTEMPTED=0
SIGNAL_EXIT_CODE=""
CLEANUP_IN_PROGRESS=0

DB_NAME=""
QUOTED_DB=""
DB_USER=""
DB_PASS=""
DB_HOST=""

handle_signal() {
  local sig_exit_code="$1"
  SIGNAL_EXIT_CODE="${sig_exit_code}"
  exit "${sig_exit_code}"
}

acquire_deploy_lock() {
  if [ -L "${LOCK_FILE}" ] || [ -L "${LOCK_META_FILE}" ]; then
    echo "CRITICAL ERROR: Lock path '${LOCK_FILE}' or metadata file is a symlink!" >&2
    return 1
  fi
  if [ -e "${LOCK_FILE}" ] && [ ! -f "${LOCK_FILE}" ]; then
    echo "CRITICAL ERROR: Lock path '${LOCK_FILE}' exists and is not a regular file!" >&2
    return 1
  fi
  if [ -e "${LOCK_META_FILE}" ] && [ ! -f "${LOCK_META_FILE}" ]; then
    echo "CRITICAL ERROR: Lock metadata path '${LOCK_META_FILE}' exists and is not a regular file!" >&2
    return 1
  fi

  if [ "${GBA_DISABLE_FLOCK:-0}" = "1" ]; then
    echo "CRITICAL ERROR: flock is unavailable/disabled; failing closed rather than reclaiming lock with a race!" >&2
    return 1
  fi

  local use_flock_cli=0
  if command -v flock >/dev/null 2>&1; then
    use_flock_cli=1
  elif [ "${GBA_REQUIRE_FLOCK_CLI:-0}" = "1" ]; then
    echo "CRITICAL ERROR: flock CLI is unavailable; failing closed rather than reclaiming lock with a race!" >&2
    return 1
  elif ! python3 -c 'import fcntl; assert hasattr(fcntl, "flock")' >/dev/null 2>&1; then
    echo "CRITICAL ERROR: flock is unavailable on this host; failing closed rather than reclaiming lock with a race!" >&2
    return 1
  fi

  # Open canonical regular lock file on stable file descriptor 9 for process lifetime
  # Scope stderr suppression strictly to the compound redirection so parent stderr is preserved
  { exec 9>>"${LOCK_FILE}"; } 2>/dev/null || {
    echo "CRITICAL ERROR: Unable to open regular lock file '${LOCK_FILE}'!" >&2
    return 1
  }

  if ! python3 - "${LOCK_FILE}" <<'PYEOF'
import os, stat, sys
lock_path = sys.argv[1]
try:
    st_path = os.lstat(lock_path)
    st_fd = os.fstat(9)
except Exception:
    sys.exit(1)
if not stat.S_ISREG(st_path.st_mode) or not stat.S_ISREG(st_fd.st_mode):
    sys.exit(1)
if (st_path.st_dev, st_path.st_ino) != (st_fd.st_dev, st_fd.st_ino):
    sys.exit(1)
os.fchmod(9, 0o600)
PYEOF
  then
    { exec 9>&-; } 2>/dev/null || true
    echo "CRITICAL ERROR: Lock file '${LOCK_FILE}' failed canonical regular-file verification!" >&2
    return 1
  fi

  local locked=0
  if [ "${use_flock_cli}" -eq 1 ]; then
    if flock -n 9 2>/dev/null; then
      locked=1
    fi
  else
    if python3 - <<'PYEOF'
import fcntl, sys
try:
    fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB)
except Exception:
    sys.exit(1)
PYEOF
    then
      locked=1
    fi
  fi

  if [ "${locked}" -ne 1 ]; then
    { exec 9>&-; } 2>/dev/null || true
    local holder_info=""
    if [ -f "${LOCK_META_FILE}" ] && [ ! -L "${LOCK_META_FILE}" ]; then
      holder_info="$(tr '\n' ' ' < "${LOCK_META_FILE}" 2>/dev/null || true)"
    fi
    echo "CRITICAL ERROR: Another deployment or rollback operation holds lock '${LOCK_FILE}' (${holder_info:-active OS flock})!" >&2
    return 1
  fi

  # Re-verify inode identity after lock acquisition
  if ! python3 - "${LOCK_FILE}" <<'PYEOF'
import os, stat, sys
lock_path = sys.argv[1]
st_path = os.lstat(lock_path)
st_fd = os.fstat(9)
if not stat.S_ISREG(st_path.st_mode) or (st_path.st_dev, st_path.st_ino) != (st_fd.st_dev, st_fd.st_ino):
    sys.exit(1)
PYEOF
  then
    { exec 9>&-; } 2>/dev/null || true
    echo "CRITICAL ERROR: Lock file '${LOCK_FILE}' inode changed during lock acquisition!" >&2
    return 1
  fi

  LOCK_ACQUIRED=1

  # Write owner metadata separately and safely via same-directory temp file + fsync + atomic rename
  if ! python3 - "${LOCK_META_FILE}" "${LOCK_OWNER_TOKEN}" "$$" "$(date -u +%s)" "rollback:${RELEASE_ID}" <<'PYEOF'
import json, os, sys, tempfile
meta_path, owner, pid_str, created_str, op = sys.argv[1:6]
if os.path.islink(meta_path):
    sys.exit(1)
parent = os.path.dirname(meta_path)
payload = (json.dumps({
    "owner": owner,
    "pid": int(pid_str),
    "created_at": int(created_str),
    "operation": op,
}, indent=2) + "\n").encode("utf-8")
fd, tmp_path = tempfile.mkstemp(prefix=".lock-meta.", dir=parent)
try:
    os.fchmod(fd, 0o600)
    os.write(fd, payload)
    os.fsync(fd)
    os.close(fd)
    fd = -1
    os.replace(tmp_path, meta_path)
except Exception:
    if fd >= 0:
        try:
            os.close(fd)
        except Exception:
            pass
    try:
        os.unlink(tmp_path)
    except Exception:
        pass
    sys.exit(1)
PYEOF
  then
    release_deploy_lock
    echo "CRITICAL ERROR: Failed to write lock owner metadata '${LOCK_META_FILE}'!" >&2
    return 1
  fi
  LOCK_META_OWNED=1
  return 0
}

release_deploy_lock() {
  if [ "${LOCK_ACQUIRED:-0}" -eq 1 ]; then
    if [ "${LOCK_META_OWNED:-0}" -eq 1 ] && [ -n "${LOCK_META_FILE:-}" ] && [ ! -L "${LOCK_META_FILE}" ] && [ -f "${LOCK_META_FILE}" ]; then
      python3 - "${LOCK_META_FILE}" "${LOCK_OWNER_TOKEN}" <<'PYEOF' 2>/dev/null || true
import json, os, sys
meta_path, expected_owner = sys.argv[1:3]
try:
    if not os.path.islink(meta_path) and os.path.isfile(meta_path):
        with open(meta_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if data.get("owner") == expected_owner:
            os.unlink(meta_path)
except Exception:
    pass
PYEOF
      LOCK_META_OWNED=0
    fi
    if command -v flock >/dev/null 2>&1; then
      flock -u 9 2>/dev/null || true
    else
      python3 -c 'import fcntl; fcntl.flock(9, fcntl.LOCK_UN)' 2>/dev/null || true
    fi
    { exec 9>&-; } 2>/dev/null || true
    LOCK_ACQUIRED=0
  fi
}

compensate_rollback_manifests() {
  python3 - \
    "${ROLLBACK_MANIFEST:-}" \
    "${MANIFEST_FILE:-}" \
    "${HAD_PRIOR_ROLLBACK_MANIFEST:-0}" \
    "${PRE_ROLLBACK_ORIG_RB_MANIFEST:-}" \
    "${PRE_ROLLBACK_ORIG_MANIFEST:-}" \
    "${TEST_MODE:-0}" \
    "${TEST_UNWRITABLE_MANIFEST_PARENT_AFTER_AUDIT_REMOVE:-0}" <<'PYEOF'
import os, sys, tempfile

(
    rb_path,
    mf_path,
    had_prior_str,
    orig_rb_path,
    orig_mf_path,
    test_mode_str,
    unwritable_after_audit_str,
) = sys.argv[1:8]
had_prior = had_prior_str == "1"
test_mode = test_mode_str == "1"
unwritable_after_audit = test_mode and (unwritable_after_audit_str == "1")

def check_parent_writable(parent_dir):
    if not parent_dir or not os.path.isdir(parent_dir) or os.path.islink(parent_dir):
        raise RuntimeError(f"Manifest parent directory '{parent_dir}' is missing or a symlink")
    st_parent = os.lstat(parent_dir)
    if (st_parent.st_mode & 0o222) == 0 or not os.access(parent_dir, os.W_OK):
        raise PermissionError(
            f"Manifest parent directory '{parent_dir}' is not writable (mode={oct(st_parent.st_mode & 0o777)})"
        )

def atomic_restore_file(src_path, dst_path, label):
    if not src_path or not dst_path:
        sys.stderr.write(f"CRITICAL ERROR: Missing source or destination path for {label} restore!\n")
        return False
    if os.path.islink(src_path) or not os.path.isfile(src_path):
        sys.stderr.write(f"CRITICAL ERROR: Snapshot source '{src_path}' for {label} is missing or a symlink!\n")
        return False
    if os.path.islink(dst_path):
        sys.stderr.write(f"CRITICAL ERROR: Destination '{dst_path}' for {label} is a symlink!\n")
        return False
    parent = os.path.dirname(dst_path)
    fd = -1
    tmp_p = ""
    try:
        check_parent_writable(parent)
        with open(src_path, "rb") as sf:
            raw = sf.read()
        if not raw:
            raise ValueError(f"Snapshot source '{src_path}' is empty")
        fd, tmp_p = tempfile.mkstemp(prefix="." + os.path.basename(dst_path) + ".restore.", dir=parent)
        os.fchmod(fd, 0o600)
        os.write(fd, raw)
        os.fsync(fd)
        os.close(fd)
        fd = -1
        os.replace(tmp_p, dst_path)
        tmp_p = ""
        try:
            dir_fd = os.open(parent, os.O_RDONLY)
            try:
                os.fsync(dir_fd)
            finally:
                os.close(dir_fd)
        except Exception:
            pass
        if os.path.islink(dst_path) or not os.path.isfile(dst_path):
            raise RuntimeError(f"Restored {label} '{dst_path}' is missing or not a regular file after replace")
        with open(dst_path, "rb") as vf:
            restored_bytes = vf.read()
        if restored_bytes != raw:
            raise ValueError(f"Restored {label} '{dst_path}' content mismatch against snapshot '{src_path}'")
        return True
    except Exception as exc:
        if fd >= 0:
            try:
                os.close(fd)
            except Exception:
                pass
        if tmp_p:
            try:
                if os.path.lexists(tmp_p):
                    os.unlink(tmp_p)
            except Exception:
                pass
        sys.stderr.write(f"CRITICAL ERROR: Failed to restore {label} '{dst_path}' from snapshot '{src_path}': {exc}\n")
        return False

audit_ok = True
if not rb_path or os.path.islink(rb_path):
    sys.stderr.write(f"CRITICAL ERROR: Rollback audit manifest path '{rb_path}' is missing or a symlink during compensation!\n")
    audit_ok = False
elif had_prior:
    if not atomic_restore_file(orig_rb_path, rb_path, "prior rollback audit manifest"):
        audit_ok = False
else:
    if os.path.lexists(rb_path):
        try:
            check_parent_writable(os.path.dirname(rb_path))
            os.unlink(rb_path)
        except Exception as exc:
            sys.stderr.write(f"CRITICAL ERROR: Failed to remove uncompleted rollback audit manifest '{rb_path}': {exc}\n")
            audit_ok = False
        if os.path.lexists(rb_path):
            sys.stderr.write(f"CRITICAL ERROR: False rollback audit manifest '{rb_path}' still exists after removal attempt!\n")
            audit_ok = False

if unwritable_after_audit and mf_path:
    try:
        os.chmod(os.path.dirname(mf_path), 0o500)
    except Exception as exc:
        sys.stderr.write(f"CRITICAL ERROR: Failed to set unwritable parent in test mode: {exc}\n")
        audit_ok = False

orig_ok = atomic_restore_file(orig_mf_path, mf_path, "original release manifest")

if not audit_ok or not orig_ok:
    sys.stderr.write(
        f"CRITICAL ERROR: Rollback manifest compensation/restoration failed (audit_ok={audit_ok}, orig_manifest_ok={orig_ok})!\n"
    )
    sys.exit(1)
PYEOF
}

restore_pre_rollback_state() {
  if [ "${RESTORE_ATTEMPTED}" -eq 1 ]; then
    return "${RESTORE_LAST_RC:-1}"
  fi
  RESTORE_ATTEMPTED=1
  set +e

  echo "Initiating automatic restoration of pre-rollback live state..." >&2

  local manifests_ok=0
  if compensate_rollback_manifests; then
    echo "✓ Rollback manifest state compensated and verified." >&2
    manifests_ok=1
  else
    echo "CRITICAL ERROR: Rollback manifest compensation/restoration FAILED!" >&2
    manifests_ok=0
  fi

  python3 - "${DOCROOT}" "${PRE_ROLLBACK_HAD_FILES}" "${PRE_ROLLBACK_RECOVERY_TREE:-}" "${PRE_ROLLBACK_FILES_TAR:-}" <<'PYEOF'
import os, shutil, sys, tarfile

docroot, had_files_str, recovery_tree, backup_tar = sys.argv[1:5]
had_files = int(had_files_str) == 1

if not os.path.isdir(docroot) or os.path.islink(docroot):
    sys.stderr.write(f"CRITICAL ERROR: Cannot restore into invalid docroot '{docroot}'\n")
    sys.exit(1)

for entry in os.listdir(docroot):
    full = os.path.join(docroot, entry)
    if os.path.islink(full) or os.path.isfile(full):
        os.unlink(full)
    elif os.path.isdir(full):
        shutil.rmtree(full)

if had_files:
    restored = False
    if recovery_tree and os.path.isdir(recovery_tree) and not os.path.islink(recovery_tree):
        for entry in os.listdir(recovery_tree):
            src = os.path.join(recovery_tree, entry)
            dst = os.path.join(docroot, entry)
            if os.path.isdir(src) and not os.path.islink(src):
                shutil.copytree(src, dst, symlinks=False)
            else:
                shutil.copy2(src, dst, follow_symlinks=False)
        restored = True
    elif backup_tar and os.path.isfile(backup_tar) and not os.path.islink(backup_tar):
        with tarfile.open(backup_tar, "r:gz") as tf:
            tf.extractall(docroot)
        restored = True

    if not restored:
        sys.stderr.write("CRITICAL ERROR: No valid pre-rollback recovery source available for docroot restore!\n")
        sys.exit(1)

    for dirpath, dirnames, filenames in os.walk(docroot, followlinks=False):
        os.chmod(dirpath, 0o755)
        for fn in filenames:
            fp = os.path.join(dirpath, fn)
            if not os.path.islink(fp):
                os.chmod(fp, 0o644)
PYEOF
  local py_rc=$?

  local restored_digest=""
  restored_digest="$(compute_tree_digest "${DOCROOT}" 2>/dev/null || echo "ERROR")"
  local sym_ok=0
  if assert_no_symlinks_in_tree "${DOCROOT}" "restored DOCROOT" 2>/dev/null; then
    sym_ok=1
  fi

  local files_ok=0
  if [ "${py_rc}" -eq 0 ] && [ "${sym_ok}" -eq 1 ] && [ "${restored_digest}" = "${PRE_ROLLBACK_DIGEST}" ]; then
    echo "✓ Previously live docroot files restored and cryptographically verified (${restored_digest})." >&2
    files_ok=1
  else
    echo "CRITICAL ERROR: Pre-rollback docroot restore verification FAILED (expected=${PRE_ROLLBACK_DIGEST}, actual=${restored_digest})!" >&2
  fi

  local db_ok=1
  if [ "${DB_MUTATION_STARTED}" -eq 1 ]; then
    db_ok=0
    echo "Database mutation had begun during rollback; restoring pre-rollback database state for '${DB_NAME}'..." >&2
    if [ "${TEST_MODE:-0}" = "1" ] && [ "${TEST_USE_MYSQL_BIN:-0}" != "1" ]; then
      if [ "${TEST_MOCK_DB_RECOVERY_FAIL:-0}" != "1" ]; then
        echo "✓ MOCK: Pre-rollback database state restored for '${DB_NAME}'." >&2
        db_ok=1
      fi
    else
      if [ "${TEST_MOCK_DB_RECOVERY_FAIL:-0}" != "1" ] && [ -n "${TMP_MYCNF:-}" ] && [ -f "${TMP_MYCNF}" ]; then
        if [ "${PRE_ROLLBACK_DB_EXISTED}" -eq 1 ]; then
          if [ -n "${PRE_ROLLBACK_DB_DUMP:-}" ] && [ -f "${PRE_ROLLBACK_DB_DUMP}" ] && [ ! -L "${PRE_ROLLBACK_DB_DUMP}" ] && [ -s "${PRE_ROLLBACK_DB_DUMP}" ] && gzip -t "${PRE_ROLLBACK_DB_DUMP}" 2>/dev/null; then
            local reset_ok=1
            if ! mysql --defaults-extra-file="${TMP_MYCNF}" -e "DROP DATABASE ${QUOTED_DB};" 2>/dev/null; then
              local cur_tables=""
              if cur_tables="$(mysql --defaults-extra-file="${TMP_MYCNF}" -N -B -e "SHOW TABLES FROM ${QUOTED_DB};" 2>/dev/null)"; then
                if [ -n "${cur_tables}" ]; then
                  local drop_sql="SET FOREIGN_KEY_CHECKS = 0;"
                  while IFS= read -r tbl; do
                    [ -z "${tbl}" ] && continue
                    local qtbl=""
                    qtbl="$(quote_sql_ident "${tbl}" "table name" 2>/dev/null)" || { reset_ok=0; break; }
                    drop_sql="${drop_sql} DROP TABLE IF EXISTS ${QUOTED_DB}.${qtbl};"
                  done <<< "${cur_tables}"
                  drop_sql="${drop_sql} SET FOREIGN_KEY_CHECKS = 1;"
                  if [ "${reset_ok}" -eq 1 ] && ! mysql --defaults-extra-file="${TMP_MYCNF}" -e "${drop_sql}" 2>/dev/null; then
                    reset_ok=0
                  fi
                fi
              else
                reset_ok=0
              fi
            fi
            if [ "${reset_ok}" -eq 1 ]; then
              local schema_ready=0
              if mysql --defaults-extra-file="${TMP_MYCNF}" -e "CREATE DATABASE IF NOT EXISTS ${QUOTED_DB};" 2>/dev/null; then
                schema_ready=1
              else
                local schema_exists_raw=""
                if schema_exists_raw="$(mysql --defaults-extra-file="${TMP_MYCNF}" -N -B -e "SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '${DB_NAME}';" 2>/dev/null)"; then
                  local schema_exists=""
                  schema_exists="$(printf '%s' "${schema_exists_raw}" | tr -d '[:space:]')"
                  if [ "${schema_exists}" = "1" ]; then
                    schema_ready=1
                  fi
                fi
              fi
              if [ "${schema_ready}" -eq 1 ] && gunzip -c "${PRE_ROLLBACK_DB_DUMP}" | mysql --defaults-extra-file="${TMP_MYCNF}" -- "${DB_NAME}" 2>/dev/null; then
                echo "✓ Pre-rollback database '${DB_NAME}' restored from pre-rollback snapshot." >&2
                db_ok=1
              fi
            fi
          fi
        else
          # Database did not exist before rollback; drop it or purge its tables to restore pre-rollback state
          if mysql --defaults-extra-file="${TMP_MYCNF}" -e "DROP DATABASE ${QUOTED_DB};" 2>/dev/null; then
            echo "✓ Pre-rollback absent database state restored for '${DB_NAME}'." >&2
            db_ok=1
          else
            local cur_tables=""
            if cur_tables="$(mysql --defaults-extra-file="${TMP_MYCNF}" -N -B -e "SHOW TABLES FROM ${QUOTED_DB};" 2>/dev/null)"; then
              local purge_ok=1
              if [ -n "${cur_tables}" ]; then
                local drop_sql="SET FOREIGN_KEY_CHECKS = 0;"
                while IFS= read -r tbl; do
                  [ -z "${tbl}" ] && continue
                  local qtbl=""
                  qtbl="$(quote_sql_ident "${tbl}" "table name" 2>/dev/null)" || { purge_ok=0; break; }
                  drop_sql="${drop_sql} DROP TABLE IF EXISTS ${QUOTED_DB}.${qtbl};"
                done <<< "${cur_tables}"
                drop_sql="${drop_sql} SET FOREIGN_KEY_CHECKS = 1;"
                if [ "${purge_ok}" -eq 1 ] && ! mysql --defaults-extra-file="${TMP_MYCNF}" -e "${drop_sql}" 2>/dev/null; then
                  purge_ok=0
                fi
              fi
              if [ "${purge_ok}" -eq 1 ]; then
                echo "✓ Pre-rollback empty database state restored for '${DB_NAME}'." >&2
                db_ok=1
              fi
            fi
          fi
        fi
      fi
    fi
    if [ "${db_ok}" -ne 1 ]; then
      echo "CRITICAL ERROR: Pre-rollback database state restoration FAILED!" >&2
    fi
  fi

  if [ "${files_ok}" -eq 1 ] && [ "${db_ok}" -eq 1 ] && [ "${manifests_ok}" -eq 1 ]; then
    if [ "${PRE_ROLLBACK_HAD_FILES}" -eq 0 ] || [ -s "${PRE_ROLLBACK_FILES_TAR:-}" ]; then
      if [ "${PRE_ROLLBACK_RECOVERY_TREE_OWNED:-0}" -eq 1 ] && [ -n "${PRE_ROLLBACK_RECOVERY_TREE:-}" ] && [ ! -L "${PRE_ROLLBACK_RECOVERY_TREE}" ] && [ -d "${PRE_ROLLBACK_RECOVERY_TREE}" ]; then
        rm -rf -- "${PRE_ROLLBACK_RECOVERY_TREE}" 2>/dev/null || true
        PRE_ROLLBACK_RECOVERY_TREE=""
        PRE_ROLLBACK_RECOVERY_TREE_OWNED=0
      fi
    fi
    RESTORE_LAST_RC=0
    return 0
  else
    echo "CRITICAL ERROR: Pre-rollback recovery failed (files_ok=${files_ok}, db_ok=${db_ok}, manifests_ok=${manifests_ok}); preserving all recovery evidence:" >&2
    [ -n "${PRE_ROLLBACK_RECOVERY_DIR:-}" ] && echo "  Recovery Dir:              ${PRE_ROLLBACK_RECOVERY_DIR}" >&2
    [ -n "${PRE_ROLLBACK_ORIG_MANIFEST:-}" ] && echo "  Original Manifest Snap:    ${PRE_ROLLBACK_ORIG_MANIFEST}" >&2
    [ -n "${PRE_ROLLBACK_ORIG_RB_MANIFEST:-}" ] && echo "  Prior Audit Manifest Snap: ${PRE_ROLLBACK_ORIG_RB_MANIFEST}" >&2
    [ -n "${PRE_ROLLBACK_FILES_TAR:-}" ] && echo "  Files Snapshot:            ${PRE_ROLLBACK_FILES_TAR}" >&2
    [ -n "${PRE_ROLLBACK_RECOVERY_TREE:-}" ] && echo "  Recovery Tree:             ${PRE_ROLLBACK_RECOVERY_TREE}" >&2
    [ -n "${PRE_ROLLBACK_DB_DUMP:-}" ] && echo "  DB Snapshot:               ${PRE_ROLLBACK_DB_DUMP}" >&2
    RESTORE_LAST_RC=1
    return 1
  fi
}

cleanup() {
  local exit_code=$?
  set +e
  if [ "${CLEANUP_IN_PROGRESS:-0}" -eq 1 ]; then
    return 0
  fi
  CLEANUP_IN_PROGRESS=1
  trap - EXIT
  trap '' INT TERM HUP
  if [ -n "${SIGNAL_EXIT_CODE:-}" ]; then
    exit_code="${SIGNAL_EXIT_CODE}"
  fi

  if [ "${STAGE_DIR_OWNED:-0}" -eq 1 ] && [ -n "${STAGE_DIR:-}" ] && [ ! -L "${STAGE_DIR}" ] && [ -d "${STAGE_DIR}" ]; then
    rm -rf -- "${STAGE_DIR}" 2>/dev/null || true
    STAGE_DIR_OWNED=0
  fi
  if [ -n "${HEALTH_TMP:-}" ] && [ -f "${HEALTH_TMP}" ]; then
    rm -f -- "${HEALTH_TMP}" 2>/dev/null || true
  fi

  if [ "${exit_code}" -ne 0 ] || [ "${ROLLBACK_COMPLETED}" -eq 0 ]; then
    if [ "${exit_code}" -eq 0 ]; then
      exit_code=1
    fi
    if [ "${ROLLBACK_MUTATION_STARTED}" -eq 1 ] && [ "${ROLLBACK_COMPLETED}" -eq 0 ]; then
      if restore_pre_rollback_state; then
        # Delete original-manifest snapshots ONLY after file/DB/live-state restoration AND manifest compensation have BOTH been verified
        if [ "${PRE_ROLLBACK_ORIG_MANIFEST_OWNED:-0}" -eq 1 ] && [ -n "${PRE_ROLLBACK_ORIG_MANIFEST:-}" ] && [ ! -L "${PRE_ROLLBACK_ORIG_MANIFEST}" ] && [ -f "${PRE_ROLLBACK_ORIG_MANIFEST}" ]; then
          rm -f -- "${PRE_ROLLBACK_ORIG_MANIFEST}" 2>/dev/null || true
          PRE_ROLLBACK_ORIG_MANIFEST_OWNED=0
        fi
        if [ "${PRE_ROLLBACK_ORIG_RB_MANIFEST_OWNED:-0}" -eq 1 ] && [ -n "${PRE_ROLLBACK_ORIG_RB_MANIFEST:-}" ] && [ ! -L "${PRE_ROLLBACK_ORIG_RB_MANIFEST}" ] && [ -f "${PRE_ROLLBACK_ORIG_RB_MANIFEST}" ]; then
          rm -f -- "${PRE_ROLLBACK_ORIG_RB_MANIFEST}" 2>/dev/null || true
          PRE_ROLLBACK_ORIG_RB_MANIFEST_OWNED=0
        fi
        if [ "${PRE_ROLLBACK_HAD_FILES}" -eq 0 ] && [ "${PRE_ROLLBACK_DB_DUMP_OWNED:-0}" -eq 0 ] && [ "${PRE_ROLLBACK_RECOVERY_DIR_OWNED:-0}" -eq 1 ] && [ -n "${PRE_ROLLBACK_RECOVERY_DIR:-}" ] && [ ! -L "${PRE_ROLLBACK_RECOVERY_DIR}" ] && [ -d "${PRE_ROLLBACK_RECOVERY_DIR}" ]; then
          rmdir "${PRE_ROLLBACK_RECOVERY_DIR}" 2>/dev/null || true
        fi
      else
        echo "CRITICAL ERROR: Rollback transaction recovery failed; preserving original-manifest snapshots and all recovery evidence in '${PRE_ROLLBACK_RECOVERY_DIR:-unknown}'!" >&2
      fi
    else
      # Failed before any mutation started: clean up invocation-owned pre-rollback staging
      if [ "${PRE_ROLLBACK_RECOVERY_TREE_OWNED:-0}" -eq 1 ] && [ -n "${PRE_ROLLBACK_RECOVERY_TREE:-}" ] && [ ! -L "${PRE_ROLLBACK_RECOVERY_TREE}" ] && [ -d "${PRE_ROLLBACK_RECOVERY_TREE}" ]; then
        rm -rf -- "${PRE_ROLLBACK_RECOVERY_TREE}" 2>/dev/null || true
      fi
      if [ "${PRE_ROLLBACK_FILES_TAR_OWNED:-0}" -eq 1 ] && [ -n "${PRE_ROLLBACK_FILES_TAR:-}" ] && [ ! -L "${PRE_ROLLBACK_FILES_TAR}" ] && [ -f "${PRE_ROLLBACK_FILES_TAR}" ]; then
        rm -f -- "${PRE_ROLLBACK_FILES_TAR}" 2>/dev/null || true
      fi
      if [ "${PRE_ROLLBACK_DB_DUMP_OWNED:-0}" -eq 1 ] && [ -n "${PRE_ROLLBACK_DB_DUMP:-}" ] && [ ! -L "${PRE_ROLLBACK_DB_DUMP}" ] && [ -f "${PRE_ROLLBACK_DB_DUMP}" ]; then
        rm -f -- "${PRE_ROLLBACK_DB_DUMP}" 2>/dev/null || true
      fi
      if [ "${PRE_ROLLBACK_ORIG_MANIFEST_OWNED:-0}" -eq 1 ] && [ -n "${PRE_ROLLBACK_ORIG_MANIFEST:-}" ] && [ ! -L "${PRE_ROLLBACK_ORIG_MANIFEST}" ] && [ -f "${PRE_ROLLBACK_ORIG_MANIFEST}" ]; then
        rm -f -- "${PRE_ROLLBACK_ORIG_MANIFEST}" 2>/dev/null || true
      fi
      if [ "${PRE_ROLLBACK_ORIG_RB_MANIFEST_OWNED:-0}" -eq 1 ] && [ -n "${PRE_ROLLBACK_ORIG_RB_MANIFEST:-}" ] && [ ! -L "${PRE_ROLLBACK_ORIG_RB_MANIFEST}" ] && [ -f "${PRE_ROLLBACK_ORIG_RB_MANIFEST}" ]; then
        rm -f -- "${PRE_ROLLBACK_ORIG_RB_MANIFEST}" 2>/dev/null || true
      fi
      if [ "${PRE_ROLLBACK_RECOVERY_DIR_OWNED:-0}" -eq 1 ] && [ -n "${PRE_ROLLBACK_RECOVERY_DIR:-}" ] && [ ! -L "${PRE_ROLLBACK_RECOVERY_DIR}" ] && [ -d "${PRE_ROLLBACK_RECOVERY_DIR}" ]; then
        rmdir "${PRE_ROLLBACK_RECOVERY_DIR}" 2>/dev/null || true
      fi
    fi
    echo "================================================================================" >&2
    echo "ROLLBACK SCRIPT FAILED WITH CODE: ${exit_code}" >&2
    echo "================================================================================" >&2
  else
    if [ "${ROLLBACK_COMPLETED}" -eq 1 ]; then
      if [ "${PRE_ROLLBACK_RECOVERY_TREE_OWNED:-0}" -eq 1 ] && [ -n "${PRE_ROLLBACK_RECOVERY_TREE:-}" ] && [ ! -L "${PRE_ROLLBACK_RECOVERY_TREE}" ] && [ -d "${PRE_ROLLBACK_RECOVERY_TREE}" ]; then
        rm -rf -- "${PRE_ROLLBACK_RECOVERY_TREE}" 2>/dev/null || true
      fi
      if [ "${PRE_ROLLBACK_FILES_TAR_OWNED:-0}" -eq 1 ] && [ -n "${PRE_ROLLBACK_FILES_TAR:-}" ] && [ ! -L "${PRE_ROLLBACK_FILES_TAR}" ] && [ -f "${PRE_ROLLBACK_FILES_TAR}" ]; then
        rm -f -- "${PRE_ROLLBACK_FILES_TAR}" 2>/dev/null || true
      fi
      if [ "${PRE_ROLLBACK_DB_DUMP_OWNED:-0}" -eq 1 ] && [ -n "${PRE_ROLLBACK_DB_DUMP:-}" ] && [ ! -L "${PRE_ROLLBACK_DB_DUMP}" ] && [ -f "${PRE_ROLLBACK_DB_DUMP}" ]; then
        rm -f -- "${PRE_ROLLBACK_DB_DUMP}" 2>/dev/null || true
      fi
      if [ "${PRE_ROLLBACK_ORIG_MANIFEST_OWNED:-0}" -eq 1 ] && [ -n "${PRE_ROLLBACK_ORIG_MANIFEST:-}" ] && [ ! -L "${PRE_ROLLBACK_ORIG_MANIFEST}" ] && [ -f "${PRE_ROLLBACK_ORIG_MANIFEST}" ]; then
        rm -f -- "${PRE_ROLLBACK_ORIG_MANIFEST}" 2>/dev/null || true
      fi
      if [ "${PRE_ROLLBACK_ORIG_RB_MANIFEST_OWNED:-0}" -eq 1 ] && [ -n "${PRE_ROLLBACK_ORIG_RB_MANIFEST:-}" ] && [ ! -L "${PRE_ROLLBACK_ORIG_RB_MANIFEST}" ] && [ -f "${PRE_ROLLBACK_ORIG_RB_MANIFEST}" ]; then
        rm -f -- "${PRE_ROLLBACK_ORIG_RB_MANIFEST}" 2>/dev/null || true
      fi
      if [ "${PRE_ROLLBACK_RECOVERY_DIR_OWNED:-0}" -eq 1 ] && [ -n "${PRE_ROLLBACK_RECOVERY_DIR:-}" ] && [ ! -L "${PRE_ROLLBACK_RECOVERY_DIR}" ] && [ -d "${PRE_ROLLBACK_RECOVERY_DIR}" ]; then
        rmdir "${PRE_ROLLBACK_RECOVERY_DIR}" 2>/dev/null || true
      fi
    fi
  fi

  if [ -n "${TMP_MYCNF:-}" ] && [ -f "${TMP_MYCNF}" ]; then
    rm -f -- "${TMP_MYCNF}" 2>/dev/null || true
  fi

  release_deploy_lock
  exit "${exit_code}"
}
trap cleanup EXIT
trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM
trap 'handle_signal 129' HUP

acquire_deploy_lock

echo "================================================================================"
echo "GBA Furniture: Initiating Rollback"
echo "Target Release ID: ${RELEASE_ID}"
echo "Docroot:           ${DOCROOT}"
echo "Backup Repository: ${BACKUP_ROOT}"
echo "Verify URL:        ${VERIFY_URL}"
echo "================================================================================"

WP_BACKUP_FILES="${BACKUP_ROOT}/${RELEASE_ID}_files.tar.gz"
WP_BACKUP_DB="${BACKUP_ROOT}/${RELEASE_ID}_db.sql.gz"
MANIFEST_FILE="${BACKUP_ROOT}/${RELEASE_ID}_manifest.json"
ROLLBACK_MANIFEST="${BACKUP_ROOT}/${RELEASE_ID}_rollback_manifest.json"

# ==============================================================================
# 3. Parse Manifest as Strict JSON & Validate All Bindings Before Any Mutation
# ==============================================================================
if [ -L "${MANIFEST_FILE}" ] || [ ! -f "${MANIFEST_FILE}" ] || [ ! -s "${MANIFEST_FILE}" ]; then
  echo "CRITICAL ERROR: Required release manifest not found, empty, or symlink: ${MANIFEST_FILE}" >&2
  exit 1
fi

if [ -L "${WP_BACKUP_FILES}" ] || [ ! -f "${WP_BACKUP_FILES}" ] || [ ! -s "${WP_BACKUP_FILES}" ]; then
  echo "CRITICAL ERROR: Files backup archive not found, empty, or symlink: ${WP_BACKUP_FILES}" >&2
  exit 1
fi

PARSED_MANIFEST="$(python3 - "${MANIFEST_FILE}" "${RELEASE_ID}" "${DOCROOT}" "${WP_BACKUP_FILES}" "${WP_BACKUP_DB}" <<'PYEOF'
import json, os, re, sys

manifest_path, exp_rel, exp_docroot, exp_files_path, exp_db_path = sys.argv[1:6]

def reject_duplicates(pairs):
    obj = {}
    for k, v in pairs:
        if k in obj:
            raise ValueError(f"Duplicate JSON key '{k}' in rollback manifest")
        obj[k] = v
    return obj

def reject_constants(val):
    raise ValueError(f"Invalid JSON constant '{val}' in rollback manifest")

try:
    with open(manifest_path, "r", encoding="utf-8") as f:
        raw = f.read()
    data = json.loads(raw, object_pairs_hook=reject_duplicates, parse_constant=reject_constants)
except Exception as exc:
    sys.stderr.write(f"CRITICAL ERROR: Failed to parse manifest {manifest_path} as strict JSON: {exc}\n")
    sys.exit(1)

if not isinstance(data, dict):
    sys.stderr.write(f"CRITICAL ERROR: Manifest {manifest_path} root must be a JSON object!\n")
    sys.exit(1)

required_base_keys = {
    "release_id",
    "git_sha",
    "artifact_name",
    "artifact_sha256",
    "timestamp_utc",
    "docroot",
    "files_backup",
    "files_backup_sha256",
    "files_backup_size_bytes",
    "status",
}
missing_keys = required_base_keys - set(data.keys())
if missing_keys:
    sys.stderr.write(f"CRITICAL ERROR: Manifest {manifest_path} missing required bound fields: {sorted(missing_keys)}\n")
    sys.exit(1)

rel_id = data.get("release_id")
if not isinstance(rel_id, str) or rel_id != exp_rel:
    sys.stderr.write(f"CRITICAL ERROR: Manifest release_id {rel_id!r} != target RELEASE_ID {exp_rel!r}!\n")
    sys.exit(1)

docroot = data.get("docroot")
if not isinstance(docroot, str) or docroot != exp_docroot:
    sys.stderr.write(f"CRITICAL ERROR: Manifest docroot {docroot!r} != canonical DOCROOT {exp_docroot!r}!\n")
    sys.exit(1)

git_sha = data.get("git_sha")
if not isinstance(git_sha, str) or not re.match(r"^[a-zA-Z0-9._-]+$", git_sha) or ".." in git_sha:
    sys.stderr.write(f"CRITICAL ERROR: Manifest git_sha {git_sha!r} is invalid!\n")
    sys.exit(1)

art_sha = data.get("artifact_sha256")
if not isinstance(art_sha, str) or not re.match(r"^[0-9a-fA-F]{64}$", art_sha):
    sys.stderr.write(f"CRITICAL ERROR: Manifest artifact_sha256 {art_sha!r} is invalid!\n")
    sys.exit(1)

files_backup = data.get("files_backup")
if not isinstance(files_backup, str) or files_backup != exp_files_path or os.path.basename(files_backup) != f"{exp_rel}_files.tar.gz":
    sys.stderr.write(f"CRITICAL ERROR: Manifest files_backup {files_backup!r} != expected {exp_files_path!r}!\n")
    sys.exit(1)

files_sha = data.get("files_backup_sha256")
if not isinstance(files_sha, str) or not re.match(r"^[0-9a-fA-F]{64}$", files_sha):
    sys.stderr.write(f"CRITICAL ERROR: Manifest files_backup_sha256 {files_sha!r} is invalid!\n")
    sys.exit(1)

files_size = data.get("files_backup_size_bytes")
if not isinstance(files_size, int) or isinstance(files_size, bool) or files_size <= 0:
    sys.stderr.write(f"CRITICAL ERROR: Manifest files_backup_size_bytes {files_size!r} is invalid!\n")
    sys.exit(1)

has_db_fields = any(k in data for k in ("db_backup", "db_backup_sha256", "db_name", "db_user", "db_host"))
if "db_required" in data:
    if not isinstance(data["db_required"], bool):
        sys.stderr.write("CRITICAL ERROR: Manifest db_required must be a boolean!\n")
        sys.exit(1)
    db_req = data["db_required"]
    if db_req != has_db_fields:
        sys.stderr.write("CRITICAL ERROR: Manifest db_required flag conflicts with presence of db_* fields!\n")
        sys.exit(1)
else:
    db_req = has_db_fields

db_sha = ""
db_name = ""
db_user = ""
db_host = ""

if db_req:
    for k in ("db_backup", "db_backup_sha256", "db_backup_size_bytes", "db_name", "db_user", "db_host"):
        if k not in data:
            sys.stderr.write(f"CRITICAL ERROR: Manifest missing required DB field '{k}' when db_required=true!\n")
            sys.exit(1)
    db_backup = data["db_backup"]
    if not isinstance(db_backup, str) or db_backup != exp_db_path or os.path.basename(db_backup) != f"{exp_rel}_db.sql.gz":
        sys.stderr.write(f"CRITICAL ERROR: Manifest db_backup {db_backup!r} != expected {exp_db_path!r}!\n")
        sys.exit(1)
    db_sha = data["db_backup_sha256"]
    if not isinstance(db_sha, str) or not re.match(r"^[0-9a-fA-F]{64}$", db_sha):
        sys.stderr.write(f"CRITICAL ERROR: Manifest db_backup_sha256 {db_sha!r} is invalid!\n")
        sys.exit(1)
    db_size = data["db_backup_size_bytes"]
    if not isinstance(db_size, int) or isinstance(db_size, bool) or db_size <= 0:
        sys.stderr.write(f"CRITICAL ERROR: Manifest db_backup_size_bytes {db_size!r} is invalid!\n")
        sys.exit(1)
    db_name = data["db_name"]
    db_user = data["db_user"]
    db_host = data["db_host"]
    if not isinstance(db_name, str) or not re.match(r"^[a-zA-Z0-9_$]{1,64}$", db_name):
        sys.stderr.write(f"CRITICAL ERROR: Manifest db_name {db_name!r} is invalid!\n")
        sys.exit(1)
    if not isinstance(db_user, str) or not re.match(r"^[a-zA-Z0-9_.-]{1,80}$", db_user):
        sys.stderr.write(f"CRITICAL ERROR: Manifest db_user {db_user!r} is invalid!\n")
        sys.exit(1)
    if not isinstance(db_host, str) or not re.match(r"^[a-zA-Z0-9_.:-]+$", db_host):
        sys.stderr.write(f"CRITICAL ERROR: Manifest db_host {db_host!r} is invalid!\n")
        sys.exit(1)

print("1" if db_req else "0")
print(files_sha)
print(db_sha)
print(db_name)
print(db_user)
print(db_host)
PYEOF
)"

DB_RESTORE_REQUIRED="$(printf '%s\n' "${PARSED_MANIFEST}" | sed -n '1p')"
MANIFEST_FILES_SHA256="$(printf '%s\n' "${PARSED_MANIFEST}" | sed -n '2p')"
MANIFEST_DB_SHA256="$(printf '%s\n' "${PARSED_MANIFEST}" | sed -n '3p')"
MANIFEST_DB_NAME="$(printf '%s\n' "${PARSED_MANIFEST}" | sed -n '4p')"
MANIFEST_DB_USER="$(printf '%s\n' "${PARSED_MANIFEST}" | sed -n '5p')"
MANIFEST_DB_HOST="$(printf '%s\n' "${PARSED_MANIFEST}" | sed -n '6p')"

ACTUAL_FILES_SHA256="$(compute_sha256 "${WP_BACKUP_FILES}")"
shopt -s nocasematch
if [[ "${ACTUAL_FILES_SHA256}" != "${MANIFEST_FILES_SHA256}" ]]; then
  shopt -u nocasematch
  echo "CRITICAL ERROR: Files backup SHA256 mismatch against manifest!" >&2
  echo "  Manifest expected: ${MANIFEST_FILES_SHA256}" >&2
  echo "  Actual archive:    ${ACTUAL_FILES_SHA256}" >&2
  exit 1
fi
shopt -u nocasematch
echo "✓ Files backup SHA256 verified against manifest: ${ACTUAL_FILES_SHA256}"

echo "Verifying files backup tar archive integrity..."
if ! tar -tzf "${WP_BACKUP_FILES}" >/dev/null; then
  echo "CRITICAL ERROR: Backup archive ${WP_BACKUP_FILES} is corrupted!" >&2
  exit 1
fi
echo "✓ Files backup tar archive is valid."

# Stage files backup in temporary directory before touching docroot
STAGE_DIR="$(mktemp -d)"
STAGE_DIR_OWNED=1
tar -xzf "${WP_BACKUP_FILES}" -C "${STAGE_DIR}"

assert_no_symlinks_in_tree "${STAGE_DIR}" "staged files backup archive"

# Reject inconsistent DB state: if manifest says db_required=false, neither wp-config.php nor DB archive may exist
if [ "${DB_RESTORE_REQUIRED}" -eq 0 ]; then
  if [ -f "${STAGE_DIR}/wp-config.php" ] || [ -e "${WP_BACKUP_DB}" ] || [ -L "${WP_BACKUP_DB}" ]; then
    echo "CRITICAL ERROR: Manifest states db_required=false, but wp-config.php or DB backup archive exists!" >&2
    exit 1
  fi
fi

if [ "${DB_RESTORE_REQUIRED}" -eq 1 ]; then
  echo "Database rollback required for release ${RELEASE_ID}. Verifying DB backup archive & manifest hash..."

  if [ -L "${WP_BACKUP_DB}" ] || [ ! -f "${WP_BACKUP_DB}" ] || [ ! -s "${WP_BACKUP_DB}" ]; then
    echo "CRITICAL ERROR: Required database backup archive is missing, empty, or symlink: ${WP_BACKUP_DB}" >&2
    exit 1
  fi

  ACTUAL_DB_SHA256="$(compute_sha256 "${WP_BACKUP_DB}")"
  shopt -s nocasematch
  if [[ "${ACTUAL_DB_SHA256}" != "${MANIFEST_DB_SHA256}" ]]; then
    shopt -u nocasematch
    echo "CRITICAL ERROR: Database backup SHA256 mismatch against manifest!" >&2
    echo "  Manifest expected: ${MANIFEST_DB_SHA256}" >&2
    echo "  Actual archive:    ${ACTUAL_DB_SHA256}" >&2
    exit 1
  fi
  shopt -u nocasematch
  echo "✓ Database backup SHA256 verified against manifest: ${ACTUAL_DB_SHA256}"

  echo "Verifying database backup gzip integrity..."
  if ! gzip -t "${WP_BACKUP_DB}"; then
    echo "CRITICAL ERROR: Database backup archive ${WP_BACKUP_DB} is corrupted gzip!" >&2
    exit 1
  fi
  echo "✓ Database backup gzip archive is valid."

  STAGED_WP_CONFIG="${STAGE_DIR}/wp-config.php"
  if [ -f "${STAGED_WP_CONFIG}" ]; then
    WP_DB_NAME="$(sed -n -E "/define\([[:space:]]*['\"]DB_NAME['\"]/{s/.*['\"]DB_NAME['\"][[:space:]]*,[[:space:]]*['\"]([^'\"]+)['\"].*/\1/p;q;}" "${STAGED_WP_CONFIG}")"
    WP_DB_USER="$(sed -n -E "/define\([[:space:]]*['\"]DB_USER['\"]/{s/.*['\"]DB_USER['\"][[:space:]]*,[[:space:]]*['\"]([^'\"]+)['\"].*/\1/p;q;}" "${STAGED_WP_CONFIG}")"
    DB_PASS="$(sed -n -E "/define\([[:space:]]*['\"]DB_PASSWORD['\"]/{s/.*['\"]DB_PASSWORD['\"][[:space:]]*,[[:space:]]*['\"]([^'\"]+)['\"].*/\1/p;q;}" "${STAGED_WP_CONFIG}")"
    WP_DB_HOST="$(sed -n -E "/define\([[:space:]]*['\"]DB_HOST['\"]/{s/.*['\"]DB_HOST['\"][[:space:]]*,[[:space:]]*['\"]([^'\"]+)['\"].*/\1/p;q;}" "${STAGED_WP_CONFIG}")"
    if [ -n "${WP_DB_NAME}" ] && [ "${WP_DB_NAME}" != "${MANIFEST_DB_NAME}" ]; then
      echo "CRITICAL ERROR: wp-config.php DB_NAME '${WP_DB_NAME}' != manifest db_name '${MANIFEST_DB_NAME}'!" >&2
      exit 1
    fi
    if [ -n "${WP_DB_USER}" ] && [ "${WP_DB_USER}" != "${MANIFEST_DB_USER}" ]; then
      echo "CRITICAL ERROR: wp-config.php DB_USER '${WP_DB_USER}' != manifest db_user '${MANIFEST_DB_USER}'!" >&2
      exit 1
    fi
    if [ -n "${WP_DB_HOST}" ] && [ "${WP_DB_HOST}" != "${MANIFEST_DB_HOST}" ]; then
      echo "CRITICAL ERROR: wp-config.php DB_HOST '${WP_DB_HOST}' != manifest db_host '${MANIFEST_DB_HOST}'!" >&2
      exit 1
    fi
  fi

  DB_NAME="${MANIFEST_DB_NAME}"
  DB_USER="${MANIFEST_DB_USER}"
  DB_HOST="${MANIFEST_DB_HOST:-localhost}"

  validate_sql_identifier "${DB_NAME}" "DB_NAME"
  QUOTED_DB="$(quote_sql_ident "${DB_NAME}" "DB_NAME")"

  if [[ "${DB_PASS}" == *$'\n'* ]] || [[ "${DB_PASS}" == *$'\r'* ]]; then
    echo "CRITICAL ERROR: Invalid control characters in DB_PASSWORD." >&2
    exit 1
  fi

  TMP_MYCNF="$(mktemp)"
  chmod 600 "${TMP_MYCNF}"
  cat > "${TMP_MYCNF}" <<EOF
[client]
user=${DB_USER}
password="${DB_PASS//\"/\\\"}"
host=${DB_HOST}
EOF
fi

# ==============================================================================
# 4. Pre-Rollback Schema Verification & Snapshot/Recovery Tree Before Mutation
# ==============================================================================
if [ -L "${ROLLBACK_MANIFEST}" ] || { [ -e "${ROLLBACK_MANIFEST}" ] && [ ! -f "${ROLLBACK_MANIFEST}" ]; }; then
  echo "CRITICAL ERROR: Rollback manifest path '${ROLLBACK_MANIFEST}' is a symlink or non-regular file!" >&2
  exit 1
fi

PRE_ROLLBACK_DIGEST="$(compute_tree_digest "${DOCROOT}")"
if [ "${PRE_ROLLBACK_DIGEST}" = "INVALID" ]; then
  echo "CRITICAL ERROR: Failed to compute pre-rollback digest of DOCROOT '${DOCROOT}'!" >&2
  exit 1
fi

# Verify pre-rollback schema count is strictly 0 or 1 BEFORE creating any snapshot or mutating state
if [ "${DB_RESTORE_REQUIRED}" -eq 1 ]; then
  if [ "${TEST_MODE:-0}" = "1" ] && [ "${TEST_USE_MYSQL_BIN:-0}" != "1" ]; then
    if [ "${TEST_PRE_ROLLBACK_DB_EXISTED:-0}" = "1" ]; then
      PRE_ROLLBACK_DB_EXISTED=1
    elif [ "${TEST_PRE_ROLLBACK_DB_EXISTED:-0}" = "0" ]; then
      PRE_ROLLBACK_DB_EXISTED=0
    else
      echo "CRITICAL ERROR: Unexpected pre-rollback schema state '${TEST_PRE_ROLLBACK_DB_EXISTED}' for '${DB_NAME}' (must be 0 or 1)!" >&2
      exit 1
    fi
  else
    if ! PRE_SCHEMA_RAW="$(mysql --defaults-extra-file="${TMP_MYCNF}" -N -B -e "SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '${DB_NAME}';")"; then
      echo "CRITICAL ERROR: Failed to query pre-rollback schema state for '${DB_NAME}'!" >&2
      exit 1
    fi
    PRE_SCHEMA_COUNT="$(printf '%s' "${PRE_SCHEMA_RAW}" | tr -d '[:space:]')"
    if [ "${PRE_SCHEMA_COUNT}" != "0" ] && [ "${PRE_SCHEMA_COUNT}" != "1" ]; then
      echo "CRITICAL ERROR: Unexpected pre-rollback schema count '${PRE_SCHEMA_RAW}' for '${DB_NAME}' (must be 0 or 1)!" >&2
      exit 1
    fi
    if [ "${PRE_SCHEMA_COUNT}" = "1" ]; then
      PRE_ROLLBACK_DB_EXISTED=1
    else
      PRE_ROLLBACK_DB_EXISTED=0
    fi
  fi
fi

ROLLBACK_RUN_ID="${RELEASE_ID}-$$-$(date -u +%s)-${RANDOM}"
CANDIDATE_RECOVERY_DIR="${BACKUP_ROOT}/.rollback-recovery-${ROLLBACK_RUN_ID}"
if [ -e "${CANDIDATE_RECOVERY_DIR}" ] || [ -L "${CANDIDATE_RECOVERY_DIR}" ]; then
  echo "CRITICAL ERROR: Pre-rollback recovery directory '${CANDIDATE_RECOVERY_DIR}' already exists or is a symlink!" >&2
  exit 1
fi
mkdir -m 700 -- "${CANDIDATE_RECOVERY_DIR}"
PRE_ROLLBACK_RECOVERY_DIR="$(guard_and_canonicalize_dir "${CANDIDATE_RECOVERY_DIR}" "PRE_ROLLBACK_RECOVERY_DIR" "0" "1")"
PRE_ROLLBACK_RECOVERY_DIR_OWNED=1

PRE_ROLLBACK_ORIG_MANIFEST="${PRE_ROLLBACK_RECOVERY_DIR}/pre-rollback-manifest.json"
cp "${MANIFEST_FILE}" "${PRE_ROLLBACK_ORIG_MANIFEST}"
chmod 600 "${PRE_ROLLBACK_ORIG_MANIFEST}"
PRE_ROLLBACK_ORIG_MANIFEST_OWNED=1

if [ -f "${ROLLBACK_MANIFEST}" ]; then
  HAD_PRIOR_ROLLBACK_MANIFEST=1
  PRE_ROLLBACK_ORIG_RB_MANIFEST="${PRE_ROLLBACK_RECOVERY_DIR}/pre-rollback-audit-manifest.json"
  cp "${ROLLBACK_MANIFEST}" "${PRE_ROLLBACK_ORIG_RB_MANIFEST}"
  chmod 600 "${PRE_ROLLBACK_ORIG_RB_MANIFEST}"
  PRE_ROLLBACK_ORIG_RB_MANIFEST_OWNED=1
fi

if [ -n "$(ls -A "${DOCROOT}" 2>/dev/null)" ]; then
  PRE_ROLLBACK_HAD_FILES=1
  PRE_ROLLBACK_FILES_TAR="${PRE_ROLLBACK_RECOVERY_DIR}/pre-rollback-files.tar.gz"
  PRE_ROLLBACK_FILES_TAR_OWNED=1
  (
    cd "${DOCROOT}"
    COPYFILE_DISABLE=1 tar -czf "${PRE_ROLLBACK_FILES_TAR}" .
  )
  chmod 600 "${PRE_ROLLBACK_FILES_TAR}"
  if [ ! -s "${PRE_ROLLBACK_FILES_TAR}" ] || ! tar -tzf "${PRE_ROLLBACK_FILES_TAR}" >/dev/null; then
    echo "CRITICAL ERROR: Pre-rollback docroot snapshot tar archive failed integrity verification!" >&2
    exit 1
  fi

  CANDIDATE_RECOVERY_TREE="${PRE_ROLLBACK_RECOVERY_DIR}/pre-rollback-tree"
  mkdir -m 700 -- "${CANDIDATE_RECOVERY_TREE}"
  PRE_ROLLBACK_RECOVERY_TREE="${CANDIDATE_RECOVERY_TREE}"
  PRE_ROLLBACK_RECOVERY_TREE_OWNED=1
  tar -xzf "${PRE_ROLLBACK_FILES_TAR}" -C "${PRE_ROLLBACK_RECOVERY_TREE}"
  assert_no_symlinks_in_tree "${PRE_ROLLBACK_RECOVERY_TREE}" "PRE_ROLLBACK_RECOVERY_TREE"
  if [ "$(compute_tree_digest "${PRE_ROLLBACK_RECOVERY_TREE}")" != "${PRE_ROLLBACK_DIGEST}" ]; then
    echo "CRITICAL ERROR: Pre-rollback recovery tree digest mismatch before docroot mutation!" >&2
    exit 1
  fi
fi

if [ "${DB_RESTORE_REQUIRED}" -eq 1 ] && [ "${PRE_ROLLBACK_DB_EXISTED}" -eq 1 ]; then
  PRE_ROLLBACK_DB_DUMP="${PRE_ROLLBACK_RECOVERY_DIR}/pre-rollback-db.sql.gz"
  PRE_ROLLBACK_DB_DUMP_OWNED=1
  if [ "${TEST_MODE:-0}" = "1" ] && [ "${TEST_USE_MYSQL_BIN:-0}" != "1" ]; then
    printf -- '-- Mock pre-rollback DB dump\nCREATE TABLE `pre_existing` (`id` int);\n' | gzip -9 > "${PRE_ROLLBACK_DB_DUMP}"
    chmod 600 "${PRE_ROLLBACK_DB_DUMP}"
  else
    mysqldump --defaults-extra-file="${TMP_MYCNF}" --single-transaction --routines --triggers --quick -- "${DB_NAME}" | gzip -9 > "${PRE_ROLLBACK_DB_DUMP}"
    chmod 600 "${PRE_ROLLBACK_DB_DUMP}"
    if [ ! -s "${PRE_ROLLBACK_DB_DUMP}" ] || ! gzip -t "${PRE_ROLLBACK_DB_DUMP}"; then
      echo "CRITICAL ERROR: Pre-rollback database snapshot failed gzip integrity check!" >&2
      exit 1
    fi
  fi
fi

# ==============================================================================
# 5. Restore Docroot Files & Database Under Active Recovery Trap
# ==============================================================================
find "${STAGE_DIR}" -type d -exec chmod 755 {} +
find "${STAGE_DIR}" -type f -exec chmod 644 {} +

# Mutation begins here: ANY failure in rsync, chmod, DB restore, file checks,
# health checks, or manifest writes will trigger restore_pre_rollback_state.
ROLLBACK_MUTATION_STARTED=1
DOCROOT_MUTATION_STARTED=1

echo "Restoring docroot files from ${WP_BACKUP_FILES} into ${DOCROOT}..."
rsync -a --delete --delay-updates "${STAGE_DIR}/" "${DOCROOT}/"
rm -rf -- "${STAGE_DIR}"
STAGE_DIR=""
STAGE_DIR_OWNED=0

find "${DOCROOT}" -type d -exec chmod 755 {} +
find "${DOCROOT}" -type f -exec chmod 644 {} +
assert_no_symlinks_in_tree "${DOCROOT}" "restored DOCROOT"
echo "✓ Docroot files successfully restored."

if [ "${DB_RESTORE_REQUIRED}" -eq 1 ]; then
  DB_MUTATION_STARTED=1
  echo "Restoring database '${DB_NAME}' (${QUOTED_DB}) from ${WP_BACKUP_DB}..."
  if [ "${TEST_MODE:-0}" = "1" ] && [ "${TEST_USE_MYSQL_BIN:-0}" != "1" ]; then
    if [ "${TEST_MOCK_DB_RESTORE_FAIL:-0}" = "1" ]; then
      echo "CRITICAL ERROR: Simulated database restore failure!" >&2
      exit 1
    fi
    echo "MOCK: Database '${DB_NAME}' restored from ${WP_BACKUP_DB}."
  else
    if ! mysql --defaults-extra-file="${TMP_MYCNF}" -e "CREATE DATABASE IF NOT EXISTS ${QUOTED_DB};"; then
      if ! SCHEMA_EXISTS_RAW="$(mysql --defaults-extra-file="${TMP_MYCNF}" -N -B -e "SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '${DB_NAME}';")"; then
        echo "CRITICAL ERROR: Failed to create database ${QUOTED_DB} and schema existence query failed!" >&2
        exit 1
      fi
      SCHEMA_EXISTS="$(printf '%s' "${SCHEMA_EXISTS_RAW}" | tr -d '[:space:]')"
      if [ "${SCHEMA_EXISTS}" != "1" ]; then
        echo "CRITICAL ERROR: Failed to create database ${QUOTED_DB} and schema does not exist (count='${SCHEMA_EXISTS_RAW}')!" >&2
        exit 1
      fi
    fi

    if ! gunzip -c "${WP_BACKUP_DB}" | mysql --defaults-extra-file="${TMP_MYCNF}" -- "${DB_NAME}"; then
      echo "CRITICAL ERROR: Failed to import database dump ${WP_BACKUP_DB} into ${QUOTED_DB}!" >&2
      exit 1
    fi

    RESTORED_TABLES_RAW="$(mysql --defaults-extra-file="${TMP_MYCNF}" -N -B -e "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = '${DB_NAME}';")"
    RESTORED_TABLES_COUNT="$(printf '%s' "${RESTORED_TABLES_RAW}" | tr -d '[:space:]')"
    if [[ ! "${RESTORED_TABLES_COUNT}" =~ ^[0-9]+$ ]] || [ "${RESTORED_TABLES_COUNT}" -le 0 ]; then
      echo "CRITICAL ERROR: Post-restore database verification failed! Table count in ${QUOTED_DB}: '${RESTORED_TABLES_RAW}'" >&2
      exit 1
    fi
    echo "✓ Database '${DB_NAME}' successfully restored and verified (${RESTORED_TABLES_COUNT} tables)."
  fi
fi

# ==============================================================================
# 6. Enforce Post-Rollback HTTP 200 & Fatal-Error/Content Health on EVERY Endpoint
# ==============================================================================
echo "Verifying post-rollback HTTP and content health at ${VERIFY_URL}..."
HEALTH_TMP="$(mktemp)"

verify_rollback_endpoint() {
  local target_url="$1"
  local endpoint_label="$2"
  local required_marker="${3:-}"
  local reject_dir_listing="${4:-0}"

  local code
  code="$(curl -sSL --max-time 15 -w "%{http_code}" -o "${HEALTH_TMP}" -- "${target_url}" || echo "000")"
  if [ "${code}" != "200" ]; then
    echo "CRITICAL ERROR: Post-rollback HTTP health check failed on ${endpoint_label} (${target_url}): expected HTTP 200, received HTTP ${code}." >&2
    return 1
  fi

  if [ ! -s "${HEALTH_TMP}" ]; then
    echo "CRITICAL ERROR: Post-rollback content health check failed on ${endpoint_label} (${target_url}): empty response body." >&2
    return 1
  fi

  if ! python3 - "${HEALTH_TMP}" "${endpoint_label}" "${target_url}" "${required_marker}" "${reject_dir_listing}" <<'PYEOF'
import re, sys

body_path, label, url, marker, reject_listing_str = sys.argv[1:6]
reject_listing = int(reject_listing_str) == 1

with open(body_path, "rb") as f:
    raw = f.read()

text = raw.decode("utf-8", errors="replace")
if not text.strip():
    sys.stderr.write(f"CRITICAL ERROR: Post-rollback response from {label} ({url}) contains only whitespace!\n")
    sys.exit(1)

fatal_patterns = [
    r"Error establishing a database connection",
    r"Fatal error\s*:",
    r"Parse error\s*:",
    r"Uncaught Error",
    r"Uncaught Exception",
    r"500 Internal Server Error",
    r"Database Error",
    r"Briefly unavailable for scheduled maintenance",
    r"<\?php",
    r"<\?=",
]

for pat in fatal_patterns:
    if re.search(pat, text, re.IGNORECASE):
        sys.stderr.write(
            f"CRITICAL ERROR: Post-rollback health check detected fatal error or unexecuted PHP pattern ({pat}) on {label} ({url})!\n"
        )
        sys.exit(1)

if reject_listing and re.search(r"<title>\s*(Directory listing for|Index of)\b", text, re.IGNORECASE):
    sys.stderr.write(f"CRITICAL ERROR: Post-rollback health check received directory listing on {label} ({url})!\n")
    sys.exit(1)

if marker and marker not in text:
    sys.stderr.write(f"CRITICAL ERROR: Post-rollback health check missing expected content '{marker}' on {label} ({url})!\n")
    sys.exit(1)
PYEOF
  then
    return 1
  fi

  return 0
}

# 1. Check root VERIFY_URL
verify_rollback_endpoint "${VERIFY_URL}" "root endpoint" "" "0"
HTTP_CODE="200"

# 2. If restored docroot contains index.php, strictly verify /index.php with full fatal-error & content checks
if [ -f "${DOCROOT}/index.php" ]; then
  verify_rollback_endpoint "${VERIFY_URL}/index.php" "/index.php" "" "1"
fi

# 3. If restored docroot contains index.html, strictly verify both root and /index.html with brand marker
if [ -f "${DOCROOT}/index.html" ]; then
  verify_rollback_endpoint "${VERIFY_URL}" "root index.html" "GBA Furniture" "1"
  verify_rollback_endpoint "${VERIFY_URL}/index.html" "/index.html" "GBA Furniture" "1"
fi

echo "✓ Post-rollback HTTP 200 and content health verified across all endpoints at ${VERIFY_URL}"

# ==============================================================================
# 7. Transactionally Finalize Rollback Audit & Original Manifest Status
#    (Stage & validate both, then publish with automatic compensation on failure)
# ==============================================================================
DB_REQ_BOOL="false"
if [ "${DB_RESTORE_REQUIRED}" -eq 1 ]; then
  DB_REQ_BOOL="true"
fi
ROLLBACK_TS_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

ROLLBACK_AUDIT_JSON="$(cat <<EOF
{
  "restored_release_id": "${RELEASE_ID}",
  "timestamp_utc": "${ROLLBACK_TS_UTC}",
  "docroot": "${DOCROOT}",
  "files_backup_restored": "${WP_BACKUP_FILES}",
  "files_backup_sha256": "${ACTUAL_FILES_SHA256}",
  "db_backup_restored": "${WP_BACKUP_DB}",
  "db_restore_required": ${DB_REQ_BOOL},
  "db_name": "${DB_NAME:-none}",
  "db_user": "${DB_USER:-none}",
  "db_host": "${DB_HOST:-none}",
  "status": "rolled_back",
  "verified_url": "${VERIFY_URL}",
  "http_status": "${HTTP_CODE}"
}
EOF
)"

python3 - \
  "${ROLLBACK_MANIFEST}" \
  "${MANIFEST_FILE}" \
  "${ROLLBACK_AUDIT_JSON}" \
  "${TEST_FAIL_FINAL_MANIFEST_WRITE:-0}" \
  "${TEST_FAIL_ROLLBACK_SECOND_WRITE:-0}" \
  "${TEST_MODE:-0}" \
  "${TEST_UNWRITABLE_MANIFEST_PARENT_AFTER_FIRST:-0}" <<'PYEOF'
import json, os, sys, tempfile

(
    rb_path,
    mf_path,
    rb_raw_json,
    fail_final_str,
    fail_second_str,
    test_mode_str,
    unwritable_after_first_str,
) = sys.argv[1:8]

fail_final = fail_final_str == "1"
fail_second = fail_second_str == "1"
test_mode = test_mode_str == "1"
unwritable_after_first = test_mode and (unwritable_after_first_str == "1")

for p in (rb_path, mf_path):
    if os.path.islink(p):
        sys.stderr.write(f"CRITICAL ERROR: Manifest target '{p}' is a symlink!\n")
        sys.exit(1)
    parent = os.path.dirname(p)
    if not os.path.isdir(parent) or os.path.islink(parent):
        sys.stderr.write(f"CRITICAL ERROR: Manifest parent '{parent}' is invalid or a symlink!\n")
        sys.exit(1)

if not os.path.isfile(mf_path):
    sys.stderr.write(f"CRITICAL ERROR: Original manifest '{mf_path}' is missing!\n")
    sys.exit(1)

def reject_duplicates(pairs):
    obj = {}
    for k, v in pairs:
        if k in obj:
            raise ValueError(f"Duplicate JSON key '{k}'")
        obj[k] = v
    return obj

def reject_constants(val):
    raise ValueError(f"Invalid JSON constant '{val}'")

try:
    rb_parsed = json.loads(rb_raw_json, object_pairs_hook=reject_duplicates, parse_constant=reject_constants)
    with open(mf_path, "r", encoding="utf-8") as f:
        mf_parsed = json.loads(f.read(), object_pairs_hook=reject_duplicates, parse_constant=reject_constants)
except Exception as exc:
    sys.stderr.write(f"CRITICAL ERROR: Failed to parse rollback finalization manifests as strict JSON: {exc}\n")
    sys.exit(1)

if not isinstance(rb_parsed, dict) or not isinstance(mf_parsed, dict):
    sys.stderr.write("CRITICAL ERROR: Rollback manifests must be JSON objects!\n")
    sys.exit(1)

mf_parsed["status"] = "rolled_back"
mf_parsed["rolled_back_at_utc"] = rb_parsed["timestamp_utc"]
mf_parsed["rollback_verified_url"] = rb_parsed["verified_url"]

rb_bytes = (json.dumps(rb_parsed, indent=2) + "\n").encode("utf-8")
mf_bytes = (json.dumps(mf_parsed, indent=2) + "\n").encode("utf-8")

parent_dir = os.path.dirname(mf_path)
fd_rb, tmp_rb = tempfile.mkstemp(prefix="." + os.path.basename(rb_path) + ".tmp.", dir=parent_dir)
fd_mf, tmp_mf = tempfile.mkstemp(prefix="." + os.path.basename(mf_path) + ".tmp.", dir=parent_dir)

try:
    # Stage and fsync both temporary files before any publication
    os.fchmod(fd_rb, 0o600)
    os.write(fd_rb, rb_bytes)
    os.fsync(fd_rb)
    os.close(fd_rb)
    fd_rb = -1

    os.fchmod(fd_mf, 0o600)
    os.write(fd_mf, mf_bytes)
    os.fsync(fd_mf)
    os.close(fd_mf)
    fd_mf = -1

    # Validate both staged temporary files on disk before renaming either one
    with open(tmp_rb, "r", encoding="utf-8") as vrb:
        ver_rb = json.loads(vrb.read(), object_pairs_hook=reject_duplicates, parse_constant=reject_constants)
    with open(tmp_mf, "r", encoding="utf-8") as vmf:
        ver_mf = json.loads(vmf.read(), object_pairs_hook=reject_duplicates, parse_constant=reject_constants)
    if ver_rb != rb_parsed or ver_mf != mf_parsed:
        raise ValueError("Staged temporary manifest verification mismatch on disk")

    if fail_final:
        raise RuntimeError("Simulated final manifest write failure before atomic replace")

    # Step 1 of publication: publish rollback audit manifest
    os.replace(tmp_rb, rb_path)
    tmp_rb = ""

    if unwritable_after_first:
        if tmp_mf and os.path.lexists(tmp_mf):
            os.unlink(tmp_mf)
            tmp_mf = ""
        os.chmod(parent_dir, 0o500)

    # Step 2 of publication: publish updated original manifest
    if fail_second:
        raise RuntimeError("Simulated second manifest publication failure after rollback audit write")

    st_parent = os.lstat(parent_dir)
    if (st_parent.st_mode & 0o222) == 0 or not os.access(parent_dir, os.W_OK):
        raise PermissionError(
            f"Manifest parent directory '{parent_dir}' is not writable (mode={oct(st_parent.st_mode & 0o777)})"
        )

    os.replace(tmp_mf, mf_path)
    tmp_mf = ""

    try:
        dir_fd = os.open(parent_dir, os.O_RDONLY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    except Exception:
        pass
except Exception as exc:
    for fd in (fd_rb, fd_mf):
        if fd >= 0:
            try:
                os.close(fd)
            except Exception:
                pass
    for tp in (tmp_rb, tmp_mf):
        if tp:
            try:
                if os.path.lexists(tp):
                    os.unlink(tp)
            except Exception:
                pass
    sys.stderr.write(f"CRITICAL ERROR: Transactional rollback manifest finalization failed: {exc}\n")
    sys.exit(1)
PYEOF

ROLLBACK_COMPLETED=1

echo "================================================================================"
echo "ROLLBACK COMPLETE FOR RELEASE: ${RELEASE_ID}"
echo "Docroot restored to: ${DOCROOT}"
echo "Rollback manifest written to: ${ROLLBACK_MANIFEST}"
echo "================================================================================"
