#!/usr/bin/env bash
# ==============================================================================
# GBA Furniture — Static Release Packaging Script
#
# Purpose:
#   Packages strictly the 5 approved static assets into an immutable deployment
#   artifact with SHA256 checksums, release identity metadata, and exhaustive
#   static-only allowlist verification:
#     1. index.html
#     2. styles.css
#     3. script.js
#     4. data/
#     5. assets/
#
# Constraints Enforced:
#   - Strictly validates RELEASE_ID, GIT_SHA, and canonical dist/output ancestry
#     before arming cleanup traps.
#   - Rejects symlinked dist, dist/staging, and any ancestor or child symlinks.
#   - Reserves an exclusive invocation-owned staging directory (mkdir -m 700)
#     and exclusively created same-filesystem temporary files (O_CREAT | O_EXCL),
#     and cleans up only paths created by this invocation.
#   - Acquires an OS-held nonblocking flock on a canonical regular packaging lock
#     file in dist/ (.gba-package.lock) before duplicate checks and holds it
#     through all publication and latest-pointer steps (failing closed if flock
#     is unavailable).
#   - Publishes artifact and checksum via kernel-atomic NO-CLOBBER hardlink
#     publication (os.link + os.unlink) under the lock, eliminating
#     check-then-rename races across concurrent invocations.
#   - Disables macOS AppleDouble resource fork synthesis (COPYFILE_DISABLE=1).
#   - Uses complete error-checked symlink scans (find ... -type l -print with
#     captured output/status; never find|grep -q which can SIGPIPE under pipefail).
#   - Enforces an exhaustive static-only allowlist for root files, directories,
#     recursive assets/data paths, and extensions; rejects PHP/server-executable
#     files, tags (<?php, <?=, #!), and unexpected files.
#   - Generates release-metadata.json with release_id, git_sha, and tree_sha256.
#   - Generates checksums.sha256 and standalone .tar.gz.sha256.
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DEFAULT_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"

if [ "${TEST_MODE:-0}" != "1" ] && [ -n "${GBA_REPO_ROOT_OVERRIDE:-}" ]; then
  echo "CRITICAL ERROR: GBA_REPO_ROOT_OVERRIDE is forbidden when TEST_MODE != 1!" >&2
  exit 1
fi

RAW_REPO_ROOT="${GBA_REPO_ROOT_OVERRIDE:-${DEFAULT_REPO_ROOT}}"
RELEASE_ID="${1:-$(date -u +%Y%m%d%H%M%S)}"
GIT_SHA="${2:-${GITHUB_SHA:-$(git -C "${DEFAULT_REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo "untracked")}}"

