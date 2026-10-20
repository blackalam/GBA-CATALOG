#!/usr/bin/env bash
# ==============================================================================
# GBA Furniture — Sandbox Release-Preview Deployment Script
#
# Usage:
#   ./scripts/remote-deploy-sandbox.sh <TARBALL_PATH> [PREVIEW_URL] [ARTIFACT_SHA256] [RELEASE_ID] [GIT_SHA]
#
# Process:
#   1. Strict URL & Input Validation
#   2. Canonical Realpath Guards & Error-Checked Symlink Scan (Sandbox outside
#      docroot at /home/alibhatt/sandbox/gbafurniture and recovery root at
#      /home/alibhatt/sandbox/.gba-sandbox-recovery; overrides ONLY in TEST_MODE=1)
#   3. Shared Host-Side OS-Held Lock (/home/alibhatt/.gba-deploy.lock) via
#      nonblocking flock on a canonical regular file with stable fd & separate
#      atomic owner metadata
#   4. Outer Archive Checksum Verification
#   5. Staged Extraction, Exhaustive Static-Only Allowlist (Zero PHP/Executables),
#      Packaged Checksum Verification & release-metadata.json Binding
#   6. Exclusive Invocation-Owned Pre-Cutover Recovery Archive & Tree with
#      Trap-Driven Recovery Covering Every Error After Mutation Begins
#   7. Public Smoke Test Proving Exact Deployed Identity (/release-metadata.json)
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

TARBALL_PATH="${1:-}"
PREVIEW_URL="${2:-https://gbafurniture.com/release-preview}"
ARTIFACT_SHA256="${3:-${ARTIFACT_SHA256:-}}"
RELEASE_ID_INPUT="${4:-${RELEASE_ID:-}}"
GIT_SHA_INPUT="${5:-${GIT_SHA:-}}"

if [ -z "${TARBALL_PATH}" ]; then
  echo "Usage: $0 <TARBALL_PATH> [PREVIEW_URL] [ARTIFACT_SHA256] [RELEASE_ID] [GIT_SHA]" >&2
  exit 1
fi

# Strip trailing slash from PREVIEW_URL and validate strictly
PREVIEW_URL="${PREVIEW_URL%/}"
if [ -z "${PREVIEW_URL}" ] || [[ ! "${PREVIEW_URL}" =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]{1,5})?(/[a-zA-Z0-9._/-]*)?$ ]]; then
  echo "CRITICAL ERROR: Invalid PREVIEW_URL '${PREVIEW_URL}'. Must match ^https?://[a-zA-Z0-9.-]+(:[0-9]{1,5})?(/[a-zA-Z0-9._/-]*)?$" >&2
  exit 1
fi

if [ "${TEST_MODE:-0}" != "1" ] && [ -z "${ARTIFACT_SHA256}" ]; then
  echo "CRITICAL ERROR: ARTIFACT_SHA256 is required for sandbox deployment." >&2
  exit 1
