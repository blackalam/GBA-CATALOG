#!/usr/bin/env bash
# ==============================================================================
# GBA Furniture — Production Release Deployment Script
#
# Usage:
#   ./scripts/remote-deploy-production.sh <RELEASE_ID> <TARBALL_PATH> [PRODUCTION_URL] [GIT_SHA] [ARTIFACT_SHA256]
#
# Process:
#   1. Strict Input, URL, Runtime Preflight ('node --check' before any mutation)
#      & Canonical Realpath Guards (Error-Checked Symlink Scan)
#   2. Host-Side Shared OS-Held Lock (/home/alibhatt/.gba-deploy.lock) via
#      nonblocking flock on a canonical regular file with stable fd & separate
#      atomic owner metadata
#   3. Duplicate Release ID Rejection Before Any Writes
#   4. Outer Tarball SHA256, Packaged Checksum, Exhaustive Static-Only Allowlist,
#      and release-metadata.json Binding (release_id, git_sha, checksum)
#   5. SQL Identifier Validation, Safe Quoting & Dual-Verified Backups Outside
#      Docroot with Pre-Cutover Tree Digest
#   6. Cutover with Comprehensive Trap-Driven Transaction Recovery Active Until
#      ALL DB Cleanup and Final Manifest Writes Complete
#   7. Public Smoke Test Bound to Immutable Checksum-Verified RELEASE_DIR
#      (Proving Exact Deployed Bytes & /release-metadata.json Identity)
#   8. Destructive Database Cleanup with Unsuppressed Positive Zero-Table Proof
#      (Restores both original WordPress files and database if DB deletion has
#      begun and any later step fails)
#   9. Atomic Strict JSON Audit Manifest Recording via Same-Directory Temp File,
#      fsync, Strict JSON Validation & Rename (Zero Credentials)
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
TARBALL_PATH="${2:-}"
PRODUCTION_URL="${3:-https://gbafurniture.com}"
GIT_SHA_INPUT="${4:-${GIT_SHA:-}}"
ARTIFACT_SHA256="${5:-${ARTIFACT_SHA256:-}}"

if [ -z "${RELEASE_ID}" ] || [ -z "${TARBALL_PATH}" ]; then
  echo "Usage: $0 <RELEASE_ID> <TARBALL_PATH> [PRODUCTION_URL] [GIT_SHA] [ARTIFACT_SHA256]" >&2
  exit 1
fi

# Validate RELEASE_ID (must start with alphanumeric, contain only [a-zA-Z0-9._-], and no '..')
if [[ ! "${RELEASE_ID}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || [[ "${RELEASE_ID}" == *".."* ]]; then
  echo "CRITICAL ERROR: Invalid RELEASE_ID '${RELEASE_ID}'. Must match ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ without '..'" >&2
  exit 1
fi

# Strip trailing slash and strictly validate PRODUCTION_URL
PRODUCTION_URL="${PRODUCTION_URL%/}"
if [ -z "${PRODUCTION_URL}" ] || [[ ! "${PRODUCTION_URL}" =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]{1,5})?(/[a-zA-Z0-9._/-]*)?$ ]]; then
  echo "CRITICAL ERROR: Invalid PRODUCTION_URL '${PRODUCTION_URL}'. Must match ^https?://[a-zA-Z0-9.-]+(:[0-9]{1,5})?(/[a-zA-Z0-9._/-]*)?$" >&2
  exit 1
fi

# Validate GIT_SHA_INPUT if provided (mandatory when TEST_MODE != 1)
if [ "${TEST_MODE:-0}" != "1" ] && [ -z "${GIT_SHA_INPUT}" ]; then
  echo "CRITICAL ERROR: GIT_SHA is required for production deployment." >&2
  exit 1
fi
if [ -n "${GIT_SHA_INPUT}" ]; then
  if [[ ! "${GIT_SHA_INPUT}" =~ ^[a-zA-Z0-9._-]+$ ]] || [[ "${GIT_SHA_INPUT}" == *".."* ]]; then
    echo "CRITICAL ERROR: Invalid GIT_SHA '${GIT_SHA_INPUT}'. Must match ^[a-zA-Z0-9._-]+$ without '..'" >&2
    exit 1
  fi
fi

# Validate ARTIFACT_SHA256 if provided (mandatory when TEST_MODE != 1)
if [ "${TEST_MODE:-0}" != "1" ] && [ -z "${ARTIFACT_SHA256}" ]; then
  echo "CRITICAL ERROR: ARTIFACT_SHA256 is required for production deployment." >&2
  exit 1