if [[ ! "${RELEASE_ID}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || [[ "${RELEASE_ID}" == *".."* ]]; then
  echo "ERROR: Invalid RELEASE_ID '${RELEASE_ID}'. Must match ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ without '..'" >&2
  exit 1
fi

if [[ ! "${GIT_SHA}" =~ ^[a-zA-Z0-9._-]+$ ]] || [[ "${GIT_SHA}" == *".."* ]]; then
  echo "ERROR: Invalid GIT_SHA '${GIT_SHA}'. Must match ^[a-zA-Z0-9._-]+$ without '..'" >&2
  exit 1
fi

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

assert_no_symlinks_in_tree() {
  local target_dir="$1"
  local label="${2:-directory}"
  if [ -L "${target_dir}" ]; then
    echo "ERROR: ${label} '${target_dir}' is itself a symlink!" >&2
    return 1
  fi
  if [ ! -d "${target_dir}" ]; then
    echo "ERROR: ${label} '${target_dir}' is not a valid directory!" >&2
    return 1
  fi
  local find_out=""
  local find_rc=0
  find_out="$(find "${target_dir}" -type l -print 2>&1)" || find_rc=$?
  if [ "${find_rc}" -ne 0 ]; then
    echo "ERROR: Symlink scan failed (exit ${find_rc}) inside ${label} '${target_dir}': ${find_out}" >&2
    return 1
  fi
  if [ -n "${find_out}" ]; then
    local first_link="${find_out%%$'\n'*}"
    echo "ERROR: Symlinks are strictly forbidden inside ${label} '${target_dir}' (found: ${first_link})!" >&2
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
    echo "ERROR: ${label} '${raw_path}' must be an absolute path." >&2
    return 1
  fi

  if [ "${raw_path}" != "/" ]; then
    raw_path="${raw_path%/}"
  fi

  if [[ "${raw_path}" =~ (^|/)\.\.?(/|$) ]] || [[ "${raw_path}" == *"//"* ]]; then
    echo "ERROR: ${label} '${raw_path}' contains non-canonical dot or empty segments." >&2
    return 1
  fi

  if [ -L "${raw_path}" ]; then
    echo "ERROR: ${label} '${raw_path}' is a symlink! Symlinks are strictly rejected." >&2
    return 1
  fi

  if [ -e "${raw_path}" ] && [ ! -d "${raw_path}" ]; then
    echo "ERROR: ${label} '${raw_path}' exists and is not a directory!" >&2
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
      if [ "$(uname -s)" = "Darwin" ] && [[ "${current}" =~ ^/(var|tmp|etc)$ ]]; then
        continue
      fi
      echo "ERROR: ${label} ancestor '${current}' is a symlink! Symlinks are strictly rejected." >&2
      return 1
    fi
    if [ -e "${current}" ] && [ ! -d "${current}" ]; then
      echo "ERROR: ${label} path component '${current}' exists and is not a directory!" >&2
      return 1
    fi
  done

  local canonical
  if [ -d "${raw_path}" ]; then
    canonical="$(cd -P -- "${raw_path}" && pwd -P)" || return 1
  else
    if [ "${create_if_missing}" != "1" ]; then
      echo "ERROR: Required directory for ${label} does not exist: '${raw_path}'" >&2
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

  local expected_canon="${raw_path}"
  if [ "$(uname -s)" = "Darwin" ] && [[ "${raw_path}" =~ ^/(var|tmp|etc)(/|$) ]]; then
    expected_canon="/private${raw_path}"
  fi
  if [ "${canonical}" != "${expected_canon}" ]; then
    echo "ERROR: Canonical realpath '${canonical}' does not match '${expected_canon}' for ${label} (symlink detected)!" >&2
    return 1
  fi

  if [ -d "${canonical}" ] && [ "${scan_tree}" = "1" ]; then
    assert_no_symlinks_in_tree "${canonical}" "${label}" || return 1
  fi

  printf '%s\n' "${canonical}"
}

# Validate REPO_ROOT and DIST_DIR ancestry before arming cleanup trap
REPO_ROOT="$(guard_and_canonicalize_dir "${RAW_REPO_ROOT}" "REPO_ROOT" "0" "0")"
RAW_DIST_DIR="${REPO_ROOT}/dist"

if [ -L "${RAW_DIST_DIR}" ]; then
  echo "ERROR: DIST_DIR '${RAW_DIST_DIR}' is a symlink! Symlinks are strictly rejected." >&2
  exit 1
fi
if [ -e "${RAW_DIST_DIR}" ] && [ ! -d "${RAW_DIST_DIR}" ]; then
  echo "ERROR: DIST_DIR '${RAW_DIST_DIR}' exists and is not a directory!" >&2
  exit 1
fi

DIST_DIR="$(guard_and_canonicalize_dir "${RAW_DIST_DIR}" "DIST_DIR" "1" "1")"
LEGACY_STAGE_PATH="${DIST_DIR}/staging"
RELEASE_STAGE_PATH="${DIST_DIR}/staging-${RELEASE_ID}"
RELEASE_OUTPUT_DIR="${DIST_DIR}/${RELEASE_ID}"
RELEASE_PREFIX_PATH="${DIST_DIR}/gba-static-${RELEASE_ID}"

TARBALL_NAME="gba-static-${RELEASE_ID}.tar.gz"
TARBALL_PATH="${DIST_DIR}/${TARBALL_NAME}"
TARBALL_SHA_PATH="${TARBALL_PATH}.sha256"
LATEST_PTR_PATH="${DIST_DIR}/latest-artifact.txt"
PACKAGE_LOCK_FILE="${DIST_DIR}/.gba-package.lock"
PACKAGE_LOCK_META_FILE="${PACKAGE_LOCK_FILE}.meta"

STAGE_DIR=""
STAGE_DIR_OWNED=0
DIST_DIR_OWNED=0
PACKAGE_LOCK_ACQUIRED=0
PACKAGE_LOCK_META_OWNED=0
PACKAGE_LOCK_OWNER_TOKEN="$$:$(date -u +%s):${RANDOM}"
TMP_TARBALL_PATH=""
TMP_TARBALL_OWNED=0
TMP_SHA_PATH=""
TMP_SHA_OWNED=0
TMP_LATEST_PATH=""
TMP_LATEST_OWNED=0
TARBALL_PUBLISHED_BY_US=0
TARBALL_SHA_PUBLISHED_BY_US=0
PACKAGING_COMPLETED=0
SIGNAL_EXIT_CODE=""
CLEANUP_IN_PROGRESS=0

handle_signal() {
  local sig_exit_code="$1"
  SIGNAL_EXIT_CODE="${sig_exit_code}"
  exit "${sig_exit_code}"
}

acquire_package_lock() {
  if [ -L "${PACKAGE_LOCK_FILE}" ] || [ -L "${PACKAGE_LOCK_META_FILE}" ]; then
    echo "ERROR: Packaging lock path '${PACKAGE_LOCK_FILE}' or metadata file is a symlink!" >&2
    return 1
  fi
  if [ -e "${PACKAGE_LOCK_FILE}" ] && [ ! -f "${PACKAGE_LOCK_FILE}" ]; then
    echo "ERROR: Packaging lock path '${PACKAGE_LOCK_FILE}' exists and is not a regular file!" >&2
    return 1
  fi
  if [ -e "${PACKAGE_LOCK_META_FILE}" ] && [ ! -f "${PACKAGE_LOCK_META_FILE}" ]; then
    echo "ERROR: Packaging lock metadata path '${PACKAGE_LOCK_META_FILE}' exists and is not a regular file!" >&2
    return 1
  fi

  if [ "${GBA_DISABLE_FLOCK:-0}" = "1" ]; then
    echo "ERROR: flock is unavailable/disabled; failing closed rather than packaging without an OS lock!" >&2
    return 1
  fi

  local use_flock_cli=0
  if command -v flock >/dev/null 2>&1; then
    use_flock_cli=1
  elif [ "${GBA_REQUIRE_FLOCK_CLI:-0}" = "1" ]; then
    echo "ERROR: flock CLI is unavailable; failing closed rather than packaging without an OS lock!" >&2
    return 1
  elif ! python3 -c 'import fcntl; assert hasattr(fcntl, "flock")' >/dev/null 2>&1; then
    echo "ERROR: flock is unavailable on this host; failing closed rather than packaging without an OS lock!" >&2
    return 1
  fi

  # Open canonical regular packaging lock file on stable file descriptor 9 for process lifetime
  # Scope stderr suppression strictly to the compound redirection so parent stderr is preserved
  { exec 9>>"${PACKAGE_LOCK_FILE}"; } 2>/dev/null || {
    echo "ERROR: Unable to open regular packaging lock file '${PACKAGE_LOCK_FILE}'!" >&2
    return 1
  }

  if ! python3 - "${PACKAGE_LOCK_FILE}" <<'PYEOF'
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
    echo "ERROR: Packaging lock file '${PACKAGE_LOCK_FILE}' failed canonical regular-file verification!" >&2
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
    if [ -f "${PACKAGE_LOCK_META_FILE}" ] && [ ! -L "${PACKAGE_LOCK_META_FILE}" ]; then
      holder_info="$(tr '\n' ' ' < "${PACKAGE_LOCK_META_FILE}" 2>/dev/null || true)"
    fi
    echo "ERROR: Another packaging process holds lock '${PACKAGE_LOCK_FILE}' (${holder_info:-active OS flock})!" >&2
    return 1
  fi

  # Re-verify inode identity after lock acquisition
  if ! python3 - "${PACKAGE_LOCK_FILE}" <<'PYEOF'
import os, stat, sys
lock_path = sys.argv[1]
st_path = os.lstat(lock_path)
st_fd = os.fstat(9)
if not stat.S_ISREG(st_path.st_mode) or (st_path.st_dev, st_path.st_ino) != (st_fd.st_dev, st_fd.st_ino):
    sys.exit(1)
PYEOF
  then
    { exec 9>&-; } 2>/dev/null || true
    echo "ERROR: Packaging lock file '${PACKAGE_LOCK_FILE}' inode changed during lock acquisition!" >&2
    return 1
  fi

  PACKAGE_LOCK_ACQUIRED=1

  # Write owner metadata separately and safely via same-directory temp file + fsync + atomic rename
  if ! python3 - "${PACKAGE_LOCK_META_FILE}" "${PACKAGE_LOCK_OWNER_TOKEN}" "$$" "$(date -u +%s)" "package:${RELEASE_ID}" <<'PYEOF'
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
fd, tmp_path = tempfile.mkstemp(prefix=".pkg-lock-meta.", dir=parent)
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
    release_package_lock "1"
    echo "ERROR: Failed to write packaging lock owner metadata '${PACKAGE_LOCK_META_FILE}'!" >&2
    return 1
  fi
  PACKAGE_LOCK_META_OWNED=1
  return 0
}

release_package_lock() {
  local cleaning_failed_owned_dist="${1:-0}"
  if [ "${PACKAGE_LOCK_ACQUIRED:-0}" -eq 1 ]; then
    if [ "${PACKAGE_LOCK_META_OWNED:-0}" -eq 1 ] && [ -n "${PACKAGE_LOCK_META_FILE:-}" ] && [ ! -L "${PACKAGE_LOCK_META_FILE}" ] && [ -f "${PACKAGE_LOCK_META_FILE}" ]; then
      python3 - "${PACKAGE_LOCK_META_FILE}" "${PACKAGE_LOCK_OWNER_TOKEN}" <<'PYEOF' 2>/dev/null || true
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
      PACKAGE_LOCK_META_OWNED=0
    fi
    if [ "${cleaning_failed_owned_dist}" = "1" ] && [ "${DIST_DIR_OWNED:-0}" -eq 1 ] && [ "${PACKAGING_COMPLETED:-0}" -eq 0 ] && [ -n "${PACKAGE_LOCK_FILE:-}" ] && [ ! -L "${PACKAGE_LOCK_FILE}" ] && [ -f "${PACKAGE_LOCK_FILE}" ]; then
      rm -f -- "${PACKAGE_LOCK_FILE}" 2>/dev/null || true
    fi
    if command -v flock >/dev/null 2>&1; then
      flock -u 9 2>/dev/null || true
    else
      python3 -c 'import fcntl; fcntl.flock(9, fcntl.LOCK_UN)' 2>/dev/null || true
    fi
    { exec 9>&-; } 2>/dev/null || true
    PACKAGE_LOCK_ACQUIRED=0
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
  if [ "${TMP_TARBALL_OWNED:-0}" -eq 1 ] && [ -n "${TMP_TARBALL_PATH:-}" ] && [ ! -L "${TMP_TARBALL_PATH}" ] && [ -e "${TMP_TARBALL_PATH}" ]; then
    rm -f -- "${TMP_TARBALL_PATH}" 2>/dev/null || true
    TMP_TARBALL_OWNED=0
  fi
  if [ "${TMP_SHA_OWNED:-0}" -eq 1 ] && [ -n "${TMP_SHA_PATH:-}" ] && [ ! -L "${TMP_SHA_PATH}" ] && [ -e "${TMP_SHA_PATH}" ]; then
    rm -f -- "${TMP_SHA_PATH}" 2>/dev/null || true
    TMP_SHA_OWNED=0
  fi
  if [ "${TMP_LATEST_OWNED:-0}" -eq 1 ] && [ -n "${TMP_LATEST_PATH:-}" ] && [ ! -L "${TMP_LATEST_PATH}" ] && [ -e "${TMP_LATEST_PATH}" ]; then
    rm -f -- "${TMP_LATEST_PATH}" 2>/dev/null || true
    TMP_LATEST_OWNED=0
  fi
  local clean_owned_dist=0
  if [ "${exit_code}" -ne 0 ] && [ "${PACKAGING_COMPLETED:-0}" -eq 0 ]; then
    if [ "${TARBALL_PUBLISHED_BY_US:-0}" -eq 1 ] && [ -n "${TARBALL_PATH:-}" ] && [ ! -L "${TARBALL_PATH}" ] && [ -f "${TARBALL_PATH}" ]; then
      rm -f -- "${TARBALL_PATH}" 2>/dev/null || true
      TARBALL_PUBLISHED_BY_US=0
    fi
    if [ "${TARBALL_SHA_PUBLISHED_BY_US:-0}" -eq 1 ] && [ -n "${TARBALL_SHA_PATH:-}" ] && [ ! -L "${TARBALL_SHA_PATH}" ] && [ -f "${TARBALL_SHA_PATH}" ]; then
      rm -f -- "${TARBALL_SHA_PATH}" 2>/dev/null || true
      TARBALL_SHA_PUBLISHED_BY_US=0
    fi
    if [ "${DIST_DIR_OWNED:-0}" -eq 1 ]; then
      clean_owned_dist=1
    fi
  fi
  release_package_lock "${clean_owned_dist}"
  if [ "${clean_owned_dist}" -eq 1 ] && [ -n "${DIST_DIR:-}" ] && [ ! -L "${DIST_DIR}" ] && [ -d "${DIST_DIR}" ]; then
    rmdir "${DIST_DIR}" 2>/dev/null || true
  fi
  exit "${exit_code}"
}
trap cleanup EXIT
trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM
trap 'handle_signal 129' HUP

# Create DIST_DIR exclusively if missing and acquire OS-held packaging lock BEFORE duplicate checks
if [ -L "${DIST_DIR}" ]; then
  echo "ERROR: DIST_DIR '${DIST_DIR}' is a symlink!" >&2
  exit 1
fi
if [ -e "${DIST_DIR}" ] && [ ! -d "${DIST_DIR}" ]; then
  echo "ERROR: DIST_DIR '${DIST_DIR}' exists and is not a directory!" >&2
  exit 1
fi
if [ ! -d "${DIST_DIR}" ]; then
  if mkdir -m 755 -- "${DIST_DIR}" 2>/dev/null; then
    DIST_DIR_OWNED=1
  elif [ -L "${DIST_DIR}" ] || [ ! -d "${DIST_DIR}" ]; then
    echo "ERROR: Failed to create DIST_DIR '${DIST_DIR}'!" >&2
    exit 1
  fi
fi
DIST_DIR="$(guard_and_canonicalize_dir "${DIST_DIR}" "DIST_DIR" "0" "1")"

acquire_package_lock

if [ -L "${LATEST_PTR_PATH}" ] || { [ -e "${LATEST_PTR_PATH}" ] && [ ! -f "${LATEST_PTR_PATH}" ]; }; then
  echo "ERROR: Output path '${LATEST_PTR_PATH}' is a symlink or non-regular file!" >&2
  exit 1
fi

for dup_path in \
  "${TARBALL_PATH}" \
  "${TARBALL_SHA_PATH}" \
  "${LEGACY_STAGE_PATH}" \
  "${RELEASE_STAGE_PATH}" \
  "${RELEASE_OUTPUT_DIR}" \
  "${RELEASE_PREFIX_PATH}"; do
  if [ -e "${dup_path}" ] || [ -L "${dup_path}" ]; then
    echo "ERROR: Duplicate or pre-existing output/staging path '${dup_path}' is strictly rejected!" >&2
    exit 1
  fi
done

if [ -d "${DIST_DIR}" ]; then
  existing_rel_temps="$(find "${DIST_DIR}" -maxdepth 1 \( -name "staging-${RELEASE_ID}-*" -o -name ".staging-${RELEASE_ID}-*" -o -name ".${TARBALL_NAME}*" \) -print 2>/dev/null || true)"
  if [ -n "${existing_rel_temps}" ]; then
    echo "ERROR: Pre-existing staging or temporary output for RELEASE_ID '${RELEASE_ID}' found in '${DIST_DIR}'!" >&2
    exit 1
  fi
fi

echo "================================================================================"
echo "GBA Furniture: Packaging Static Release Artifact"
echo "Release ID: ${RELEASE_ID}"
echo "Git SHA:    ${GIT_SHA}"
echo "Repo Root:  ${REPO_ROOT}"
echo "================================================================================"

# Fail fast if essential source targets do not exist or are symlinks
REQUIRED_SOURCES=(
  "index.html"
  "styles.css"
  "script.js"
  "data/products.json"
  "assets/gba-logo-web.png"
  "assets/gba-logo.png"
  "assets/current-banner.jpg"
)

for target in "${REQUIRED_SOURCES[@]}"; do
  if [ ! -f "${REPO_ROOT}/${target}" ] || [ -L "${REPO_ROOT}/${target}" ] || [ ! -s "${REPO_ROOT}/${target}" ]; then
    echo "ERROR: Required file '${target}' missing, empty, or is a symlink in repository root." >&2
    exit 1
  fi
done

for src_dir in "data" "assets" "assets/placeholders"; do
  if [ ! -d "${REPO_ROOT}/${src_dir}" ] || [ -L "${REPO_ROOT}/${src_dir}" ]; then
    echo "ERROR: Required directory '${src_dir}' missing or is a symlink in repository root." >&2
    exit 1
  fi
done

assert_no_symlinks_in_tree "${REPO_ROOT}/data" "source data/"
assert_no_symlinks_in_tree "${REPO_ROOT}/assets" "source assets/"

# Pre-validate source data/ and assets/ trees against exhaustive static allowlist before copying
python3 - "${REPO_ROOT}" <<'PYEOF'
import os, re, sys

repo_root = sys.argv[1]

allowed_data_dirs = {"."}
allowed_data_files = {"products.json"}

allowed_assets_dirs = {".", "placeholders"}
allowed_assets_files = {
    "current-banner.jpg",
    "gba-logo-web.png",
    "gba-logo.png",
    "placeholders/appliance.svg",
    "placeholders/bed-divan.svg",
    "placeholders/bed-frame.svg",
    "placeholders/bunk.svg",
    "placeholders/chest.svg",
    "placeholders/coffee-table.svg",
    "placeholders/dining-table.svg",
    "placeholders/sofa.svg",
    "placeholders/van.svg",
    "placeholders/wardrobe.svg",
}

forbidden_ext_re = re.compile(
    r"\.(php[0-9]*|phtml|phar|inc|cgi|pl|py|rb|sh|bash|zsh|fcgi|shtml|jsp|jspx|asp|aspx|exe|dll|so|dylib|bin|htaccess|htpasswd|ini|conf)$",
    re.IGNORECASE,
)

def scan_source_subdir(sub, allowed_dirs, allowed_files):
    base = os.path.join(repo_root, sub)
    seen_files = set()
    for dirpath, dirnames, filenames in os.walk(base, followlinks=False):
        rel_dir = os.path.relpath(dirpath, base).replace(os.sep, "/")
        if rel_dir not in allowed_dirs:
            sys.stderr.write(f"ERROR: Unexpected directory '{sub}/{rel_dir}' not in static allowlist!\n")
            sys.exit(1)
        for d in dirnames:
            full_d = os.path.join(dirpath, d)
            if os.path.islink(full_d):
                sys.stderr.write(f"ERROR: Symlink directory '{full_d}' forbidden!\n")
                sys.exit(1)
        for fn in filenames:
            full_f = os.path.join(dirpath, fn)
            rel_f = os.path.relpath(full_f, base).replace(os.sep, "/")
            if os.path.islink(full_f) or not os.path.isfile(full_f):
                sys.stderr.write(f"ERROR: Non-regular or symlink file '{sub}/{rel_f}' forbidden!\n")
                sys.exit(1)
            if forbidden_ext_re.search(fn) or fn.startswith("."):
                sys.stderr.write(f"ERROR: Server-executable or hidden file '{sub}/{rel_f}' strictly rejected!\n")
                sys.exit(1)
            if rel_f not in allowed_files:
                sys.stderr.write(f"ERROR: Unexpected file '{sub}/{rel_f}' is not in the exhaustive static allowlist!\n")
                sys.exit(1)
            seen_files.add(rel_f)
    missing = allowed_files - seen_files
    if missing:
        sys.stderr.write(f"ERROR: Missing required static files in '{sub}/': {sorted(missing)}\n")
        sys.exit(1)

scan_source_subdir("data", allowed_data_dirs, allowed_data_files)
scan_source_subdir("assets", allowed_assets_dirs, allowed_assets_files)
PYEOF

# Re-verify DIST_DIR canonical directory and duplicate-destination guards under the held packaging lock
DIST_DIR="$(guard_and_canonicalize_dir "${DIST_DIR}" "DIST_DIR" "0" "1")"

for dup_path in \
  "${TARBALL_PATH}" \
  "${TARBALL_SHA_PATH}" \
  "${LEGACY_STAGE_PATH}" \
  "${RELEASE_STAGE_PATH}" \
  "${RELEASE_OUTPUT_DIR}" \
  "${RELEASE_PREFIX_PATH}"; do
  if [ -e "${dup_path}" ] || [ -L "${dup_path}" ]; then
    echo "ERROR: Pre-existing or symlinked '${dup_path}' is strictly rejected!" >&2
    exit 1
  fi
done

INVOCATION_RANDOM="$(python3 -c 'import secrets; print(secrets.token_hex(8))')"
INVOCATION_ID="${RELEASE_ID}-$$-$(date -u +%s)-${RANDOM}-${INVOCATION_RANDOM}"
CANDIDATE_STAGE_DIR="${DIST_DIR}/staging-${INVOCATION_ID}"
CANDIDATE_TMP_TARBALL="${DIST_DIR}/.${TARBALL_NAME}.tmp.${INVOCATION_ID}"
CANDIDATE_TMP_SHA="${DIST_DIR}/.${TARBALL_NAME}.sha256.tmp.${INVOCATION_ID}"
CANDIDATE_TMP_LATEST="${DIST_DIR}/.latest-artifact.txt.tmp.${INVOCATION_ID}"

for cand_tmp in "${CANDIDATE_STAGE_DIR}" "${CANDIDATE_TMP_TARBALL}" "${CANDIDATE_TMP_SHA}" "${CANDIDATE_TMP_LATEST}"; do
  if [ -e "${cand_tmp}" ] || [ -L "${cand_tmp}" ]; then
    echo "ERROR: Candidate temporary path '${cand_tmp}' already exists or is a symlink!" >&2
    exit 1
  fi
done

mkdir -m 700 -- "${CANDIDATE_STAGE_DIR}"
STAGE_DIR_OWNED=1
STAGE_DIR="$(guard_and_canonicalize_dir "${CANDIDATE_STAGE_DIR}" "STAGE_DIR" "0" "1")"

echo "Copying approved static assets..."
cp "${REPO_ROOT}/index.html" "${STAGE_DIR}/index.html"
cp "${REPO_ROOT}/styles.css" "${STAGE_DIR}/styles.css"
cp "${REPO_ROOT}/script.js" "${STAGE_DIR}/script.js"
cp -R "${REPO_ROOT}/data" "${STAGE_DIR}/data"
cp -R "${REPO_ROOT}/assets" "${STAGE_DIR}/assets"

# Remove any OS-synthesized AppleDouble files if present and verify no symlinks
find "${STAGE_DIR}" -name '._*' -type f -delete 2>/dev/null || true
assert_no_symlinks_in_tree "${STAGE_DIR}" "staged release directory"

# Normalize permissions before computing checksums and archiving
find "${STAGE_DIR}" -type d -exec chmod 755 {} +
find "${STAGE_DIR}" -type f -exec chmod 644 {} +

# Compute deterministic static payload tree_sha256 over the 17 static payload files
TREE_SHA256="$(python3 - "${STAGE_DIR}" <<'PYEOF'
import hashlib, os, sys

stage = sys.argv[1]
records = []
for dirpath, dirnames, filenames in os.walk(stage, followlinks=False):
    dirnames.sort()
    filenames.sort()
    for fn in filenames:
        if fn in ("release-metadata.json", "checksums.sha256"):
            continue
        full = os.path.join(dirpath, fn)
        rel = "./" + os.path.relpath(full, stage).replace(os.sep, "/")
        h = hashlib.sha256()
        with open(full, "rb") as f:
            for chunk in iter(lambda: f.read(65536), b""):
                h.update(chunk)
        records.append(f"{h.hexdigest()}  {rel}")
records.sort()
if len(records) != 17:
    sys.stderr.write(f"ERROR: Expected exactly 17 static payload files for tree_sha256, found {len(records)}\n")
    sys.exit(1)
tree_hash = hashlib.sha256(("\n".join(records) + "\n").encode("utf-8")).hexdigest()
print(tree_hash)
PYEOF
)"

# Generate build metadata and checksums inside staging
echo "Generating release metadata and SHA256 checksums..."
cat > "${STAGE_DIR}/release-metadata.json" <<EOF
{
  "release_id": "${RELEASE_ID}",
  "git_sha": "${GIT_SHA}",
  "tree_sha256": "${TREE_SHA256}",
  "build_timestamp_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "included_targets": [
    "index.html",
    "styles.css",
    "script.js",
    "data/",
    "assets/"
  ]
}
EOF
chmod 644 "${STAGE_DIR}/release-metadata.json"