fi
if [ -n "${ARTIFACT_SHA256}" ] && [[ ! "${ARTIFACT_SHA256}" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "CRITICAL ERROR: Invalid ARTIFACT_SHA256 '${ARTIFACT_SHA256}'. Must be a 64-character hex SHA256." >&2
  exit 1
fi

if [ -n "${RELEASE_ID_INPUT}" ]; then
  if [[ ! "${RELEASE_ID_INPUT}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || [[ "${RELEASE_ID_INPUT}" == *".."* ]]; then
    echo "CRITICAL ERROR: Invalid RELEASE_ID '${RELEASE_ID_INPUT}'." >&2
    exit 1
  fi
fi

if [ -n "${GIT_SHA_INPUT}" ]; then
  if [[ ! "${GIT_SHA_INPUT}" =~ ^[a-zA-Z0-9._-]+$ ]] || [[ "${GIT_SHA_INPUT}" == *".."* ]]; then
    echo "CRITICAL ERROR: Invalid GIT_SHA '${GIT_SHA_INPUT}'." >&2
    exit 1
  fi
fi

if [ -L "${TARBALL_PATH}" ] || [ ! -f "${TARBALL_PATH}" ]; then
  echo "CRITICAL ERROR: Preview tarball not found or is a symlink at '${TARBALL_PATH}'" >&2
  exit 1
fi

# ==============================================================================
# 1. Canonical Realpath & Error-Checked Symlink Guards (Overrides ONLY in TEST_MODE=1)
# ==============================================================================
EXPECTED_DOCROOT="/home/alibhatt/web/gbafurniture.com"
EXPECTED_SANDBOX="/home/alibhatt/sandbox/gbafurniture"
EXPECTED_SANDBOX_RECOVERY="/home/alibhatt/sandbox/.gba-sandbox-recovery"
EXPECTED_LOCK_DIR="/home/alibhatt/.gba-deploy.lock"

if [ "${TEST_MODE:-0}" = "1" ]; then
  RAW_DOCROOT="${GBA_DOCROOT_OVERRIDE:-${EXPECTED_DOCROOT}}"
  RAW_SANDBOX="${GBA_SANDBOX_OVERRIDE:-${EXPECTED_SANDBOX}}"
  RAW_LOCK_DIR="${GBA_LOCK_OVERRIDE:-$(dirname "${RAW_DOCROOT%/}")/.gba-deploy.lock}"
else
  if [ -n "${GBA_DOCROOT_OVERRIDE:-}" ] || [ -n "${GBA_SANDBOX_OVERRIDE:-}" ] || [ -n "${GBA_BACKUP_OVERRIDE:-}" ] || [ -n "${GBA_RELEASES_OVERRIDE:-}" ] || [ -n "${GBA_LOCK_OVERRIDE:-}" ] || [ -n "${GBA_STAGE_ROOT_OVERRIDE:-}" ]; then
    echo "CRITICAL ERROR: Path overrides (GBA_*_OVERRIDE) are strictly forbidden when TEST_MODE != 1!" >&2
    exit 1
  fi
  RAW_DOCROOT="${EXPECTED_DOCROOT}"
  RAW_SANDBOX="${EXPECTED_SANDBOX}"
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

DOCROOT="$(guard_and_canonicalize_dir "${RAW_DOCROOT}" "DOCROOT" "1")"
SANDBOX_DIR="$(guard_and_canonicalize_dir "${RAW_SANDBOX}" "SANDBOX_DIR" "1")"
RAW_SANDBOX_RECOVERY="$(dirname "${RAW_SANDBOX%/}")/.gba-sandbox-recovery"
SANDBOX_RECOVERY_DIR="$(guard_and_canonicalize_dir "${RAW_SANDBOX_RECOVERY}" "SANDBOX_RECOVERY_DIR" "1" "1")"
LOCK_PARENT="$(guard_and_canonicalize_dir "$(dirname "${RAW_LOCK_DIR%/}")" "LOCK_PARENT" "1" "0")"
LOCK_DIR="${LOCK_PARENT}/$(basename "${RAW_LOCK_DIR%/}")"
LOCK_FILE="${LOCK_DIR}"
LOCK_META_FILE="${LOCK_FILE}.meta"

if [ "${TEST_MODE:-0}" != "1" ]; then
  if [ "${DOCROOT}" != "${EXPECTED_DOCROOT}" ] || [ "${SANDBOX_DIR}" != "${EXPECTED_SANDBOX}" ] || [ "${SANDBOX_RECOVERY_DIR}" != "${EXPECTED_SANDBOX_RECOVERY}" ] || [ "${LOCK_DIR}" != "${EXPECTED_LOCK_DIR}" ]; then
    echo "CRITICAL ERROR: Canonical path guard failed! DOCROOT='${DOCROOT}', SANDBOX_DIR='${SANDBOX_DIR}', SANDBOX_RECOVERY_DIR='${SANDBOX_RECOVERY_DIR}'" >&2
    exit 1
  fi
fi

# Enforce that SANDBOX_DIR and SANDBOX_RECOVERY_DIR are strictly outside DOCROOT and disjoint
if paths_overlap "${DOCROOT}" "${SANDBOX_DIR}"; then
  echo "CRITICAL ERROR: SANDBOX_DIR '${SANDBOX_DIR}' must be strictly outside DOCROOT '${DOCROOT}'!" >&2
  exit 1
fi
if paths_overlap "${DOCROOT}" "${SANDBOX_RECOVERY_DIR}"; then
  echo "CRITICAL ERROR: SANDBOX_RECOVERY_DIR '${SANDBOX_RECOVERY_DIR}' must be strictly outside DOCROOT '${DOCROOT}'!" >&2
  exit 1
fi
if paths_overlap "${SANDBOX_DIR}" "${SANDBOX_RECOVERY_DIR}"; then
  echo "CRITICAL ERROR: SANDBOX_RECOVERY_DIR '${SANDBOX_RECOVERY_DIR}' must not overlap SANDBOX_DIR '${SANDBOX_DIR}'!" >&2
  exit 1
fi

mkdir -p -- "${DOCROOT}" "${SANDBOX_DIR}"

SANDBOX_RECOVERY_ROOT_OWNED=0
if [ -L "${SANDBOX_RECOVERY_DIR}" ] || { [ -e "${SANDBOX_RECOVERY_DIR}" ] && [ ! -d "${SANDBOX_RECOVERY_DIR}" ]; }; then
  echo "CRITICAL ERROR: SANDBOX_RECOVERY_DIR '${SANDBOX_RECOVERY_DIR}' is a symlink or non-directory!" >&2
  exit 1
fi
if [ ! -d "${SANDBOX_RECOVERY_DIR}" ]; then
  mkdir -m 700 -- "${SANDBOX_RECOVERY_DIR}"
  SANDBOX_RECOVERY_ROOT_OWNED=1
fi
chmod 700 "${SANDBOX_RECOVERY_DIR}"
SANDBOX_RECOVERY_DIR="$(guard_and_canonicalize_dir "${SANDBOX_RECOVERY_DIR}" "SANDBOX_RECOVERY_DIR" "0" "1")"

# ==============================================================================
# 2. Shared Host-Side OS-Held Lock & Trap Recovery State
# ==============================================================================
LOCK_ACQUIRED=0
LOCK_META_OWNED=0
LOCK_OWNER_TOKEN="$$:$(date -u +%s):${RANDOM}"
STAGE_DIR=""
STAGE_DIR_OWNED=0
SANDBOX_RECOVERY_RUN_DIR=""
SANDBOX_RECOVERY_RUN_OWNED=0
SANDBOX_RECOVERY_TAR=""
SANDBOX_RECOVERY_TAR_OWNED=0
SANDBOX_RECOVERY_TREE=""
SANDBOX_RECOVERY_TREE_OWNED=0
PRE_SANDBOX_DIGEST=""
SANDBOX_HAD_FILES=0
MUTATION_STARTED=0
DEPLOY_COMPLETED=0
RESTORE_ATTEMPTED=0
SIGNAL_EXIT_CODE=""
CLEANUP_IN_PROGRESS=0

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
  if ! python3 - "${LOCK_META_FILE}" "${LOCK_OWNER_TOKEN}" "$$" "$(date -u +%s)" "sandbox:$(basename "${TARBALL_PATH}")" <<'PYEOF'
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

restore_previous_sandbox() {
  if [ "${RESTORE_ATTEMPTED}" -eq 1 ]; then
    return 0
  fi
  RESTORE_ATTEMPTED=1
  set +e

  echo "Initiating automatic restoration of previous sandbox state..." >&2

  python3 - "${SANDBOX_DIR}" "${SANDBOX_HAD_FILES}" "${SANDBOX_RECOVERY_TREE:-}" "${SANDBOX_RECOVERY_TAR:-}" <<'PYEOF'
import os, shutil, sys, tarfile

sandbox_dir, had_files_str, recovery_tree, backup_tar = sys.argv[1:5]
had_files = int(had_files_str) == 1

if not os.path.isdir(sandbox_dir) or os.path.islink(sandbox_dir):
    sys.stderr.write(f"CRITICAL ERROR: Cannot restore into invalid sandbox_dir '{sandbox_dir}'\n")
    sys.exit(1)

for entry in os.listdir(sandbox_dir):
    full = os.path.join(sandbox_dir, entry)
    if os.path.islink(full) or os.path.isfile(full):
        os.unlink(full)
    elif os.path.isdir(full):
        shutil.rmtree(full)

if had_files:
    restored = False
    if recovery_tree and os.path.isdir(recovery_tree) and not os.path.islink(recovery_tree):
        for entry in os.listdir(recovery_tree):
            src = os.path.join(recovery_tree, entry)
            dst = os.path.join(sandbox_dir, entry)
            if os.path.isdir(src) and not os.path.islink(src):
                shutil.copytree(src, dst, symlinks=False)
            else:
                shutil.copy2(src, dst, follow_symlinks=False)
        restored = True
    elif backup_tar and os.path.isfile(backup_tar) and not os.path.islink(backup_tar):
        with tarfile.open(backup_tar, "r:gz") as tf:
            tf.extractall(sandbox_dir)
        restored = True

    if not restored:
        sys.stderr.write("CRITICAL ERROR: No valid recovery source available for sandbox restore!\n")
        sys.exit(1)

    for dirpath, dirnames, filenames in os.walk(sandbox_dir, followlinks=False):
        os.chmod(dirpath, 0o755)
        for fn in filenames:
            fp = os.path.join(dirpath, fn)
            if not os.path.islink(fp):
                os.chmod(fp, 0o644)
PYEOF
  local py_rc=$?

  local restored_digest=""
  restored_digest="$(compute_tree_digest "${SANDBOX_DIR}" 2>/dev/null || echo "ERROR")"
  local sym_ok=0
  if assert_no_symlinks_in_tree "${SANDBOX_DIR}" "restored SANDBOX_DIR" 2>/dev/null; then
    sym_ok=1
  fi

  if [ "${py_rc}" -eq 0 ] && [ "${sym_ok}" -eq 1 ] && [ "${restored_digest}" = "${PRE_SANDBOX_DIGEST}" ]; then
    echo "✓ Previous sandbox state restored and cryptographically verified (${restored_digest})." >&2
    # Never delete the sole recovery copy (SANDBOX_RECOVERY_TAR) when a deployment fails!
    # Only remove the invocation-owned unpacked tree if the verified tar archive is preserved.
    if [ "${SANDBOX_HAD_FILES}" -eq 0 ] || [ -s "${SANDBOX_RECOVERY_TAR:-}" ]; then
      if [ "${SANDBOX_RECOVERY_TREE_OWNED:-0}" -eq 1 ] && [ -n "${SANDBOX_RECOVERY_TREE:-}" ] && [ ! -L "${SANDBOX_RECOVERY_TREE}" ] && [ -d "${SANDBOX_RECOVERY_TREE}" ]; then
        rm -rf -- "${SANDBOX_RECOVERY_TREE}" 2>/dev/null || true
        SANDBOX_RECOVERY_TREE=""
        SANDBOX_RECOVERY_TREE_OWNED=0
      fi
    fi
    return 0
  else
    echo "CRITICAL ERROR: Sandbox restore verification FAILED (expected=${PRE_SANDBOX_DIGEST}, actual=${restored_digest})!" >&2
    echo "Preserving all sandbox recovery evidence:" >&2
    [ -n "${SANDBOX_RECOVERY_TAR:-}" ] && echo "  Recovery Archive: ${SANDBOX_RECOVERY_TAR}" >&2
    [ -n "${SANDBOX_RECOVERY_TREE:-}" ] && echo "  Recovery Tree:    ${SANDBOX_RECOVERY_TREE}" >&2
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

  if [ "${exit_code}" -ne 0 ]; then
    if [ "${MUTATION_STARTED}" -eq 1 ] && [ "${DEPLOY_COMPLETED}" -eq 0 ]; then
      restore_previous_sandbox || true
      if [ "${SANDBOX_HAD_FILES}" -eq 0 ] && [ "${SANDBOX_RECOVERY_RUN_OWNED:-0}" -eq 1 ] && [ -n "${SANDBOX_RECOVERY_RUN_DIR:-}" ] && [ ! -L "${SANDBOX_RECOVERY_RUN_DIR}" ] && [ -d "${SANDBOX_RECOVERY_RUN_DIR}" ]; then
        rmdir "${SANDBOX_RECOVERY_RUN_DIR}" 2>/dev/null || true
        SANDBOX_RECOVERY_RUN_OWNED=0
      fi
    else
      # Failed before mutation started: safe to remove only invocation-owned recovery paths
      if [ "${SANDBOX_RECOVERY_TREE_OWNED:-0}" -eq 1 ] && [ -n "${SANDBOX_RECOVERY_TREE:-}" ] && [ ! -L "${SANDBOX_RECOVERY_TREE}" ] && [ -d "${SANDBOX_RECOVERY_TREE}" ]; then
        rm -rf -- "${SANDBOX_RECOVERY_TREE}" 2>/dev/null || true
        SANDBOX_RECOVERY_TREE_OWNED=0
      fi
      if [ "${SANDBOX_RECOVERY_TAR_OWNED:-0}" -eq 1 ] && [ -n "${SANDBOX_RECOVERY_TAR:-}" ] && [ ! -L "${SANDBOX_RECOVERY_TAR}" ] && [ -f "${SANDBOX_RECOVERY_TAR}" ]; then
        rm -f -- "${SANDBOX_RECOVERY_TAR}" 2>/dev/null || true
        SANDBOX_RECOVERY_TAR_OWNED=0
      fi
      if [ "${SANDBOX_RECOVERY_RUN_OWNED:-0}" -eq 1 ] && [ -n "${SANDBOX_RECOVERY_RUN_DIR:-}" ] && [ ! -L "${SANDBOX_RECOVERY_RUN_DIR}" ] && [ -d "${SANDBOX_RECOVERY_RUN_DIR}" ]; then
        rmdir "${SANDBOX_RECOVERY_RUN_DIR}" 2>/dev/null || true
        SANDBOX_RECOVERY_RUN_OWNED=0
      fi
      if [ "${SANDBOX_RECOVERY_ROOT_OWNED:-0}" -eq 1 ] && [ -n "${SANDBOX_RECOVERY_DIR:-}" ] && [ ! -L "${SANDBOX_RECOVERY_DIR}" ] && [ -d "${SANDBOX_RECOVERY_DIR}" ]; then
        rmdir "${SANDBOX_RECOVERY_DIR}" 2>/dev/null || true
      fi
    fi
  else
    if [ "${DEPLOY_COMPLETED}" -eq 1 ]; then
      if [ "${SANDBOX_RECOVERY_TREE_OWNED:-0}" -eq 1 ] && [ -n "${SANDBOX_RECOVERY_TREE:-}" ] && [ ! -L "${SANDBOX_RECOVERY_TREE}" ] && [ -d "${SANDBOX_RECOVERY_TREE}" ]; then
        rm -rf -- "${SANDBOX_RECOVERY_TREE}" 2>/dev/null || true
        SANDBOX_RECOVERY_TREE_OWNED=0
      fi
      if [ "${SANDBOX_RECOVERY_TAR_OWNED:-0}" -eq 1 ] && [ -n "${SANDBOX_RECOVERY_TAR:-}" ] && [ ! -L "${SANDBOX_RECOVERY_TAR}" ] && [ -f "${SANDBOX_RECOVERY_TAR}" ]; then
        rm -f -- "${SANDBOX_RECOVERY_TAR}" 2>/dev/null || true
        SANDBOX_RECOVERY_TAR_OWNED=0
      fi
      if [ "${SANDBOX_RECOVERY_RUN_OWNED:-0}" -eq 1 ] && [ -n "${SANDBOX_RECOVERY_RUN_DIR:-}" ] && [ ! -L "${SANDBOX_RECOVERY_RUN_DIR}" ] && [ -d "${SANDBOX_RECOVERY_RUN_DIR}" ]; then
        rmdir "${SANDBOX_RECOVERY_RUN_DIR}" 2>/dev/null || true
        SANDBOX_RECOVERY_RUN_OWNED=0
      fi
    fi
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
echo "GBA Furniture: Starting Sandbox Deployment"
echo "Docroot:     ${DOCROOT} (untouched)"
echo "Sandbox Dir: ${SANDBOX_DIR} (strictly outside docroot)"
echo "Preview URL: ${PREVIEW_URL}"
echo "================================================================================"

# ==============================================================================
# 3. Outer Tarball Checksum Verification
# ==============================================================================
ACTUAL_TARBALL_SHA256="$(compute_sha256 "${TARBALL_PATH}")"
HASH_VERIFIED=0

if [ -n "${ARTIFACT_SHA256}" ]; then
  shopt -s nocasematch
  if [[ "${ACTUAL_TARBALL_SHA256}" != "${ARTIFACT_SHA256}" ]]; then
    shopt -u nocasematch
    echo "CRITICAL ERROR: Sandbox tarball SHA256 mismatch! Expected ${ARTIFACT_SHA256}, got ${ACTUAL_TARBALL_SHA256}" >&2
    exit 1
  fi
  shopt -u nocasematch
  echo "✓ Outer tarball SHA256 verified against expected hash: ${ACTUAL_TARBALL_SHA256}"
  HASH_VERIFIED=1
fi

if [ -f "${TARBALL_PATH}.sha256" ]; then
  if [ -L "${TARBALL_PATH}.sha256" ]; then
    echo "CRITICAL ERROR: Checksum companion file '${TARBALL_PATH}.sha256' is a symlink!" >&2
    exit 1
  fi
  echo "Verifying archive tarball SHA256 checksum companion file..."
  COMPANION_HASH="$(awk '{print $1}' "${TARBALL_PATH}.sha256" | head -n1)"
  shopt -s nocasematch
  if [ -z "${COMPANION_HASH}" ] || [[ "${COMPANION_HASH}" != "${ACTUAL_TARBALL_SHA256}" ]]; then
    shopt -u nocasematch
    echo "CRITICAL ERROR: Sandbox companion .sha256 mismatch (${COMPANION_HASH} != ${ACTUAL_TARBALL_SHA256})!" >&2
    exit 1
  fi
  shopt -u nocasematch
  echo "✓ Archive tarball SHA256 companion file verified successfully."
  HASH_VERIFIED=1
fi

if [ "${HASH_VERIFIED}" -ne 1 ]; then
  echo "CRITICAL ERROR: No ARTIFACT_SHA256 argument or companion .sha256 file provided for '${TARBALL_PATH}'!" >&2
  exit 1
fi

# ==============================================================================
# 4. Staged Extraction, Allowlist & Packaged Checksum Verification on Host
# ==============================================================================
STAGE_DIR="$(mktemp -d)"
STAGE_DIR_OWNED=1

echo "Extracting preview artifact to staging area: ${STAGE_DIR}"
tar -xzf "${TARBALL_PATH}" -C "${STAGE_DIR}"
find "${STAGE_DIR}" -name '._*' -type f -delete 2>/dev/null || true

assert_no_symlinks_in_tree "${STAGE_DIR}" "extracted sandbox package"

echo "Verifying packaged SHA256 checksums on remote host..."
if [ ! -f "${STAGE_DIR}/checksums.sha256" ]; then
  echo "CRITICAL ERROR: checksums.sha256 missing from preview package!" >&2
  exit 1
fi

(
  cd "${STAGE_DIR}"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c checksums.sha256 >/dev/null
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -c checksums.sha256 >/dev/null
  else
    echo "ERROR: Neither sha256sum nor shasum available to verify checksums." >&2
    exit 1
  fi
)
echo "✓ All packaged checksums verified successfully on host."

verify_static_tree_allowlist "${STAGE_DIR}" "extracted sandbox package"

# Strictly parse release-metadata.json and bind release_id, git_sha, and tree_sha256
TARBALL_BASENAME="$(basename "${TARBALL_PATH}")"
META_PARSED="$(python3 - "${STAGE_DIR}" "${RELEASE_ID_INPUT}" "${GIT_SHA_INPUT}" "${TARBALL_BASENAME}" <<'PYEOF'
import hashlib, json, os, re, sys

stage_dir, expected_rel, expected_sha, tarball_basename = sys.argv[1:5]
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

if expected_rel and meta_rel != expected_rel:
    sys.stderr.write(f"CRITICAL ERROR: release-metadata.json release_id '{meta_rel}' != expected '{expected_rel}'!\n")
    sys.exit(1)

m_tar = re.match(r"^gba-static-(.+)\.tar\.gz$", tarball_basename)
if m_tar and m_tar.group(1) != meta_rel:
    sys.stderr.write(f"CRITICAL ERROR: Tarball name release '{m_tar.group(1)}' != release-metadata.json '{meta_rel}'!\n")
    sys.exit(1)

if expected_sha and expected_sha != "unspecified" and meta_sha != expected_sha:
    sys.stderr.write(f"CRITICAL ERROR: release-metadata.json git_sha '{meta_sha}' != expected '{expected_sha}'!\n")
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
  if [ ! -s "${STAGE_DIR}/${f}" ]; then
    echo "CRITICAL ERROR: Required file '${f}' missing or empty in preview package!" >&2
    exit 1
  fi
done

# Content verification on staged candidate before cutover
grep -F -q -- "GBA Furniture" "${STAGE_DIR}/index.html" || { echo "CRITICAL ERROR: Staged index.html missing brand title" >&2; exit 1; }
grep -F -q -- "assets/gba-logo-official-transparent.png" "${STAGE_DIR}/index.html" || { echo "CRITICAL ERROR: Staged index.html missing official transparent logo reference" >&2; exit 1; }
grep -F -q -- "--color-petrol" "${STAGE_DIR}/styles.css" || { echo "CRITICAL ERROR: Staged styles.css missing brand variables" >&2; exit 1; }
grep -F -q -- "products" "${STAGE_DIR}/script.js" || { echo "CRITICAL ERROR: Staged script.js missing catalogue logic" >&2; exit 1; }
grep -F -q -- "beds-mattresses" "${STAGE_DIR}/data/products.json" || { echo "CRITICAL ERROR: Staged products.json missing category data" >&2; exit 1; }

# Normalize permissions in staging area
find "${STAGE_DIR}" -type d -exec chmod 755 {} +
find "${STAGE_DIR}" -type f -exec chmod 644 {} +

# ==============================================================================
# 5. Backup Current Sandbox State in Validated Exclusive Invocation-Owned Path
# ==============================================================================
PRE_SANDBOX_DIGEST="$(compute_tree_digest "${SANDBOX_DIR}")"
if [ "${PRE_SANDBOX_DIGEST}" = "INVALID" ]; then
  echo "CRITICAL ERROR: Failed to compute pre-mutation digest of SANDBOX_DIR '${SANDBOX_DIR}'!" >&2
  exit 1
fi

# Re-validate SANDBOX_RECOVERY_DIR canonical ancestry & reject symlinks for root and children
SANDBOX_RECOVERY_DIR="$(guard_and_canonicalize_dir "${SANDBOX_RECOVERY_DIR}" "SANDBOX_RECOVERY_DIR" "0" "1")"
chmod 700 "${SANDBOX_RECOVERY_DIR}"

SANDBOX_RUN_ID="${META_RELEASE_ID}-$$-$(date -u +%s)-${RANDOM}"
CANDIDATE_RUN_DIR="${SANDBOX_RECOVERY_DIR}/run-${SANDBOX_RUN_ID}"
if [ -e "${CANDIDATE_RUN_DIR}" ] || [ -L "${CANDIDATE_RUN_DIR}" ]; then
  echo "CRITICAL ERROR: Sandbox recovery run directory '${CANDIDATE_RUN_DIR}' already exists or is a symlink!" >&2
  exit 1
fi
mkdir -m 700 -- "${CANDIDATE_RUN_DIR}"
SANDBOX_RECOVERY_RUN_DIR="$(guard_and_canonicalize_dir "${CANDIDATE_RUN_DIR}" "SANDBOX_RECOVERY_RUN_DIR" "0" "1")"
SANDBOX_RECOVERY_RUN_OWNED=1

if [ -n "$(ls -A "${SANDBOX_DIR}" 2>/dev/null)" ]; then
  SANDBOX_HAD_FILES=1
  CANDIDATE_RECOVERY_TAR="${SANDBOX_RECOVERY_RUN_DIR}/sandbox-recovery-${SANDBOX_RUN_ID}.tar.gz"
  CANDIDATE_RECOVERY_TREE="${SANDBOX_RECOVERY_RUN_DIR}/sandbox-recovery-${SANDBOX_RUN_ID}-tree"
  if [ -e "${CANDIDATE_RECOVERY_TAR}" ] || [ -L "${CANDIDATE_RECOVERY_TAR}" ] || [ -e "${CANDIDATE_RECOVERY_TREE}" ] || [ -L "${CANDIDATE_RECOVERY_TREE}" ]; then
    echo "CRITICAL ERROR: Sandbox recovery target path already exists or is a symlink!" >&2
    exit 1
  fi
  SANDBOX_RECOVERY_TAR="${CANDIDATE_RECOVERY_TAR}"
  SANDBOX_RECOVERY_TAR_OWNED=1
  (
    cd "${SANDBOX_DIR}"
    COPYFILE_DISABLE=1 tar -czf "${SANDBOX_RECOVERY_TAR}" .
  )
  chmod 600 "${SANDBOX_RECOVERY_TAR}"
  if ! tar -tzf "${SANDBOX_RECOVERY_TAR}" >/dev/null; then
    echo "CRITICAL ERROR: Sandbox recovery tar archive failed integrity check before cutover!" >&2
    exit 1
  fi
  mkdir -m 700 -- "${CANDIDATE_RECOVERY_TREE}"
  SANDBOX_RECOVERY_TREE="${CANDIDATE_RECOVERY_TREE}"
  SANDBOX_RECOVERY_TREE_OWNED=1
  tar -xzf "${SANDBOX_RECOVERY_TAR}" -C "${SANDBOX_RECOVERY_TREE}"
  assert_no_symlinks_in_tree "${SANDBOX_RECOVERY_TREE}" "SANDBOX_RECOVERY_TREE"
  if [ "$(compute_tree_digest "${SANDBOX_RECOVERY_TREE}")" != "${PRE_SANDBOX_DIGEST}" ]; then
    echo "CRITICAL ERROR: Sandbox recovery tree digest mismatch before cutover!" >&2
    exit 1
  fi
fi

# Mutation begins here: ANY error in rsync, metadata copy, chmod, post-copy verify, or smoke
# will automatically trigger restore_previous_sandbox via the EXIT trap.
MUTATION_STARTED=1

echo "Syncing staged files into ${SANDBOX_DIR}..."
rsync -a --delete --delay-updates "${STAGE_DIR}/" "${SANDBOX_DIR}/"
cp "${STAGE_DIR}/release-metadata.json" "${SANDBOX_DIR}/release-metadata.json"

find "${SANDBOX_DIR}" -type d -exec chmod 755 {} +
find "${SANDBOX_DIR}" -type f -exec chmod 644 {} +

verify_static_tree_allowlist "${SANDBOX_DIR}" "deployed SANDBOX_DIR"

if [ "$(compute_sha256 "${SANDBOX_DIR}/release-metadata.json")" != "$(compute_sha256 "${STAGE_DIR}/release-metadata.json")" ]; then
  echo "CRITICAL ERROR: Deployed release-metadata.json in SANDBOX_DIR does not match staged candidate!" >&2
  exit 1
fi

echo "✓ Artifact atomically installed into ${SANDBOX_DIR}"

# ==============================================================================
# 6. Smoke Test Verification (Proving Public Identity with Auto-Restore on Failure)
# ==============================================================================
echo "Running smoke test on preview URL: ${PREVIEW_URL}..."
SMOKE_TEST_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/smoke-test.sh"

SMOKE_OK=1
if [ -f "${SMOKE_TEST_SCRIPT}" ]; then
  if ! EXPECTED_RELEASE_ID="${META_RELEASE_ID}" \
       EXPECTED_GIT_SHA="${META_GIT_SHA}" \
       EXPECTED_TREE_SHA256="${META_TREE_SHA256}" \
       EXPECTED_METADATA_FILE="${SANDBOX_DIR}/release-metadata.json" \
       bash "${SMOKE_TEST_SCRIPT}" "${PREVIEW_URL}"; then
    SMOKE_OK=0
  fi
else
  SMOKE_OK=0
fi

if [ "${SMOKE_OK}" -ne 1 ]; then
  echo "CRITICAL ERROR: Sandbox smoke test failed against ${PREVIEW_URL}! Restoring previous sandbox state..." >&2
  restore_previous_sandbox
  exit 1
fi

DEPLOY_COMPLETED=1

echo "================================================================================"
echo "SANDBOX PREVIEW DEPLOYMENT SUCCESSFUL"
echo "Release ID:  ${META_RELEASE_ID}"
echo "Git SHA:     ${META_GIT_SHA}"
echo "Sandbox Dir: ${SANDBOX_DIR}"
echo "Preview URL: ${PREVIEW_URL}"
echo "================================================================================"