fi
if [ -n "${ARTIFACT_SHA256}" ] && [[ ! "${ARTIFACT_SHA256}" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "CRITICAL ERROR: Invalid ARTIFACT_SHA256 '${ARTIFACT_SHA256}'. Must be a 64-character hex SHA256." >&2
  exit 1
fi

if [ -L "${TARBALL_PATH}" ] || [ ! -f "${TARBALL_PATH}" ]; then
  echo "CRITICAL ERROR: Release tarball not found or is a symlink at '${TARBALL_PATH}'" >&2
  exit 1
fi

# Note: In deployment mode (SMOKE_DEPLOYMENT_MODE=1) with mandatory EXPECTED_METADATA_FILE
# and TRUSTED_ASSET_ROOT (EXPECTED_ASSET_ROOT) exact byte-size/SHA256 binding, smoke-test.sh
# validates JavaScript without requiring a remote 'node' binary ('node --check') on PATH
# because the packaged trusted bytes were syntax-checked in CI.

# ==============================================================================
# 1. Canonical Realpath Guards & Error-Checked Symlink Scan
# ==============================================================================
EXPECTED_DOCROOT="/home/alibhatt/web/gbafurniture.com"
EXPECTED_BACKUP_ROOT="/home/alibhatt/backups/gbafurniture"
EXPECTED_RELEASES_ROOT="/home/alibhatt/releases/gbafurniture"
EXPECTED_LOCK_DIR="/home/alibhatt/.gba-deploy.lock"

if [ "${TEST_MODE:-0}" = "1" ]; then
  RAW_DOCROOT="${GBA_DOCROOT_OVERRIDE:-${EXPECTED_DOCROOT}}"
  RAW_BACKUP_ROOT="${GBA_BACKUP_OVERRIDE:-${EXPECTED_BACKUP_ROOT}}"
  RAW_RELEASES_ROOT="${GBA_RELEASES_OVERRIDE:-${EXPECTED_RELEASES_ROOT}}"
  RAW_LOCK_DIR="${GBA_LOCK_OVERRIDE:-$(dirname "${RAW_DOCROOT%/}")/.gba-deploy.lock}"
else
  if [ -n "${GBA_DOCROOT_OVERRIDE:-}" ] || [ -n "${GBA_BACKUP_OVERRIDE:-}" ] || [ -n "${GBA_RELEASES_OVERRIDE:-}" ] || [ -n "${GBA_SANDBOX_OVERRIDE:-}" ] || [ -n "${GBA_LOCK_OVERRIDE:-}" ] || [ -n "${GBA_STAGE_ROOT_OVERRIDE:-}" ]; then
    echo "CRITICAL ERROR: Path overrides (GBA_*_OVERRIDE) are strictly forbidden when TEST_MODE != 1!" >&2
    exit 1
  fi
  RAW_DOCROOT="${EXPECTED_DOCROOT}"
  RAW_BACKUP_ROOT="${EXPECTED_BACKUP_ROOT}"
  RAW_RELEASES_ROOT="${EXPECTED_RELEASES_ROOT}"
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

verify_static_tree_allowlist() {
  local target_dir="$1"
  local label="$2"
  assert_no_symlinks_in_tree "${target_dir}" "${label}" || return 1
  python3 - "${target_dir}" "${label}" <<'PYEOF'
import os, re, stat, sys

target_dir, label = sys.argv[1:3]

ALLOWED_DIRS = {
    ".",
    "./data",
    "./assets",
    "./assets/placeholders",
}

ALLOWED_FILES = {
    "./index.html",
    "./styles.css",
    "./script.js",
    "./release-metadata.json",
    "./checksums.sha256",
    "./data/products.json",
    "./assets/current-banner.jpg",
    "./assets/gba-logo-official-transparent.png",
    "./assets/gba-logo-web.png",
    "./assets/gba-logo.png",
    "./assets/placeholders/appliance.svg",
    "./assets/placeholders/bed-divan.svg",
    "./assets/placeholders/bed-frame.svg",
    "./assets/placeholders/bunk.svg",
    "./assets/placeholders/chest.svg",
    "./assets/placeholders/coffee-table.svg",
    "./assets/placeholders/dining-table.svg",
    "./assets/placeholders/sofa.svg",
    "./assets/placeholders/van.svg",
    "./assets/placeholders/wardrobe.svg",
}

ALLOWED_EXTENSIONS = {".html", ".css", ".js", ".json", ".sha256", ".jpg", ".png", ".svg"}
TEXT_EXTENSIONS = {".html", ".css", ".js", ".json", ".sha256", ".svg"}
SERVER_CODE_RE = re.compile(rb"(<\?php|<\?=|<script\s+[^>]*language\s*=\s*['\"]?php|^#!/)", re.IGNORECASE)

seen_dirs = set()
seen_files = set()
for dirpath, dirnames, filenames in os.walk(target_dir, followlinks=False):
    rel_d = os.path.relpath(dirpath, target_dir).replace(os.sep, "/")
    norm_d = "." if rel_d == "." else f"./{rel_d}"
    if norm_d not in ALLOWED_DIRS:
        sys.stderr.write(f"CRITICAL ERROR: Unexpected directory '{norm_d}' in {label}!\n")
        sys.exit(1)
    seen_dirs.add(norm_d)
    for fn in filenames:
        full_f = os.path.join(dirpath, fn)
        rel_f = "./" + os.path.relpath(full_f, target_dir).replace(os.sep, "/")
        if os.path.islink(full_f) or not os.path.isfile(full_f):
            sys.stderr.write(f"CRITICAL ERROR: Non-regular or symlink file '{rel_f}' in {label}!\n")
            sys.exit(1)
        if rel_f not in ALLOWED_FILES:
            sys.stderr.write(f"CRITICAL ERROR: Forbidden or unexpected file '{rel_f}' in {label}!\n")
            sys.exit(1)
        _, ext = os.path.splitext(fn)
        if ext.lower() not in ALLOWED_EXTENSIONS:
            sys.stderr.write(f"CRITICAL ERROR: Disallowed file extension '{ext}' on '{rel_f}' in {label}!\n")
            sys.exit(1)
        if ext.lower() in TEXT_EXTENSIONS:
            with open(full_f, "rb") as f:
                data = f.read()
            if SERVER_CODE_RE.search(data):
                sys.stderr.write(f"CRITICAL ERROR: Server-executable code tag found inside '{rel_f}' in {label}!\n")
                sys.exit(1)
        seen_files.add(rel_f)

if seen_dirs != ALLOWED_DIRS or seen_files != ALLOWED_FILES:
    missing = sorted(ALLOWED_FILES - seen_files)
    extra = sorted(seen_files - ALLOWED_FILES)
    sys.stderr.write(f"CRITICAL ERROR: Static allowlist mismatch in {label}: missing={missing}, extra={extra}\n")
    sys.exit(1)
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
BACKUP_ROOT="$(guard_and_canonicalize_dir "${RAW_BACKUP_ROOT}" "BACKUP_ROOT" "1")"
RELEASES_ROOT="$(guard_and_canonicalize_dir "${RAW_RELEASES_ROOT}" "RELEASES_ROOT" "1")"
LOCK_PARENT="$(guard_and_canonicalize_dir "$(dirname "${RAW_LOCK_DIR%/}")" "LOCK_PARENT" "1" "0")"
LOCK_DIR="${LOCK_PARENT}/$(basename "${RAW_LOCK_DIR%/}")"
LOCK_FILE="${LOCK_DIR}"
LOCK_META_FILE="${LOCK_FILE}.meta"

if [ "${TEST_MODE:-0}" != "1" ]; then
  if [ "${DOCROOT}" != "${EXPECTED_DOCROOT}" ] || [ "${BACKUP_ROOT}" != "${EXPECTED_BACKUP_ROOT}" ] || [ "${RELEASES_ROOT}" != "${EXPECTED_RELEASES_ROOT}" ] || [ "${LOCK_DIR}" != "${EXPECTED_LOCK_DIR}" ]; then
    echo "CRITICAL ERROR: Canonical production path guard failed!" >&2
    exit 1
  fi
fi

# Enforce strict separation between DOCROOT, BACKUP_ROOT, and RELEASES_ROOT before creating directories
if paths_overlap "${DOCROOT}" "${BACKUP_ROOT}"; then
  echo "CRITICAL ERROR: BACKUP_ROOT '${BACKUP_ROOT}' overlaps with DOCROOT '${DOCROOT}'!" >&2
  exit 1
fi
if paths_overlap "${DOCROOT}" "${RELEASES_ROOT}"; then
  echo "CRITICAL ERROR: RELEASES_ROOT '${RELEASES_ROOT}' overlaps with DOCROOT '${DOCROOT}'!" >&2
  exit 1
fi
if paths_overlap "${BACKUP_ROOT}" "${RELEASES_ROOT}"; then
  echo "CRITICAL ERROR: BACKUP_ROOT '${BACKUP_ROOT}' overlaps with RELEASES_ROOT '${RELEASES_ROOT}'!" >&2
  exit 1
fi

mkdir -p -- "${DOCROOT}" "${BACKUP_ROOT}" "${RELEASES_ROOT}"
chmod 700 "${BACKUP_ROOT}" "${RELEASES_ROOT}"

# ==============================================================================
# 2. Shared Host-Side OS-Held Lock & Trap Recovery State
# ==============================================================================
LOCK_ACQUIRED=0
LOCK_META_OWNED=0
LOCK_OWNER_TOKEN="$$:$(date -u +%s):${RANDOM}"
TMP_MYCNF=""
TEMP_STAGE_DIR=""
PRE_CUTOVER_RECOVERY_TREE=""
PRE_CUTOVER_RECOVERY_TREE_OWNED=0
PRE_CUTOVER_DIGEST=""
DOCROOT_HAD_FILES=0
HAS_WORDPRESS=0
DB_NAME=""
QUOTED_DB=""
DB_USER=""
DB_PASS=""
DB_HOST=""
FILES_BACKUP_SHA256=""
FILES_BACKUP_SIZE=0
DB_BACKUP_SHA256=""
DB_BACKUP_SIZE=0
BACKUP_STARTED=0
BACKUP_COMPLETED=0
RELEASE_DIR_CREATED=0
MUTATION_STARTED=0
DB_DELETION_STARTED=0
CUTOVER_VERIFIED=0
DEPLOY_COMPLETED=0
RESTORE_ATTEMPTED=0
SIGNAL_EXIT_CODE=""
CLEANUP_IN_PROGRESS=0

RELEASE_DIR="${RELEASES_ROOT}/${RELEASE_ID}"
WP_BACKUP_FILES="${BACKUP_ROOT}/${RELEASE_ID}_files.tar.gz"
WP_BACKUP_DB="${BACKUP_ROOT}/${RELEASE_ID}_db.sql.gz"
MANIFEST_FILE="${BACKUP_ROOT}/${RELEASE_ID}_manifest.json"
ROLLBACK_MANIFEST="${BACKUP_ROOT}/${RELEASE_ID}_rollback_manifest.json"

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
  if ! python3 - "${LOCK_META_FILE}" "${LOCK_OWNER_TOKEN}" "$$" "$(date -u +%s)" "production:${RELEASE_ID}" <<'PYEOF'
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

update_manifest_status() {
  local new_status="$1"
  if [ -n "${MANIFEST_FILE:-}" ] && [ -f "${MANIFEST_FILE}" ] && [ ! -L "${MANIFEST_FILE}" ]; then
    local updated_json=""
    if updated_json="$(python3 - "${MANIFEST_FILE}" "${new_status}" <<'PYEOF'
import json, sys
path, status = sys.argv[1:3]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
data["status"] = status
print(json.dumps(data, indent=2))
PYEOF
    )"; then
      printf '%s\n' "${updated_json}" | write_json_manifest_atomically "${MANIFEST_FILE}" "0" || true
    fi
  fi
}

restore_previous_docroot() {
  if [ "${RESTORE_ATTEMPTED}" -eq 1 ]; then
    return 0
  fi
  RESTORE_ATTEMPTED=1
  set +e

  echo "Initiating automatic restoration of previous production state..." >&2

  python3 - "${DOCROOT}" "${DOCROOT_HAD_FILES}" "${PRE_CUTOVER_RECOVERY_TREE:-}" "${WP_BACKUP_FILES:-}" <<'PYEOF'
import os, shutil, stat, sys, tarfile

docroot, had_files_str, recovery_tree, backup_tar = sys.argv[1:5]
had_files = int(had_files_str) == 1

if not os.path.isdir(docroot) or os.path.islink(docroot):
    sys.stderr.write(f"CRITICAL ERROR: Cannot restore into invalid docroot '{docroot}'\n")
    sys.exit(1)

# Clear partially mutated docroot contents without removing docroot inode itself
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
        sys.stderr.write("CRITICAL ERROR: No valid recovery source available for docroot restore!\n")
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
  if [ "${py_rc}" -eq 0 ] && [ "${sym_ok}" -eq 1 ] && [ "${restored_digest}" = "${PRE_CUTOVER_DIGEST}" ]; then
    echo "✓ Previous docroot state restored and cryptographically verified (${restored_digest})." >&2
    files_ok=1
  else
    echo "CRITICAL ERROR: Docroot restore verification FAILED (expected=${PRE_CUTOVER_DIGEST}, actual=${restored_digest})!" >&2
  fi

  local db_ok=1
  if [ "${HAS_WORDPRESS}" -eq 1 ] && [ "${DB_DELETION_STARTED}" -eq 1 ]; then
    db_ok=0
    echo "DB deletion had begun before failure; restoring original WordPress database '${DB_NAME}' from verified backup '${WP_BACKUP_DB}'..." >&2
    if [ -f "${WP_BACKUP_DB}" ] && [ ! -L "${WP_BACKUP_DB}" ] && [ -s "${WP_BACKUP_DB}" ]; then
      local actual_db_sha=""
      actual_db_sha="$(compute_sha256 "${WP_BACKUP_DB}" 2>/dev/null || true)"
      if [ "${actual_db_sha}" = "${DB_BACKUP_SHA256}" ] && gzip -t "${WP_BACKUP_DB}" 2>/dev/null; then
        if [ "${TEST_MODE:-0}" = "1" ] && [ "${TEST_USE_MYSQL_BIN:-0}" != "1" ]; then
          if [ "${TEST_MOCK_DB_RESTORE_FAIL:-0}" != "1" ]; then
            echo "✓ MOCK: Previous WordPress database '${DB_NAME}' restored from verified backup ${WP_BACKUP_DB}." >&2
            db_ok=1
          fi
        else
          if [ "${TEST_MOCK_DB_RESTORE_FAIL:-0}" != "1" ] && [ -n "${TMP_MYCNF:-}" ] && [ -f "${TMP_MYCNF}" ]; then
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
                else
                  echo "CRITICAL ERROR: Failed to create database ${QUOTED_DB} during recovery and schema count is '${schema_exists_raw}' (expected 1)!" >&2
                fi
              else
                echo "CRITICAL ERROR: Failed to create database ${QUOTED_DB} during recovery and schema existence query failed!" >&2
              fi
            fi
            if [ "${schema_ready}" -eq 1 ] && gunzip -c "${WP_BACKUP_DB}" | mysql --defaults-extra-file="${TMP_MYCNF}" -- "${DB_NAME}" 2>/dev/null; then
              echo "✓ Previous WordPress database '${DB_NAME}' restored from verified backup ${WP_BACKUP_DB}." >&2
              db_ok=1
            fi
          fi
        fi
      fi
    fi
    if [ "${db_ok}" -ne 1 ]; then
      echo "CRITICAL ERROR: Database restore from '${WP_BACKUP_DB}' FAILED after DB deletion began!" >&2
    fi
  fi

  if [ "${files_ok}" -eq 1 ] && [ "${db_ok}" -eq 1 ]; then
    if [ "${DB_DELETION_STARTED}" -eq 1 ]; then
      update_manifest_status "aborted_post_cutover_files_and_db_restored"
    else
      update_manifest_status "aborted_smoke_failed_docroot_restored"
    fi
    # Only remove unpacked recovery tree if the persistent tar archive exists and is non-empty
    if [ "${DOCROOT_HAD_FILES}" -eq 0 ] || [ -s "${WP_BACKUP_FILES}" ]; then
      if [ "${PRE_CUTOVER_RECOVERY_TREE_OWNED:-0}" -eq 1 ] && [ -n "${PRE_CUTOVER_RECOVERY_TREE:-}" ] && [ ! -L "${PRE_CUTOVER_RECOVERY_TREE}" ] && [ -d "${PRE_CUTOVER_RECOVERY_TREE}" ]; then
        rm -rf -- "${PRE_CUTOVER_RECOVERY_TREE}" 2>/dev/null || true
        PRE_CUTOVER_RECOVERY_TREE=""
        PRE_CUTOVER_RECOVERY_TREE_OWNED=0
      fi
    fi
    return 0
  else
    echo "Preserving all recovery evidence:" >&2
    [ -n "${WP_BACKUP_FILES:-}" ] && echo "  Backup Archive: ${WP_BACKUP_FILES}" >&2
    [ -n "${WP_BACKUP_DB:-}" ] && echo "  DB Backup:      ${WP_BACKUP_DB}" >&2
    [ -n "${PRE_CUTOVER_RECOVERY_TREE:-}" ] && echo "  Recovery Tree:  ${PRE_CUTOVER_RECOVERY_TREE}" >&2
    update_manifest_status "aborted_restore_failed_evidence_preserved"
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

  if [ -n "${TEMP_STAGE_DIR:-}" ] && [ ! -L "${TEMP_STAGE_DIR}" ] && [ -d "${TEMP_STAGE_DIR}" ]; then
    rm -rf -- "${TEMP_STAGE_DIR}" 2>/dev/null || true
  fi

  if [ "${exit_code}" -ne 0 ]; then
    if [ "${MUTATION_STARTED}" -eq 1 ] && [ "${CUTOVER_VERIFIED}" -eq 0 ]; then
      restore_previous_docroot || true
    fi
    if [ "${RELEASE_DIR_CREATED}" -eq 1 ] && [ "${CUTOVER_VERIFIED}" -eq 0 ] && [ -n "${RELEASE_DIR:-}" ] && [ ! -L "${RELEASE_DIR}" ] && [ -d "${RELEASE_DIR}" ]; then
      rm -rf -- "${RELEASE_DIR}" 2>/dev/null || true
    fi
    if [ "${BACKUP_STARTED}" -eq 1 ] && [ "${BACKUP_COMPLETED}" -eq 0 ]; then
      rm -f -- "${WP_BACKUP_DB}" "${WP_BACKUP_FILES}" "${MANIFEST_FILE}" 2>/dev/null || true
      if [ "${PRE_CUTOVER_RECOVERY_TREE_OWNED:-0}" -eq 1 ] && [ -n "${PRE_CUTOVER_RECOVERY_TREE:-}" ] && [ ! -L "${PRE_CUTOVER_RECOVERY_TREE}" ] && [ -d "${PRE_CUTOVER_RECOVERY_TREE}" ]; then
        rm -rf -- "${PRE_CUTOVER_RECOVERY_TREE}" 2>/dev/null || true
      fi
    fi
    echo "================================================================================" >&2
    echo "DEPLOYMENT HALTED WITH FAILURE CODE: ${exit_code}" >&2
    echo "================================================================================" >&2
  else
    if [ "${DEPLOY_COMPLETED}" -eq 1 ] && [ "${PRE_CUTOVER_RECOVERY_TREE_OWNED:-0}" -eq 1 ] && [ -n "${PRE_CUTOVER_RECOVERY_TREE:-}" ] && [ ! -L "${PRE_CUTOVER_RECOVERY_TREE}" ] && [ -d "${PRE_CUTOVER_RECOVERY_TREE}" ]; then
      if [ "${DOCROOT_HAD_FILES}" -eq 0 ] || [ -s "${WP_BACKUP_FILES}" ]; then
        rm -rf -- "${PRE_CUTOVER_RECOVERY_TREE}" 2>/dev/null || true
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

# ==============================================================================
# 3. Reject Duplicate Release IDs Before Writes
# ==============================================================================
for existing_artifact in "${RELEASE_DIR}" "${WP_BACKUP_FILES}" "${WP_BACKUP_DB}" "${MANIFEST_FILE}" "${ROLLBACK_MANIFEST}"; do
  if [ -e "${existing_artifact}" ] || [ -L "${existing_artifact}" ]; then
    echo "CRITICAL ERROR: Duplicate RELEASE_ID '${RELEASE_ID}' detected! Artifact '${existing_artifact}' already exists. Refusing to overwrite existing release or backup materials." >&2
    exit 1
  fi
done

# ==============================================================================
# 4. Verify Outer Tarball Checksum, Extract & Bind release-metadata.json
# ==============================================================================
ACTUAL_TARBALL_SHA256="$(compute_sha256 "${TARBALL_PATH}")"
HASH_VERIFIED=0

if [ -n "${ARTIFACT_SHA256}" ]; then
  shopt -s nocasematch
  if [[ "${ACTUAL_TARBALL_SHA256}" != "${ARTIFACT_SHA256}" ]]; then
    shopt -u nocasematch
    echo "CRITICAL ERROR: Tarball SHA256 mismatch!" >&2
    echo "  Expected: ${ARTIFACT_SHA256}" >&2
    echo "  Actual:   ${ACTUAL_TARBALL_SHA256}" >&2
    exit 1
  fi
  shopt -u nocasematch
  HASH_VERIFIED=1
fi

if [ -f "${TARBALL_PATH}.sha256" ]; then
  if [ -L "${TARBALL_PATH}.sha256" ]; then
    echo "CRITICAL ERROR: Companion checksum file '${TARBALL_PATH}.sha256' is a symlink!" >&2
    exit 1
  fi
  COMPANION_HASH="$(awk '{print $1}' "${TARBALL_PATH}.sha256" | head -n1)"
  shopt -s nocasematch
  if [ -z "${COMPANION_HASH}" ] || [[ "${COMPANION_HASH}" != "${ACTUAL_TARBALL_SHA256}" ]]; then
    shopt -u nocasematch
    echo "CRITICAL ERROR: Companion .sha256 file mismatch (${COMPANION_HASH} != ${ACTUAL_TARBALL_SHA256})!" >&2
    exit 1
  fi
  shopt -u nocasematch
  HASH_VERIFIED=1
fi

if [ "${HASH_VERIFIED}" -ne 1 ]; then
  echo "CRITICAL ERROR: No ARTIFACT_SHA256 argument or companion .sha256 file provided to verify '${TARBALL_PATH}'!" >&2
  exit 1
fi
ARTIFACT_SHA256="${ACTUAL_TARBALL_SHA256}"

echo "[Step 1/6] Extracting artifact into staging and verifying candidate integrity before cutover..."
RAW_TEMP_STAGE_DIR="$(mktemp -d)"
TEMP_STAGE_DIR="$(cd -P -- "${RAW_TEMP_STAGE_DIR}" && pwd -P)"
TEMP_STAGE_DIR="$(guard_and_canonicalize_dir "${TEMP_STAGE_DIR}" "TEMP_STAGE_DIR" "0" "1")"

tar -xzf "${TARBALL_PATH}" -C "${TEMP_STAGE_DIR}"
find "${TEMP_STAGE_DIR}" -name '._*' -type f -delete 2>/dev/null || true

assert_no_symlinks_in_tree "${TEMP_STAGE_DIR}" "staged release package"

if [ ! -f "${TEMP_STAGE_DIR}/checksums.sha256" ]; then
  echo "CRITICAL ERROR: checksums.sha256 missing from release package!" >&2
  exit 1
fi

(
  cd "${TEMP_STAGE_DIR}"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c checksums.sha256 >/dev/null
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -c checksums.sha256 >/dev/null
  else
    echo "ERROR: Neither sha256sum nor shasum available to verify checksums." >&2
    exit 1
  fi
)
echo "✓ All packaged SHA256 checksums verified successfully on remote host."

verify_static_tree_allowlist "${TEMP_STAGE_DIR}" "staged release package"

# Strictly parse release-metadata.json and bind release_id, git_sha, and tree_sha256
META_PARSED="$(python3 - "${TEMP_STAGE_DIR}" "${RELEASE_ID}" "${GIT_SHA_INPUT}" <<'PYEOF'
import hashlib, json, os, re, sys

stage_dir, expected_rel, expected_sha = sys.argv[1:4]
meta_path = os.path.join(stage_dir, "release-metadata.json")

def no_dups(pairs):
    obj = {}
    for k, v in pairs:
        if k in obj:
            raise ValueError(f"Duplicate key '{k}' in release-metadata.json")
        obj[k] = v
    return obj

with open(meta_path, "r", encoding="utf-8") as f:
    meta = json.loads(f.read(), object_pairs_hook=no_dups)

if not isinstance(meta, dict):
    sys.stderr.write("CRITICAL ERROR: release-metadata.json must be a JSON object!\n")
    sys.exit(1)

meta_rel = meta.get("release_id", "")
meta_sha = meta.get("git_sha", "")
meta_tree = meta.get("tree_sha256", "")

if not isinstance(meta_rel, str) or not re.match(r"^[a-zA-Z0-9][a-zA-Z0-9._-]*$", meta_rel) or ".." in meta_rel:
    sys.stderr.write(f"CRITICAL ERROR: Invalid release_id in release-metadata.json: {meta_rel!r}\n")
    sys.exit(1)
if not isinstance(meta_sha, str) or not re.match(r"^[a-zA-Z0-9._-]+$", meta_sha) or ".." in meta_sha:
    sys.stderr.write(f"CRITICAL ERROR: Invalid git_sha in release-metadata.json: {meta_sha!r}\n")
    sys.exit(1)

if meta_rel != expected_rel:
    sys.stderr.write(f"CRITICAL ERROR: release-metadata.json release_id '{meta_rel}' does not match invocation RELEASE_ID '{expected_rel}'!\n")
    sys.exit(1)

if expected_sha and expected_sha != "unspecified" and meta_sha != expected_sha:
    sys.stderr.write(f"CRITICAL ERROR: release-metadata.json git_sha '{meta_sha}' does not match invocation GIT_SHA '{expected_sha}'!\n")
    sys.exit(1)

records = []
for dirpath, dirnames, filenames in os.walk(stage_dir, followlinks=False):
    dirnames.sort()
    filenames.sort()
    for fn in filenames:
        if fn in ("release-metadata.json", "checksums.sha256"):
            continue
        full = os.path.join(dirpath, fn)
        rel = "./" + os.path.relpath(full, stage_dir).replace(os.sep, "/")
        h = hashlib.sha256()
        with open(full, "rb") as rf:
            for chunk in iter(lambda: rf.read(65536), b""):
                h.update(chunk)
        records.append(f"{h.hexdigest()}  {rel}")
records.sort()
actual_tree = hashlib.sha256(("\n".join(records) + "\n").encode("utf-8")).hexdigest()

if meta_tree and meta_tree != actual_tree:
    sys.stderr.write(f"CRITICAL ERROR: release-metadata.json tree_sha256 '{meta_tree}' != actual '{actual_tree}'!\n")
    sys.exit(1)

print(f"{meta_rel}\n{meta_sha}\n{actual_tree}")
PYEOF
)"

META_RELEASE_ID="$(printf '%s\n' "${META_PARSED}" | sed -n '1p')"
META_GIT_SHA="$(printf '%s\n' "${META_PARSED}" | sed -n '2p')"
META_TREE_SHA256="$(printf '%s\n' "${META_PARSED}" | sed -n '3p')"
GIT_SHA="${META_GIT_SHA}"

echo "================================================================================"
echo "GBA Furniture: Starting Production Deployment"
echo "Release ID:    ${RELEASE_ID}"
echo "Git SHA:       ${GIT_SHA}"
echo "Docroot:       ${DOCROOT}"
echo "Backup Root:   ${BACKUP_ROOT} (strictly outside docroot)"
echo "Releases Root: ${RELEASES_ROOT}"
echo "URL:           ${PRODUCTION_URL}"
echo "================================================================================"
echo "✓ Outer tarball SHA256 matches expected checksum: ${ACTUAL_TARBALL_SHA256}"

REQUIRED_STATIC=(
  "index.html"
  "styles.css"
  "script.js"
  "data/products.json"
  "assets/gba-logo-official-transparent.png"
  "assets/gba-logo-web.png"
  "assets/current-banner.jpg"
  "assets/placeholders/bed-divan.svg"
  "release-metadata.json"
)

for f in "${REQUIRED_STATIC[@]}"; do
  if [ ! -s "${TEMP_STAGE_DIR}/${f}" ]; then
    echo "CRITICAL ERROR: Required file '${f}' missing or empty in release package!" >&2
    exit 1
  fi
done

# Verify candidate content markers before touching backups or docroot
grep -F -q -- "GBA Furniture" "${TEMP_STAGE_DIR}/index.html" || { echo "CRITICAL ERROR: Candidate index.html missing brand title" >&2; exit 1; }
grep -F -q -- "assets/gba-logo-official-transparent.png" "${TEMP_STAGE_DIR}/index.html" || { echo "CRITICAL ERROR: Candidate index.html missing official transparent logo reference" >&2; exit 1; }
grep -F -q -- "020 8888 0322" "${TEMP_STAGE_DIR}/index.html" || { echo "CRITICAL ERROR: Candidate index.html missing telephone" >&2; exit 1; }
grep -F -q -- "401 Lordship Lane" "${TEMP_STAGE_DIR}/index.html" || { echo "CRITICAL ERROR: Candidate index.html missing address" >&2; exit 1; }
grep -F -q -- "--color-petrol" "${TEMP_STAGE_DIR}/styles.css" || { echo "CRITICAL ERROR: Candidate styles.css missing brand variables" >&2; exit 1; }
grep -F -q -- "products" "${TEMP_STAGE_DIR}/script.js" || { echo "CRITICAL ERROR: Candidate script.js missing catalogue logic" >&2; exit 1; }
grep -F -q -- "beds-mattresses" "${TEMP_STAGE_DIR}/data/products.json" || { echo "CRITICAL ERROR: Candidate data/products.json missing category data" >&2; exit 1; }
grep -F -q -- "<svg" "${TEMP_STAGE_DIR}/assets/placeholders/bed-divan.svg" || { echo "CRITICAL ERROR: Candidate SVG asset invalid" >&2; exit 1; }

echo "✓ Staged candidate structure, allowlist, and release identity verified before cutover."

# ==============================================================================
# 5. Secure WordPress & Database Backup (Outside Docroot)
# ==============================================================================
WP_CONFIG="${DOCROOT}/wp-config.php"

PRE_CUTOVER_DIGEST="$(compute_tree_digest "${DOCROOT}")"
if [ "${PRE_CUTOVER_DIGEST}" = "INVALID" ]; then
  echo "CRITICAL ERROR: Failed to compute pre-cutover digest of DOCROOT '${DOCROOT}'!" >&2
  exit 1
fi

if [ -f "${WP_CONFIG}" ]; then
  if [ -L "${WP_CONFIG}" ]; then
    echo "CRITICAL ERROR: ${WP_CONFIG} is a symlink! Aborting." >&2
    exit 1
  fi
  HAS_WORDPRESS=1
  DOCROOT_HAD_FILES=1
  echo "[Step 2/6] WordPress installation detected in docroot. Validating DB identifiers and securing backup outside docroot..."

  # Extract DB credentials safely without pipeline SIGPIPE
  DB_NAME="$(sed -n -E "/define\([[:space:]]*['\"]DB_NAME['\"]/{s/.*['\"]DB_NAME['\"][[:space:]]*,[[:space:]]*['\"]([^'\"]+)['\"].*/\1/p;q;}" "${WP_CONFIG}")"
  DB_USER="$(sed -n -E "/define\([[:space:]]*['\"]DB_USER['\"]/{s/.*['\"]DB_USER['\"][[:space:]]*,[[:space:]]*['\"]([^'\"]+)['\"].*/\1/p;q;}" "${WP_CONFIG}")"
  DB_PASS="$(sed -n -E "/define\([[:space:]]*['\"]DB_PASSWORD['\"]/{s/.*['\"]DB_PASSWORD['\"][[:space:]]*,[[:space:]]*['\"]([^'\"]+)['\"].*/\1/p;q;}" "${WP_CONFIG}")"
  DB_HOST="$(sed -n -E "/define\([[:space:]]*['\"]DB_HOST['\"]/{s/.*['\"]DB_HOST['\"][[:space:]]*,[[:space:]]*['\"]([^'\"]+)['\"].*/\1/p;q;}" "${WP_CONFIG}")"
  DB_HOST="${DB_HOST:-localhost}"

  if [ -z "${DB_NAME}" ] || [ -z "${DB_USER}" ]; then
    echo "CRITICAL ERROR: Failed to securely parse DB credentials from ${WP_CONFIG}" >&2
    exit 1
  fi

  validate_sql_identifier "${DB_NAME}" "DB_NAME"
  QUOTED_DB="$(quote_sql_ident "${DB_NAME}" "DB_NAME")"

  if [[ ! "${DB_USER}" =~ ^[a-zA-Z0-9_.-]{1,80}$ ]]; then
    echo "CRITICAL ERROR: Invalid DB_USER '${DB_USER}' in ${WP_CONFIG}" >&2
    exit 1
  fi

  if [[ ! "${DB_HOST}" =~ ^[a-zA-Z0-9_.:-]+$ ]]; then
    echo "CRITICAL ERROR: Invalid DB_HOST '${DB_HOST}' in ${WP_CONFIG}" >&2
    exit 1
  fi

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

  BACKUP_STARTED=1
  echo "Backing up WordPress database '${DB_NAME}' (${QUOTED_DB}) to ${WP_BACKUP_DB}..."
  if [ "${TEST_MODE:-0}" = "1" ] && [ "${TEST_USE_MYSQL_BIN:-0}" != "1" ]; then
    if [ "${TEST_CORRUPT_DB_BACKUP:-0}" = "1" ]; then
      echo "CORRUPTED_GZIP_MOCK" > "${WP_BACKUP_DB}"
    else
      printf -- '-- Mock dump for %s\nCREATE TABLE `wp_posts` (`id` int);\n' "${QUOTED_DB}" | gzip -9 > "${WP_BACKUP_DB}"
    fi
  else
    mysqldump --defaults-extra-file="${TMP_MYCNF}" --single-transaction --routines --triggers --quick -- "${DB_NAME}" | gzip -9 > "${WP_BACKUP_DB}"
  fi
  chmod 600 "${WP_BACKUP_DB}"

  if [ ! -s "${WP_BACKUP_DB}" ]; then
    echo "CRITICAL ERROR: Database dump produced empty file! Halting deployment." >&2
    exit 1
  fi

  echo "Verifying database backup gzip integrity..."
  if ! gzip -t "${WP_BACKUP_DB}"; then
    echo "CRITICAL ERROR: Database backup archive ${WP_BACKUP_DB} failed gzip integrity check (corrupt archive)! Halting deployment before cutover." >&2
    exit 1
  fi

  DB_BACKUP_SHA256="$(compute_sha256 "${WP_BACKUP_DB}")"
  DB_BACKUP_SIZE="$(wc -c < "${WP_BACKUP_DB}" | tr -d ' ')"
  echo "✓ Database backup complete & verified valid gzip. Size: $(du -h "${WP_BACKUP_DB}" | cut -f1)"

  echo "Backing up docroot files to ${WP_BACKUP_FILES}..."
  (
    cd "${DOCROOT}"
    COPYFILE_DISABLE=1 tar -czf "${WP_BACKUP_FILES}" .
  )
  chmod 600 "${WP_BACKUP_FILES}"

  if [ ! -s "${WP_BACKUP_FILES}" ]; then
    echo "CRITICAL ERROR: Files backup archive produced empty file! Halting deployment." >&2
    exit 1
  fi

  echo "Verifying docroot files tar archive integrity..."
  if ! tar -tzf "${WP_BACKUP_FILES}" >/dev/null; then
    echo "CRITICAL ERROR: Files backup archive ${WP_BACKUP_FILES} failed tar integrity check! Halting deployment before cutover." >&2
    exit 1
  fi

  FILES_BACKUP_SHA256="$(compute_sha256 "${WP_BACKUP_FILES}")"
  FILES_BACKUP_SIZE="$(wc -c < "${WP_BACKUP_FILES}" | tr -d ' ')"
  echo "✓ Docroot files backup complete & verified valid tar. Size: $(du -h "${WP_BACKUP_FILES}" | cut -f1)"

  CANDIDATE_RECOVERY_TREE="${BACKUP_ROOT}/${RELEASE_ID}_recovery_tree"
  if [ -e "${CANDIDATE_RECOVERY_TREE}" ] || [ -L "${CANDIDATE_RECOVERY_TREE}" ]; then
    echo "CRITICAL ERROR: Pre-cutover recovery tree path '${CANDIDATE_RECOVERY_TREE}' already exists!" >&2
    exit 1
  fi
  mkdir -m 700 -- "${CANDIDATE_RECOVERY_TREE}"
  PRE_CUTOVER_RECOVERY_TREE="${CANDIDATE_RECOVERY_TREE}"
  PRE_CUTOVER_RECOVERY_TREE_OWNED=1
  tar -xzf "${WP_BACKUP_FILES}" -C "${PRE_CUTOVER_RECOVERY_TREE}"
  assert_no_symlinks_in_tree "${PRE_CUTOVER_RECOVERY_TREE}" "PRE_CUTOVER_RECOVERY_TREE"
  if [ "$(compute_tree_digest "${PRE_CUTOVER_RECOVERY_TREE}")" != "${PRE_CUTOVER_DIGEST}" ]; then
    echo "CRITICAL ERROR: Pre-cutover recovery tree digest mismatch!" >&2
    exit 1
  fi

  write_json_manifest_atomically "${MANIFEST_FILE}" "0" <<EOF
{
  "release_id": "${RELEASE_ID}",
  "git_sha": "${GIT_SHA}",
  "artifact_name": "$(basename "${TARBALL_PATH}")",
  "artifact_sha256": "${ARTIFACT_SHA256}",
  "timestamp_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "docroot": "${DOCROOT}",
  "db_required": true,
  "files_backup": "${WP_BACKUP_FILES}",
  "files_backup_sha256": "${FILES_BACKUP_SHA256}",
  "files_backup_size_bytes": ${FILES_BACKUP_SIZE},
  "db_backup": "${WP_BACKUP_DB}",
  "db_backup_sha256": "${DB_BACKUP_SHA256}",
  "db_backup_size_bytes": ${DB_BACKUP_SIZE},
  "db_name": "${DB_NAME}",
  "db_user": "${DB_USER}",
  "db_host": "${DB_HOST}",
  "status": "backed_up_pre_cutover"
}
EOF
  BACKUP_COMPLETED=1
else
  echo "[Step 2/6] No WordPress wp-config.php found in docroot. Checking existing files..."
  if [ -d "${DOCROOT}" ] && [ -n "$(ls -A "${DOCROOT}" 2>/dev/null)" ]; then
    DOCROOT_HAD_FILES=1
    BACKUP_STARTED=1
    (
      cd "${DOCROOT}"
      COPYFILE_DISABLE=1 tar -czf "${WP_BACKUP_FILES}" .
    )
    chmod 600 "${WP_BACKUP_FILES}"

    echo "Verifying existing files tar archive integrity..."
    if ! tar -tzf "${WP_BACKUP_FILES}" >/dev/null; then
      echo "CRITICAL ERROR: Existing files backup failed tar integrity check! Halting deployment before cutover." >&2
      exit 1
    fi
    FILES_BACKUP_SHA256="$(compute_sha256 "${WP_BACKUP_FILES}")"
    FILES_BACKUP_SIZE="$(wc -c < "${WP_BACKUP_FILES}" | tr -d ' ')"
    echo "✓ Existing files backup complete: ${WP_BACKUP_FILES}"

    CANDIDATE_RECOVERY_TREE="${BACKUP_ROOT}/${RELEASE_ID}_recovery_tree"
    if [ -e "${CANDIDATE_RECOVERY_TREE}" ] || [ -L "${CANDIDATE_RECOVERY_TREE}" ]; then
      echo "CRITICAL ERROR: Pre-cutover recovery tree path '${CANDIDATE_RECOVERY_TREE}' already exists!" >&2
      exit 1
    fi
    mkdir -m 700 -- "${CANDIDATE_RECOVERY_TREE}"
    PRE_CUTOVER_RECOVERY_TREE="${CANDIDATE_RECOVERY_TREE}"
    PRE_CUTOVER_RECOVERY_TREE_OWNED=1
    tar -xzf "${WP_BACKUP_FILES}" -C "${PRE_CUTOVER_RECOVERY_TREE}"
    assert_no_symlinks_in_tree "${PRE_CUTOVER_RECOVERY_TREE}" "PRE_CUTOVER_RECOVERY_TREE"
    if [ "$(compute_tree_digest "${PRE_CUTOVER_RECOVERY_TREE}")" != "${PRE_CUTOVER_DIGEST}" ]; then
      echo "CRITICAL ERROR: Pre-cutover recovery tree digest mismatch!" >&2
      exit 1
    fi

    write_json_manifest_atomically "${MANIFEST_FILE}" "0" <<EOF
{
  "release_id": "${RELEASE_ID}",
  "git_sha": "${GIT_SHA}",
  "artifact_name": "$(basename "${TARBALL_PATH}")",
  "artifact_sha256": "${ARTIFACT_SHA256}",
  "timestamp_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "docroot": "${DOCROOT}",
  "db_required": false,
  "files_backup": "${WP_BACKUP_FILES}",
  "files_backup_sha256": "${FILES_BACKUP_SHA256}",
  "files_backup_size_bytes": ${FILES_BACKUP_SIZE},
  "status": "backed_up_pre_cutover"
}
EOF
    BACKUP_COMPLETED=1
  else
    BACKUP_COMPLETED=1
  fi
fi

# ==============================================================================
# 6. Stage Release Candidate into Releases Store & Atomically Cutover Docroot
# ==============================================================================
echo "[Step 3/6] Staging verified candidate in ${RELEASE_DIR} and cutting over ${DOCROOT}..."
mkdir -m 755 -- "${RELEASE_DIR}"
RELEASE_DIR_CREATED=1
cp -R "${TEMP_STAGE_DIR}/." "${RELEASE_DIR}/"

find "${RELEASE_DIR}" -type d -exec chmod 755 {} +
find "${RELEASE_DIR}" -type f -exec chmod 644 {} +

verify_static_tree_allowlist "${RELEASE_DIR}" "RELEASE_DIR"

(
  cd "${RELEASE_DIR}"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c checksums.sha256 >/dev/null
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -c checksums.sha256 >/dev/null
  else
    echo "ERROR: Neither sha256sum nor shasum available to verify checksums in RELEASE_DIR." >&2
    exit 1
  fi
)

for f in "${REQUIRED_STATIC[@]}"; do
  if [ ! -s "${RELEASE_DIR}/${f}" ] || [ -L "${RELEASE_DIR}/${f}" ]; then
    echo "CRITICAL ERROR: Staged candidate file '${RELEASE_DIR}/${f}' missing or invalid before cutover!" >&2
    exit 1
  fi
done

# Mutation begins here: ANY error in rsync, metadata copy, chmod, post-copy verify,
# smoke test, DB cleanup, or final manifest write will automatically trigger
# restore_previous_docroot (including DB restoration if DB_DELETION_STARTED=1) via EXIT trap.
MUTATION_STARTED=1

rsync -a --delete --delay-updates "${RELEASE_DIR}/" "${DOCROOT}/"
cp "${RELEASE_DIR}/release-metadata.json" "${DOCROOT}/release-metadata.json"

find "${DOCROOT}" -type d -exec chmod 755 {} +
find "${DOCROOT}" -type f -exec chmod 644 {} +

verify_static_tree_allowlist "${DOCROOT}" "deployed DOCROOT"

if [ "$(compute_sha256 "${DOCROOT}/release-metadata.json")" != "$(compute_sha256 "${RELEASE_DIR}/release-metadata.json")" ]; then
  echo "CRITICAL ERROR: Deployed release-metadata.json in DOCROOT does not match staged release candidate!" >&2
  exit 1
fi

echo "✓ Static site candidate atomically installed into ${DOCROOT}"

# ==============================================================================
# 7. Verify Public Homepage, Assets & Exact Release Identity (Smoke Test)
# ==============================================================================
echo "[Step 4/6] Verifying public homepage and assets via smoke tests..."
SMOKE_TEST_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/smoke-test.sh"

SMOKE_PASSED=1
if [ -f "${SMOKE_TEST_SCRIPT}" ]; then
  if ! SMOKE_DEPLOYMENT_MODE="1" \
       EXPECTED_RELEASE_ID="${RELEASE_ID}" \
       EXPECTED_GIT_SHA="${GIT_SHA}" \
       EXPECTED_TREE_SHA256="${META_TREE_SHA256}" \
       EXPECTED_METADATA_FILE="${RELEASE_DIR}/release-metadata.json" \
       TRUSTED_ASSET_ROOT="${RELEASE_DIR}" \
       EXPECTED_ASSET_ROOT="${RELEASE_DIR}" \
       bash "${SMOKE_TEST_SCRIPT}" "${PRODUCTION_URL}"; then
    SMOKE_PASSED=0
  fi
else
  SMOKE_PASSED=0
fi

if [ "${SMOKE_PASSED}" -ne 1 ]; then
  echo "================================================================================" >&2
  echo "CRITICAL ERROR: Smoke test verification failed against ${PRODUCTION_URL}!" >&2
  restore_previous_docroot
  echo "Old database has NOT been dropped. Previous docroot has been automatically restored." >&2
  echo "================================================================================" >&2
  exit 1
fi

echo "✓ Public verification succeeded across all endpoints."

# ==============================================================================
# 8. Drop Old Database & Positively Verify DB Absent or Zero Tables
#    (Transaction recovery remains active until DB cleanup & final manifest complete!)
# ==============================================================================
DB_CLEANUP_METHOD="none"
DB_STILL_EXISTS=false
REMAINING_TABLES_COUNT=0

if [ "${HAS_WORDPRESS}" -eq 1 ]; then
  echo "[Step 5/6] Verification passed. Dropping old WordPress database '${DB_NAME}' (${QUOTED_DB})..."

  if [ ! -s "${WP_BACKUP_DB}" ] || ! gzip -t "${WP_BACKUP_DB}"; then
    echo "CRITICAL SAFETY ABORT: Database backup file '${WP_BACKUP_DB}' missing, empty, or invalid gzip! Refusing to drop DB." >&2
    exit 1
  fi

  DB_DELETION_STARTED=1

  if [ "${TEST_MODE:-0}" = "1" ] && [ "${TEST_USE_MYSQL_BIN:-0}" != "1" ]; then
    if [ "${TEST_MOCK_MYSQL_VERIFY_FAIL:-0}" = "1" ]; then
      echo "CRITICAL ERROR: Simulated MySQL verification command failure (connection/query error)!" >&2
      exit 1
    elif [ "${TEST_MOCK_DB_FAIL:-0}" = "1" ]; then
      echo "MOCK: Simulating DROP failure where tables remain."
      DB_STILL_EXISTS=true
      REMAINING_TABLES_COUNT=5
    else
      echo "MOCK: Database '${DB_NAME}' dropped successfully."
      DB_CLEANUP_METHOD="database_dropped"
      DB_STILL_EXISTS=false
      REMAINING_TABLES_COUNT=0
    fi
  else
    # Attempt 1: DROP DATABASE using safely quoted identifier
    if mysql --defaults-extra-file="${TMP_MYCNF}" -e "DROP DATABASE ${QUOTED_DB};"; then
      echo "✓ Database '${DB_NAME}' successfully dropped."
      DB_CLEANUP_METHOD="database_dropped"
    else
      echo "Notice: DROP DATABASE not permitted by user grant; attempting table-by-table drop in ${QUOTED_DB}..."
      if ! TABLES="$(mysql --defaults-extra-file="${TMP_MYCNF}" -N -B -e "SHOW TABLES FROM ${QUOTED_DB};")"; then
        echo "CRITICAL ERROR: Failed to list tables from ${QUOTED_DB} during fallback cleanup!" >&2
        exit 1
      fi

      if [ -n "${TABLES}" ]; then
        DROP_CMD="SET FOREIGN_KEY_CHECKS = 0;"
        while IFS= read -r tbl; do
          if [ -z "${tbl}" ]; then
            continue
          fi
          QUOTED_TBL="$(quote_sql_ident "${tbl}" "table name")"
          DROP_CMD="${DROP_CMD} DROP TABLE IF EXISTS ${QUOTED_DB}.${QUOTED_TBL};"
        done <<< "${TABLES}"
        DROP_CMD="${DROP_CMD} SET FOREIGN_KEY_CHECKS = 1;"

        if ! mysql --defaults-extra-file="${TMP_MYCNF}" -e "${DROP_CMD}"; then
          echo "CRITICAL ERROR: Failed to drop tables in ${QUOTED_DB}!" >&2
          exit 1
        fi
        DB_CLEANUP_METHOD="all_tables_purged"
      else
        echo "Notice: Database '${DB_NAME}' had 0 tables."
        DB_CLEANUP_METHOD="tables_already_empty"
      fi
    fi

    if ! SCHEMA_COUNT_RAW="$(mysql --defaults-extra-file="${TMP_MYCNF}" -N -B -e "SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '${DB_NAME}';")"; then
      echo "CRITICAL ERROR: MySQL post-cleanup schema verification query failed!" >&2
      exit 1
    fi
    SCHEMA_COUNT="$(printf '%s' "${SCHEMA_COUNT_RAW}" | tr -d '[:space:]')"
    if [[ ! "${SCHEMA_COUNT}" =~ ^[01]$ ]]; then
      echo "CRITICAL ERROR: Unexpected output from MySQL schema verification query: '${SCHEMA_COUNT_RAW}'" >&2
      exit 1
    fi

    if [ "${SCHEMA_COUNT}" = "0" ]; then
      DB_STILL_EXISTS=false
      REMAINING_TABLES_COUNT=0
      echo "✓ Positively verified via INFORMATION_SCHEMA: Database '${DB_NAME}' is absent (SCHEMA_COUNT=0)."
    else
      DB_STILL_EXISTS=true
      if ! TABLE_COUNT_RAW="$(mysql --defaults-extra-file="${TMP_MYCNF}" -N -B -e "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = '${DB_NAME}';")"; then
        echo "CRITICAL ERROR: MySQL post-cleanup table count verification query failed!" >&2
        exit 1
      fi
      TABLE_COUNT="$(printf '%s' "${TABLE_COUNT_RAW}" | tr -d '[:space:]')"
      if [[ ! "${TABLE_COUNT}" =~ ^[0-9]+$ ]]; then
        echo "CRITICAL ERROR: Unexpected output from MySQL table count query: '${TABLE_COUNT_RAW}'" >&2
        exit 1
      fi

      if ! REMAINING_TABLES_LIST="$(mysql --defaults-extra-file="${TMP_MYCNF}" -N -B -e "SHOW TABLES FROM ${QUOTED_DB};")"; then
        echo "CRITICAL ERROR: MySQL SHOW TABLES verification query failed!" >&2
        exit 1
      fi

      REMAINING_TABLES_COUNT="${TABLE_COUNT}"
      if [ -n "${REMAINING_TABLES_LIST}" ] && [ "${REMAINING_TABLES_COUNT}" -eq 0 ]; then
        REMAINING_TABLES_COUNT="$(printf '%s\n' "${REMAINING_TABLES_LIST}" | sed '/^$/d' | wc -l | tr -d ' ')"
      fi
    fi
  fi

  if [ "${REMAINING_TABLES_COUNT}" -ne 0 ]; then
    echo "================================================================================" >&2
    echo "CRITICAL ERROR: Destructive database cleanup failed!" >&2
    echo "Database '${DB_NAME}' still exists and contains ${REMAINING_TABLES_COUNT} table(s)." >&2
    echo "Treating destructive cleanup failure as an aborted deployment step." >&2
    echo "================================================================================" >&2
    exit 1
  fi

  echo "✓ Destructive database cleanup positively verified: database absent or contains 0 tables."

  # ============================================================================
  # 9. Record Production Audit Manifest Atomically (No In-Place Truncation)
  # ============================================================================
  echo "[Step 6/6] Updating audit manifest with post-cutover evidence..."
  write_json_manifest_atomically "${MANIFEST_FILE}" "1" <<EOF
{
  "release_id": "${RELEASE_ID}",
  "git_sha": "${GIT_SHA}",
  "artifact_name": "$(basename "${TARBALL_PATH}")",
  "artifact_sha256": "${ARTIFACT_SHA256}",
  "timestamp_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "docroot": "${DOCROOT}",
  "db_required": true,
  "files_backup": "${WP_BACKUP_FILES}",
  "files_backup_sha256": "${FILES_BACKUP_SHA256}",
  "files_backup_size_bytes": ${FILES_BACKUP_SIZE},
  "db_backup": "${WP_BACKUP_DB}",
  "db_backup_sha256": "${DB_BACKUP_SHA256}",
  "db_backup_size_bytes": ${DB_BACKUP_SIZE},
  "db_name": "${DB_NAME}",
  "db_user": "${DB_USER}",
  "db_host": "${DB_HOST}",
  "db_cleanup_status": "${DB_CLEANUP_METHOD}",
  "db_still_exists": ${DB_STILL_EXISTS},
  "db_remaining_tables_count": ${REMAINING_TABLES_COUNT},
  "status": "production_live_db_purged",
  "verified_url": "${PRODUCTION_URL}",
  "smoke_test_status": "passed"
}
EOF
else
  echo "[Step 5/6] No WordPress database to drop. Skipping DB cleanup."
  echo "[Step 6/6] Finalizing deployment manifest..."
  if [ -f "${MANIFEST_FILE}" ]; then
    write_json_manifest_atomically "${MANIFEST_FILE}" "1" <<EOF
{
  "release_id": "${RELEASE_ID}",
  "git_sha": "${GIT_SHA}",
  "artifact_name": "$(basename "${TARBALL_PATH}")",
  "artifact_sha256": "${ARTIFACT_SHA256}",
  "timestamp_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "docroot": "${DOCROOT}",
  "db_required": false,
  "files_backup": "${WP_BACKUP_FILES}",
  "files_backup_sha256": "${FILES_BACKUP_SHA256}",
  "files_backup_size_bytes": ${FILES_BACKUP_SIZE},
  "status": "production_live_no_db",
  "verified_url": "${PRODUCTION_URL}",
  "smoke_test_status": "passed"
}
EOF
  fi
fi

# Only mark cutover verified and deployment completed AFTER all DB cleanup and final manifest writes succeed!
CUTOVER_VERIFIED=1
DEPLOY_COMPLETED=1

echo "================================================================================"
echo "PRODUCTION DEPLOYMENT SUCCESSFUL: ${RELEASE_ID}"
echo "Git SHA:       ${GIT_SHA}"
echo "Artifact Hash: ${ARTIFACT_SHA256}"
echo "Static site is live at: ${PRODUCTION_URL}"
echo "Rollback materials safely retained outside docroot:"
echo "  Files Archive: ${WP_BACKUP_FILES}"
if [ "${HAS_WORDPRESS}" -eq 1 ]; then
  echo "  Database Dump: ${WP_BACKUP_DB}"
  echo "  Manifest:      ${MANIFEST_FILE}"
  echo "  DB Cleanup:    ${DB_CLEANUP_METHOD} (Remaining tables: ${REMAINING_TABLES_COUNT})"
fi
echo "================================================================================"