(
  cd "${STAGE_DIR}"
  if command -v sha256sum >/dev/null 2>&1; then
    find . -type f ! -name "checksums.sha256" -print0 | sort -z | xargs -0 sha256sum > checksums.sha256
  else
    find . -type f ! -name "checksums.sha256" -print0 | sort -z | xargs -0 shasum -a 256 > checksums.sha256
  fi
  chmod 644 checksums.sha256
)

# Archive to invocation-owned temporary tarball in destination filesystem with COPYFILE_DISABLE=1
# Reserve temporary tarball path exclusively via O_CREAT | O_EXCL before marking owned
echo "Archiving to temporary artifact in ${DIST_DIR}..."
if [ -e "${TARBALL_PATH}" ] || [ -L "${TARBALL_PATH}" ]; then
  echo "ERROR: Target tarball path '${TARBALL_PATH}' already exists or is a symlink!" >&2
  exit 1
fi
python3 - "${CANDIDATE_TMP_TARBALL}" <<'PYEOF'
import os, sys

tmp_tar = sys.argv[1]
fd = os.open(tmp_tar, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
try:
    os.fchmod(fd, 0o600)
finally:
    os.close(fd)
PYEOF
TMP_TARBALL_PATH="${CANDIDATE_TMP_TARBALL}"
TMP_TARBALL_OWNED=1
(
  cd "${STAGE_DIR}"
  COPYFILE_DISABLE=1 tar -czf "${TMP_TARBALL_PATH}" .
)
chmod 644 "${TMP_TARBALL_PATH}"

# Exhaustive static-only allowlist verification on both staging tree and temporary archive
echo "Verifying archive contents against whitelist..."
python3 - "${STAGE_DIR}" "${TMP_TARBALL_PATH}" "${RELEASE_ID}" "${GIT_SHA}" "${TREE_SHA256}" <<'PYEOF'
import json, os, re, stat, sys, tarfile

stage_dir, tarball_path, expected_rel, expected_sha, expected_tree = sys.argv[1:6]

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

# 1. Verify staged directory tree exhaustively
seen_stage_dirs = set()
seen_stage_files = set()
for dirpath, dirnames, filenames in os.walk(stage_dir, followlinks=False):
    rel_d = os.path.relpath(dirpath, stage_dir).replace(os.sep, "/")
    norm_d = "." if rel_d == "." else f"./{rel_d}"
    seen_stage_dirs.add(norm_d)
    if norm_d not in ALLOWED_DIRS:
        sys.stderr.write(f"ERROR: Forbidden or unexpected directory in staging: '{norm_d}'\n")
        sys.exit(1)
    for fn in filenames:
        full_f = os.path.join(dirpath, fn)
        rel_f = "./" + os.path.relpath(full_f, stage_dir).replace(os.sep, "/")
        if os.path.islink(full_f) or not os.path.isfile(full_f):
            sys.stderr.write(f"ERROR: Non-regular or symlink file in staging: '{rel_f}'\n")
            sys.exit(1)
        if rel_f not in ALLOWED_FILES:
            sys.stderr.write(f"ERROR: Unexpected file '{rel_f}' rejected by exhaustive static allowlist!\n")
            sys.exit(1)
        _, ext = os.path.splitext(fn)
        if ext.lower() not in ALLOWED_EXTENSIONS:
            sys.stderr.write(f"ERROR: File '{rel_f}' has disallowed extension '{ext}'!\n")
            sys.exit(1)
        st = os.lstat(full_f)
        if st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH):
            sys.stderr.write(f"ERROR: Executable permission bit set on static file '{rel_f}'!\n")
            sys.exit(1)
        if ext.lower() in TEXT_EXTENSIONS:
            with open(full_f, "rb") as f:
                data = f.read()
            if SERVER_CODE_RE.search(data):
                sys.stderr.write(f"ERROR: Server-executable code tag detected inside '{rel_f}'!\n")
                sys.exit(1)
        seen_stage_files.add(rel_f)

if seen_stage_dirs != ALLOWED_DIRS:
    sys.stderr.write(f"ERROR: Staged directory set mismatch: {sorted(seen_stage_dirs)} != {sorted(ALLOWED_DIRS)}\n")
    sys.exit(1)
if seen_stage_files != ALLOWED_FILES:
    sys.stderr.write(f"ERROR: Staged file set mismatch: missing={sorted(ALLOWED_FILES - seen_stage_files)}, extra={sorted(seen_stage_files - ALLOWED_FILES)}\n")
    sys.exit(1)

# 2. Verify release-metadata.json strict JSON and identity binding
def no_dups(pairs):
    obj = {}
    for k, v in pairs:
        if k in obj:
            raise ValueError(f"Duplicate JSON key: {k}")
        obj[k] = v
    return obj

with open(os.path.join(stage_dir, "release-metadata.json"), "r", encoding="utf-8") as mf:
    meta = json.loads(mf.read(), object_pairs_hook=no_dups)

if meta.get("release_id") != expected_rel or meta.get("git_sha") != expected_sha or meta.get("tree_sha256") != expected_tree:
    sys.stderr.write("ERROR: release-metadata.json fields do not match packaging inputs!\n")
    sys.exit(1)

# 3. Verify tar archive entries exhaustively
seen_tar_dirs = set()
seen_tar_files = set()
with tarfile.open(tarball_path, "r:gz") as tf:
    for member in tf.getmembers():
        raw_name = member.name.rstrip("/")
        norm = "." if raw_name in ("", ".") else ("./" + raw_name.lstrip("./"))
        if member.issym() or member.islnk() or member.ischr() or member.isblk() or member.isfifo():
            sys.stderr.write(f"ERROR: Forbidden special or symlink tar entry '{member.name}'!\n")
            sys.exit(1)
        if member.isdir():
            if norm not in ALLOWED_DIRS:
                sys.stderr.write(f"ERROR: Unexpected directory in tarball: '{norm}'\n")
                sys.exit(1)
            seen_tar_dirs.add(norm)
        elif member.isfile():
            if norm not in ALLOWED_FILES:
                sys.stderr.write(f"ERROR: Unexpected file in tarball: '{norm}'\n")
                sys.exit(1)
            if member.mode & 0o111:
                sys.stderr.write(f"ERROR: Tarball file '{norm}' has executable mode {oct(member.mode)}!\n")
                sys.exit(1)
            seen_tar_files.add(norm)
        else:
            sys.stderr.write(f"ERROR: Unknown tar entry type for '{member.name}'!\n")
            sys.exit(1)

if seen_tar_files != ALLOWED_FILES:
    sys.stderr.write(f"ERROR: Tarball file set mismatch: missing={sorted(ALLOWED_FILES - seen_tar_files)}, extra={sorted(seen_tar_files - ALLOWED_FILES)}\n")
    sys.exit(1)
PYEOF

# Compute tarball SHA256 and exclusively create/write/validate/fsync temporary checksum and latest pointer files
TARBALL_SHA256="$(compute_sha256 "${TMP_TARBALL_PATH}")"

if [ -e "${TARBALL_SHA_PATH}" ] || [ -L "${TARBALL_SHA_PATH}" ]; then
  echo "ERROR: Target checksum path '${TARBALL_SHA_PATH}' already exists or is a symlink!" >&2
  exit 1
fi
if [ -L "${LATEST_PTR_PATH}" ] || { [ -e "${LATEST_PTR_PATH}" ] && [ ! -f "${LATEST_PTR_PATH}" ]; }; then
  echo "ERROR: Target latest pointer path '${LATEST_PTR_PATH}' is invalid or is a symlink!" >&2
  exit 1
fi

python3 - "${TMP_TARBALL_PATH}" "${CANDIDATE_TMP_SHA}" "${TARBALL_SHA256}" "${TARBALL_NAME}" <<'PYEOF'
import hashlib, os, sys

tmp_tar, tmp_sha, expected_sha, tarball_name = sys.argv[1:5]

if os.path.islink(tmp_tar) or not os.path.isfile(tmp_tar) or os.path.getsize(tmp_tar) <= 0:
    sys.stderr.write(f"ERROR: Temporary tarball '{tmp_tar}' is missing, empty, or a symlink!\n")
    sys.exit(1)

# fsync and re-verify temporary tarball hash
tar_fd = os.open(tmp_tar, os.O_RDONLY)
try:
    os.fsync(tar_fd)
finally:
    os.close(tar_fd)

h = hashlib.sha256()
with open(tmp_tar, "rb") as tf:
    for chunk in iter(lambda: tf.read(65536), b""):
        h.update(chunk)
if h.hexdigest().lower() != expected_sha.lower():
    sys.stderr.write("ERROR: Temporary tarball SHA256 verification mismatch after fsync!\n")
    sys.exit(1)

sha_content = f"{expected_sha}  {tarball_name}\n".encode("utf-8")
fd_sha = os.open(tmp_sha, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
try:
    os.fchmod(fd_sha, 0o644)
    os.write(fd_sha, sha_content)
    os.fsync(fd_sha)
finally:
    os.close(fd_sha)

with open(tmp_sha, "rb") as sf:
    if sf.read() != sha_content:
        sys.stderr.write("ERROR: Temporary checksum file verification failed!\n")
        sys.exit(1)
PYEOF
TMP_SHA_PATH="${CANDIDATE_TMP_SHA}"
TMP_SHA_OWNED=1

python3 - "${CANDIDATE_TMP_LATEST}" "${TARBALL_NAME}" <<'PYEOF'
import os, sys

tmp_latest, tarball_name = sys.argv[1:3]

latest_content = f"{tarball_name}\n".encode("utf-8")
fd_latest = os.open(tmp_latest, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
try:
    os.fchmod(fd_latest, 0o644)
    os.write(fd_latest, latest_content)
    os.fsync(fd_latest)
finally:
    os.close(fd_latest)

with open(tmp_latest, "rb") as lf:
    if lf.read() != latest_content:
        sys.stderr.write("ERROR: Temporary latest pointer verification failed!\n")
        sys.exit(1)
PYEOF
TMP_LATEST_PATH="${CANDIDATE_TMP_LATEST}"
TMP_LATEST_OWNED=1

if [ "${TEST_MODE:-0}" = "1" ] && [ -n "${TEST_PACKAGE_LOCK_DELAY_SEC:-}" ]; then
  sleep "${TEST_PACKAGE_LOCK_DELAY_SEC}"
fi

if [ "${TEST_MODE:-0}" = "1" ] && [ "${TEST_FAIL_PACKAGE_AFTER_TEMP_STAGE:-0}" = "1" ]; then
  echo "ERROR: Simulated packaging failure after temporary output creation!" >&2
  exit 1
fi

# Remove invocation-owned staging directory before atomic NO-CLOBBER publication
if [ "${STAGE_DIR_OWNED}" -eq 1 ] && [ -n "${STAGE_DIR}" ] && [ ! -L "${STAGE_DIR}" ] && [ -d "${STAGE_DIR}" ]; then
  rm -rf -- "${STAGE_DIR}"
  STAGE_DIR_OWNED=0
fi

# Under the held packaging lock, reject any existing destination before publication
for final_dup in "${TARBALL_PATH}" "${TARBALL_SHA_PATH}" "${LEGACY_STAGE_PATH}" "${RELEASE_STAGE_PATH}" "${RELEASE_OUTPUT_DIR}" "${RELEASE_PREFIX_PATH}"; do
  if [ -e "${final_dup}" ] || [ -L "${final_dup}" ]; then
    echo "ERROR: Destination path '${final_dup}' already exists under packaging lock!" >&2
    exit 1
  fi
done
if [ -L "${LATEST_PTR_PATH}" ] || { [ -e "${LATEST_PTR_PATH}" ] && [ ! -f "${LATEST_PTR_PATH}" ]; }; then
  echo "ERROR: Destination latest pointer '${LATEST_PTR_PATH}' is a symlink or non-regular file!" >&2
  exit 1
fi

# Atomic NO-CLOBBER publication via hardlink (os.link + os.unlink); eliminates check-then-rename
python3 - "${TMP_TARBALL_PATH}" "${TARBALL_PATH}" <<'PYEOF'
import errno, os, sys

src, dst = sys.argv[1:3]
try:
    os.link(src, dst)
except FileExistsError:
    sys.stderr.write(f"ERROR: Atomic no-clobber publication rejected existing destination '{dst}'!\n")
    sys.exit(1)
except OSError as exc:
    if exc.errno == errno.EEXIST:
        sys.stderr.write(f"ERROR: Atomic no-clobber publication rejected existing destination '{dst}'!\n")
        sys.exit(1)
    raise
os.unlink(src)
PYEOF
TARBALL_PUBLISHED_BY_US=1
TMP_TARBALL_OWNED=0

python3 - "${TMP_SHA_PATH}" "${TARBALL_SHA_PATH}" <<'PYEOF'
import errno, os, sys

src, dst = sys.argv[1:3]
try:
    os.link(src, dst)
except FileExistsError:
    sys.stderr.write(f"ERROR: Atomic no-clobber publication rejected existing destination '{dst}'!\n")
    sys.exit(1)
except OSError as exc:
    if exc.errno == errno.EEXIST:
        sys.stderr.write(f"ERROR: Atomic no-clobber publication rejected existing destination '{dst}'!\n")
        sys.exit(1)
    raise
os.unlink(src)
PYEOF
TARBALL_SHA_PUBLISHED_BY_US=1
TMP_SHA_OWNED=0

if [ "${TEST_MODE:-0}" = "1" ] && [ "${TEST_FAIL_PACKAGE_BEFORE_LATEST:-0}" = "1" ]; then
  echo "ERROR: Simulated packaging failure before updating latest-artifact.txt!" >&2
  exit 1
fi

# Update latest-artifact.txt atomically ONLY after all validations and artifact publications succeed
python3 - "${TMP_LATEST_PATH}" "${LATEST_PTR_PATH}" "${DIST_DIR}" <<'PYEOF'
import os, sys

tmp_latest, latest_ptr, dist_dir = sys.argv[1:4]
if os.path.islink(latest_ptr) or (os.path.exists(latest_ptr) and not os.path.isfile(latest_ptr)):
    sys.stderr.write(f"ERROR: Refusing to replace symlink or directory '{latest_ptr}'\n")
    sys.exit(1)
os.replace(tmp_latest, latest_ptr)
try:
    dir_fd = os.open(dist_dir, os.O_RDONLY)
    try:
        os.fsync(dir_fd)
    finally:
        os.close(dir_fd)
except Exception:
    pass
PYEOF
TMP_LATEST_OWNED=0
PACKAGING_COMPLETED=1

# If running in GitHub Actions and GITHUB_OUTPUT is defined, populate outputs
if [ -n "${GITHUB_OUTPUT:-}" ] && [ -f "${GITHUB_OUTPUT}" ]; then
  {
    echo "tarball_name=${TARBALL_NAME}"
    echo "tarball_path=${TARBALL_PATH}"
    echo "tarball_sha_path=${TARBALL_SHA_PATH}"
    echo "artifact_sha256=${TARBALL_SHA256}"
    echo "release_id=${RELEASE_ID}"
    echo "git_sha=${GIT_SHA}"
    echo "tree_sha256=${TREE_SHA256}"
  } >> "${GITHUB_OUTPUT}"
fi

echo "Artifact verification passed. Release tarball ready:"
echo "  Path:            ${TARBALL_PATH}"
echo "  SHA256:          ${TARBALL_SHA256}"
echo "  Tree SHA256:     ${TREE_SHA256}"
echo "  Size:            $(du -h "${TARBALL_PATH}" | cut -f1)"
echo "  Git SHA:         ${GIT_SHA}"
echo "================================================================================"
