#!/usr/bin/env bash
# ==============================================================================
# GBA Furniture — Local Release Scaffolding Verification Suite
#
# Reproduces and verifies all release engineering security and logic controls
# locally without touching any remote servers or production credentials:
#   1. Bash syntax validation across all scripts AND YAML-decoded workflow run
#      blocks (including inner <<'EOF' and <<'CLEANEOF' heredocs)
#   2. Exhaustive static-only packaging allowlist, dist/staging canonical
#      ancestry validation before arming cleanup, symlink rejection, exclusive
#      invocation-owned staging, and PHP/executable rejection
#   3. Packaged checksum verification & release-metadata.json binding
#      (rejection of mismatched release_id, git_sha, or artifact_sha256)
#   4. Dual archive integrity verification before cutover (gzip -t & tar -tzf)
#   5. Remote command injection & SQL identifier injection rejection
#   6. Canonical realpath guards, 2400-symlink flood fail-open prevention,
#      TEST_MODE override guard, sandbox .gba-sandbox-recovery canonical
#      ancestry/symlink/ownership guards, and sandbox isolation outside docroot
#   7. Unsuppressed MySQL verification failures, positive zero-table proof,
#      and full files + DB restoration when DB deletion has begun and fails
#   8. Comprehensive post-mutation & finalization recovery across sandbox &
#      production: preflight node --check availability before any mutation,
#      injected rsync partial failure, injected successful-copy rsync CSS
#      mutation detected against retained STAGE_DIR / RELEASE_DIR, injected
#      chmod failure, public identity mismatch (/release-metadata.json),
#      HTTP 500 smoke failure, mandatory trusted binding (requiring both
#      EXPECTED_METADATA_FILE and EXPECTED_ASSET_ROOT, rejecting any symlink
#      ancestor such as alias-parent/trusted, and recursively scanning the
#      complete EXPECTED_ASSET_ROOT tree in preflight before the first HTTP
#      fetch to reject both unreferenced nested symlinks such as
#      assets/nested-extra/link and referenced SVG symlinks with zero HTTP
#      requests), fail-closed smoke-test Content-Type/format negative fixtures
#      (HTML fallbacks, wrong MIME types & fake bodies for versioned/underlying
#      SVG, PNG, JPG, CSS, JS, JSON), valid exact-trusted CSS fixtures (quoted
#      delimiters, string values containing literal '<html>' and
#      '<!-- example -->', and omitting the optional semicolon on the last
#      declaration before '}'), and atomic final manifest write failure
#      (never truncating in place)
#   9. Shared host-side OS-held flock lock (/home/alibhatt/.gba-deploy.lock):
#      active lock contention, two concurrent contenders proving only one enters,
#      automatic OS release on process exit, and fail-closed when flock unavailable
#  10. Hardened rollback: strict JSON manifest parsing, pre-rollback snapshot &
#      recovery tree, trap recovery on partial rsync/chmod/DB/health/manifest
#      failures (restoring live files + pre-rollback DB state & preserving
#      evidence on restore failure), and verified DB + HTTP 200 rollback
#  11. Workflow security controls: immutable github.sha checkout + HEAD check,
#      shared concurrency, full-SHA pinning, explicit SSH/SCP keepalive options
#      (ServerAliveInterval=30, ServerAliveCountMax=60, TCPKeepAlive=yes), and
#      pre-upload staging symlink escape prevention
# ==============================================================================

set -euo pipefail

if [ "${GBA_SIG_DFL_PID:-}" != "$$" ] && command -v python3 >/dev/null 2>&1; then
  if python3 -c 'import signal, sys; sys.exit(0 if any(signal.getsignal(s) == signal.SIG_IGN for s in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM)) else 1)' 2>/dev/null; then
    export GBA_SIG_DFL_PID="$$"
    exec python3 -c 'import os, signal, sys
for s in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
    signal.signal(s, signal.SIG_DFL)
os.execv(sys.argv[1], sys.argv[1:])' "$0" "$@"
  fi
fi

export COPYFILE_DISABLE=1
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"

echo "================================================================================"
echo "GBA Furniture: Running Local Release Scaffolding Test Suite"
echo "================================================================================"

# ==============================================================================
# Test 1: Syntax Validation (Scripts + YAML-Decoded Workflow Run Blocks)
# ==============================================================================
echo "[Test 1] Validating syntax of all shell scripts and YAML-decoded workflow run blocks..."
for script in "${SCRIPT_DIR}"/*.sh; do
  bash -n "${script}"
  echo "  ✓ Syntax valid: $(basename "${script}")"
done

python3 - "${REPO_ROOT}/.github/workflows" <<'PYEOF'
import glob, os, re, subprocess, sys

wf_dir = sys.argv[1]
wf_files = sorted(glob.glob(os.path.join(wf_dir, "*.yml")))
if not wf_files:
    sys.stderr.write("FAIL: No workflow YAML files found!\n")
    sys.exit(1)

def parse_run_blocks(wf_path):
    try:
        import yaml
        with open(wf_path, "r", encoding="utf-8") as f:
            doc = yaml.safe_load(f)
        blocks = []
        for job_name, job in (doc.get("jobs") or {}).items():
            for idx, step in enumerate(job.get("steps") or []):
                if "run" in step:
                    blocks.append((f"{job_name}:{step.get('name', idx)}", step["run"]))
        return blocks
    except ImportError:
        # Pure-Python fallback for literal block scalars (run: |)
        with open(wf_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
        blocks = []
        i = 0
        while i < len(lines):
            m = re.match(r"^(\s*)run:\s*\|\s*$", lines[i])
            if m:
                base_indent = len(m.group(1))
                i += 1
                block_indent = None
                buf = []
                while i < len(lines):
                    line = lines[i]
                    if line.strip() == "":
                        buf.append("\n")
                        i += 1
                        continue
                    cur_indent = len(line) - len(line.lstrip(" "))
                    if cur_indent <= base_indent:
                        break
                    if block_indent is None:
                        block_indent = cur_indent
                    buf.append(line[block_indent:])
                    i += 1
                blocks.append((f"line-{i}", "".join(buf)))
            else:
                i += 1
        return blocks

total_blocks = 0
total_heredocs = 0
for wf_path in wf_files:
    wf_name = os.path.basename(wf_path)
    blocks = parse_run_blocks(wf_path)
    if not blocks:
        sys.stderr.write(f"FAIL: No run blocks parsed from {wf_name}\n")
        sys.exit(1)
    for label, script in blocks:
        total_blocks += 1
        proc = subprocess.run(["bash", "-n"], input=script.encode("utf-8"), capture_output=True)
        if proc.returncode != 0:
            sys.stderr.write(
                f"FAIL: YAML-decoded run block syntax error in {wf_name} ({label}):\n{proc.stderr.decode('utf-8', errors='replace')}\n"
            )
            sys.exit(1)
        # Also extract and syntax-check every single-quoted heredoc (<<'EOF', <<'CLEANEOF') inside the decoded run block
        lines = script.splitlines(True)
        idx = 0
        while idx < len(lines):
            hm = re.search(r"<<'([A-Za-z0-9_]+)'", lines[idx])
            if hm:
                delim = hm.group(1)
                idx += 1
                hbuf = []
                found_end = False
                while idx < len(lines):
                    if lines[idx].rstrip("\r\n") == delim:
                        found_end = True
                        break
                    hbuf.append(lines[idx])
                    idx += 1
                if not found_end:
                    sys.stderr.write(
                        f"FAIL: Unterminated heredoc <<'{delim}' in YAML-decoded run block {wf_name} ({label})!\n"
                    )
                    sys.exit(1)
                total_heredocs += 1
                hproc = subprocess.run(["bash", "-n"], input="".join(hbuf).encode("utf-8"), capture_output=True)
                if hproc.returncode != 0:
                    sys.stderr.write(
                        f"FAIL: Inner heredoc <<'{delim}' syntax error in {wf_name} ({label}):\n{hproc.stderr.decode('utf-8', errors='replace')}\n"
                    )
                    sys.exit(1)
            idx += 1

print(f"  ✓ Validated {total_blocks} YAML-decoded workflow run blocks and {total_heredocs} inner heredocs with bash -n.")
PYEOF

# ==============================================================================
# Setup Isolated Canonical Mock Environment & HTTP Servers
# ==============================================================================
RAW_TEST_ENV_DIR="$(mktemp -d)"
TEST_ENV_DIR="$(cd -P -- "${RAW_TEST_ENV_DIR}" && pwd -P)"
SERVER_PID=""
FAIL_SERVER_PID=""
SANDBOX_SERVER_PID=""
STALE_SERVER_PID=""
FATAL_PHP_SERVER_PID=""
SMOKE_FIXTURE_SERVER_PID=""
ORIG_PATH="${PATH}"

cleanup() {
  local exit_code=$?
  export PATH="${ORIG_PATH}"
  for pid_var in "${SERVER_PID:-}" "${FAIL_SERVER_PID:-}" "${SANDBOX_SERVER_PID:-}" "${STALE_SERVER_PID:-}" "${FATAL_PHP_SERVER_PID:-}" "${SMOKE_FIXTURE_SERVER_PID:-}"; do
    if [ -n "${pid_var}" ]; then
      kill "${pid_var}" 2>/dev/null || true
      wait "${pid_var}" 2>/dev/null || true
    fi
  done
  if [ -n "${TEST_ENV_DIR:-}" ] && [ -d "${TEST_ENV_DIR}" ]; then
    rm -rf "${TEST_ENV_DIR}"
  fi
  rm -rf "${REPO_ROOT}/dist"
  exit ${exit_code}
}
trap cleanup EXIT INT TERM HUP

# ==============================================================================
# Test 2: Exhaustive Static Allowlist Packaging, dist/staging Guards & PHP Rejection
# ==============================================================================
echo "[Test 2] Packaging static artifact and verifying dist/staging guards, allowlist & PHP rejection..."
TEST_REL="test-rel-$(date +%s)"
TEST_GIT_SHA="0123456789abcdef0123456789abcdef01234567"
"${SCRIPT_DIR}/package-artifact.sh" "${TEST_REL}" "${TEST_GIT_SHA}" >/dev/null

TARBALL="${REPO_ROOT}/dist/gba-static-${TEST_REL}.tar.gz"
TARBALL_SHA_FILE="${TARBALL}.sha256"
TARBALL_HASH="$(awk '{print $1}' "${TARBALL_SHA_FILE}")"

[ -f "${TARBALL}" ] || { echo "  ✗ FAIL: Tarball was not created!" >&2; exit 1; }
[ -f "${TARBALL_SHA_FILE}" ] || { echo "  ✗ FAIL: Tarball SHA256 companion file was not created!" >&2; exit 1; }

TAR_CONTENTS="$(tar -tzf "${TARBALL}")"
for req in "index.html" "styles.css" "script.js" "data/products.json" "assets/current-banner.jpg" "assets/gba-logo-official-transparent.png" "assets/gba-logo-web.png" "checksums.sha256" "release-metadata.json"; do
  grep -F -q "${req}" <<< "${TAR_CONTENTS}" || { echo "Missing ${req} in tarball"; exit 1; }
done

EXPECTED_HERO_SHA256="1677a163a5cad2b7741a21877c059a7952faa6473f0ee7da92ade9878f831614"
ACTUAL_HERO_SHA256="$(python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "${REPO_ROOT}/assets/current-banner.jpg")"
[ "${ACTUAL_HERO_SHA256}" = "${EXPECTED_HERO_SHA256}" ] || {
  echo "  ✗ FAIL: assets/current-banner.jpg SHA256 mismatch (expected ${EXPECTED_HERO_SHA256}, got ${ACTUAL_HERO_SHA256})!" >&2
  exit 1
}
grep -F -q -- 'src="assets/current-banner.jpg?v=hero-20261020-1677a163a5ca"' "${REPO_ROOT}/index.html" || {
  echo "  ✗ FAIL: index.html missing cache-busted hero reference assets/current-banner.jpg?v=hero-20261020-1677a163a5ca!" >&2
  exit 1
}

FORBIDDEN=("serve.js" "test-site.js" "README.md" "RELEASE.md" "reference" "screenshot" "gba-logo-official-transparent-original.png" "gba-logo-official-cropped.jpg" "gba-logo-replacement-original.jpg" "._")
for f in "${FORBIDDEN[@]}"; do
  if grep -F -q "${f}" <<< "${TAR_CONTENTS}"; then
    echo "  ✗ FAIL: Forbidden file '${f}' found in tarball!" >&2
    exit 1
  fi
done

# 2b. Independent Reproduction: Reject PHP, server-executable, unexpected files, and <?php tags in package-artifact.sh
MOCK_REPO_COPY="${TEST_ENV_DIR}/mock-repo"
mkdir -p "${MOCK_REPO_COPY}"
cp "${REPO_ROOT}/index.html" "${MOCK_REPO_COPY}/index.html"
cp "${REPO_ROOT}/styles.css" "${MOCK_REPO_COPY}/styles.css"
cp "${REPO_ROOT}/script.js" "${MOCK_REPO_COPY}/script.js"
cp -R "${REPO_ROOT}/data" "${MOCK_REPO_COPY}/data"
cp -R "${REPO_ROOT}/assets" "${MOCK_REPO_COPY}/assets"

# Probe A: PHP file inside assets/
echo '<?php system($_GET["cmd"]); ?>' > "${MOCK_REPO_COPY}/assets/probe.php"
if TEST_MODE="1" GBA_REPO_ROOT_OVERRIDE="${MOCK_REPO_COPY}" "${SCRIPT_DIR}/package-artifact.sh" "php-probe" "${TEST_GIT_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: package-artifact.sh accepted assets/probe.php!" >&2
  exit 1
fi
rm -f "${MOCK_REPO_COPY}/assets/probe.php"

# Probe B: PHP file inside data/
echo '<?php phpinfo(); ?>' > "${MOCK_REPO_COPY}/data/probe.php"
if TEST_MODE="1" GBA_REPO_ROOT_OVERRIDE="${MOCK_REPO_COPY}" "${SCRIPT_DIR}/package-artifact.sh" "php-data-probe" "${TEST_GIT_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: package-artifact.sh accepted data/probe.php!" >&2
  exit 1
fi
rm -f "${MOCK_REPO_COPY}/data/probe.php"

# Probe C: Unexpected static file inside assets/
echo "unexpected" > "${MOCK_REPO_COPY}/assets/unexpected.txt"
if TEST_MODE="1" GBA_REPO_ROOT_OVERRIDE="${MOCK_REPO_COPY}" "${SCRIPT_DIR}/package-artifact.sh" "unexp-probe" "${TEST_GIT_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: package-artifact.sh accepted unexpected file assets/unexpected.txt!" >&2
  exit 1
fi
rm -f "${MOCK_REPO_COPY}/assets/unexpected.txt"

# Probe D: Embedded <?php code tag inside an allowlisted SVG file
cp "${MOCK_REPO_COPY}/assets/placeholders/bed-divan.svg" "${MOCK_REPO_COPY}/assets/placeholders/bed-divan.svg.bak"
echo '<?php echo 1; ?>' >> "${MOCK_REPO_COPY}/assets/placeholders/bed-divan.svg"
if TEST_MODE="1" GBA_REPO_ROOT_OVERRIDE="${MOCK_REPO_COPY}" "${SCRIPT_DIR}/package-artifact.sh" "svg-php-probe" "${TEST_GIT_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: package-artifact.sh accepted <?php tag inside SVG file!" >&2
  exit 1
fi
mv "${MOCK_REPO_COPY}/assets/placeholders/bed-divan.svg.bak" "${MOCK_REPO_COPY}/assets/placeholders/bed-divan.svg"

# Probe E: Symlinked dist/ or dist/staging or symlinked repo ancestor must be rejected BEFORE arming cleanup, preserving target files
VICTIM_DIR="${TEST_ENV_DIR}/victim-dir"
mkdir -p "${VICTIM_DIR}"
echo "precious-data" > "${VICTIM_DIR}/keep.txt"

ln -s "${VICTIM_DIR}" "${MOCK_REPO_COPY}/dist"
if TEST_MODE="1" GBA_REPO_ROOT_OVERRIDE="${MOCK_REPO_COPY}" "${SCRIPT_DIR}/package-artifact.sh" "sym-dist" "${TEST_GIT_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: package-artifact.sh accepted symlinked dist/!" >&2
  exit 1
fi
[ -f "${VICTIM_DIR}/keep.txt" ] || { echo "  ✗ FAIL: package-artifact.sh deleted symlinked dist/ target!" >&2; exit 1; }
rm -f "${MOCK_REPO_COPY}/dist"

mkdir -p "${MOCK_REPO_COPY}/dist"
echo "preserve-existing-artifact" > "${MOCK_REPO_COPY}/dist/existing-artifact.txt"
ln -s "${VICTIM_DIR}" "${MOCK_REPO_COPY}/dist/staging"
if TEST_MODE="1" GBA_REPO_ROOT_OVERRIDE="${MOCK_REPO_COPY}" "${SCRIPT_DIR}/package-artifact.sh" "sym-staging" "${TEST_GIT_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: package-artifact.sh accepted symlinked dist/staging!" >&2
  exit 1
fi
[ -f "${VICTIM_DIR}/keep.txt" ] || { echo "  ✗ FAIL: package-artifact.sh deleted symlinked dist/staging target!" >&2; exit 1; }
[ -f "${MOCK_REPO_COPY}/dist/existing-artifact.txt" ] || { echo "  ✗ FAIL: package-artifact.sh deleted pre-existing file in dist/!" >&2; exit 1; }
rm -f "${MOCK_REPO_COPY}/dist/staging"

# Probe F: Pre-existing dist/staging directory must be rejected and NOT deleted by cleanup
mkdir -p "${MOCK_REPO_COPY}/dist/staging"
echo "do-not-delete" > "${MOCK_REPO_COPY}/dist/staging/sentinel.txt"
if TEST_MODE="1" GBA_REPO_ROOT_OVERRIDE="${MOCK_REPO_COPY}" "${SCRIPT_DIR}/package-artifact.sh" "pre-staging" "${TEST_GIT_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: package-artifact.sh accepted pre-existing dist/staging directory!" >&2
  exit 1
fi
[ -f "${MOCK_REPO_COPY}/dist/staging/sentinel.txt" ] || { echo "  ✗ FAIL: package-artifact.sh cleanup deleted pre-existing dist/staging/sentinel.txt!" >&2; exit 1; }
rm -rf "${MOCK_REPO_COPY}/dist/staging"

# Probe G: Symlinked repo ancestor must be rejected
SYM_REPO_LINK="${TEST_ENV_DIR}/sym-repo-link"
ln -s "${MOCK_REPO_COPY}" "${SYM_REPO_LINK}"
if TEST_MODE="1" GBA_REPO_ROOT_OVERRIDE="${SYM_REPO_LINK}" "${SCRIPT_DIR}/package-artifact.sh" "sym-anc" "${TEST_GIT_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: package-artifact.sh accepted symlinked REPO_ROOT!" >&2
  exit 1
fi
rm -f "${SYM_REPO_LINK}"

# Probe H: Valid packaging in MOCK_REPO_COPY preserves pre-existing dist/existing-artifact.txt and cleans only invocation staging
TEST_MODE="1" GBA_REPO_ROOT_OVERRIDE="${MOCK_REPO_COPY}" "${SCRIPT_DIR}/package-artifact.sh" "clean-pkg" "${TEST_GIT_SHA}" >/dev/null
[ -f "${MOCK_REPO_COPY}/dist/existing-artifact.txt" ] || { echo "  ✗ FAIL: package-artifact.sh wiped pre-existing file in dist/!" >&2; exit 1; }
[ -f "${MOCK_REPO_COPY}/dist/gba-static-clean-pkg.tar.gz" ] || { echo "  ✗ FAIL: package-artifact.sh did not create expected tarball!" >&2; exit 1; }
[ -f "${MOCK_REPO_COPY}/dist/gba-static-clean-pkg.tar.gz.sha256" ] || { echo "  ✗ FAIL: package-artifact.sh did not create expected checksum!" >&2; exit 1; }
[ "$(cat "${MOCK_REPO_COPY}/dist/latest-artifact.txt")" = "gba-static-clean-pkg.tar.gz" ] || {
  echo "  ✗ FAIL: latest-artifact.txt did not point to clean-pkg tarball!" >&2
  exit 1
}

# Probe I: Duplicate existing tarball, checksum, staging, or release output paths must be rejected BEFORE writes and never deleted
ORIG_CLEAN_PKG_SHA="$(shasum -a 256 "${MOCK_REPO_COPY}/dist/gba-static-clean-pkg.tar.gz" | awk '{print $1}')"
if TEST_MODE="1" GBA_REPO_ROOT_OVERRIDE="${MOCK_REPO_COPY}" "${SCRIPT_DIR}/package-artifact.sh" "clean-pkg" "${TEST_GIT_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: package-artifact.sh accepted duplicate existing tarball release ID!" >&2
  exit 1
fi
[ -f "${MOCK_REPO_COPY}/dist/gba-static-clean-pkg.tar.gz" ] || { echo "  ✗ FAIL: duplicate run deleted pre-existing tarball!" >&2; exit 1; }
[ -f "${MOCK_REPO_COPY}/dist/gba-static-clean-pkg.tar.gz.sha256" ] || { echo "  ✗ FAIL: duplicate run deleted pre-existing checksum!" >&2; exit 1; }
[ "$(shasum -a 256 "${MOCK_REPO_COPY}/dist/gba-static-clean-pkg.tar.gz" | awk '{print $1}')" = "${ORIG_CLEAN_PKG_SHA}" ] || {
  echo "  ✗ FAIL: duplicate run modified pre-existing tarball!" >&2
  exit 1
}

# Pre-existing checksum path without tarball
echo "pre-existing-sha" > "${MOCK_REPO_COPY}/dist/gba-static-dup-sha.tar.gz.sha256"
if TEST_MODE="1" GBA_REPO_ROOT_OVERRIDE="${MOCK_REPO_COPY}" "${SCRIPT_DIR}/package-artifact.sh" "dup-sha" "${TEST_GIT_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: package-artifact.sh accepted pre-existing checksum path!" >&2
  exit 1
fi
[ "$(cat "${MOCK_REPO_COPY}/dist/gba-static-dup-sha.tar.gz.sha256")" = "pre-existing-sha" ] || {
  echo "  ✗ FAIL: package-artifact.sh deleted or overwrote pre-existing checksum file!" >&2
  exit 1
}
rm -f "${MOCK_REPO_COPY}/dist/gba-static-dup-sha.tar.gz.sha256"

# Pre-existing staging-<id> path
mkdir -p "${MOCK_REPO_COPY}/dist/staging-dup-stage"
echo "keep-stage" > "${MOCK_REPO_COPY}/dist/staging-dup-stage/sentinel.txt"
if TEST_MODE="1" GBA_REPO_ROOT_OVERRIDE="${MOCK_REPO_COPY}" "${SCRIPT_DIR}/package-artifact.sh" "dup-stage" "${TEST_GIT_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: package-artifact.sh accepted pre-existing dist/staging-<id> path!" >&2
  exit 1
fi
[ -f "${MOCK_REPO_COPY}/dist/staging-dup-stage/sentinel.txt" ] || {
  echo "  ✗ FAIL: package-artifact.sh deleted pre-existing dist/staging-<id>!" >&2
  exit 1
}
rm -rf "${MOCK_REPO_COPY}/dist/staging-dup-stage"

# Pre-existing release output path dist/<id>
mkdir -p "${MOCK_REPO_COPY}/dist/dup-rel-dir"
echo "keep-rel" > "${MOCK_REPO_COPY}/dist/dup-rel-dir/sentinel.txt"
if TEST_MODE="1" GBA_REPO_ROOT_OVERRIDE="${MOCK_REPO_COPY}" "${SCRIPT_DIR}/package-artifact.sh" "dup-rel-dir" "${TEST_GIT_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: package-artifact.sh accepted pre-existing dist/<id> release output path!" >&2
  exit 1
fi
[ -f "${MOCK_REPO_COPY}/dist/dup-rel-dir/sentinel.txt" ] || {
  echo "  ✗ FAIL: package-artifact.sh deleted pre-existing dist/<id> release output path!" >&2
  exit 1
}
rm -rf "${MOCK_REPO_COPY}/dist/dup-rel-dir"

# Probe J: Injected packaging failures must clean up invocation-owned temp files and preserve pre-existing latest-artifact.txt
if TEST_MODE="1" TEST_FAIL_PACKAGE_AFTER_TEMP_STAGE="1" GBA_REPO_ROOT_OVERRIDE="${MOCK_REPO_COPY}" "${SCRIPT_DIR}/package-artifact.sh" "fail-pkg-1" "${TEST_GIT_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: package-artifact.sh succeeded despite TEST_FAIL_PACKAGE_AFTER_TEMP_STAGE=1!" >&2
  exit 1
fi
if TEST_MODE="1" TEST_FAIL_PACKAGE_BEFORE_LATEST="1" GBA_REPO_ROOT_OVERRIDE="${MOCK_REPO_COPY}" "${SCRIPT_DIR}/package-artifact.sh" "fail-pkg-2" "${TEST_GIT_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: package-artifact.sh succeeded despite TEST_FAIL_PACKAGE_BEFORE_LATEST=1!" >&2
  exit 1
fi
[ ! -e "${MOCK_REPO_COPY}/dist/gba-static-fail-pkg-1.tar.gz" ] && [ ! -e "${MOCK_REPO_COPY}/dist/gba-static-fail-pkg-2.tar.gz" ] || {
  echo "  ✗ FAIL: Failed package-artifact.sh left partial/published tarball behind!" >&2
  exit 1
}
[ ! -e "${MOCK_REPO_COPY}/dist/gba-static-fail-pkg-1.tar.gz.sha256" ] && [ ! -e "${MOCK_REPO_COPY}/dist/gba-static-fail-pkg-2.tar.gz.sha256" ] || {
  echo "  ✗ FAIL: Failed package-artifact.sh left partial/published checksum behind!" >&2
  exit 1
}
LEFTOVER_PKG_TEMPS="$(find "${MOCK_REPO_COPY}/dist" -maxdepth 1 \( -name '.*tmp*' -o -name '.staging-*' \) 2>/dev/null || true)"
[ -z "${LEFTOVER_PKG_TEMPS}" ] || {
  echo "  ✗ FAIL: Failed package-artifact.sh left temporary files in dist/: ${LEFTOVER_PKG_TEMPS}" >&2
  exit 1
}
[ "$(cat "${MOCK_REPO_COPY}/dist/latest-artifact.txt")" = "gba-static-clean-pkg.tar.gz" ] || {
  echo "  ✗ FAIL: Failed package-artifact.sh corrupted or overwrote pre-existing latest-artifact.txt!" >&2
  exit 1
}

# Probe K: Subsequent valid package atomically updates latest-artifact.txt only after full success
TEST_MODE="1" GBA_REPO_ROOT_OVERRIDE="${MOCK_REPO_COPY}" "${SCRIPT_DIR}/package-artifact.sh" "clean-pkg-2" "${TEST_GIT_SHA}" >/dev/null
[ "$(cat "${MOCK_REPO_COPY}/dist/latest-artifact.txt")" = "gba-static-clean-pkg-2.tar.gz" ] || {
  echo "  ✗ FAIL: latest-artifact.txt was not updated after clean-pkg-2 succeeded!" >&2
  exit 1
}

# Probe L: Packaging OS-held flock fail-closed check & two-concurrent-invocation atomic NO-CLOBBER regression
if TEST_MODE="1" GBA_DISABLE_FLOCK="1" GBA_REPO_ROOT_OVERRIDE="${MOCK_REPO_COPY}" "${SCRIPT_DIR}/package-artifact.sh" "flock-disabled-pkg" "${TEST_GIT_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: package-artifact.sh succeeded when flock was unavailable (GBA_DISABLE_FLOCK=1)!" >&2
  exit 1
fi
[ ! -e "${MOCK_REPO_COPY}/dist/gba-static-flock-disabled-pkg.tar.gz" ] || {
  echo "  ✗ FAIL: package-artifact.sh created artifact when flock was disabled!" >&2
  exit 1
}

CONC_REL="concurrent-pkg-rel"
GIT_SHA_PUB1="aaaa111111111111111111111111111111111111"
GIT_SHA_PUB2="bbbb222222222222222222222222222222222222"
PUB1_LOG="${TEST_ENV_DIR}/pub1.log"
PUB2_LOG="${TEST_ENV_DIR}/pub2.log"
PUB1_RC=0
PUB2_RC=0

(
  TEST_MODE="1" TEST_PACKAGE_LOCK_DELAY_SEC="0.35" GBA_REPO_ROOT_OVERRIDE="${MOCK_REPO_COPY}" \
    "${SCRIPT_DIR}/package-artifact.sh" "${CONC_REL}" "${GIT_SHA_PUB1}" >"${PUB1_LOG}" 2>&1
) &
PUB1_PID=$!

(
  sleep 0.05
  TEST_MODE="1" TEST_PACKAGE_LOCK_DELAY_SEC="0.35" GBA_REPO_ROOT_OVERRIDE="${MOCK_REPO_COPY}" \
    "${SCRIPT_DIR}/package-artifact.sh" "${CONC_REL}" "${GIT_SHA_PUB2}" >"${PUB2_LOG}" 2>&1
) &
PUB2_PID=$!

wait "${PUB1_PID}" || PUB1_RC=$?
wait "${PUB2_PID}" || PUB2_RC=$?

if { [ "${PUB1_RC}" -eq 0 ] && [ "${PUB2_RC}" -eq 0 ]; } || { [ "${PUB1_RC}" -ne 0 ] && [ "${PUB2_RC}" -ne 0 ]; }; then
  echo "  ✗ FAIL: Expected exactly one concurrent package-artifact.sh invocation to succeed, got rc1=${PUB1_RC}, rc2=${PUB2_RC}!" >&2
  exit 1
fi

if [ "${PUB1_RC}" -eq 0 ]; then
  WINNER_LOG="${PUB1_LOG}"
  WINNER_GIT_SHA="${GIT_SHA_PUB1}"
else
  WINNER_LOG="${PUB2_LOG}"
  WINNER_GIT_SHA="${GIT_SHA_PUB2}"
fi

WINNER_SHA256="$(awk '/^  SHA256:/ {print $2}' "${WINNER_LOG}")"
[ -n "${WINNER_SHA256}" ] || { echo "  ✗ FAIL: Could not parse winner SHA256 from packaging log!" >&2; exit 1; }

CONC_TARBALL="${MOCK_REPO_COPY}/dist/gba-static-${CONC_REL}.tar.gz"
CONC_SHA_FILE="${CONC_TARBALL}.sha256"
[ -f "${CONC_TARBALL}" ] && [ -f "${CONC_SHA_FILE}" ] || {
  echo "  ✗ FAIL: Winner artifact or checksum missing after concurrent packaging!" >&2
  exit 1
}

ACTUAL_CONC_SHA256="$(shasum -a 256 "${CONC_TARBALL}" | awk '{print $1}')"
RECORDED_CONC_SHA256="$(awk '{print $1}' "${CONC_SHA_FILE}")"
[ "${ACTUAL_CONC_SHA256}" = "${WINNER_SHA256}" ] && [ "${RECORDED_CONC_SHA256}" = "${WINNER_SHA256}" ] || {
  echo "  ✗ FAIL: Winner artifact/checksum was altered by concurrent contender (winner=${WINNER_SHA256}, actual=${ACTUAL_CONC_SHA256}, recorded=${RECORDED_CONC_SHA256})!" >&2
  exit 1
}

python3 - "${CONC_TARBALL}" "${WINNER_GIT_SHA}" <<'PYEOF'
import json, sys, tarfile
tar_p, exp_sha = sys.argv[1:3]
with tarfile.open(tar_p, "r:gz") as tf:
    meta = json.loads(tf.extractfile("./release-metadata.json").read().decode("utf-8"))
if meta.get("git_sha") != exp_sha:
    sys.stderr.write(f"FAIL: Tarball metadata git_sha {meta.get('git_sha')!r} != winner {exp_sha!r}\n")
    sys.exit(1)
PYEOF

[ "$(cat "${MOCK_REPO_COPY}/dist/latest-artifact.txt")" = "gba-static-${CONC_REL}.tar.gz" ] || {
  echo "  ✗ FAIL: latest-artifact.txt does not match winner artifact after concurrent packaging!" >&2
  exit 1
}
[ ! -e "${MOCK_REPO_COPY}/dist/.gba-package.lock.meta" ] || {
  echo "  ✗ FAIL: Packaging lock metadata file was not cleaned up after exit!" >&2
  exit 1
}
LEFTOVER_CONC_TEMPS="$(find "${MOCK_REPO_COPY}/dist" -maxdepth 1 \( -name '.*tmp*' -o -name 'staging-*' -o -name '.staging-*' \) 2>/dev/null || true)"
[ -z "${LEFTOVER_CONC_TEMPS}" ] || {
  echo "  ✗ FAIL: Concurrent packaging left temporary paths in dist/: ${LEFTOVER_CONC_TEMPS}" >&2
  exit 1
}
rm -f "${PUB1_LOG}" "${PUB2_LOG}"
rm -rf "${MOCK_REPO_COPY}" "${VICTIM_DIR}"

echo "  ✓ Tarball packaging enforces OS-held flock lock, atomic NO-CLOBBER publication across concurrent publishers, and latest-pointer preservation."

# ==============================================================================
# Configure Mock Directories, Binaries & HTTP Servers
# ==============================================================================
MOCK_DOCROOT="${TEST_ENV_DIR}/web/gbafurniture.com"
MOCK_BACKUPS="${TEST_ENV_DIR}/backups/gbafurniture"
MOCK_RELEASES="${TEST_ENV_DIR}/releases/gbafurniture"
MOCK_SANDBOX="${TEST_ENV_DIR}/sandbox/gbafurniture"
MOCK_LOCK="${TEST_ENV_DIR}/.gba-deploy.lock"
MOCK_BIN="${TEST_ENV_DIR}/mock-bin"
MYSQL_LOG="${TEST_ENV_DIR}/mysql_queries.log"
mkdir -p "${MOCK_DOCROOT}" "${MOCK_BACKUPS}" "${MOCK_RELEASES}" "${MOCK_SANDBOX}" "${MOCK_BIN}"

populate_mock_wordpress() {
  local db_name="${1:-gba_wp_db}"
  mkdir -p "${MOCK_DOCROOT}"
  find "${MOCK_DOCROOT}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  mkdir -p "${MOCK_DOCROOT}/wp-content/uploads"
  cat > "${MOCK_DOCROOT}/wp-config.php" <<EOF
<?php
define( 'DB_NAME', '${db_name}' );
define( 'DB_USER', 'gba_wp_user' );
define( 'DB_PASSWORD', 's0m3_s3cr3t_p@ss!' );
define( 'DB_HOST', 'localhost' );
\$table_prefix = 'wp_';
EOF
  echo "<html><body>Old WP Home</body></html>" > "${MOCK_DOCROOT}/index.php"
  echo "Dummy upload" > "${MOCK_DOCROOT}/wp-content/uploads/sample.jpg"
}

reset_test_release_state() {
  local rel="${1:-${TEST_REL}}"
  rm -rf "${MOCK_RELEASES}/${rel}" "${MOCK_BACKUPS}/${rel}_"* "${MOCK_BACKUPS}/.rollback-recovery-"*
}

populate_mock_wordpress

TEST_PORT=3888
SANDBOX_PORT=3889
FAIL_PORT=3890
STALE_PORT=3891
FATAL_PHP_PORT=3892
SMOKE_FIXTURE_PORT=3893

python3 -m http.server "${TEST_PORT}" --bind 127.0.0.1 --directory "${MOCK_DOCROOT}" >/dev/null 2>&1 &
SERVER_PID=$!

python3 - "${SANDBOX_PORT}" "${MOCK_SANDBOX}" >/dev/null 2>&1 <<'PYEOF' &
import http.server, os, sys

port = int(sys.argv[1])
sandbox_dir = sys.argv[2]

class SandboxHandler(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path):
        clean = path.split('?', 1)[0].split('#', 1)[0]
        if clean.startswith('/release-preview'):
            rel = clean[len('/release-preview'):].lstrip('/')
            return os.path.join(sandbox_dir, rel)
        return os.path.join(sandbox_dir, clean.lstrip('/'))
    def log_message(self, format, *args):
        pass

http.server.HTTPServer(('127.0.0.1', port), SandboxHandler).serve_forever()
PYEOF
SANDBOX_SERVER_PID=$!

python3 - "${FAIL_PORT}" >/dev/null 2>&1 <<'PYEOF' &
import http.server, sys

port = int(sys.argv[1])

class Fail500Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(500)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'500 Internal Server Error')
    def log_message(self, format, *args):
        pass

http.server.HTTPServer(('127.0.0.1', port), Fail500Handler).serve_forever()
PYEOF
FAIL_SERVER_PID=$!

# Stale HTTP server serving a valid static tree but from a DIFFERENT release ID / Git SHA
STALE_HTTP_DIR="${TEST_ENV_DIR}/stale-http-root"
mkdir -p "${STALE_HTTP_DIR}"
tar -xzf "${TARBALL}" -C "${STALE_HTTP_DIR}"
cat > "${STALE_HTTP_DIR}/release-metadata.json" <<'EOF'
{
  "release_id": "stale-release-old",
  "git_sha": "1111111111111111111111111111111111111111",
  "build_timestamp_utc": "2026-01-01T00:00:00Z",
  "included_targets": ["index.html", "styles.css", "script.js", "data/", "assets/"]
}
EOF
python3 -m http.server "${STALE_PORT}" --bind 127.0.0.1 --directory "${STALE_HTTP_DIR}" >/dev/null 2>&1 &
STALE_SERVER_PID=$!

# Fatal /index.php HTTP server (returns 200 OK on / but returns PHP Fatal error / raw <?php on /index.php)
python3 - "${FATAL_PHP_PORT}" >/dev/null 2>&1 <<'PYEOF' &
import http.server, sys

port = int(sys.argv[1])

class FatalPhpHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        if self.path.startswith('/index.php'):
            self.wfile.write(b'<html><body>Fatal error: Uncaught Error: Call to undefined function wp() in /index.php:1</body></html>')
        else:
            self.wfile.write(b'<html><body>Healthy Root Wrapper</body></html>')
    def log_message(self, format, *args):
        pass

http.server.HTTPServer(('127.0.0.1', port), FatalPhpHandler).serve_forever()
PYEOF
FATAL_PHP_SERVER_PID=$!

# Controllable Smoke-Test Asset Fixture Server (serves valid unpacked artifact by default;
# injects targeted HTML fallbacks, wrong MIME types, or fake bodies based on mode file,
# and logs every received request to SMOKE_FIXTURE_REQ_LOG so preflight tests can prove zero requests)
SMOKE_FIXTURE_DIR="${TEST_ENV_DIR}/smoke-fixture-root"
SMOKE_FIXTURE_MODE_FILE="${TEST_ENV_DIR}/smoke-fixture-mode.txt"
SMOKE_FIXTURE_REQ_LOG="${TEST_ENV_DIR}/smoke-fixture-requests.log"
mkdir -p "${SMOKE_FIXTURE_DIR}"
tar -xzf "${TARBALL}" -C "${SMOKE_FIXTURE_DIR}"
printf 'valid_app_js\n' > "${SMOKE_FIXTURE_MODE_FILE}"
: > "${SMOKE_FIXTURE_REQ_LOG}"

python3 - "${SMOKE_FIXTURE_PORT}" "${SMOKE_FIXTURE_DIR}" "${SMOKE_FIXTURE_MODE_FILE}" "${SMOKE_FIXTURE_REQ_LOG}" >/dev/null 2>&1 <<'PYEOF' &
import http.server, os, struct, sys, zlib

port = int(sys.argv[1])
root_dir = sys.argv[2]
mode_file = sys.argv[3]
req_log_file = sys.argv[4]

MIME_MAP = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
}

def make_png_chunk(chunk_type, data, corrupt_crc=False):
    crc = zlib.crc32(chunk_type + data) & 0xFFFFFFFF
    if corrupt_crc:
        crc ^= 0x00000001
    return struct.pack(">I", len(data)) + chunk_type + data + struct.pack(">I", crc)

def build_valid_1x1_png():
    sig = bytes.fromhex("89504e470d0a1a0a")
    ihdr = make_png_chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
    idat = make_png_chunk(b"IDAT", zlib.compress(b"\x00\x01\x46\x60"))
    iend = make_png_chunk(b"IEND", b"")
    return sig + ihdr + idat + iend

class SmokeFixtureHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            with open(req_log_file, "a", encoding="utf-8") as rlf:
                rlf.write(f"{self.path}\n")
        except Exception:
            pass
        try:
            with open(mode_file, "r", encoding="utf-8") as mf:
                mode = mf.read().strip()
        except Exception:
            mode = "valid_app_js"

        req_target = self.path
        clean_path = req_target.split("?", 1)[0].split("#", 1)[0]
        if clean_path in ("", "/"):
            rel_path = "index.html"
        else:
            rel_path = clean_path.lstrip("/")

        disk_path = os.path.join(root_dir, rel_path)
        if not os.path.isfile(disk_path):
            self.send_response(404)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"Not Found")
            return

        with open(disk_path, "rb") as f:
            raw_bytes = f.read()

        _, ext = os.path.splitext(rel_path)
        ext = ext.lower()
        content_type = MIME_MAP.get(ext, "application/octet-stream")
        if mode == "valid_text_js" and ext == ".js":
            content_type = "text/javascript; charset=utf-8"

        claimed_content_length = None
        force_close = False

        # Targeted negative fixtures (all returning HTTP 200 OK)
        if mode == "versioned_svg_html_fallback" and req_target == "/assets/placeholders/wardrobe.svg?v=public-audit-20261020":
            content_type = "text/html; charset=utf-8"
            raw_bytes = (
                "<!DOCTYPE html><html><body><svg>Illustration only \u2014 not a product photograph</svg></body></html>"
            ).encode("utf-8")
        elif mode == "versioned_svg_html_body_with_svg_mime" and req_target == "/assets/placeholders/wardrobe.svg?v=public-audit-20261020":
            content_type = "image/svg+xml"
            raw_bytes = (
                "<!DOCTYPE html><html><body><svg>Illustration only \u2014 not a product photograph</svg></body></html>"
            ).encode("utf-8")
        elif mode == "versioned_svg_wrong_mime" and req_target == "/assets/placeholders/van.svg?v=public-audit-20261020":
            content_type = "text/plain; charset=utf-8"
        elif mode == "versioned_svg_fake_body" and req_target == "/assets/placeholders/van.svg?v=public-audit-20261020":
            content_type = "image/svg+xml"
            raw_bytes = b"Furniture removal service - plain text fake body without SVG root"
        elif mode == "versioned_svg_non_svg_xml_root" and req_target == "/assets/placeholders/van.svg?v=public-audit-20261020":
            content_type = "image/svg+xml"
            raw_bytes = b'<?xml version="1.0" encoding="UTF-8"?><g xmlns="http://www.w3.org/2000/svg"><svg>Furniture removal service</svg></g>'
        elif mode == "underlying_svg_html_fallback" and req_target == "/assets/placeholders/bed-divan.svg":
            content_type = "text/html; charset=utf-8"
            raw_bytes = (
                "<!DOCTYPE html><html><body><svg>Illustration only \u2014 not a product photograph</svg></body></html>"
            ).encode("utf-8")
        elif mode == "png_html_fallback" and req_target == "/assets/gba-logo-official-transparent.png":
            content_type = "text/html; charset=utf-8"
            raw_bytes = b"<!DOCTYPE html><html><body>Logo HTML Fallback</body></html>"
        elif mode == "png_wrong_mime" and req_target == "/assets/gba-logo-official-transparent.png":
            content_type = "image/jpeg"
        elif mode == "png_fake_body" and req_target == "/assets/gba-logo-official-transparent.png":
            content_type = "image/png"
            raw_bytes = b"FAKE_PNG_BODY_WITHOUT_89504E470D0A1A0A_SIGNATURE"
        elif mode == "png_forged_ihdr_only" and req_target == "/assets/gba-logo-official-transparent.png":
            content_type = "image/png"
            raw_bytes = (
                bytes.fromhex("89504e470d0a1a0a")
                + make_png_chunk(b"IHDR", struct.pack(">IIBBBBB", 16, 16, 8, 6, 0, 0, 0))
            )
        elif mode == "png_truncated_stream" and req_target == "/assets/gba-logo-official-transparent.png":
            content_type = "image/png"
            raw_bytes = raw_bytes[: len(raw_bytes) // 2]
        elif mode == "png_bad_crc" and req_target == "/assets/gba-logo-official-transparent.png":
            content_type = "image/png"
            raw_bytes = (
                bytes.fromhex("89504e470d0a1a0a")
                + make_png_chunk(b"IHDR", struct.pack(">IIBBBBB", 16, 16, 8, 6, 0, 0, 0), corrupt_crc=True)
                + make_png_chunk(b"IDAT", zlib.compress(b"\x00" * 65))
                + make_png_chunk(b"IEND", b"")
            )
        elif mode == "png_zero_dimensions" and req_target == "/assets/gba-logo-official-transparent.png":
            content_type = "image/png"
            raw_bytes = (
                bytes.fromhex("89504e470d0a1a0a")
                + make_png_chunk(b"IHDR", struct.pack(">IIBBBBB", 0, 16, 8, 6, 0, 0, 0))
                + make_png_chunk(b"IDAT", zlib.compress(b"\x00" * 16))
                + make_png_chunk(b"IEND", b"")
            )
        elif mode == "png_mutated_valid" and req_target == "/assets/gba-logo-official-transparent.png":
            content_type = "image/png"
            raw_bytes = build_valid_1x1_png()
        elif mode == "jpg_html_fallback" and req_target == "/assets/current-banner.jpg":
            content_type = "text/html; charset=utf-8"
            raw_bytes = b"<!DOCTYPE html><html><body>Banner HTML Fallback</body></html>"
        elif mode == "versioned_jpg_html_fallback" and req_target == "/assets/current-banner.jpg?v=hero-20261020-1677a163a5ca":
            content_type = "text/html; charset=utf-8"
            raw_bytes = b"<!DOCTYPE html><html><body>Versioned Banner HTML Fallback</body></html>"
        elif mode == "jpg_wrong_mime" and req_target == "/assets/current-banner.jpg":
            content_type = "image/png"
        elif mode == "versioned_jpg_wrong_mime" and req_target == "/assets/current-banner.jpg?v=hero-20261020-1677a163a5ca":
            content_type = "image/png"
        elif mode == "jpg_fake_body" and req_target == "/assets/current-banner.jpg":
            content_type = "image/jpeg"
            raw_bytes = b"FAKE_JPEG_BODY_WITHOUT_FFD8FF_SIGNATURE"
        elif mode == "jpg_ffd8ff00_prefix" and req_target == "/assets/current-banner.jpg":
            content_type = "image/jpeg"
            raw_bytes = bytes.fromhex("ffd8ff00")
        elif mode == "jpg_truncated_stream" and req_target == "/assets/current-banner.jpg":
            content_type = "image/jpeg"
            raw_bytes = raw_bytes[:-32]
        elif mode == "jpg_missing_sos" and req_target == "/assets/current-banner.jpg":
            content_type = "image/jpeg"
            raw_bytes = bytes.fromhex("ffd8ffc0000b080010001001011100ffd9")
        elif mode == "jpg_mutated_valid" and req_target == "/assets/current-banner.jpg":
            content_type = "image/jpeg"
            raw_bytes = raw_bytes[:2] + b"\xff\xfe\x00\x06test" + raw_bytes[2:]
        elif mode == "versioned_jpg_mutated_valid" and req_target == "/assets/current-banner.jpg?v=hero-20261020-1677a163a5ca":
            content_type = "image/jpeg"
            raw_bytes = raw_bytes[:2] + b"\xff\xfe\x00\x06test" + raw_bytes[2:]
        elif mode == "css_html_fallback" and req_target == "/styles.css?v=public-audit-20261020":
            content_type = "text/html; charset=utf-8"
            raw_bytes = b"<!DOCTYPE html><html><head><style>:root { --color-petrol: #014660; }</style></head><body>Fallback</body></html>"
        elif mode == "css_wrong_mime" and req_target == "/styles.css":
            content_type = "text/plain; charset=utf-8"
        elif mode == "css_fake_html_body" and req_target == "/styles.css?v=public-audit-20261020":
            content_type = "text/css; charset=utf-8"
            raw_bytes = b"<!DOCTYPE html><html><body>:root { --color-petrol: #014660; }</body></html>"
        elif mode == "css_fake_plain_body" and req_target == "/styles.css?v=public-audit-20261020":
            content_type = "text/css; charset=utf-8"
            raw_bytes = b"--color-petrol plain text without css block syntax"
        elif mode == "css_marker_spoofed_unbalanced" and req_target == "/styles.css?v=public-audit-20261020":
            content_type = "text/css; charset=utf-8"
            raw_bytes = b":root { --color-petrol: #014660; } .broken-rule { color: #111111;"
        elif mode == "css_marker_spoofed_malformed" and req_target == "/styles.css?v=public-audit-20261020":
            content_type = "text/css; charset=utf-8"
            raw_bytes = b":root { --color-petrol: #014660; invalid_token_without_colon; } GARBAGE_OUTSIDE_RULES"
        elif mode == "css_marker_spoofed_comment_only" and req_target == "/styles.css?v=public-audit-20261020":
            content_type = "text/css; charset=utf-8"
            raw_bytes = b"/* :root { --color-petrol: #014660; } */"
        elif mode == "css_crossed_rgb_paren_bracket" and req_target == "/styles.css?v=public-audit-20261020":
            content_type = "text/css; charset=utf-8"
            raw_bytes = b":root { --color-petrol: #014660; } .bad-rgb { color: rgb([)]; }"
        elif mode == "css_crossed_bracket_paren" and req_target == "/styles.css?v=public-audit-20261020":
            content_type = "text/css; charset=utf-8"
            raw_bytes = b":root { --color-petrol: #014660; } .bad-bracket[(]) { color: #014660; }"
        elif mode == "css_markup_div_open" and req_target == "/styles.css?v=public-audit-20261020":
            content_type = "text/css; charset=utf-8"
            raw_bytes = b":root { --color-petrol: #014660; } <div> .bad-div { color: #014660; }"
        elif mode == "css_markup_div_close" and req_target == "/styles.css?v=public-audit-20261020":
            content_type = "text/css; charset=utf-8"
            raw_bytes = b":root { --color-petrol: #014660; } </div> .bad-div-close { color: #014660; }"
        elif mode == "css_markup_bang_foo" and req_target == "/styles.css?v=public-audit-20261020":
            content_type = "text/css; charset=utf-8"
            raw_bytes = b":root { --color-petrol: #014660; } <!foo> .bad-bang { color: #014660; }"
        elif mode == "css_markup_pi_foo" and req_target == "/styles.css?v=public-audit-20261020":
            content_type = "text/css; charset=utf-8"
            raw_bytes = b":root { --color-petrol: #014660; } <?foo?> .bad-pi { color: #014660; }"
        elif mode == "versioned_css_mutated_valid" and req_target == "/styles.css?v=public-audit-20261020":
            content_type = "text/css; charset=utf-8"
            raw_bytes = raw_bytes + b"\n.mutated-probe { color: #000000; }\n"
        elif mode == "js_html_fallback" and req_target == "/script.js?v=public-audit-20261020":
            content_type = "text/html; charset=utf-8"
            with open(os.path.join(root_dir, "index.html"), "rb") as hf:
                raw_bytes = hf.read()
        elif mode == "js_wrong_mime" and req_target == "/script.js":
            content_type = "text/plain; charset=utf-8"
        elif mode == "js_fake_html_body" and req_target == "/script.js?v=public-audit-20261020":
            content_type = "application/javascript; charset=utf-8"
            raw_bytes = b"<!DOCTYPE html><html><body>const CATALOGUE_DATA = {}; function x(){}; products v=public-audit-20261020</body></html>"
        elif mode == "js_fake_plain_body" and req_target == "/script.js?v=public-audit-20261020":
            content_type = "application/javascript; charset=utf-8"
            raw_bytes = b"products v=public-audit-20261020 plain text without js syntax"
        elif mode == "js_invalid_syntax_app_mime" and req_target == "/script.js?v=public-audit-20261020":
            content_type = "application/javascript; charset=utf-8"
            raw_bytes = b'const CATALOGUE_DATA = {; function broken() { return "products v=public-audit-20261020"; };'
        elif mode == "js_invalid_syntax_text_mime" and req_target == "/script.js?v=public-audit-20261020":
            content_type = "text/javascript; charset=utf-8"
            raw_bytes = b'const CATALOGUE_DATA = {; function broken() { return "products v=public-audit-20261020"; };'
        elif mode == "versioned_js_mutated_valid" and req_target == "/script.js?v=public-audit-20261020":
            content_type = "application/javascript; charset=utf-8"
            raw_bytes = raw_bytes + b"\nvoid 0;\n"
        elif mode == "versioned_svg_mutated_valid" and req_target == "/assets/placeholders/wardrobe.svg?v=public-audit-20261020":
            content_type = "image/svg+xml"
            raw_bytes = raw_bytes.replace(b"</svg>", b"<g id=\"mutated-probe\"/></svg>")
        elif mode == "json_wrong_mime" and req_target == "/data/products.json":
            content_type = "text/html; charset=utf-8"
        elif mode == "json_fake_body" and req_target == "/data/products.json":
            content_type = "application/json; charset=utf-8"
            raw_bytes = b"{not valid json: beds-mattresses v=public-audit-20261020}"
        elif mode == "json_duplicate_keys" and req_target == "/data/products.json":
            content_type = "application/json; charset=utf-8"
            raw_bytes = b'{"categories": [], "categories": [], "products": "beds-mattresses v=public-audit-20261020"}'
        elif mode == "json_nan_constant" and req_target == "/data/products.json":
            content_type = "application/json; charset=utf-8"
            raw_bytes = b'{"categories": [], "products": "beds-mattresses v=public-audit-20261020", "bad": NaN}'
        elif mode == "incomplete_transfer_css_with_charset" and req_target == "/styles.css?v=public-audit-20261020":
            content_type = "text/css; charset=utf-8"
            claimed_content_length = len(raw_bytes) + 4096
            force_close = True
        elif mode == "incomplete_transfer_js_with_charset" and req_target == "/script.js?v=public-audit-20261020":
            content_type = "application/javascript; charset=utf-8"
            claimed_content_length = len(raw_bytes) + 4096
            force_close = True
        elif mode == "incomplete_transfer_metadata_with_charset" and req_target == "/release-metadata.json":
            content_type = "application/json; charset=utf-8"
            claimed_content_length = len(raw_bytes) + 1024
            force_close = True

        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header(
            "Content-Length",
            str(claimed_content_length if claimed_content_length is not None else len(raw_bytes)),
        )
        self.end_headers()
        self.wfile.write(raw_bytes)
        if force_close:
            self.wfile.flush()
            self.close_connection = True

    def log_message(self, format, *args):
        pass

http.server.HTTPServer(("127.0.0.1", port), SmokeFixtureHandler).serve_forever()
PYEOF
SMOKE_FIXTURE_SERVER_PID=$!

sleep 1

# Create Mock MySQL & Mysqldump Binaries for testing real SQL execution paths
cat > "${MOCK_BIN}/mysqldump" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${MOCK_MYSQLDUMP_FAIL:-0}" = "1" ]; then
  echo "mysqldump error" >&2
  exit 1
fi
printf -- '-- Mock SQL Dump\nCREATE TABLE `wp_posts` (`ID` bigint);\nCREATE TABLE `wp_options` (`option_id` bigint);\n'
EOF
chmod +x "${MOCK_BIN}/mysqldump"

cat > "${MOCK_BIN}/mysql" <<EOF
#!/usr/bin/env bash
set -euo pipefail
QUERY=""
for arg in "\$@"; do
  QUERY="\${arg}"
done

if [ -n "\${QUERY}" ]; then
  printf 'QUERY:%s\n' "\${QUERY}" >> "${MYSQL_LOG}"
fi

if [ "\${MOCK_MYSQL_CONN_FAIL:-0}" = "1" ]; then
  echo "ERROR 2002 (HY000): Can't connect to local MySQL server" >&2
  exit 1
fi

if [[ "\${QUERY}" == *"DROP DATABASE"* ]]; then
  if [ "\${MOCK_DROP_DB_DENIED:-0}" = "1" ]; then
    echo "ERROR 1044 (42000): Access denied for user to DROP DATABASE" >&2
    exit 1
  fi
  exit 0
fi

if [[ "\${QUERY}" == *"SHOW TABLES FROM"* ]]; then
  if [ "\${MOCK_SHOW_TABLES_FAIL:-0}" = "1" ]; then
    echo "ERROR 1142 (42000): SHOW command denied" >&2
    exit 1
  fi
  if [ -n "\${MOCK_TABLES_OUTPUT:-}" ]; then
    printf '%s\n' "\${MOCK_TABLES_OUTPUT}"
  fi
  exit 0
fi

if [[ "\${QUERY}" == *"DROP TABLE IF EXISTS"* ]]; then
  if [ "\${MOCK_DROP_TABLE_FAIL:-0}" = "1" ]; then
    echo "ERROR 1142 (42000): DROP command denied" >&2
    exit 1
  fi
  exit 0
fi

if [[ "\${QUERY}" == *"SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA"* ]]; then
  if [ "\${MOCK_VERIFY_SCHEMA_FAIL:-0}" = "1" ]; then
    echo "ERROR 2013 (HY000): Lost connection to MySQL server during query" >&2
    exit 1
  fi
  echo "\${MOCK_SCHEMA_COUNT:-0}"
  exit 0
fi

if [[ "\${QUERY}" == *"SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES"* ]]; then
  if [ "\${MOCK_VERIFY_TABLES_FAIL:-0}" = "1" ]; then
    echo "ERROR 2013 (HY000): Lost connection to MySQL server during query" >&2
    exit 1
  fi
  echo "\${MOCK_TABLE_COUNT:-0}"
  exit 0
fi

if [[ "\${QUERY}" == *"CREATE DATABASE IF NOT EXISTS"* ]]; then
  if [ "\${MOCK_CREATE_DB_FAIL:-0}" = "1" ]; then
    exit 1
  fi
  exit 0
fi

STDIN_DATA="\$(cat)"
if [ "\${MOCK_IMPORT_FAIL:-0}" = "1" ]; then
  echo "ERROR 1064 (42000): SQL import failed" >&2
  exit 1
fi
printf 'IMPORT:%s:%s\n' "\${QUERY}" "\$(printf '%s' "\${STDIN_DATA}" | head -n1)" >> "${MYSQL_LOG}"
exit 0
EOF
chmod +x "${MOCK_BIN}/mysql"

export PATH="${MOCK_BIN}:${ORIG_PATH}"
export TEST_MODE="1"
export TEST_USE_MYSQL_BIN="1"
export GBA_DOCROOT_OVERRIDE="${MOCK_DOCROOT}"
export GBA_BACKUP_OVERRIDE="${MOCK_BACKUPS}"
export GBA_RELEASES_OVERRIDE="${MOCK_RELEASES}"
export GBA_SANDBOX_OVERRIDE="${MOCK_SANDBOX}"
export GBA_LOCK_OVERRIDE="${MOCK_LOCK}"

# ==============================================================================
# Test 3: Packaged Checksum Verification & Mismatched Metadata Binding Rejection
# ==============================================================================
echo "[Test 3] Testing Checksum Tampering & Mismatched Metadata (release_id/git_sha/hash) Rejection..."
TAMPERED_DIR="${TEST_ENV_DIR}/tampered_pkg"
mkdir -p "${TAMPERED_DIR}"
tar -xzf "${TARBALL}" -C "${TAMPERED_DIR}"
echo "<!-- Tampered malicious content -->" >> "${TAMPERED_DIR}/index.html"
TAMPERED_TARBALL="${TEST_ENV_DIR}/tampered.tar.gz"
( cd "${TAMPERED_DIR}" && COPYFILE_DISABLE=1 tar -czf "${TAMPERED_TARBALL}" . )
TAMPERED_OUTER_SHA="$(shasum -a 256 "${TAMPERED_TARBALL}" | awk '{print $1}')"

if "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TAMPERED_TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TAMPERED_OUTER_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: Tampered package with invalid inner checksums was accepted!" >&2
  exit 1
fi

# 3b. Independent Reproduction: Reject archive containing PHP file even if checksums.sha256 is recalculated
PHP_PKG_DIR="${TEST_ENV_DIR}/php_pkg"
mkdir -p "${PHP_PKG_DIR}"
tar -xzf "${TARBALL}" -C "${PHP_PKG_DIR}"
echo '<?php echo "evil"; ?>' > "${PHP_PKG_DIR}/assets/evil.php"
(
  cd "${PHP_PKG_DIR}"
  find . -type f ! -name "checksums.sha256" -print0 | sort -z | xargs -0 shasum -a 256 > checksums.sha256
  COPYFILE_DISABLE=1 tar -czf "${TEST_ENV_DIR}/evil-php.tar.gz" .
)
EVIL_PHP_SHA="$(shasum -a 256 "${TEST_ENV_DIR}/evil-php.tar.gz" | awk '{print $1}')"
if "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TEST_ENV_DIR}/evil-php.tar.gz" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${EVIL_PHP_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: remote-deploy-production.sh accepted tarball containing assets/evil.php!" >&2
  exit 1
fi
if "${SCRIPT_DIR}/remote-deploy-sandbox.sh" "${TEST_ENV_DIR}/evil-php.tar.gz" "http://127.0.0.1:${SANDBOX_PORT}/release-preview" "${EVIL_PHP_SHA}" "${TEST_REL}" "${TEST_GIT_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: remote-deploy-sandbox.sh accepted tarball containing assets/evil.php!" >&2
  exit 1
fi

# 3c. Independent Reproduction: Mismatched invocation RELEASE_ID vs release-metadata.json
if "${SCRIPT_DIR}/remote-deploy-production.sh" "DIFFERENT_RELEASE" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: remote-deploy-production.sh accepted mismatched RELEASE_ID ('DIFFERENT_RELEASE' != '${TEST_REL}')!" >&2
  exit 1
fi
[ ! -e "${MOCK_BACKUPS}/DIFFERENT_RELEASE_files.tar.gz" ] || { echo "  ✗ FAIL: Backup written despite mismatched RELEASE_ID!" >&2; exit 1; }

# 3d. Independent Reproduction: Mismatched invocation GIT_SHA vs release-metadata.json
if "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "2222222222222222222222222222222222222222" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: remote-deploy-production.sh accepted mismatched GIT_SHA!" >&2
  exit 1
fi
if "${SCRIPT_DIR}/remote-deploy-sandbox.sh" "${TARBALL}" "http://127.0.0.1:${SANDBOX_PORT}/release-preview" "${TARBALL_HASH}" "${TEST_REL}" "2222222222222222222222222222222222222222" 2>/dev/null; then
  echo "  ✗ FAIL: remote-deploy-sandbox.sh accepted mismatched GIT_SHA!" >&2
  exit 1
fi

# 3e. Independent Reproduction: Mismatched invocation ARTIFACT_SHA256
WRONG_SHA256="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
if "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${WRONG_SHA256}" 2>/dev/null; then
  echo "  ✗ FAIL: remote-deploy-production.sh accepted mismatched ARTIFACT_SHA256!" >&2
  exit 1
fi
if "${SCRIPT_DIR}/remote-deploy-sandbox.sh" "${TARBALL}" "http://127.0.0.1:${SANDBOX_PORT}/release-preview" "${WRONG_SHA256}" "${TEST_REL}" "${TEST_GIT_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: remote-deploy-sandbox.sh accepted mismatched ARTIFACT_SHA256!" >&2
  exit 1
fi
echo "  ✓ Tampered packages and mismatched release_id, git_sha, and artifact_sha256 rejected before cutover."

# ==============================================================================
# Test 4: Dual Archive Integrity Verification Before Cutover
# ==============================================================================
echo "[Test 4] Testing Dual Archive Integrity Verification Before Cutover..."
export TEST_USE_MYSQL_BIN="0"
export TEST_CORRUPT_DB_BACKUP="1"
if "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: Corrupt database gzip dump was accepted during deployment pre-cutover!" >&2
  exit 1
fi
export TEST_CORRUPT_DB_BACKUP="0"
export TEST_USE_MYSQL_BIN="1"
reset_test_release_state "${TEST_REL}"
[ -f "${MOCK_DOCROOT}/wp-config.php" ] || { echo "Fail: docroot altered during failed backup integrity test"; exit 1; }
echo "  ✓ Corrupt DB gzip backup was rejected by gzip -t; deployment aborted before cutover."

# ==============================================================================
# Test 5: Reproduce Remote Command Injection & SQL Identifier Injection Rejection
# ==============================================================================
echo "[Test 5] Reproducing Remote Command Injection & SQL Identifier Injection Rejection..."
PWN_MARKER="${TEST_ENV_DIR}/pwned_marker"
INJECT_URLS=(
  "https://gbafurniture.com';touch ${PWN_MARKER};'"
  "http://127.0.0.1:${TEST_PORT}/\$(touch ${PWN_MARKER})"
  "http://127.0.0.1:${TEST_PORT}/\`touch ${PWN_MARKER}\`"
  "file:///etc/passwd"
  "-oProxyCommand=touch"
)
for bad_url in "${INJECT_URLS[@]}"; do
  if "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "${bad_url}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
    echo "  ✗ FAIL: remote-deploy-production.sh accepted malicious URL '${bad_url}'!" >&2
    exit 1
  fi
  if "${SCRIPT_DIR}/remote-deploy-sandbox.sh" "${TARBALL}" "${bad_url}" "${TARBALL_HASH}" 2>/dev/null; then
    echo "  ✗ FAIL: remote-deploy-sandbox.sh accepted malicious URL '${bad_url}'!" >&2
    exit 1
  fi
  if "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "${bad_url}" 2>/dev/null; then
    echo "  ✗ FAIL: rollback.sh accepted malicious URL '${bad_url}'!" >&2
    exit 1
  fi
  if EXPECTED_METADATA_FILE="${SMOKE_FIXTURE_DIR}/release-metadata.json" \
     EXPECTED_ASSET_ROOT="${SMOKE_FIXTURE_DIR}" \
     "${SCRIPT_DIR}/smoke-test.sh" "${bad_url}" 2>/dev/null; then
    echo "  ✗ FAIL: smoke-test.sh accepted malicious URL '${bad_url}'!" >&2
    exit 1
  fi
  if [ -e "${PWN_MARKER}" ]; then
    echo "  ✗ FAIL: Command injection payload executed and created ${PWN_MARKER}!" >&2
    exit 1
  fi
done
echo "  ✓ Malicious URL command injection payloads rejected across all scripts."

# Reproduce SQL identifier injection in wp-config.php DB_NAME and SHOW TABLES output
populate_mock_wordpress 'gba_wp_db`; DROP DATABASE mysql; --'
if "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: SQL injection in DB_NAME was accepted!" >&2
  exit 1
fi
reset_test_release_state "${TEST_REL}"
populate_mock_wordpress

# Reproduce malicious table identifier returned during table-by-table fallback
export MOCK_DROP_DB_DENIED="1"
export MOCK_TABLES_OUTPUT="wp_posts;DROP DATABASE mysql"
if "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: Invalid SQL table identifier was accepted during fallback drop!" >&2
  exit 1
fi
export MOCK_DROP_DB_DENIED="0"
export MOCK_TABLES_OUTPUT=""
reset_test_release_state "${TEST_REL}"
populate_mock_wordpress
echo "  ✓ SQL identifier validation & backtick quoting rejected unsafe DB and table names."

# ==============================================================================
# Test 6: Canonical Realpath Guards, 2400-Symlink Flood, .gba-sandbox-recovery & Sandbox Isolation
# ==============================================================================
echo "[Test 6] Reproducing Symlink Rejection, 2400-Symlink Flood, .gba-sandbox-recovery Guards & Sandbox Isolation..."

# 6a. Overrides must be rejected when TEST_MODE != 1
if TEST_MODE="0" GBA_DOCROOT_OVERRIDE="${MOCK_DOCROOT}" "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: GBA_DOCROOT_OVERRIDE was allowed when TEST_MODE=0!" >&2
  exit 1
fi
if TEST_MODE="0" GBA_SANDBOX_OVERRIDE="${MOCK_SANDBOX}" "${SCRIPT_DIR}/remote-deploy-sandbox.sh" "${TARBALL}" "http://127.0.0.1:${SANDBOX_PORT}/release-preview" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: GBA_SANDBOX_OVERRIDE was allowed when TEST_MODE=0!" >&2
  exit 1
fi
if TEST_MODE="0" GBA_BACKUP_OVERRIDE="${MOCK_BACKUPS}" "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${TEST_PORT}" 2>/dev/null; then
  echo "  ✗ FAIL: GBA_BACKUP_OVERRIDE was allowed when TEST_MODE=0!" >&2
  exit 1
fi
echo "  ✓ Path overrides strictly rejected outside TEST_MODE=1."

# 6b. Symlinked target directories and symlinked parent components must be rejected
SYMLINK_DOCROOT="${TEST_ENV_DIR}/symlink-docroot"
SYMLINK_BACKUP="${TEST_ENV_DIR}/symlink-backup"
SYMLINK_SANDBOX="${TEST_ENV_DIR}/symlink-sandbox"
SYMLINK_PARENT="${TEST_ENV_DIR}/symlink-parent"
ln -s "${MOCK_DOCROOT}" "${SYMLINK_DOCROOT}"
ln -s "${MOCK_BACKUPS}" "${SYMLINK_BACKUP}"
ln -s "${MOCK_SANDBOX}" "${SYMLINK_SANDBOX}"
ln -s "${TEST_ENV_DIR}/web" "${SYMLINK_PARENT}"

if GBA_DOCROOT_OVERRIDE="${SYMLINK_DOCROOT}" "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: Symlinked DOCROOT was accepted!" >&2
  exit 1
fi
if GBA_DOCROOT_OVERRIDE="${SYMLINK_PARENT}/gbafurniture.com" "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: Symlinked ancestor directory was accepted!" >&2
  exit 1
fi
if GBA_BACKUP_OVERRIDE="${SYMLINK_BACKUP}" "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: Symlinked BACKUP_ROOT was accepted!" >&2
  exit 1
fi
if GBA_SANDBOX_OVERRIDE="${SYMLINK_SANDBOX}" "${SCRIPT_DIR}/remote-deploy-sandbox.sh" "${TARBALL}" "http://127.0.0.1:${SANDBOX_PORT}/release-preview" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: Symlinked SANDBOX_DIR was accepted!" >&2
  exit 1
fi
if GBA_DOCROOT_OVERRIDE="${SYMLINK_DOCROOT}" "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${TEST_PORT}" 2>/dev/null; then
  echo "  ✗ FAIL: Symlinked DOCROOT was accepted by rollback.sh!" >&2
  exit 1
fi
rm -f "${SYMLINK_DOCROOT}" "${SYMLINK_BACKUP}" "${SYMLINK_SANDBOX}" "${SYMLINK_PARENT}"

# 6c. Independent Reproduction: 2,400-Symlink Flood Fail-Open Test (exceeds 64KB pipe buffer under pipefail)
LINK_FLOOD_DIR="${TEST_ENV_DIR}/link-flood"
mkdir -p "${LINK_FLOOD_DIR}"
python3 - "${LINK_FLOOD_DIR}" <<'PYEOF'
import os, sys
base = sys.argv[1]
suffix = "x" * 120
for i in range(2400):
    os.symlink("missing", os.path.join(base, f"{i}{suffix}"))
PYEOF

FLOOD_OUT=""
if FLOOD_OUT="$(GBA_DOCROOT_OVERRIDE="${LINK_FLOOD_DIR}" "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>&1)"; then
  echo "  ✗ FAIL: 2400-symlink flood directory failed open in remote-deploy-production.sh!" >&2
  exit 1
fi
grep -F -q "Symlink detected inside DOCROOT" <<< "${FLOOD_OUT}" || { echo "  ✗ FAIL: Production script did not catch 2400-symlink flood at DOCROOT guard!" >&2; exit 1; }
[ ! -e "${MOCK_BACKUPS}/${TEST_REL}_files.tar.gz" ] || { echo "  ✗ FAIL: Production script created backup on symlink-flooded docroot!" >&2; exit 1; }

if FLOOD_OUT="$(GBA_SANDBOX_OVERRIDE="${LINK_FLOOD_DIR}" "${SCRIPT_DIR}/remote-deploy-sandbox.sh" "${TARBALL}" "http://127.0.0.1:${SANDBOX_PORT}/release-preview" "${TARBALL_HASH}" 2>&1)"; then
  echo "  ✗ FAIL: 2400-symlink flood directory failed open in remote-deploy-sandbox.sh!" >&2
  exit 1
fi
grep -F -q "Symlink detected inside SANDBOX_DIR" <<< "${FLOOD_OUT}" || { echo "  ✗ FAIL: Sandbox script did not catch 2400-symlink flood at SANDBOX_DIR guard!" >&2; exit 1; }

if FLOOD_OUT="$(GBA_DOCROOT_OVERRIDE="${LINK_FLOOD_DIR}" "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${TEST_PORT}" 2>&1)"; then
  echo "  ✗ FAIL: 2400-symlink flood directory failed open in rollback.sh!" >&2
  exit 1
fi
grep -F -q "Symlink detected inside DOCROOT" <<< "${FLOOD_OUT}" || { echo "  ✗ FAIL: Rollback script did not catch 2400-symlink flood at DOCROOT guard!" >&2; exit 1; }
rm -rf "${LINK_FLOOD_DIR}"
echo "  ✓ 2,400-symlink flood deterministically rejected at entry guard without SIGPIPE fail-open."

# 6d. Non-canonical dot segments and overlapping directories must be rejected
if GBA_DOCROOT_OVERRIDE="${MOCK_DOCROOT}/../gbafurniture.com" "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: Non-canonical '../' path was accepted!" >&2
  exit 1
fi
if GBA_BACKUP_OVERRIDE="${MOCK_DOCROOT}/nested-backups" "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: BACKUP_ROOT inside DOCROOT was accepted!" >&2
  exit 1
fi
if GBA_SANDBOX_OVERRIDE="${MOCK_DOCROOT}/release-preview" "${SCRIPT_DIR}/remote-deploy-sandbox.sh" "${TARBALL}" "http://127.0.0.1:${SANDBOX_PORT}/release-preview" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: SANDBOX_DIR inside DOCROOT was accepted!" >&2
  exit 1
fi
echo "  ✓ Symlinks, non-canonical dot paths, and docroot-overlapping paths rejected."

# 6e. Independent Reproduction: Sandbox .gba-sandbox-recovery root and child symlink rejection + ownership tracking
SANDBOX_RECOVERY_ROOT="$(dirname "${MOCK_SANDBOX}")/.gba-sandbox-recovery"
rm -rf "${SANDBOX_RECOVERY_ROOT}"
REC_VICTIM="${TEST_ENV_DIR}/rec-victim"
mkdir -p "${REC_VICTIM}"
echo "keep-victim" > "${REC_VICTIM}/keep.txt"

# Symlinked .gba-sandbox-recovery root must be rejected
ln -s "${REC_VICTIM}" "${SANDBOX_RECOVERY_ROOT}"
if "${SCRIPT_DIR}/remote-deploy-sandbox.sh" "${TARBALL}" "http://127.0.0.1:${SANDBOX_PORT}/release-preview" "${TARBALL_HASH}" "${TEST_REL}" "${TEST_GIT_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: remote-deploy-sandbox.sh accepted symlinked .gba-sandbox-recovery root!" >&2
  exit 1
fi
[ -f "${REC_VICTIM}/keep.txt" ] || { echo "  ✗ FAIL: Symlinked .gba-sandbox-recovery target was deleted!" >&2; exit 1; }
rm -f "${SANDBOX_RECOVERY_ROOT}"

# Child symlink inside .gba-sandbox-recovery must be rejected
mkdir -m 700 -p "${SANDBOX_RECOVERY_ROOT}"
ln -s "${REC_VICTIM}" "${SANDBOX_RECOVERY_ROOT}/child-symlink"
if "${SCRIPT_DIR}/remote-deploy-sandbox.sh" "${TARBALL}" "http://127.0.0.1:${SANDBOX_PORT}/release-preview" "${TARBALL_HASH}" "${TEST_REL}" "${TEST_GIT_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: remote-deploy-sandbox.sh accepted child symlink inside .gba-sandbox-recovery!" >&2
  exit 1
fi
rm -f "${SANDBOX_RECOVERY_ROOT}/child-symlink"
rm -rf "${REC_VICTIM}"

# Pre-existing recovery evidence from a prior run inside .gba-sandbox-recovery must NOT be deleted by a new invocation
mkdir -m 700 -p "${SANDBOX_RECOVERY_ROOT}/prior-preserved-evidence"
echo "preserved-archive" > "${SANDBOX_RECOVERY_ROOT}/prior-preserved-evidence/keep.tar.gz"

# 6f. Verify Sandbox deploys cleanly outside docroot to MOCK_SANDBOX and preserves non-owned recovery paths
"${SCRIPT_DIR}/remote-deploy-sandbox.sh" "${TARBALL}" "http://127.0.0.1:${SANDBOX_PORT}/release-preview" "${TARBALL_HASH}" "${TEST_REL}" "${TEST_GIT_SHA}" >/dev/null
[ -f "${MOCK_SANDBOX}/index.html" ] || { echo "Fail: sandbox index.html missing"; exit 1; }
[ -f "${MOCK_SANDBOX}/styles.css" ] || { echo "Fail: sandbox styles.css missing"; exit 1; }
[ -f "${MOCK_SANDBOX}/script.js" ] || { echo "Fail: sandbox script.js missing"; exit 1; }
[ -f "${MOCK_SANDBOX}/data/products.json" ] || { echo "Fail: sandbox data/products.json missing"; exit 1; }
[ -f "${MOCK_SANDBOX}/assets/gba-logo-official-transparent.png" ] || { echo "Fail: sandbox assets/gba-logo-official-transparent.png missing"; exit 1; }
[ -f "${MOCK_SANDBOX}/release-metadata.json" ] || { echo "Fail: sandbox release-metadata.json missing"; exit 1; }
[ ! -d "${MOCK_DOCROOT}/release-preview" ] || { echo "Fail: sandbox wrote inside MOCK_DOCROOT!"; exit 1; }
[ -f "${SANDBOX_RECOVERY_ROOT}/prior-preserved-evidence/keep.tar.gz" ] || { echo "  ✗ FAIL: Sandbox cleanup deleted non-owned prior recovery path!" >&2; exit 1; }
rm -rf "${SANDBOX_RECOVERY_ROOT}/prior-preserved-evidence"
echo "  ✓ Sandbox .gba-sandbox-recovery enforces canonical ancestry, rejects root/child symlinks, tracks ownership, and deploys strictly outside docroot."

# ==============================================================================
# Test 7: Reproduce MySQL Verification Failures (No Suppression), Zero-Table Proof,
#         and Full Files + DB Restoration When DB Deletion Has Begun and Fails
# ==============================================================================
echo "[Test 7] Reproducing MySQL Verification Failures, Positive Zero-Table Proof & Post-DB-Deletion Recovery..."

# 7a. When MySQL verification query fails AFTER DROP DATABASE ran, script MUST fail AND restore both WordPress files and DB!
populate_mock_wordpress
: > "${MYSQL_LOG}"
export MOCK_VERIFY_SCHEMA_FAIL="1"
if "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: MySQL schema verification query failure was suppressed and treated as success!" >&2
  exit 1
fi
export MOCK_VERIFY_SCHEMA_FAIL="0"
[ -f "${MOCK_DOCROOT}/wp-config.php" ] || { echo "  ✗ FAIL: wp-config.php was NOT restored when post-DROP schema verification failed!" >&2; exit 1; }
[ -f "${MOCK_DOCROOT}/index.php" ] || { echo "  ✗ FAIL: index.php was NOT restored when post-DROP schema verification failed!" >&2; exit 1; }
[ ! -f "${MOCK_DOCROOT}/styles.css" ] || { echo "  ✗ FAIL: Candidate styles.css remained in docroot after post-DROP failure!" >&2; exit 1; }
[ ! -d "${MOCK_RELEASES}/${TEST_REL}" ] || { echo "  ✗ FAIL: RELEASE_DIR was not cleaned up after post-DROP failure!" >&2; exit 1; }
grep -q "CREATE DATABASE IF NOT EXISTS \`gba_wp_db\`" "${MYSQL_LOG}" || { echo "  ✗ FAIL: Database was NOT recreated during recovery after DB deletion began!" >&2; exit 1; }
grep -q "IMPORT:gba_wp_db:-- Mock SQL Dump" "${MYSQL_LOG}" || { echo "  ✗ FAIL: Database backup was NOT re-imported during recovery after DB deletion began!" >&2; exit 1; }
grep -q '"status": "aborted_post_cutover_files_and_db_restored"' "${MOCK_BACKUPS}/${TEST_REL}_manifest.json" || { echo "  ✗ FAIL: Manifest did not record aborted_post_cutover_files_and_db_restored!" >&2; exit 1; }
reset_test_release_state "${TEST_REL}"

# 7b. When DROP DATABASE is denied and SHOW TABLES fails during fallback, script MUST fail and restore both files and DB
populate_mock_wordpress
: > "${MYSQL_LOG}"
export MOCK_DROP_DB_DENIED="1"
export MOCK_SHOW_TABLES_FAIL="1"
if "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: MySQL SHOW TABLES failure during fallback cleanup was suppressed!" >&2
  exit 1
fi
export MOCK_DROP_DB_DENIED="0"
export MOCK_SHOW_TABLES_FAIL="0"
[ -f "${MOCK_DOCROOT}/wp-config.php" ] || { echo "  ✗ FAIL: wp-config.php was NOT restored after SHOW TABLES fallback failure!" >&2; exit 1; }
grep -q "IMPORT:gba_wp_db:-- Mock SQL Dump" "${MYSQL_LOG}" || { echo "  ✗ FAIL: Database backup was NOT restored after SHOW TABLES fallback failure!" >&2; exit 1; }
reset_test_release_state "${TEST_REL}"

# 7c. When database still exists and tables remain (SCHEMA_COUNT=1, TABLE_COUNT=2), script MUST fail and restore both files and DB
populate_mock_wordpress
: > "${MYSQL_LOG}"
export MOCK_SCHEMA_COUNT="1"
export MOCK_TABLE_COUNT="2"
if "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: Remaining tables in database were ignored!" >&2
  exit 1
fi
export MOCK_SCHEMA_COUNT="0"
export MOCK_TABLE_COUNT="0"
[ -f "${MOCK_DOCROOT}/wp-config.php" ] || { echo "  ✗ FAIL: wp-config.php was NOT restored when remaining tables were detected!" >&2; exit 1; }
grep -q "IMPORT:gba_wp_db:-- Mock SQL Dump" "${MYSQL_LOG}" || { echo "  ✗ FAIL: Database was NOT restored when remaining tables were detected!" >&2; exit 1; }
reset_test_release_state "${TEST_REL}"

# 7d. Production DB recovery when CREATE DATABASE IF NOT EXISTS is denied:
#     Must positively query INFORMATION_SCHEMA.SCHEMATA; import only if count == 1; fail recovery if 0, unexpected count, or query error
populate_mock_wordpress
: > "${MYSQL_LOG}"
export MOCK_DROP_DB_DENIED="1"
export MOCK_SHOW_TABLES_FAIL="1"
export MOCK_CREATE_DB_FAIL="1"
export MOCK_SCHEMA_COUNT="1"
if "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: Production deploy succeeded despite SHOW TABLES failure!" >&2
  exit 1
fi
grep -q "IMPORT:gba_wp_db:-- Mock SQL Dump" "${MYSQL_LOG}" || {
  echo "  ✗ FAIL: Production DB recovery did not import backup when CREATE DATABASE was denied but schema count was 1!" >&2
  exit 1
}
grep -q '"status": "aborted_post_cutover_files_and_db_restored"' "${MOCK_BACKUPS}/${TEST_REL}_manifest.json" || {
  echo "  ✗ FAIL: Manifest did not record aborted_post_cutover_files_and_db_restored when schema count was 1!" >&2
  exit 1
}
reset_test_release_state "${TEST_REL}"

for bad_recovery_case in "count_zero" "count_two" "query_error"; do
  populate_mock_wordpress
  : > "${MYSQL_LOG}"
  export MOCK_DROP_DB_DENIED="1"
  export MOCK_SHOW_TABLES_FAIL="1"
  export MOCK_CREATE_DB_FAIL="1"
  if [ "${bad_recovery_case}" = "count_zero" ]; then
    export MOCK_SCHEMA_COUNT="0"
    export MOCK_VERIFY_SCHEMA_FAIL="0"
  elif [ "${bad_recovery_case}" = "count_two" ]; then
    export MOCK_SCHEMA_COUNT="2"
    export MOCK_VERIFY_SCHEMA_FAIL="0"
  else
    export MOCK_SCHEMA_COUNT="1"
    export MOCK_VERIFY_SCHEMA_FAIL="1"
  fi
  if "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
    echo "  ✗ FAIL: Production deploy succeeded during ${bad_recovery_case} recovery test!" >&2
    exit 1
  fi
  if grep -q "IMPORT:gba_wp_db:" "${MYSQL_LOG}"; then
    echo "  ✗ FAIL: Production DB recovery imported backup despite ${bad_recovery_case} when CREATE DATABASE was denied!" >&2
    exit 1
  fi
  [ -s "${MOCK_BACKUPS}/${TEST_REL}_files.tar.gz" ] && [ -s "${MOCK_BACKUPS}/${TEST_REL}_db.sql.gz" ] || {
    echo "  ✗ FAIL: Recovery evidence was not preserved on failed DB recovery (${bad_recovery_case})!" >&2
    exit 1
  }
  grep -q '"status": "aborted_restore_failed_evidence_preserved"' "${MOCK_BACKUPS}/${TEST_REL}_manifest.json" || {
    echo "  ✗ FAIL: Manifest did not record aborted_restore_failed_evidence_preserved on ${bad_recovery_case}!" >&2
    exit 1
  }
  reset_test_release_state "${TEST_REL}"
done
export MOCK_DROP_DB_DENIED="0"
export MOCK_SHOW_TABLES_FAIL="0"
export MOCK_CREATE_DB_FAIL="0"
export MOCK_SCHEMA_COUNT="0"
export MOCK_VERIFY_SCHEMA_FAIL="0"
echo "  ✓ MySQL verification failures and CREATE DATABASE denial recovery checks enforce positive schema existence (count == 1)."

# ==============================================================================
# Test 8: Comprehensive Post-Mutation & Finalization Failure Recovery
#         (rsync, chmod, identity, HTTP 500, and atomic final manifest write failure)
# ==============================================================================
echo "[Test 8] Reproducing Injected rsync/chmod/Manifest Failures, Public Identity Mismatch & Smoke Auto-Restore..."

# 8a. Independent Reproduction: Injected rsync partial failure (deletes old-sentinel, writes partial-write, exits 23)
FAIL_RSYNC_BIN="${TEST_ENV_DIR}/fail-rsync-bin"
mkdir -p "${FAIL_RSYNC_BIN}"
cat > "${FAIL_RSYNC_BIN}/rsync" <<'EOF'
#!/usr/bin/env bash
set -eu
for arg in "$@"; do dest="$arg"; done
rm -f -- "${dest%/}/old-sentinel"
printf partial > "${dest%/}/partial-write"
exit 23
EOF
chmod +x "${FAIL_RSYNC_BIN}/rsync"

# Test sandbox recovery on rsync failure
find "${MOCK_SANDBOX}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
printf 'GBA Furniture old' > "${MOCK_SANDBOX}/index.html"
printf 'ok\n' > "${MOCK_SANDBOX}/old-sentinel"
if PATH="${FAIL_RSYNC_BIN}:${PATH}" "${SCRIPT_DIR}/remote-deploy-sandbox.sh" "${TARBALL}" "http://127.0.0.1:${SANDBOX_PORT}/release-preview" "${TARBALL_HASH}" "${TEST_REL}" "${TEST_GIT_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: Sandbox deployment succeeded despite rsync exit 23!" >&2
  exit 1
fi
[ -f "${MOCK_SANDBOX}/old-sentinel" ] || { echo "  ✗ FAIL: Sandbox old-sentinel was NOT restored after rsync failure!" >&2; exit 1; }
[ ! -e "${MOCK_SANDBOX}/partial-write" ] || { echo "  ✗ FAIL: Sandbox partial-write was left behind after rsync failure!" >&2; exit 1; }
[ "$(cat "${MOCK_SANDBOX}/index.html")" = "GBA Furniture old" ] || { echo "  ✗ FAIL: Sandbox index.html was not restored after rsync failure!" >&2; exit 1; }
rm -rf "${SANDBOX_RECOVERY_ROOT}/run-"*

# Test production recovery on rsync failure
populate_mock_wordpress
printf 'ok\n' > "${MOCK_DOCROOT}/old-sentinel"
if PATH="${FAIL_RSYNC_BIN}:${PATH}" "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: Production deployment succeeded despite rsync exit 23!" >&2
  exit 1
fi
[ -f "${MOCK_DOCROOT}/old-sentinel" ] || { echo "  ✗ FAIL: Production old-sentinel was NOT restored after rsync failure!" >&2; exit 1; }
[ -f "${MOCK_DOCROOT}/wp-config.php" ] || { echo "  ✗ FAIL: Production wp-config.php was NOT restored after rsync failure!" >&2; exit 1; }
[ ! -e "${MOCK_DOCROOT}/partial-write" ] || { echo "  ✗ FAIL: Production partial-write was left behind after rsync failure!" >&2; exit 1; }
[ -s "${MOCK_BACKUPS}/${TEST_REL}_files.tar.gz" ] || { echo "  ✗ FAIL: Recovery archive was deleted after rsync failure!" >&2; exit 1; }
reset_test_release_state "${TEST_REL}"

# 8a2. Independent Reproduction: Successful-copy rsync that silently mutates destination CSS bytes
#      Sandbox must smoke against checksum-verified retained STAGE_DIR (not newly written SANDBOX_DIR),
#      detect the mutated CSS bytes, fail deployment, and restore the previous sandbox state!
#      Production must continue smoking against immutable checksum-verified RELEASE_DIR and restore DOCROOT.
MUTATE_CSS_RSYNC_BIN="${TEST_ENV_DIR}/mutate-css-rsync-bin"
mkdir -p "${MUTATE_CSS_RSYNC_BIN}"
cat > "${MUTATE_CSS_RSYNC_BIN}/rsync" <<'EOF'
#!/usr/bin/env bash
set -eu
/usr/bin/rsync "$@"
if [[ "$*" != *"--server"* ]]; then
  for arg in "$@"; do dest="$arg"; done
  if [ -f "${dest%/}/styles.css" ]; then
    printf '\n.rsync-silent-mutation { color: #000000; }\n' >> "${dest%/}/styles.css"
  fi
fi
exit 0
EOF
chmod +x "${MUTATE_CSS_RSYNC_BIN}/rsync"

find "${MOCK_SANDBOX}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
printf 'GBA Furniture old' > "${MOCK_SANDBOX}/index.html"
printf 'ok\n' > "${MOCK_SANDBOX}/old-sentinel"
MUTATE_SBX_OUT=""
if MUTATE_SBX_OUT="$(PATH="${MUTATE_CSS_RSYNC_BIN}:${PATH}" "${SCRIPT_DIR}/remote-deploy-sandbox.sh" "${TARBALL}" "http://127.0.0.1:${SANDBOX_PORT}/release-preview" "${TARBALL_HASH}" "${TEST_REL}" "${TEST_GIT_SHA}" 2>&1)"; then
  echo "  ✗ FAIL: Sandbox deployment succeeded despite silent rsync CSS byte mutation!" >&2
  exit 1
fi
grep -F -q "Trusted byte verification failed for 'styles.css'" <<< "${MUTATE_SBX_OUT}" || {
  echo "  ✗ FAIL: Sandbox deployment did not detect silent rsync CSS mutation against retained STAGE_DIR:" >&2
  echo "${MUTATE_SBX_OUT}" >&2
  exit 1
}
[ -f "${MOCK_SANDBOX}/old-sentinel" ] || { echo "  ✗ FAIL: Sandbox old-sentinel was NOT restored after silent rsync CSS mutation!" >&2; exit 1; }
[ ! -e "${MOCK_SANDBOX}/styles.css" ] || { echo "  ✗ FAIL: Mutated styles.css remained in sandbox after failed deploy!" >&2; exit 1; }
[ "$(cat "${MOCK_SANDBOX}/index.html")" = "GBA Furniture old" ] || { echo "  ✗ FAIL: Sandbox index.html was NOT restored after silent rsync CSS mutation!" >&2; exit 1; }
rm -rf "${SANDBOX_RECOVERY_ROOT}/run-"*

populate_mock_wordpress
printf 'ok\n' > "${MOCK_DOCROOT}/old-sentinel"
MUTATE_PROD_OUT=""
if MUTATE_PROD_OUT="$(PATH="${MUTATE_CSS_RSYNC_BIN}:${PATH}" "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>&1)"; then
  echo "  ✗ FAIL: Production deployment succeeded despite silent rsync CSS byte mutation!" >&2
  exit 1
fi
grep -F -q "Trusted byte verification failed for 'styles.css'" <<< "${MUTATE_PROD_OUT}" || {
  echo "  ✗ FAIL: Production deployment did not detect silent rsync CSS mutation against immutable RELEASE_DIR:" >&2
  echo "${MUTATE_PROD_OUT}" >&2
  exit 1
}
[ -f "${MOCK_DOCROOT}/old-sentinel" ] && [ -f "${MOCK_DOCROOT}/wp-config.php" ] && [ ! -e "${MOCK_DOCROOT}/styles.css" ] || {
  echo "  ✗ FAIL: Production docroot was NOT restored after silent rsync CSS mutation!" >&2
  exit 1
}
grep -q '"status": "aborted_smoke_failed_docroot_restored"' "${MOCK_BACKUPS}/${TEST_REL}_manifest.json" || {
  echo "  ✗ FAIL: Production manifest did not record aborted_smoke_failed_docroot_restored after silent rsync CSS mutation!" >&2
  exit 1
}
reset_test_release_state "${TEST_REL}"
rm -rf "${MUTATE_CSS_RSYNC_BIN}"

# 8a3. Independent Reproduction: Trusted No-Node Deployment/Smoke Success vs Untrusted/Standalone No-Node Failure
NO_NODE_PATH_BIN="${TEST_ENV_DIR}/no-node-path-bin"
mkdir -p "${NO_NODE_PATH_BIN}"
python3 - "${PATH}" "${NO_NODE_PATH_BIN}" <<'PYEOF'
import os, sys
path_str, dst_dir = sys.argv[1:3]
for d in path_str.split(os.pathsep):
    if not d or not os.path.isdir(d):
        continue
    for entry in os.listdir(d):
        if entry == "node":
            continue
        dst = os.path.join(dst_dir, entry)
        src = os.path.join(d, entry)
        if not os.path.lexists(dst) and os.path.isfile(src) and os.access(src, os.X_OK):
            os.symlink(src, dst)
PYEOF

BROKEN_NODE_BIN="${TEST_ENV_DIR}/broken-node-bin"
mkdir -p "${BROKEN_NODE_BIN}"
cat > "${BROKEN_NODE_BIN}/node" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
chmod +x "${BROKEN_NODE_BIN}/node"

printf 'valid_app_js\n' > "${SMOKE_FIXTURE_MODE_FILE}"
FIXTURE_TREE_SHA256_PRE="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["tree_sha256"])' "${SMOKE_FIXTURE_DIR}/release-metadata.json")"

for node_test_path in "${NO_NODE_PATH_BIN}" "${BROKEN_NODE_BIN}:${NO_NODE_PATH_BIN}"; do
  # 1. Trusted no-node sandbox deployment MUST succeed (trusted bytes syntax-checked in CI & bound via STAGE_DIR)
  find "${MOCK_SANDBOX}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  printf 'GBA Furniture old' > "${MOCK_SANDBOX}/index.html"
  printf 'ok\n' > "${MOCK_SANDBOX}/old-sentinel"
  if ! PATH="${node_test_path}" "${SCRIPT_DIR}/remote-deploy-sandbox.sh" "${TARBALL}" "http://127.0.0.1:${SANDBOX_PORT}/release-preview" "${TARBALL_HASH}" "${TEST_REL}" "${TEST_GIT_SHA}" >/dev/null; then
    echo "  ✗ FAIL: remote-deploy-sandbox.sh failed when remote node was unavailable despite trusted asset binding!" >&2
    exit 1
  fi
  [ ! -e "${MOCK_SANDBOX}/old-sentinel" ] && [ -f "${MOCK_SANDBOX}/script.js" ] && [ -f "${MOCK_SANDBOX}/release-metadata.json" ] || {
    echo "  ✗ FAIL: Sandbox state was not updated during trusted no-node sandbox deployment!" >&2
    exit 1
  }
  LEFTOVER_SBX_RUNS="$(find "${SANDBOX_RECOVERY_ROOT}" -maxdepth 1 -name 'run-*' 2>/dev/null || true)"
  [ -z "${LEFTOVER_SBX_RUNS}" ] || {
    echo "  ✗ FAIL: Sandbox left recovery run directory behind after successful trusted no-node deploy!" >&2
    exit 1
  }

  # 2. Trusted no-node production deployment MUST succeed (trusted bytes syntax-checked in CI & bound via RELEASE_DIR)
  populate_mock_wordpress
  printf 'ok\n' > "${MOCK_DOCROOT}/old-sentinel"
  : > "${MYSQL_LOG}"
  if ! PATH="${node_test_path}" "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" >/dev/null; then
    echo "  ✗ FAIL: remote-deploy-production.sh failed when remote node was unavailable despite trusted asset binding!" >&2
    exit 1
  fi
  [ ! -e "${MOCK_DOCROOT}/old-sentinel" ] && [ ! -e "${MOCK_DOCROOT}/wp-config.php" ] && [ -f "${MOCK_DOCROOT}/script.js" ] || {
    echo "  ✗ FAIL: Production docroot was not updated during trusted no-node production deployment!" >&2
    exit 1
  }
  grep -q '"status": "production_live_db_purged"' "${MOCK_BACKUPS}/${TEST_REL}_manifest.json" && grep -q '"smoke_test_status": "passed"' "${MOCK_BACKUPS}/${TEST_REL}_manifest.json" || {
    echo "  ✗ FAIL: Production manifest did not record production_live_db_purged / smoke_test_status passed during trusted no-node production deployment!" >&2
    exit 1
  }
  reset_test_release_state "${TEST_REL}"

  # 3. Trusted no-node direct smoke-test.sh MUST succeed with TRUSTED_ASSET_ROOT (and EXPECTED_ASSET_ROOT)
  printf 'valid_app_js\n' > "${SMOKE_FIXTURE_MODE_FILE}"
  if ! PATH="${node_test_path}" \
       SMOKE_DEPLOYMENT_MODE="1" \
       EXPECTED_RELEASE_ID="${TEST_REL}" \
       EXPECTED_GIT_SHA="${TEST_GIT_SHA}" \
       EXPECTED_TREE_SHA256="${FIXTURE_TREE_SHA256_PRE}" \
       EXPECTED_METADATA_FILE="${SMOKE_FIXTURE_DIR}/release-metadata.json" \
       TRUSTED_ASSET_ROOT="${SMOKE_FIXTURE_DIR}" \
       "${SCRIPT_DIR}/smoke-test.sh" "http://127.0.0.1:${SMOKE_FIXTURE_PORT}" >/dev/null; then
    echo "  ✗ FAIL: smoke-test.sh in trusted mode (TRUSTED_ASSET_ROOT) failed when node was unavailable!" >&2
    exit 1
  fi

  # 4. Trusted no-node MUST still reject invalid or mutated JS via exact byte-size/SHA256 binding
  for bad_js_mode in "js_invalid_syntax_app_mime" "versioned_js_mutated_valid"; do
    printf '%s\n' "${bad_js_mode}" > "${SMOKE_FIXTURE_MODE_FILE}"
    TRUSTED_NONODE_BAD_JS_OUT=""
    if TRUSTED_NONODE_BAD_JS_OUT="$(
      PATH="${node_test_path}" \
      SMOKE_DEPLOYMENT_MODE="1" \
      EXPECTED_RELEASE_ID="${TEST_REL}" \
      EXPECTED_GIT_SHA="${TEST_GIT_SHA}" \
      EXPECTED_TREE_SHA256="${FIXTURE_TREE_SHA256_PRE}" \
      EXPECTED_METADATA_FILE="${SMOKE_FIXTURE_DIR}/release-metadata.json" \
      TRUSTED_ASSET_ROOT="${SMOKE_FIXTURE_DIR}" \
        "${SCRIPT_DIR}/smoke-test.sh" "http://127.0.0.1:${SMOKE_FIXTURE_PORT}" 2>&1
    )"; then
      echo "  ✗ FAIL: Trusted no-node smoke-test.sh accepted '${bad_js_mode}'!" >&2
      exit 1
    fi
    grep -F -q "Trusted byte verification failed for 'script.js'" <<< "${TRUSTED_NONODE_BAD_JS_OUT}" || {
      echo "  ✗ FAIL: Trusted no-node smoke-test.sh did not report trusted byte mismatch for '${bad_js_mode}':" >&2
      echo "${TRUSTED_NONODE_BAD_JS_OUT}" >&2
      exit 1
    }
  done
  printf 'valid_app_js\n' > "${SMOKE_FIXTURE_MODE_FILE}"

  # 5. Untrusted / standalone no-node MUST fail in preflight before any HTTP fetch
  : > "${SMOKE_FIXTURE_REQ_LOG}"
  UNTRUSTED_NONODE_OUT=""
  if UNTRUSTED_NONODE_OUT="$(PATH="${node_test_path}" "${SCRIPT_DIR}/smoke-test.sh" "http://127.0.0.1:${SMOKE_FIXTURE_PORT}" 2>&1)"; then
    echo "  ✗ FAIL: Untrusted/standalone smoke-test.sh succeeded when node was unavailable!" >&2
    exit 1
  fi
  grep -F -q "Required 'node' runtime (with working 'node --check') is unavailable on PATH" <<< "${UNTRUSTED_NONODE_OUT}" || {
    echo "  ✗ FAIL: Untrusted/standalone smoke-test.sh did not emit preflight node availability error:" >&2
    echo "${UNTRUSTED_NONODE_OUT}" >&2
    exit 1
  }
  if [ -s "${SMOKE_FIXTURE_REQ_LOG}" ]; then
    echo "  ✗ FAIL: Untrusted/standalone smoke-test.sh made HTTP request(s) before rejecting missing node runtime:" >&2
    cat "${SMOKE_FIXTURE_REQ_LOG}" >&2
    exit 1
  fi
done
rm -rf "${NO_NODE_PATH_BIN}" "${BROKEN_NODE_BIN}"

# 8b. Independent Reproduction: Injected chmod failure after rsync has already mutated target directory
FAIL_CHMOD_BIN="${TEST_ENV_DIR}/fail-chmod-bin"
mkdir -p "${FAIL_CHMOD_BIN}"
cat > "${FAIL_CHMOD_BIN}/chmod" <<EOF
#!/usr/bin/env bash
for arg in "\$@"; do
  if [[ "\${arg}" == "${MOCK_DOCROOT}"* ]] || [[ "\${arg}" == "${MOCK_SANDBOX}"* ]]; then
    exit 42
  fi
done
exec /bin/chmod "\$@"
EOF
chmod +x "${FAIL_CHMOD_BIN}/chmod"

find "${MOCK_SANDBOX}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
printf 'GBA Furniture old' > "${MOCK_SANDBOX}/index.html"
printf 'ok\n' > "${MOCK_SANDBOX}/old-sentinel"
if PATH="${FAIL_CHMOD_BIN}:${PATH}" "${SCRIPT_DIR}/remote-deploy-sandbox.sh" "${TARBALL}" "http://127.0.0.1:${SANDBOX_PORT}/release-preview" "${TARBALL_HASH}" "${TEST_REL}" "${TEST_GIT_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: Sandbox deployment succeeded despite post-rsync chmod failure!" >&2
  exit 1
fi
[ -f "${MOCK_SANDBOX}/old-sentinel" ] || { echo "  ✗ FAIL: Sandbox old-sentinel was NOT restored after chmod failure!" >&2; exit 1; }
[ ! -e "${MOCK_SANDBOX}/styles.css" ] || { echo "  ✗ FAIL: Candidate styles.css left in sandbox after chmod failure!" >&2; exit 1; }
rm -rf "${SANDBOX_RECOVERY_ROOT}/run-"*

populate_mock_wordpress
printf 'ok\n' > "${MOCK_DOCROOT}/old-sentinel"
if PATH="${FAIL_CHMOD_BIN}:${PATH}" "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: Production deployment succeeded despite post-rsync chmod failure!" >&2
  exit 1
fi
[ -f "${MOCK_DOCROOT}/old-sentinel" ] || { echo "  ✗ FAIL: Production old-sentinel was NOT restored after chmod failure!" >&2; exit 1; }
[ -f "${MOCK_DOCROOT}/wp-config.php" ] || { echo "  ✗ FAIL: Production wp-config.php was NOT restored after chmod failure!" >&2; exit 1; }
[ ! -e "${MOCK_DOCROOT}/styles.css" ] || { echo "  ✗ FAIL: Candidate styles.css left in docroot after chmod failure!" >&2; exit 1; }
reset_test_release_state "${TEST_REL}"
echo "  ✓ Preflight node checks aborted before mutation, and injected rsync (exit 23 & silent CSS byte mutation against STAGE_DIR/RELEASE_DIR) and chmod post-mutation failures restored previous state."

# 8c. Independent Reproduction: Public Identity Mismatch (stale HTTP server serving old release-metadata.json)
populate_mock_wordpress
if "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${STALE_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: Production deployment succeeded when public URL served stale release identity!" >&2
  exit 1
fi
[ -f "${MOCK_DOCROOT}/wp-config.php" ] || { echo "  ✗ FAIL: wp-config.php was not restored after public identity mismatch!" >&2; exit 1; }
[ ! -f "${MOCK_DOCROOT}/styles.css" ] || { echo "  ✗ FAIL: Candidate styles.css remained after public identity mismatch!" >&2; exit 1; }
reset_test_release_state "${TEST_REL}"

find "${MOCK_SANDBOX}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
printf 'GBA Furniture old' > "${MOCK_SANDBOX}/index.html"
if "${SCRIPT_DIR}/remote-deploy-sandbox.sh" "${TARBALL}" "http://127.0.0.1:${STALE_PORT}" "${TARBALL_HASH}" "${TEST_REL}" "${TEST_GIT_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: Sandbox deployment succeeded when preview URL served stale release identity!" >&2
  exit 1
fi
[ "$(cat "${MOCK_SANDBOX}/index.html")" = "GBA Furniture old" ] || { echo "  ✗ FAIL: Sandbox not restored after public identity mismatch!" >&2; exit 1; }
rm -rf "${SANDBOX_RECOVERY_ROOT}/run-"*
echo "  ✓ Public release identity mismatch (/release-metadata.json) detected and triggered automatic restore."

# 8d. HTTP 500 Smoke Test Failure Automatic Docroot Restore
populate_mock_wordpress
if "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${FAIL_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: Deployment succeeded despite HTTP 500 smoke test failure!" >&2
  exit 1
fi

[ -f "${MOCK_DOCROOT}/wp-config.php" ] || { echo "  ✗ FAIL: wp-config.php was NOT automatically restored after smoke failure!" >&2; exit 1; }
[ -f "${MOCK_DOCROOT}/index.php" ] || { echo "  ✗ FAIL: index.php was NOT automatically restored after smoke failure!" >&2; exit 1; }
[ -f "${MOCK_DOCROOT}/wp-content/uploads/sample.jpg" ] || { echo "  ✗ FAIL: wp-content uploads were NOT automatically restored after smoke failure!" >&2; exit 1; }
[ ! -f "${MOCK_DOCROOT}/styles.css" ] || { echo "  ✗ FAIL: Failed candidate styles.css was left behind in docroot!" >&2; exit 1; }
grep -q '"status": "aborted_smoke_failed_docroot_restored"' "${MOCK_BACKUPS}/${TEST_REL}_manifest.json" || { echo "  ✗ FAIL: Manifest did not record auto-restore status!" >&2; exit 1; }
reset_test_release_state "${TEST_REL}"

# 8d2. Independent Negative & Positive Smoke-Test Asset Validation Fixtures
#      Proves mandatory trusted binding (requiring BOTH EXPECTED_METADATA_FILE and EXPECTED_ASSET_ROOT,
#      rejecting unbound/partial/mismatched bindings, rejecting any symlink component/ancestor such as
#      alias-parent/trusted before canonicalization, and recursively scanning the complete
#      EXPECTED_ASSET_ROOT tree in preflight before the first HTTP fetch to reject both unreferenced
#      nested symlinks such as assets/nested-extra/link and referenced SVG symlinks with zero requests),
#      proves valid assets and valid exact-trusted CSS fixtures (quoted delimiters, string values
#      containing literal '<html>' and '<!-- example -->', and omitting the optional semicolon on the
#      last declaration before '}') pass, and proves all 43 negative HTTP endpoint fixtures fail closed.
FIXTURE_TREE_SHA256="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["tree_sha256"])' "${SMOKE_FIXTURE_DIR}/release-metadata.json")"

for valid_mode in "valid_app_js" "valid_text_js"; do
  printf '%s\n' "${valid_mode}" > "${SMOKE_FIXTURE_MODE_FILE}"
  EXPECTED_RELEASE_ID="${TEST_REL}" \
  EXPECTED_GIT_SHA="${TEST_GIT_SHA}" \
  EXPECTED_TREE_SHA256="${FIXTURE_TREE_SHA256}" \
  EXPECTED_METADATA_FILE="${SMOKE_FIXTURE_DIR}/release-metadata.json" \
  EXPECTED_ASSET_ROOT="${SMOKE_FIXTURE_DIR}" \
    "${SCRIPT_DIR}/smoke-test.sh" "http://127.0.0.1:${SMOKE_FIXTURE_PORT}" >/dev/null || {
      echo "  ✗ FAIL: smoke-test.sh rejected valid static assets in mode '${valid_mode}'!" >&2
      exit 1
    }
done

# Verify valid exact-trusted CSS fixtures pass under mandatory trusted mode:
#   1. Quoted CSS delimiters & comment tokens inside strings / attribute selectors
#   2. Valid CSS string value containing literal '<html>'
#   3. Valid CSS string value containing literal '<!-- example -->'
#   4. Valid CSS rule where the last declaration before '}' omits its optional semicolon
cp "${SMOKE_FIXTURE_DIR}/styles.css" "${SMOKE_FIXTURE_DIR}/styles.css.orig"
printf 'valid_app_js\n' > "${SMOKE_FIXTURE_MODE_FILE}"

VALID_EXACT_TRUSTED_CSS_FIXTURES=(
  $'quoted_delimiters:\n.quoted-probe[data-label="a;b:c{d}"]::after { content: ""; quotes: "“" "”"; }\n.quoted-comment::before { content: "{};/* not a comment */"; }\n'
  $'string_literal_html_tag:\n.html-string-probe::before { content: "<html>"; }\n'
  $'string_literal_html_comment:\n.html-comment-string-probe::before { content: "<!-- example -->"; }\n'
  $'omit_last_semicolon_before_brace:\n.omit-last-semicolon-probe { color: #014660; background-color: #faf8f5 }\n.single-decl-omit-semicolon { color: #014660 }\n'
  $'quoted_crossed_rgb:\n.quoted-rgb-probe::before { content: "rgb([)]"; }\n'
  $'quoted_crossed_bracket:\n.quoted-bracket-probe::before { content: "[(])"; }\n'
  $'quoted_markup_div_open:\n.quoted-div-open-probe::before { content: "<div>"; }\n'
  $'quoted_markup_div_close:\n.quoted-div-close-probe::before { content: "</div>"; }\n'
  $'quoted_markup_bang_foo:\n.quoted-bang-foo-probe::before { content: "<!foo>"; }\n'
  $'quoted_markup_pi_foo:\n.quoted-pi-foo-probe::before { content: "<?foo?>"; }\n'
  $'comment_crossed_rgb:\n/* rgb([)] */\n.comment-rgb-probe { color: #014660; }\n'
  $'comment_crossed_bracket:\n/* [(]) */\n.comment-bracket-probe { color: #014660; }\n'
  $'comment_markup_div_open:\n/* <div> */\n.comment-div-open-probe { color: #014660; }\n'
  $'comment_markup_div_close:\n/* </div> */\n.comment-div-close-probe { color: #014660; }\n'
  $'comment_markup_bang_foo:\n/* <!foo> */\n.comment-bang-foo-probe { color: #014660; }\n'
  $'comment_markup_pi_foo:\n/* <?foo?> */\n.comment-pi-foo-probe { color: #014660; }\n'
)

for css_fixture_entry in "${VALID_EXACT_TRUSTED_CSS_FIXTURES[@]}"; do
  css_fixture_name="${css_fixture_entry%%:*}"
  css_fixture_snippet="${css_fixture_entry#*:}"
  cp "${SMOKE_FIXTURE_DIR}/styles.css.orig" "${SMOKE_FIXTURE_DIR}/styles.css"
  printf '%s' "${css_fixture_snippet}" >> "${SMOKE_FIXTURE_DIR}/styles.css"
  EXPECTED_RELEASE_ID="${TEST_REL}" \
  EXPECTED_GIT_SHA="${TEST_GIT_SHA}" \
  EXPECTED_TREE_SHA256="${FIXTURE_TREE_SHA256}" \
  EXPECTED_METADATA_FILE="${SMOKE_FIXTURE_DIR}/release-metadata.json" \
  EXPECTED_ASSET_ROOT="${SMOKE_FIXTURE_DIR}" \
    "${SCRIPT_DIR}/smoke-test.sh" "http://127.0.0.1:${SMOKE_FIXTURE_PORT}" >/dev/null || {
      mv "${SMOKE_FIXTURE_DIR}/styles.css.orig" "${SMOKE_FIXTURE_DIR}/styles.css"
      echo "  ✗ FAIL: smoke-test.sh rejected valid exact-trusted CSS fixture '${css_fixture_name}' under mandatory trusted mode!" >&2
      exit 1
    }
done

INVALID_EXACT_TRUSTED_CSS_FIXTURES=(
  $'crossed_rgb_paren_bracket|crossed or unbalanced closing parenthesis|\n.bad-rgb-probe { color: rgb([)]; }\n'
  $'crossed_bracket_paren|crossed or unbalanced closing bracket|\n.bad-bracket-probe[(]) { color: #014660; }\n'
  $'markup_div_open|CSS body contains HTML/XML markup (fallback rejected)|\n<div> .bad-div-open { color: #014660; }\n'
  $'markup_div_close|CSS body contains HTML/XML markup (fallback rejected)|\n</div> .bad-div-close { color: #014660; }\n'
  $'markup_bang_foo|CSS body contains HTML/XML markup (fallback rejected)|\n<!foo> .bad-bang-foo { color: #014660; }\n'
  $'markup_pi_foo|CSS body contains HTML/XML markup (fallback rejected)|\n<?foo?> .bad-pi-foo { color: #014660; }\n'
)

for invalid_css_entry in "${INVALID_EXACT_TRUSTED_CSS_FIXTURES[@]}"; do
  invalid_css_name="${invalid_css_entry%%|*}"
  invalid_css_rest="${invalid_css_entry#*|}"
  invalid_css_expected="${invalid_css_rest%%|*}"
  invalid_css_snippet="${invalid_css_rest#*|}"
  cp "${SMOKE_FIXTURE_DIR}/styles.css.orig" "${SMOKE_FIXTURE_DIR}/styles.css"
  printf '%s' "${invalid_css_snippet}" >> "${SMOKE_FIXTURE_DIR}/styles.css"
  INVALID_CSS_OUT=""
  if INVALID_CSS_OUT="$(
    EXPECTED_RELEASE_ID="${TEST_REL}" \
    EXPECTED_GIT_SHA="${TEST_GIT_SHA}" \
    EXPECTED_TREE_SHA256="${FIXTURE_TREE_SHA256}" \
    EXPECTED_METADATA_FILE="${SMOKE_FIXTURE_DIR}/release-metadata.json" \
    EXPECTED_ASSET_ROOT="${SMOKE_FIXTURE_DIR}" \
      "${SCRIPT_DIR}/smoke-test.sh" "http://127.0.0.1:${SMOKE_FIXTURE_PORT}" 2>&1
  )"; then
    mv "${SMOKE_FIXTURE_DIR}/styles.css.orig" "${SMOKE_FIXTURE_DIR}/styles.css"
    echo "  ✗ FAIL: smoke-test.sh unexpectedly passed invalid exact-trusted CSS fixture '${invalid_css_name}'!" >&2
    exit 1
  fi
  grep -F -q -- "${invalid_css_expected}" <<< "${INVALID_CSS_OUT}" || {
    mv "${SMOKE_FIXTURE_DIR}/styles.css.orig" "${SMOKE_FIXTURE_DIR}/styles.css"
    echo "  ✗ FAIL: smoke-test.sh invalid exact-trusted CSS fixture '${invalid_css_name}' did not emit expected diagnostic '${invalid_css_expected}':" >&2
    echo "${INVALID_CSS_OUT}" >&2
    exit 1
  }
done
mv "${SMOKE_FIXTURE_DIR}/styles.css.orig" "${SMOKE_FIXTURE_DIR}/styles.css"

# Verify untrusted/standalone mode with working node passes valid JS and rejects invalid JS via node --check,
# and verify deployment mode (SMOKE_DEPLOYMENT_MODE=1) & partial/mismatched trusted bindings fail immediately in preflight.
printf 'valid_app_js\n' > "${SMOKE_FIXTURE_MODE_FILE}"
"${SCRIPT_DIR}/smoke-test.sh" "http://127.0.0.1:${SMOKE_FIXTURE_PORT}" >/dev/null || {
  echo "  ✗ FAIL: Untrusted/standalone smoke-test.sh with working node rejected valid static assets!" >&2
  exit 1
}

for untrusted_bad_js in "js_invalid_syntax_app_mime" "js_invalid_syntax_text_mime"; do
  printf '%s\n' "${untrusted_bad_js}" > "${SMOKE_FIXTURE_MODE_FILE}"
  UNTRUSTED_BAD_JS_OUT=""
  if UNTRUSTED_BAD_JS_OUT="$("${SCRIPT_DIR}/smoke-test.sh" "http://127.0.0.1:${SMOKE_FIXTURE_PORT}" 2>&1)"; then
    echo "  ✗ FAIL: Untrusted/standalone smoke-test.sh accepted invalid JS in mode '${untrusted_bad_js}'!" >&2
    exit 1
  fi
  grep -F -q "node --check syntax check failed" <<< "${UNTRUSTED_BAD_JS_OUT}" || {
    echo "  ✗ FAIL: Untrusted/standalone smoke-test.sh did not reject invalid JS via node --check in mode '${untrusted_bad_js}':" >&2
    echo "${UNTRUSTED_BAD_JS_OUT}" >&2
    exit 1
  }
done
printf 'valid_app_js\n' > "${SMOKE_FIXTURE_MODE_FILE}"

: > "${SMOKE_FIXTURE_REQ_LOG}"
UNBOUND_ERR=""
if UNBOUND_ERR="$(SMOKE_DEPLOYMENT_MODE="1" "${SCRIPT_DIR}/smoke-test.sh" "http://127.0.0.1:${SMOKE_FIXTURE_PORT}" 2>&1)"; then
  echo "  ✗ FAIL: smoke-test.sh passed in SMOKE_DEPLOYMENT_MODE=1 without EXPECTED_METADATA_FILE and TRUSTED_ASSET_ROOT!" >&2
  exit 1
fi
grep -F -q "Mandatory trusted asset binding missing: both EXPECTED_METADATA_FILE and EXPECTED_ASSET_ROOT must be set" <<< "${UNBOUND_ERR}" || {
  echo "  ✗ FAIL: smoke-test.sh did not emit mandatory binding error when both vars were absent in deployment mode:" >&2
  echo "${UNBOUND_ERR}" >&2
  exit 1
}
if [ -s "${SMOKE_FIXTURE_REQ_LOG}" ]; then
  echo "  ✗ FAIL: smoke-test.sh made HTTP request(s) before rejecting missing deployment-mode bindings!" >&2
  exit 1
fi

ONLY_META_ERR=""
if ONLY_META_ERR="$(EXPECTED_METADATA_FILE="${SMOKE_FIXTURE_DIR}/release-metadata.json" "${SCRIPT_DIR}/smoke-test.sh" "http://127.0.0.1:${SMOKE_FIXTURE_PORT}" 2>&1)"; then
  echo "  ✗ FAIL: smoke-test.sh passed when EXPECTED_ASSET_ROOT / TRUSTED_ASSET_ROOT was omitted!" >&2
  exit 1
fi
grep -F -q "Mandatory trusted asset binding missing: both EXPECTED_METADATA_FILE and EXPECTED_ASSET_ROOT must be set" <<< "${ONLY_META_ERR}" || {
  echo "  ✗ FAIL: smoke-test.sh did not emit mandatory binding error when EXPECTED_ASSET_ROOT was omitted:" >&2
  echo "${ONLY_META_ERR}" >&2
  exit 1
}

for only_root_var in "EXPECTED_ASSET_ROOT" "TRUSTED_ASSET_ROOT"; do
  ONLY_ROOT_ERR=""
  if ONLY_ROOT_ERR="$(env "${only_root_var}=${SMOKE_FIXTURE_DIR}" "${SCRIPT_DIR}/smoke-test.sh" "http://127.0.0.1:${SMOKE_FIXTURE_PORT}" 2>&1)"; then
    echo "  ✗ FAIL: smoke-test.sh passed when EXPECTED_METADATA_FILE was omitted (${only_root_var} set)!" >&2
    exit 1
  fi
  grep -F -q "Mandatory trusted asset binding missing: both EXPECTED_METADATA_FILE and EXPECTED_ASSET_ROOT must be set" <<< "${ONLY_ROOT_ERR}" || {
    echo "  ✗ FAIL: smoke-test.sh did not emit mandatory binding error when EXPECTED_METADATA_FILE was omitted (${only_root_var} set):" >&2
    echo "${ONLY_ROOT_ERR}" >&2
    exit 1
  }
done

OTHER_TRUSTED_DIR="${TEST_ENV_DIR}/other-trusted-dir"
mkdir -p "${OTHER_TRUSTED_DIR}"
cp "${SMOKE_FIXTURE_DIR}/release-metadata.json" "${OTHER_TRUSTED_DIR}/release-metadata.json"
MISMATCH_BIND_ERR=""
if MISMATCH_BIND_ERR="$(
  EXPECTED_METADATA_FILE="${OTHER_TRUSTED_DIR}/release-metadata.json" \
  EXPECTED_ASSET_ROOT="${SMOKE_FIXTURE_DIR}" \
    "${SCRIPT_DIR}/smoke-test.sh" "http://127.0.0.1:${SMOKE_FIXTURE_PORT}" 2>&1
)"; then
  echo "  ✗ FAIL: smoke-test.sh passed when EXPECTED_METADATA_FILE and EXPECTED_ASSET_ROOT were mismatched!" >&2
  exit 1
fi
grep -F -q "mismatch" <<< "${MISMATCH_BIND_ERR}" || {
  echo "  ✗ FAIL: smoke-test.sh did not emit mismatch diagnostic for mismatched EXPECTED_METADATA_FILE and EXPECTED_ASSET_ROOT:" >&2
  echo "${MISMATCH_BIND_ERR}" >&2
  exit 1
}
rm -rf "${OTHER_TRUSTED_DIR}"

# Regression: Symlink ancestor rejection before canonicalization (alias-parent/trusted where final component is a real directory/file)
REAL_TRUSTED_PARENT="${TEST_ENV_DIR}/real-trusted-parent"
REAL_TRUSTED_DIR="${REAL_TRUSTED_PARENT}/trusted"
ALIAS_PARENT="${TEST_ENV_DIR}/alias-parent"
mkdir -p "${REAL_TRUSTED_DIR}"
cp -R "${SMOKE_FIXTURE_DIR}/." "${REAL_TRUSTED_DIR}/"
ln -s "${REAL_TRUSTED_PARENT}" "${ALIAS_PARENT}"

for sym_anc_case in "both_alias" "meta_alias_only" "root_alias_only"; do
  if [ "${sym_anc_case}" = "both_alias" ]; then
    TEST_META_ARG="${ALIAS_PARENT}/trusted/release-metadata.json"
    TEST_ROOT_ARG="${ALIAS_PARENT}/trusted"
  elif [ "${sym_anc_case}" = "meta_alias_only" ]; then
    TEST_META_ARG="${ALIAS_PARENT}/trusted/release-metadata.json"
    TEST_ROOT_ARG="${REAL_TRUSTED_DIR}"
  else
    TEST_META_ARG="${REAL_TRUSTED_DIR}/release-metadata.json"
    TEST_ROOT_ARG="${ALIAS_PARENT}/trusted"
  fi
  : > "${SMOKE_FIXTURE_REQ_LOG}"
  SYM_ANC_ERR=""
  if SYM_ANC_ERR="$(
    EXPECTED_METADATA_FILE="${TEST_META_ARG}" \
    EXPECTED_ASSET_ROOT="${TEST_ROOT_ARG}" \
      "${SCRIPT_DIR}/smoke-test.sh" "http://127.0.0.1:${SMOKE_FIXTURE_PORT}" 2>&1
  )"; then
    echo "  ✗ FAIL: smoke-test.sh accepted symlink ancestor in alias-parent/trusted (${sym_anc_case})!" >&2
    exit 1
  fi
  grep -F -q "path component or ancestor is a symlink" <<< "${SYM_ANC_ERR}" || {
    echo "  ✗ FAIL: smoke-test.sh did not report symlink ancestor for alias-parent/trusted (${sym_anc_case}):" >&2
    echo "${SYM_ANC_ERR}" >&2
    exit 1
  }
  if [ -s "${SMOKE_FIXTURE_REQ_LOG}" ]; then
    echo "  ✗ FAIL: smoke-test.sh made HTTP request(s) before rejecting symlink ancestor (${sym_anc_case}):" >&2
    cat "${SMOKE_FIXTURE_REQ_LOG}" >&2
    exit 1
  fi
done

# Regression: Unreferenced nested symlink assets/nested-extra/link pointing outside EXPECTED_ASSET_ROOT
# Must fail preflight with nonzero exit BEFORE the fixture server gets any request
OUTSIDE_SYMLINK_TARGET="${TEST_ENV_DIR}/outside-symlink-target.txt"
printf 'outside-secret\n' > "${OUTSIDE_SYMLINK_TARGET}"
mkdir -p "${REAL_TRUSTED_DIR}/assets/nested-extra"
ln -s "${OUTSIDE_SYMLINK_TARGET}" "${REAL_TRUSTED_DIR}/assets/nested-extra/link"
: > "${SMOKE_FIXTURE_REQ_LOG}"
UNREF_NESTED_SYM_ERR=""
if UNREF_NESTED_SYM_ERR="$(
  EXPECTED_METADATA_FILE="${REAL_TRUSTED_DIR}/release-metadata.json" \
  EXPECTED_ASSET_ROOT="${REAL_TRUSTED_DIR}" \
    "${SCRIPT_DIR}/smoke-test.sh" "http://127.0.0.1:${SMOKE_FIXTURE_PORT}" 2>&1
)"; then
  echo "  ✗ FAIL: smoke-test.sh accepted unreferenced nested symlink assets/nested-extra/link pointing outside EXPECTED_ASSET_ROOT!" >&2
  exit 1
fi
grep -F -q "Trusted asset path 'assets/nested-extra/link' traverses symlink" <<< "${UNREF_NESTED_SYM_ERR}" || {
  echo "  ✗ FAIL: smoke-test.sh did not emit preflight symlink diagnostic for assets/nested-extra/link:" >&2
  echo "${UNREF_NESTED_SYM_ERR}" >&2
  exit 1
}
if [ -s "${SMOKE_FIXTURE_REQ_LOG}" ]; then
  echo "  ✗ FAIL: smoke-test.sh made HTTP request(s) before rejecting unreferenced nested symlink assets/nested-extra/link:" >&2
  cat "${SMOKE_FIXTURE_REQ_LOG}" >&2
  exit 1
fi
rm -rf "${REAL_TRUSTED_DIR}/assets/nested-extra" "${OUTSIDE_SYMLINK_TARGET}"

# Regression: Referenced SVG symlink inside canonical trusted root must also fail preflight with zero requests
mv "${REAL_TRUSTED_DIR}/assets/placeholders/wardrobe.svg" "${REAL_TRUSTED_DIR}/assets/placeholders/wardrobe.svg.real"
ln -s "${REAL_TRUSTED_DIR}/assets/placeholders/wardrobe.svg.real" "${REAL_TRUSTED_DIR}/assets/placeholders/wardrobe.svg"
: > "${SMOKE_FIXTURE_REQ_LOG}"
NESTED_SYM_ERR=""
if NESTED_SYM_ERR="$(
  EXPECTED_METADATA_FILE="${REAL_TRUSTED_DIR}/release-metadata.json" \
  EXPECTED_ASSET_ROOT="${REAL_TRUSTED_DIR}" \
    "${SCRIPT_DIR}/smoke-test.sh" "http://127.0.0.1:${SMOKE_FIXTURE_PORT}" 2>&1
)"; then
  echo "  ✗ FAIL: smoke-test.sh accepted nested trusted asset symlink inside EXPECTED_ASSET_ROOT!" >&2
  exit 1
fi
grep -F -q "Trusted asset path 'assets/placeholders/wardrobe.svg' traverses symlink" <<< "${NESTED_SYM_ERR}" || {
  echo "  ✗ FAIL: smoke-test.sh did not emit nested trusted asset symlink diagnostic:" >&2
  echo "${NESTED_SYM_ERR}" >&2
  exit 1
}
if [ -s "${SMOKE_FIXTURE_REQ_LOG}" ]; then
  echo "  ✗ FAIL: smoke-test.sh made HTTP request(s) before rejecting referenced SVG symlink assets/placeholders/wardrobe.svg:" >&2
  cat "${SMOKE_FIXTURE_REQ_LOG}" >&2
  exit 1
fi
rm -rf "${ALIAS_PARENT}" "${REAL_TRUSTED_PARENT}"

NEGATIVE_SMOKE_FIXTURES=(
  "versioned_svg_html_fallback:Expected Content-Type 'image/svg+xml'"
  "versioned_svg_html_body_with_svg_mime:SVG body contains HTML document tags (HTML fallback rejected)"
  "versioned_svg_wrong_mime:Expected Content-Type 'image/svg+xml'"
  "versioned_svg_fake_body:SVG body must start with <svg"
  "versioned_svg_non_svg_xml_root:Expected XML root local-name 'svg'"
  "underlying_svg_html_fallback:Expected Content-Type 'image/svg+xml'"
  "png_html_fallback:Expected Content-Type 'image/png'"
  "png_wrong_mime:Expected Content-Type 'image/png'"
  "png_fake_body:Invalid PNG binary signature"
  "png_forged_ihdr_only:Incomplete PNG structure"
  "png_truncated_stream:Invalid PNG structure: truncated chunk"
  "png_bad_crc:Invalid PNG chunk CRC"
  "png_zero_dimensions:Invalid PNG IHDR dimensions"
  "jpg_html_fallback:Expected Content-Type 'image/jpeg'"
  "versioned_jpg_html_fallback:Expected Content-Type 'image/jpeg'"
  "jpg_wrong_mime:Expected Content-Type 'image/jpeg'"
  "versioned_jpg_wrong_mime:Expected Content-Type 'image/jpeg'"
  "jpg_fake_body:Invalid JPEG SOI binary signature"
  "jpg_ffd8ff00_prefix:Invalid JPEG marker 0xff00"
  "jpg_truncated_stream:Truncated JPEG"
  "jpg_missing_sos:Incomplete JPEG structure"
  "css_html_fallback:Expected Content-Type 'text/css'"
  "css_wrong_mime:Expected Content-Type 'text/css'"
  "css_fake_html_body:CSS body starts with markup '<' (HTML/XML fallback rejected)"
  "css_fake_plain_body:CSS body missing expected stylesheet rule structure"
  "css_marker_spoofed_unbalanced:CSS body missing expected stylesheet rule structure (unbalanced braces"
  "css_marker_spoofed_malformed:CSS body missing expected stylesheet rule structure"
  "css_marker_spoofed_comment_only:CSS body missing expected stylesheet rule structure"
  "css_crossed_rgb_paren_bracket:CSS body missing expected stylesheet rule structure (crossed or unbalanced closing parenthesis ')')"
  "css_crossed_bracket_paren:CSS body missing expected stylesheet rule structure (crossed or unbalanced closing bracket ']')"
  "css_markup_div_open:CSS body contains HTML/XML markup (fallback rejected)"
  "css_markup_div_close:CSS body contains HTML/XML markup (fallback rejected)"
  "css_markup_bang_foo:CSS body contains HTML/XML markup (fallback rejected)"
  "css_markup_pi_foo:CSS body contains HTML/XML markup (fallback rejected)"
  "js_html_fallback:Expected Content-Type 'application/javascript' or 'text/javascript'"
  "js_wrong_mime:Expected Content-Type 'application/javascript' or 'text/javascript'"
  "js_fake_html_body:JavaScript body starts with markup '<' (HTML/XML fallback rejected)"
  "js_fake_plain_body:JavaScript body missing expected script structure"
  "js_invalid_syntax_app_mime:node --check syntax check failed"
  "js_invalid_syntax_text_mime:node --check syntax check failed"
  "json_wrong_mime:Expected Content-Type 'application/json'"
  "json_fake_body:Invalid JSON body"
  "json_duplicate_keys:Duplicate JSON key"
  "json_nan_constant:Invalid JSON constant"
  "incomplete_transfer_css_with_charset:curl transfer failed (exit 18)"
  "incomplete_transfer_js_with_charset:curl transfer failed (exit 18)"
  "incomplete_transfer_metadata_with_charset:curl transfer failed (exit 18)"
  "versioned_css_mutated_valid:Trusted byte verification failed for 'styles.css'"
  "versioned_js_mutated_valid:Trusted byte verification failed for 'script.js'"
  "versioned_svg_mutated_valid:Trusted byte verification failed for 'assets/placeholders/wardrobe.svg'"
  "png_mutated_valid:Trusted byte verification failed for 'assets/gba-logo-official-transparent.png'"
  "jpg_mutated_valid:Trusted byte verification failed for 'assets/current-banner.jpg'"
  "versioned_jpg_mutated_valid:Trusted byte verification failed for 'assets/current-banner.jpg'"
)

for fixture_spec in "${NEGATIVE_SMOKE_FIXTURES[@]}"; do
  fault_mode="${fixture_spec%%:*}"
  expected_err="${fixture_spec#*:}"
  printf '%s\n' "${fault_mode}" > "${SMOKE_FIXTURE_MODE_FILE}"
  SMOKE_NEG_OUT=""
  if SMOKE_NEG_OUT="$(
    EXPECTED_RELEASE_ID="${TEST_REL}" \
    EXPECTED_GIT_SHA="${TEST_GIT_SHA}" \
    EXPECTED_TREE_SHA256="${FIXTURE_TREE_SHA256}" \
    EXPECTED_METADATA_FILE="${SMOKE_FIXTURE_DIR}/release-metadata.json" \
    EXPECTED_ASSET_ROOT="${SMOKE_FIXTURE_DIR}" \
      "${SCRIPT_DIR}/smoke-test.sh" "http://127.0.0.1:${SMOKE_FIXTURE_PORT}" 2>&1
  )"; then
    echo "  ✗ FAIL: smoke-test.sh unexpectedly passed negative asset fixture '${fault_mode}'!" >&2
    exit 1
  fi
  grep -F -q -- "${expected_err}" <<< "${SMOKE_NEG_OUT}" || {
    echo "  ✗ FAIL: smoke-test.sh negative fixture '${fault_mode}' did not emit expected diagnostic '${expected_err}':" >&2
    echo "${SMOKE_NEG_OUT}" >&2
    exit 1
  }
done

# Verify production cutover aborts and auto-restores WordPress docroot on versioned fallback, versioned mutated response, and incomplete transfer
for cutover_abort_mode in \
  "versioned_svg_html_fallback" \
  "versioned_css_mutated_valid" \
  "versioned_js_mutated_valid" \
  "versioned_svg_mutated_valid" \
  "versioned_jpg_mutated_valid" \
  "incomplete_transfer_css_with_charset"; do
  printf '%s\n' "${cutover_abort_mode}" > "${SMOKE_FIXTURE_MODE_FILE}"
  populate_mock_wordpress
  if "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${SMOKE_FIXTURE_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
    echo "  ✗ FAIL: Production deployment succeeded when public endpoint served '${cutover_abort_mode}'!" >&2
    exit 1
  fi
  [ -f "${MOCK_DOCROOT}/wp-config.php" ] && [ ! -f "${MOCK_DOCROOT}/styles.css" ] || {
    echo "  ✗ FAIL: Production docroot was NOT restored after '${cutover_abort_mode}' smoke failure!" >&2
    exit 1
  }
  grep -q '"status": "aborted_smoke_failed_docroot_restored"' "${MOCK_BACKUPS}/${TEST_REL}_manifest.json" || {
    echo "  ✗ FAIL: Manifest did not record auto-restore status after '${cutover_abort_mode}'!" >&2
    exit 1
  }
  reset_test_release_state "${TEST_REL}"
done
printf 'valid_app_js\n' > "${SMOKE_FIXTURE_MODE_FILE}"
echo "  ✓ Mandatory trusted binding (both EXPECTED_METADATA_FILE and EXPECTED_ASSET_ROOT, alias-parent/trusted symlink ancestor & recursive preflight symlink rejection before first HTTP fetch), valid exact-trusted CSS fixtures, and 47 negative HTTP endpoint fixtures verified."

# 8e. Independent Reproduction: Final Manifest Atomic Write Failure After DB Deletion
#     Proves pre-cutover manifest is NEVER truncated in place and both files + DB are restored!
populate_mock_wordpress
: > "${MYSQL_LOG}"
if TEST_FAIL_FINAL_MANIFEST_WRITE="1" "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: Production deployment succeeded despite final manifest write failure!" >&2
  exit 1
fi
[ -f "${MOCK_DOCROOT}/wp-config.php" ] || { echo "  ✗ FAIL: wp-config.php was NOT restored after final manifest write failure!" >&2; exit 1; }
[ ! -f "${MOCK_DOCROOT}/styles.css" ] || { echo "  ✗ FAIL: Candidate styles.css remained after final manifest write failure!" >&2; exit 1; }
grep -q "IMPORT:gba_wp_db:-- Mock SQL Dump" "${MYSQL_LOG}" || { echo "  ✗ FAIL: Database was NOT restored after final manifest write failure!" >&2; exit 1; }
# Verify the manifest on disk is valid strict JSON (never truncated in place!)
python3 - "${MOCK_BACKUPS}/${TEST_REL}_manifest.json" <<'PYEOF'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)
assert data.get("status") == "aborted_post_cutover_files_and_db_restored", f"Unexpected manifest status: {data.get('status')}"
PYEOF
reset_test_release_state "${TEST_REL}"
# 8f. Signal Handling During Active Mutation (TERM=143, INT=130, HUP=129)
#     Mock rsync mutates destination, sends signal to parent script, and returns 0 (prior command status 0).
#     Must force nonzero signal-specific exit code and invoke EXIT recovery exactly once!
SIGNAL_RSYNC_BIN="${TEST_ENV_DIR}/signal-rsync-bin"
mkdir -p "${SIGNAL_RSYNC_BIN}"
cat > "${SIGNAL_RSYNC_BIN}/rsync" <<'EOF'
#!/usr/bin/env bash
set -eu
for arg in "$@"; do dest="$arg"; done
rm -f -- "${dest%/}/old-sentinel"
printf partial-sig > "${dest%/}/partial-signal-write"
kill -"${TEST_SIGNAL_NAME}" "${PPID}"
sleep 0.2
exit 0
EOF
chmod +x "${SIGNAL_RSYNC_BIN}/rsync"

for sig_pair in "TERM:143" "INT:130" "HUP:129"; do
  sig_name="${sig_pair%%:*}"
  expected_rc="${sig_pair##*:}"

  # Sandbox signal test
  find "${MOCK_SANDBOX}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  printf 'GBA Furniture old' > "${MOCK_SANDBOX}/index.html"
  printf 'ok\n' > "${MOCK_SANDBOX}/old-sentinel"
  SIG_RC=0
  SIG_ERR="$(TEST_SIGNAL_NAME="${sig_name}" PATH="${SIGNAL_RSYNC_BIN}:${PATH}" "${SCRIPT_DIR}/remote-deploy-sandbox.sh" "${TARBALL}" "http://127.0.0.1:${SANDBOX_PORT}/release-preview" "${TARBALL_HASH}" "${TEST_REL}" "${TEST_GIT_SHA}" 2>&1 >/dev/null)" || SIG_RC=$?
  if [ "${SIG_RC}" -ne "${expected_rc}" ]; then
    echo "  ✗ FAIL: Sandbox signal ${sig_name} exited with ${SIG_RC}, expected ${expected_rc}!" >&2
    exit 1
  fi
  [ -f "${MOCK_SANDBOX}/old-sentinel" ] && [ ! -e "${MOCK_SANDBOX}/partial-signal-write" ] || {
    echo "  ✗ FAIL: Sandbox did not restore state after signal ${sig_name}!" >&2
    exit 1
  }
  RESTORE_CALLS="$(printf '%s\n' "${SIG_ERR}" | grep -c "Initiating automatic restoration of previous sandbox state" || true)"
  if [ "${RESTORE_CALLS}" -ne 1 ]; then
    echo "  ✗ FAIL: Sandbox recovery ran ${RESTORE_CALLS} times on signal ${sig_name}, expected exactly 1!" >&2
    exit 1
  fi
  rm -rf "${SANDBOX_RECOVERY_ROOT}/run-"*

  # Production signal test
  populate_mock_wordpress
  printf 'ok\n' > "${MOCK_DOCROOT}/old-sentinel"
  SIG_RC=0
  SIG_ERR="$(TEST_SIGNAL_NAME="${sig_name}" PATH="${SIGNAL_RSYNC_BIN}:${PATH}" "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>&1 >/dev/null)" || SIG_RC=$?
  if [ "${SIG_RC}" -ne "${expected_rc}" ]; then
    echo "  ✗ FAIL: Production signal ${sig_name} exited with ${SIG_RC}, expected ${expected_rc}!" >&2
    exit 1
  fi
  [ -f "${MOCK_DOCROOT}/old-sentinel" ] && [ -f "${MOCK_DOCROOT}/wp-config.php" ] && [ ! -e "${MOCK_DOCROOT}/partial-signal-write" ] || {
    echo "  ✗ FAIL: Production did not restore state after signal ${sig_name}!" >&2
    exit 1
  }
  RESTORE_CALLS="$(printf '%s\n' "${SIG_ERR}" | grep -c "Initiating automatic restoration of previous production state" || true)"
  if [ "${RESTORE_CALLS}" -ne 1 ]; then
    echo "  ✗ FAIL: Production recovery ran ${RESTORE_CALLS} times on signal ${sig_name}, expected exactly 1!" >&2
    exit 1
  fi
  reset_test_release_state "${TEST_REL}"
done
echo "  ✓ Post-cutover smoke, final manifest, and active-mutation signal (TERM 143, INT 130, HUP 129) failures restored state and exited nonzero."

# ==============================================================================
# Test 9: Shared Host-Side OS-Held Lock (flock), Two Concurrent Contenders & Cutover
# ==============================================================================
echo "[Test 9] Testing Shared Host-Side OS-Held Lock (flock), Two Contenders & Production Cutover..."

# 9a. Active OS-held flock lock held by live background process blocks production, sandbox, and rollback
HOLDER_READY="${TEST_ENV_DIR}/holder_ready"
rm -f "${HOLDER_READY}" "${MOCK_LOCK}" "${MOCK_LOCK}.meta"
python3 - "${MOCK_LOCK}" "${HOLDER_READY}" <<'PYEOF' &
import fcntl, json, os, sys, time
lock_path, ready_path = sys.argv[1:3]
fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
with open(lock_path + ".meta", "w", encoding="utf-8") as mf:
    json.dump({"owner": "live-holder-token", "pid": os.getpid(), "created_at": int(time.time()), "operation": "test-hold"}, mf)
with open(ready_path, "w", encoding="utf-8") as rf:
    rf.write("ready\n")
time.sleep(30)
PYEOF
LOCK_HOLDER_PID=$!

for _ in $(seq 1 50); do
  [ -f "${HOLDER_READY}" ] && break
  sleep 0.05
done
[ -f "${HOLDER_READY}" ] || { echo "  ✗ FAIL: Background flock holder failed to start!" >&2; exit 1; }

if "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: remote-deploy-production.sh ignored active OS flock!" >&2
  exit 1
fi
if "${SCRIPT_DIR}/remote-deploy-sandbox.sh" "${TARBALL}" "http://127.0.0.1:${SANDBOX_PORT}/release-preview" "${TARBALL_HASH}" "${TEST_REL}" "${TEST_GIT_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: remote-deploy-sandbox.sh ignored active OS flock!" >&2
  exit 1
fi
if "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${TEST_PORT}" 2>/dev/null; then
  echo "  ✗ FAIL: rollback.sh ignored active OS flock!" >&2
  exit 1
fi

# Ensure failed contenders did NOT delete the active holder's metadata or lock file
[ -f "${MOCK_LOCK}" ] && [ -f "${MOCK_LOCK}.meta" ] && grep -q '"owner": "live-holder-token"' "${MOCK_LOCK}.meta" || {
  echo "  ✗ FAIL: Contending process corrupted active holder's lock or metadata!" >&2
  exit 1
}

# Terminate the background holder so the OS releases the flock (leaving stale .meta behind)
kill "${LOCK_HOLDER_PID}" 2>/dev/null || true
wait "${LOCK_HOLDER_PID}" 2>/dev/null || true

# Next invocation acquires the OS flock cleanly without racy mkdir reclamation and cleans up .meta on exit
"${SCRIPT_DIR}/remote-deploy-sandbox.sh" "${TARBALL}" "http://127.0.0.1:${SANDBOX_PORT}/release-preview" "${TARBALL_HASH}" "${TEST_REL}" "${TEST_GIT_SHA}" >/dev/null
[ ! -f "${MOCK_LOCK}.meta" ] || { echo "  ✗ FAIL: Lock metadata file was not cleaned up on exit!" >&2; exit 1; }

# 9b. Two concurrent contenders racing for the lock — prove ONLY ONE enters!
SLOW_RSYNC_BIN="${TEST_ENV_DIR}/slow-rsync-bin"
mkdir -p "${SLOW_RSYNC_BIN}"
ENTER_LOG="${TEST_ENV_DIR}/contender_entries.log"
: > "${ENTER_LOG}"
cat > "${SLOW_RSYNC_BIN}/rsync" <<EOF
#!/usr/bin/env bash
if [[ "\$*" != *"--server"* ]]; then
  printf 'entered:%s\n' "\$\$" >> "${ENTER_LOG}"
  sleep 0.6
fi
exec /usr/bin/rsync "\$@"
EOF
chmod +x "${SLOW_RSYNC_BIN}/rsync"

CONTENDER1_RC=0
CONTENDER2_RC=0
(
  PATH="${SLOW_RSYNC_BIN}:${PATH}" "${SCRIPT_DIR}/remote-deploy-sandbox.sh" "${TARBALL}" "http://127.0.0.1:${SANDBOX_PORT}/release-preview" "${TARBALL_HASH}" "${TEST_REL}" "${TEST_GIT_SHA}" >/dev/null 2>&1
) &
C1_PID=$!
(
  sleep 0.1
  PATH="${SLOW_RSYNC_BIN}:${PATH}" "${SCRIPT_DIR}/remote-deploy-sandbox.sh" "${TARBALL}" "http://127.0.0.1:${SANDBOX_PORT}/release-preview" "${TARBALL_HASH}" "${TEST_REL}" "${TEST_GIT_SHA}" >/dev/null 2>&1
) &
C2_PID=$!

wait "${C1_PID}" || CONTENDER1_RC=$?
wait "${C2_PID}" || CONTENDER2_RC=$?

ENTER_COUNT="$(wc -l < "${ENTER_LOG}" | tr -d ' ')"
if [ "${ENTER_COUNT}" -ne 1 ]; then
  echo "  ✗ FAIL: Expected exactly 1 contender to enter critical section, but ${ENTER_COUNT} entered!" >&2
  exit 1
fi
if { [ "${CONTENDER1_RC}" -eq 0 ] && [ "${CONTENDER2_RC}" -eq 0 ]; } || { [ "${CONTENDER1_RC}" -ne 0 ] && [ "${CONTENDER2_RC}" -ne 0 ]; }; then
  echo "  ✗ FAIL: Expected one contender to succeed (0) and one to fail (non-zero), got rc1=${CONTENDER1_RC}, rc2=${CONTENDER2_RC}!" >&2
  exit 1
fi
rm -rf "${SLOW_RSYNC_BIN}" "${ENTER_LOG}"

# 9c. If flock is unavailable, fail closed rather than reclaiming with a race
if GBA_DISABLE_FLOCK="1" "${SCRIPT_DIR}/remote-deploy-sandbox.sh" "${TARBALL}" "http://127.0.0.1:${SANDBOX_PORT}/release-preview" "${TARBALL_HASH}" "${TEST_REL}" "${TEST_GIT_SHA}" 2>/dev/null; then
  echo "  ✗ FAIL: remote-deploy-sandbox.sh succeeded when flock was unavailable!" >&2
  exit 1
fi
if GBA_DISABLE_FLOCK="1" "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: remote-deploy-production.sh succeeded when flock was unavailable!" >&2
  exit 1
fi
if GBA_DISABLE_FLOCK="1" "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${TEST_PORT}" 2>/dev/null; then
  echo "  ✗ FAIL: rollback.sh succeeded when flock was unavailable!" >&2
  exit 1
fi

# 9c2. Regression Test: No bare `exec ... 2>/dev/null` that permanently silences parent shell stderr;
#      verify post-lock diagnostics are emitted to stderr in sandbox, production, and rollback
for script_path in "${SCRIPT_DIR}"/*.sh; do
  if grep -E '^[[:space:]]*exec[[:space:]]+[0-9]+.*[[:space:]]2>/dev/null' "${script_path}"; then
    echo "  ✗ FAIL: Bare 'exec ... 2>/dev/null' found in $(basename "${script_path}") — permanently redirects parent stderr!" >&2
    exit 1
  fi
done

SBX_POST_LOCK_ERR="$(PATH="${FAIL_RSYNC_BIN}:${PATH}" "${SCRIPT_DIR}/remote-deploy-sandbox.sh" "${TARBALL}" "http://127.0.0.1:${SANDBOX_PORT}/release-preview" "${TARBALL_HASH}" "${TEST_REL}" "${TEST_GIT_SHA}" 2>&1 >/dev/null || true)"
printf '%s\n' "${SBX_POST_LOCK_ERR}" | grep -q "Initiating automatic restoration of previous sandbox state" || {
  echo "  ✗ FAIL: remote-deploy-sandbox.sh stderr was suppressed after acquire_deploy_lock!" >&2
  exit 1
}
rm -rf "${SANDBOX_RECOVERY_ROOT}/run-"*

populate_mock_wordpress
PROD_POST_LOCK_ERR="$(PATH="${FAIL_RSYNC_BIN}:${PATH}" "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>&1 >/dev/null || true)"
printf '%s\n' "${PROD_POST_LOCK_ERR}" | grep -q "Initiating automatic restoration of previous production state" || {
  echo "  ✗ FAIL: remote-deploy-production.sh stderr was suppressed after acquire_deploy_lock!" >&2
  exit 1
}
reset_test_release_state "${TEST_REL}"

RB_POST_LOCK_ERR="$("${SCRIPT_DIR}/rollback.sh" "nonexistent-rel-stderr" "http://127.0.0.1:${TEST_PORT}" 2>&1 >/dev/null || true)"
printf '%s\n' "${RB_POST_LOCK_ERR}" | grep -q "CRITICAL ERROR:" || {
  echo "  ✗ FAIL: rollback.sh stderr was suppressed after acquire_deploy_lock!" >&2
  exit 1
}
echo "  ✓ Shared OS-held flock lock proves only 1 of 2 contenders enters, fails closed if flock is unavailable, and preserves parent stderr."

# 9d. Full Production Cutover & Duplicate Release ID Rejection
populate_mock_wordpress
export MOCK_SCHEMA_COUNT="0"
export MOCK_TABLE_COUNT="0"

"${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" >/dev/null

[ -f "${MOCK_BACKUPS}/${TEST_REL}_files.tar.gz" ] || { echo "Fail: files backup missing"; exit 1; }
[ -f "${MOCK_BACKUPS}/${TEST_REL}_db.sql.gz" ] || { echo "Fail: db backup missing"; exit 1; }
[ -f "${MOCK_BACKUPS}/${TEST_REL}_manifest.json" ] || { echo "Fail: manifest missing"; exit 1; }
[ -f "${MOCK_DOCROOT}/index.html" ] || { echo "Fail: index.html not installed"; exit 1; }
[ -f "${MOCK_DOCROOT}/assets/gba-logo-official-transparent.png" ] || { echo "Fail: assets/gba-logo-official-transparent.png not installed"; exit 1; }
[ -f "${MOCK_DOCROOT}/release-metadata.json" ] || { echo "Fail: release-metadata.json not installed"; exit 1; }
[ ! -f "${MOCK_DOCROOT}/wp-config.php" ] || { echo "Fail: wp-config.php still in docroot"; exit 1; }

MANIFEST="${MOCK_BACKUPS}/${TEST_REL}_manifest.json"
grep -q "\"git_sha\": \"${TEST_GIT_SHA}\"" "${MANIFEST}" || { echo "Fail: git_sha missing from manifest"; exit 1; }
grep -q "\"artifact_sha256\":" "${MANIFEST}" || { echo "Fail: artifact_sha256 missing from manifest"; exit 1; }
grep -q "\"files_backup_sha256\":" "${MANIFEST}" || { echo "Fail: files_backup_sha256 missing from manifest"; exit 1; }
grep -q "\"db_backup_sha256\":" "${MANIFEST}" || { echo "Fail: db_backup_sha256 missing from manifest"; exit 1; }
grep -q "\"db_required\": true" "${MANIFEST}" || { echo "Fail: db_required: true missing from manifest"; exit 1; }
grep -q "\"db_remaining_tables_count\": 0" "${MANIFEST}" || { echo "Fail: db_remaining_tables_count != 0"; exit 1; }
if grep -q "s0m3_s3cr3t_p@ss!" "${MANIFEST}"; then
  echo "  ✗ FAIL: Password leaked into manifest!" >&2
  exit 1
fi

ORIG_FILES_HASH="$(grep -E '"files_backup_sha256":' "${MANIFEST}" | sed -E 's/.*"([^"]+)".*/\1/')"

if "${SCRIPT_DIR}/remote-deploy-production.sh" "${TEST_REL}" "${TARBALL}" "http://127.0.0.1:${TEST_PORT}" "${TEST_GIT_SHA}" "${TARBALL_HASH}" 2>/dev/null; then
  echo "  ✗ FAIL: Duplicate release ID '${TEST_REL}' was accepted!" >&2
  exit 1
fi

AFTER_FILES_HASH="$(grep -E '"files_backup_sha256":' "${MANIFEST}" | sed -E 's/.*"([^"]+)".*/\1/')"
[ "${ORIG_FILES_HASH}" = "${AFTER_FILES_HASH}" ] || { echo "  ✗ FAIL: Duplicate deploy altered existing manifest/backup!" >&2; exit 1; }
[ -f "${MOCK_BACKUPS}/${TEST_REL}_db.sql.gz" ] || { echo "  ✗ FAIL: Duplicate deploy removed DB backup!" >&2; exit 1; }
echo "  ✓ Production cutover succeeded and duplicate release ID was rejected before writes."

# ==============================================================================
# Test 10: Hardened Rollback — Strict JSON Manifest, Pre-Rollback Snapshot/Recovery,
#          Partial rsync/chmod/DB/Health/Manifest Failure Recovery & Verified Rollback
# ==============================================================================
echo "[Test 10] Reproducing Rollback Failures (Malformed Manifest, Partial rsync/chmod/DB/Health/Manifest Failure) & Verified Rollback..."

# 10a. Missing manifest must fail rollback
cp "${MANIFEST}" "${MANIFEST}.orig"
rm -f "${MANIFEST}"
if "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${TEST_PORT}" 2>/dev/null; then
  echo "  ✗ FAIL: Rollback succeeded when manifest was missing!" >&2
  exit 1
fi

# 10b. Independent Reproduction: Non-JSON manifest ("THIS IS NOT JSON\n...") must fail rollback
cat > "${MANIFEST}" <<EOF
THIS IS NOT JSON
"files_backup_sha256": "${ORIG_FILES_HASH}"
EOF
if "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${TEST_PORT}" 2>/dev/null; then
  echo "  ✗ FAIL: Rollback accepted non-JSON manifest!" >&2
  exit 1
fi

# 10c. Independent Reproduction: Duplicate keys in JSON manifest must fail rollback
cat > "${MANIFEST}" <<EOF
{
  "release_id": "${TEST_REL}",
  "release_id": "forged-release",
  "git_sha": "${TEST_GIT_SHA}",
  "artifact_name": "gba-static-${TEST_REL}.tar.gz",
  "artifact_sha256": "${TARBALL_HASH}",
  "timestamp_utc": "2026-10-20T00:00:00Z",
  "docroot": "${MOCK_DOCROOT}",
  "db_required": false,
  "files_backup": "${MOCK_BACKUPS}/${TEST_REL}_files.tar.gz",
  "files_backup_sha256": "${ORIG_FILES_HASH}",
  "files_backup_size_bytes": 100,
  "status": "production_live_no_db"
}
EOF
if "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${TEST_PORT}" 2>/dev/null; then
  echo "  ✗ FAIL: Rollback accepted manifest with duplicate JSON keys!" >&2
  exit 1
fi

# 10d. Independent Reproduction: Unbound/partial manifest missing docroot/files_backup/db_required must fail rollback
cat > "${MANIFEST}" <<EOF
{"release_id": "${TEST_REL}", "files_backup_sha256": "${ORIG_FILES_HASH}"}
EOF
if "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${TEST_PORT}" 2>/dev/null; then
  echo "  ✗ FAIL: Rollback accepted unbound partial manifest!" >&2
  exit 1
fi

# 10e. Independent Reproduction: Manifest claiming db_required=false when wp-config.php & DB backup exist must fail
cat > "${MANIFEST}" <<EOF
{
  "release_id": "${TEST_REL}",
  "git_sha": "${TEST_GIT_SHA}",
  "artifact_name": "gba-static-${TEST_REL}.tar.gz",
  "artifact_sha256": "${TARBALL_HASH}",
  "timestamp_utc": "2026-10-20T00:00:00Z",
  "docroot": "${MOCK_DOCROOT}",
  "db_required": false,
  "files_backup": "${MOCK_BACKUPS}/${TEST_REL}_files.tar.gz",
  "files_backup_sha256": "${ORIG_FILES_HASH}",
  "files_backup_size_bytes": 100,
  "status": "production_live_no_db"
}
EOF
if "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${TEST_PORT}" 2>/dev/null; then
  echo "  ✗ FAIL: Rollback accepted manifest with db_required=false when WordPress DB backup existed!" >&2
  exit 1
fi

mv "${MANIFEST}.orig" "${MANIFEST}"
[ ! -f "${MOCK_DOCROOT}/wp-config.php" ] || { echo "  ✗ FAIL: Docroot was mutated during failed manifest validation tests!" >&2; exit 1; }
echo "  ✓ Rollback strictly rejected non-JSON, duplicate-key, unbound, and inconsistent manifests before mutation."

# 10f. Missing DB backup for WordPress release must fail rollback before modifying docroot
mv "${MOCK_BACKUPS}/${TEST_REL}_db.sql.gz" "${MOCK_BACKUPS}/${TEST_REL}_db.sql.gz.hidden"
if "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${TEST_PORT}" 2>/dev/null; then
  echo "  ✗ FAIL: Rollback succeeded despite missing required database backup!" >&2
  exit 1
fi
mv "${MOCK_BACKUPS}/${TEST_REL}_db.sql.gz.hidden" "${MOCK_BACKUPS}/${TEST_REL}_db.sql.gz"
[ ! -f "${MOCK_DOCROOT}/wp-config.php" ] || { echo "  ✗ FAIL: Docroot was modified despite missing DB backup!" >&2; exit 1; }

# 10g. Corrupted/mismatched backup hash vs manifest must fail rollback
cp "${MOCK_BACKUPS}/${TEST_REL}_files.tar.gz" "${MOCK_BACKUPS}/${TEST_REL}_files.tar.gz.orig"
echo "tamper" >> "${MOCK_BACKUPS}/${TEST_REL}_files.tar.gz"
if "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${TEST_PORT}" 2>/dev/null; then
  echo "  ✗ FAIL: Rollback accepted files backup whose SHA256 did not match manifest!" >&2
  exit 1
fi
mv "${MOCK_BACKUPS}/${TEST_REL}_files.tar.gz.orig" "${MOCK_BACKUPS}/${TEST_REL}_files.tar.gz"

# 10g2. Pre-schema count query MUST return strictly 0 or 1; unexpected count or query error must abort BEFORE snapshot/mutation
for bad_pre_schema in "count_two" "non_numeric" "query_error"; do
  if [ "${bad_pre_schema}" = "count_two" ]; then
    export MOCK_SCHEMA_COUNT="2"
    export MOCK_VERIFY_SCHEMA_FAIL="0"
  elif [ "${bad_pre_schema}" = "non_numeric" ]; then
    export MOCK_SCHEMA_COUNT="unexpected_output"
    export MOCK_VERIFY_SCHEMA_FAIL="0"
  else
    export MOCK_SCHEMA_COUNT="0"
    export MOCK_VERIFY_SCHEMA_FAIL="1"
  fi
  if "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${TEST_PORT}" 2>/dev/null; then
    echo "  ✗ FAIL: Rollback succeeded when pre-rollback schema check returned ${bad_pre_schema}!" >&2
    exit 1
  fi
  LEFTOVER_RB_SNAP="$(find "${MOCK_BACKUPS}" -maxdepth 1 -name '.rollback-recovery-*' 2>/dev/null || true)"
  [ -z "${LEFTOVER_RB_SNAP}" ] || {
    echo "  ✗ FAIL: Rollback created pre-rollback snapshot despite invalid pre-schema count (${bad_pre_schema})!" >&2
    exit 1
  }
  [ -f "${MOCK_DOCROOT}/index.html" ] && [ ! -f "${MOCK_DOCROOT}/wp-config.php" ] || {
    echo "  ✗ FAIL: Rollback mutated docroot despite invalid pre-schema count (${bad_pre_schema})!" >&2
    exit 1
  }
done
export MOCK_SCHEMA_COUNT="0"
export MOCK_VERIFY_SCHEMA_FAIL="0"
echo "  ✓ Rollback pre-schema count check strictly requires 0 or 1 and aborts before snapshot/mutation on error or unexpected count."

# 10h. Partial rsync failure, chmod failure, and DB import failure during rollback must restore pre-rollback live static files & DB state!
printf 'live-static-sentinel\n' > "${MOCK_DOCROOT}/old-sentinel"
if PATH="${FAIL_RSYNC_BIN}:${PATH}" "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${TEST_PORT}" 2>/dev/null; then
  echo "  ✗ FAIL: Rollback succeeded despite rsync exit 23!" >&2
  exit 1
fi
[ -f "${MOCK_DOCROOT}/old-sentinel" ] || { echo "  ✗ FAIL: Pre-rollback old-sentinel was NOT restored after rollback rsync failure!" >&2; exit 1; }
[ -f "${MOCK_DOCROOT}/index.html" ] || { echo "  ✗ FAIL: Pre-rollback index.html was NOT restored after rollback rsync failure!" >&2; exit 1; }
[ ! -e "${MOCK_DOCROOT}/partial-write" ] || { echo "  ✗ FAIL: partial-write remained in docroot after rollback rsync failure!" >&2; exit 1; }
[ ! -f "${MOCK_DOCROOT}/wp-config.php" ] || { echo "  ✗ FAIL: wp-config.php remained in docroot after rollback rsync failure!" >&2; exit 1; }

if PATH="${FAIL_CHMOD_BIN}:${PATH}" "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${TEST_PORT}" 2>/dev/null; then
  echo "  ✗ FAIL: Rollback succeeded despite post-rsync chmod failure!" >&2
  exit 1
fi
[ -f "${MOCK_DOCROOT}/old-sentinel" ] || { echo "  ✗ FAIL: Pre-rollback old-sentinel was NOT restored after rollback chmod failure!" >&2; exit 1; }
[ -f "${MOCK_DOCROOT}/index.html" ] || { echo "  ✗ FAIL: Pre-rollback index.html was NOT restored after rollback chmod failure!" >&2; exit 1; }
[ ! -f "${MOCK_DOCROOT}/wp-config.php" ] || { echo "  ✗ FAIL: wp-config.php remained in docroot after rollback chmod failure!" >&2; exit 1; }

# Test DB failure during rollback when pre-rollback DB existed (MOCK_SCHEMA_COUNT=1)
: > "${MYSQL_LOG}"
export MOCK_SCHEMA_COUNT="1"
export MOCK_IMPORT_FAIL="1"
if "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${TEST_PORT}" 2>/dev/null; then
  echo "  ✗ FAIL: Rollback succeeded despite DB import failure!" >&2
  exit 1
fi
export MOCK_IMPORT_FAIL="0"
export MOCK_SCHEMA_COUNT="0"
[ -f "${MOCK_DOCROOT}/old-sentinel" ] || { echo "  ✗ FAIL: Pre-rollback old-sentinel was NOT restored after rollback DB failure!" >&2; exit 1; }
[ ! -f "${MOCK_DOCROOT}/wp-config.php" ] || { echo "  ✗ FAIL: wp-config.php remained in docroot after rollback DB failure!" >&2; exit 1; }
rm -f "${MOCK_DOCROOT}/old-sentinel"
rm -rf "${MOCK_BACKUPS}/.rollback-recovery-"*

# 10h2. Signal Handling During Active Rollback Mutation (TERM=143, INT=130, HUP=129)
#       Mock rsync mutates docroot, sends signal to rollback.sh, and exits 0.
#       Must force nonzero signal-specific status and invoke EXIT recovery exactly once!
for sig_pair in "TERM:143" "INT:130" "HUP:129"; do
  sig_name="${sig_pair%%:*}"
  expected_rc="${sig_pair##*:}"
  printf 'live-static-sentinel\n' > "${MOCK_DOCROOT}/old-sentinel"
  SIG_RC=0
  SIG_ERR="$(TEST_SIGNAL_NAME="${sig_name}" PATH="${SIGNAL_RSYNC_BIN}:${PATH}" "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${TEST_PORT}" 2>&1 >/dev/null)" || SIG_RC=$?
  if [ "${SIG_RC}" -ne "${expected_rc}" ]; then
    echo "  ✗ FAIL: Rollback signal ${sig_name} exited with ${SIG_RC}, expected ${expected_rc}!" >&2
    exit 1
  fi
  [ -f "${MOCK_DOCROOT}/old-sentinel" ] && [ -f "${MOCK_DOCROOT}/index.html" ] && [ ! -e "${MOCK_DOCROOT}/partial-signal-write" ] && [ ! -f "${MOCK_DOCROOT}/wp-config.php" ] || {
    echo "  ✗ FAIL: Rollback did not restore live static state after signal ${sig_name}!" >&2
    exit 1
  }
  RESTORE_CALLS="$(printf '%s\n' "${SIG_ERR}" | grep -c "Initiating automatic restoration of pre-rollback live state" || true)"
  if [ "${RESTORE_CALLS}" -ne 1 ]; then
    echo "  ✗ FAIL: Rollback recovery ran ${RESTORE_CALLS} times on signal ${sig_name}, expected exactly 1!" >&2
    exit 1
  fi
  rm -f "${MOCK_DOCROOT}/old-sentinel"
  rm -rf "${MOCK_BACKUPS}/.rollback-recovery-"*
done
rm -rf "${SIGNAL_RSYNC_BIN}"

# 10i. HTTP 500 from verification URL must fail rollback AND restore pre-rollback live files + pre-rollback DB state
export MOCK_TABLE_COUNT="2"
: > "${MYSQL_LOG}"
if "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${FAIL_PORT}" 2>/dev/null; then
  echo "  ✗ FAIL: Rollback succeeded when verify URL returned HTTP 500!" >&2
  exit 1
fi
[ ! -f "${MOCK_BACKUPS}/${TEST_REL}_rollback_manifest.json" ] || { echo "  ✗ FAIL: Rollback manifest written despite HTTP 500 failure!" >&2; exit 1; }
[ -f "${MOCK_DOCROOT}/index.html" ] && [ ! -f "${MOCK_DOCROOT}/wp-config.php" ] || {
  echo "  ✗ FAIL: Pre-rollback static docroot was NOT restored after HTTP 500 rollback failure!" >&2
  exit 1
}
grep -q "QUERY:DROP DATABASE \`gba_wp_db\`;" "${MYSQL_LOG}" || {
  echo "  ✗ FAIL: Pre-rollback absent DB state was NOT restored after HTTP 500 rollback failure!" >&2
  exit 1
}
rm -rf "${MOCK_BACKUPS}/.rollback-recovery-"*

# 10j. Independent Reproduction: Fatal error on /index.php (when / returns 200 OK) must fail rollback and restore pre-rollback state
if "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${FATAL_PHP_PORT}" 2>/dev/null; then
  echo "  ✗ FAIL: Rollback succeeded when /index.php returned a PHP Fatal error!" >&2
  exit 1
fi
[ ! -f "${MOCK_BACKUPS}/${TEST_REL}_rollback_manifest.json" ] || { echo "  ✗ FAIL: Rollback manifest written despite fatal /index.php!" >&2; exit 1; }
[ -f "${MOCK_DOCROOT}/index.html" ] && [ ! -f "${MOCK_DOCROOT}/wp-config.php" ] || {
  echo "  ✗ FAIL: Pre-rollback static docroot was NOT restored after fatal /index.php rollback failure!" >&2
  exit 1
}
rm -rf "${MOCK_BACKUPS}/.rollback-recovery-"*

# 10k. Independent Reproduction: If pre-rollback restoration fails, recovery evidence MUST be preserved!
if TEST_MOCK_DB_RECOVERY_FAIL="1" "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${FAIL_PORT}" 2>/dev/null; then
  echo "  ✗ FAIL: Rollback succeeded on FAIL_PORT!" >&2
  exit 1
fi
PRESERVED_TREES="$(find "${MOCK_BACKUPS}" -maxdepth 2 -name 'pre-rollback-tree' -type d 2>/dev/null || true)"
[ -n "${PRESERVED_TREES}" ] || { echo "  ✗ FAIL: Pre-rollback recovery tree was not preserved when restoration failed!" >&2; exit 1; }
# Restore MOCK_DOCROOT back to static state and clean preserved test recovery dir before final rollback test
cp -R "${MOCK_RELEASES}/${TEST_REL}/." "${MOCK_DOCROOT}/"
rm -rf "${MOCK_BACKUPS}/.rollback-recovery-"*

# 10k2. Transactional Rollback Finalization: Injected Second-Write Failure (TEST_FAIL_ROLLBACK_SECOND_WRITE=1)
#       Proves that if publishing the updated original manifest fails after publishing the rollback audit,
#       the rollback audit is immediately compensated/removed (no false rolled_back record remains)
#       and pre-rollback live static files + DB state are restored!
export MOCK_TABLE_COUNT="2"
: > "${MYSQL_LOG}"
if TEST_FAIL_ROLLBACK_SECOND_WRITE="1" "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${TEST_PORT}" 2>/dev/null; then
  echo "  ✗ FAIL: Rollback succeeded despite injected second-write finalization failure!" >&2
  exit 1
fi
[ ! -e "${MOCK_BACKUPS}/${TEST_REL}_rollback_manifest.json" ] || {
  echo "  ✗ FAIL: False rolled_back audit record (${TEST_REL}_rollback_manifest.json) remained after second-write failure!" >&2
  exit 1
}
LEFTOVER_RB_TMPS="$(find "${MOCK_BACKUPS}" -maxdepth 1 -name "*${TEST_REL}*manifest*.tmp*" 2>/dev/null || true)"
[ -z "${LEFTOVER_RB_TMPS}" ] || {
  echo "  ✗ FAIL: Leftover manifest temp files remained after second-write failure: ${LEFTOVER_RB_TMPS}" >&2
  exit 1
}
python3 - "${MOCK_BACKUPS}/${TEST_REL}_manifest.json" <<'PYEOF'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)
assert data.get("status") == "production_live_db_purged", f"Expected status production_live_db_purged, got {data.get('status')}"
assert "rolled_back_at_utc" not in data, "Unexpected rolled_back_at_utc in original manifest after failed finalization"
PYEOF
[ -f "${MOCK_DOCROOT}/index.html" ] && [ ! -f "${MOCK_DOCROOT}/wp-config.php" ] || {
  echo "  ✗ FAIL: Live static docroot was NOT restored after rollback second-write finalization failure!" >&2
  exit 1
}
grep -q "QUERY:DROP DATABASE \`gba_wp_db\`;" "${MYSQL_LOG}" || {
  echo "  ✗ FAIL: Pre-rollback absent DB state was NOT restored after rollback second-write finalization failure!" >&2
  exit 1
}
rm -rf "${MOCK_BACKUPS}/.rollback-recovery-"*

# 10k3. Regression: Manifest Parent Unwritable After First Publication & Unsuppressed Compensation Failure
#       Proves:
#         - Nonzero result when manifest parent becomes unwritable after first publication
#         - No false rolled_back audit if removable; if it cannot be removed because parent is unwritable,
#           preserved snapshots/evidence remain and an explicit failure is reported
#         - Original snapshots (pre-rollback-manifest.json and pre-rollback-audit-manifest.json) are NEVER
#           deleted on failed compensation
export MOCK_TABLE_COUNT="2"
: > "${MYSQL_LOG}"
UNWRITABLE_RC=0
UNWRITABLE_ERR="$(TEST_UNWRITABLE_MANIFEST_PARENT_AFTER_FIRST="1" "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${TEST_PORT}" 2>&1 >/dev/null)" || UNWRITABLE_RC=$?
chmod 755 "${MOCK_BACKUPS}"

if [ "${UNWRITABLE_RC}" -eq 0 ]; then
  echo "  ✗ FAIL: Rollback succeeded despite manifest parent becoming unwritable after first publication!" >&2
  exit 1
fi
printf '%s\n' "${UNWRITABLE_ERR}" | grep -q "CRITICAL ERROR: Rollback manifest compensation/restoration failed" || {
  echo "  ✗ FAIL: Rollback did not report explicit manifest compensation/restoration failure diagnostic!" >&2
  exit 1
}
printf '%s\n' "${UNWRITABLE_ERR}" | grep -q "CRITICAL ERROR: Rollback transaction recovery failed" || {
  echo "  ✗ FAIL: Rollback cleanup did not report transaction recovery failure diagnostic!" >&2
  exit 1
}
if [ -e "${MOCK_BACKUPS}/${TEST_REL}_rollback_manifest.json" ]; then
  # Audit file could not be removed because parent was 0500; verify explicit audit removal failure was reported
  printf '%s\n' "${UNWRITABLE_ERR}" | grep -q "CRITICAL ERROR: Failed to remove uncompleted rollback audit manifest" || {
    echo "  ✗ FAIL: Unremovable rollback audit manifest was not explicitly reported as an error!" >&2
    exit 1
  }
fi
PRESERVED_ORIG_SNAP="$(find "${MOCK_BACKUPS}" -maxdepth 2 -name 'pre-rollback-manifest.json' -type f 2>/dev/null || true)"
PRESERVED_FILES_SNAP="$(find "${MOCK_BACKUPS}" -maxdepth 2 -name 'pre-rollback-files.tar.gz' -type f 2>/dev/null || true)"
PRESERVED_TREE_SNAP="$(find "${MOCK_BACKUPS}" -maxdepth 2 -name 'pre-rollback-tree' -type d 2>/dev/null || true)"
[ -n "${PRESERVED_ORIG_SNAP}" ] && [ -n "${PRESERVED_FILES_SNAP}" ] && [ -n "${PRESERVED_TREE_SNAP}" ] || {
  echo "  ✗ FAIL: Original manifest snapshot or recovery evidence was deleted on failed compensation (orig=${PRESERVED_ORIG_SNAP}, files=${PRESERVED_FILES_SNAP}, tree=${PRESERVED_TREE_SNAP})!" >&2
  exit 1
}
[ -f "${MOCK_DOCROOT}/index.html" ] && [ ! -f "${MOCK_DOCROOT}/wp-config.php" ] || {
  echo "  ✗ FAIL: Live static docroot was not restored when manifest parent became unwritable!" >&2
  exit 1
}
rm -f "${MOCK_BACKUPS}/${TEST_REL}_rollback_manifest.json"
rm -rf "${MOCK_BACKUPS}/.rollback-recovery-"*

# Also test with a prior rollback audit manifest so BOTH original-manifest snapshot files exist and are preserved
cat > "${MOCK_BACKUPS}/${TEST_REL}_rollback_manifest.json" <<EOF
{
  "restored_release_id": "${TEST_REL}",
  "status": "prior_rolled_back"
}
EOF
UNWRITABLE_PRIOR_RC=0
UNWRITABLE_PRIOR_ERR="$(TEST_UNWRITABLE_MANIFEST_PARENT_AFTER_FIRST="1" "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${TEST_PORT}" 2>&1 >/dev/null)" || UNWRITABLE_PRIOR_RC=$?
chmod 755 "${MOCK_BACKUPS}"
if [ "${UNWRITABLE_PRIOR_RC}" -eq 0 ]; then
  echo "  ✗ FAIL: Rollback succeeded when manifest parent was unwritable with prior rollback manifest!" >&2
  exit 1
fi
PRESERVED_ORIG_MF2="$(find "${MOCK_BACKUPS}" -maxdepth 2 -name 'pre-rollback-manifest.json' -type f 2>/dev/null || true)"
PRESERVED_ORIG_RB2="$(find "${MOCK_BACKUPS}" -maxdepth 2 -name 'pre-rollback-audit-manifest.json' -type f 2>/dev/null || true)"
[ -n "${PRESERVED_ORIG_MF2}" ] && [ -n "${PRESERVED_ORIG_RB2}" ] || {
  echo "  ✗ FAIL: Both original-manifest snapshot files were not preserved on failed compensation (mf=${PRESERVED_ORIG_MF2}, rb=${PRESERVED_ORIG_RB2})!" >&2
  exit 1
}
rm -f "${MOCK_BACKUPS}/${TEST_REL}_rollback_manifest.json"
rm -rf "${MOCK_BACKUPS}/.rollback-recovery-"*

# Also test when false rolled_back audit IS removable (and removed), then parent becomes unwritable before original manifest restore:
# proves nonzero result, NO false rolled_back audit remains, explicit failure reported, and original snapshots/evidence preserved!
UNWRITABLE_AFTER_AUDIT_RC=0
UNWRITABLE_AFTER_AUDIT_ERR="$(TEST_FAIL_ROLLBACK_SECOND_WRITE="1" TEST_UNWRITABLE_MANIFEST_PARENT_AFTER_AUDIT_REMOVE="1" "${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${TEST_PORT}" 2>&1 >/dev/null)" || UNWRITABLE_AFTER_AUDIT_RC=$?
chmod 755 "${MOCK_BACKUPS}"
if [ "${UNWRITABLE_AFTER_AUDIT_RC}" -eq 0 ]; then
  echo "  ✗ FAIL: Rollback succeeded when original manifest restore failed during compensation!" >&2
  exit 1
fi
[ ! -e "${MOCK_BACKUPS}/${TEST_REL}_rollback_manifest.json" ] || {
  echo "  ✗ FAIL: False rolled_back audit remained even though it was removable before parent became unwritable!" >&2
  exit 1
}
PRESERVED_ORIG_MF3="$(find "${MOCK_BACKUPS}" -maxdepth 2 -name 'pre-rollback-manifest.json' -type f 2>/dev/null || true)"
PRESERVED_TREE_SNAP3="$(find "${MOCK_BACKUPS}" -maxdepth 2 -name 'pre-rollback-tree' -type d 2>/dev/null || true)"
[ -n "${PRESERVED_ORIG_MF3}" ] && [ -n "${PRESERVED_TREE_SNAP3}" ] || {
  echo "  ✗ FAIL: Original manifest snapshot or recovery tree was deleted when original manifest restore failed!" >&2
  exit 1
}
printf '%s\n' "${UNWRITABLE_AFTER_AUDIT_ERR}" | grep -q "CRITICAL ERROR: Failed to restore original release manifest" || {
  echo "  ✗ FAIL: Explicit failure diagnostic for original manifest restore was not emitted!" >&2
  exit 1
}
rm -rf "${MOCK_BACKUPS}/.rollback-recovery-"*
echo "  ✓ Rollback trapped partial rsync/chmod/DB/HTTP 500/fatal /index.php/second-write/unwritable-manifest-parent failures, never suppressed compensation errors, and preserved all snapshots/evidence on failed compensation."

# 10l. Successful rollback when manifest hashes, DB restore (table count > 0), and HTTP 200 content checks on / and /index.php pass
export MOCK_TABLE_COUNT="2"
"${SCRIPT_DIR}/rollback.sh" "${TEST_REL}" "http://127.0.0.1:${TEST_PORT}" >/dev/null
[ -f "${MOCK_DOCROOT}/wp-config.php" ] || { echo "Fail: wp-config.php not restored!"; exit 1; }
[ -f "${MOCK_DOCROOT}/index.php" ] || { echo "Fail: index.php not restored!"; exit 1; }
[ -f "${MOCK_DOCROOT}/wp-content/uploads/sample.jpg" ] || { echo "Fail: uploads not restored!"; exit 1; }
[ ! -f "${MOCK_DOCROOT}/styles.css" ] || { echo "Fail: styles.css still present after rollback!"; exit 1; }
[ -f "${MOCK_BACKUPS}/${TEST_REL}_rollback_manifest.json" ] || { echo "Fail: rollback manifest missing!"; exit 1; }
echo "  ✓ Rollback verified strict JSON manifest, restored DB and docroot files, and verified HTTP 200 health across / and /index.php."

# ==============================================================================
# Test 11: Workflow Security, Immutable Checkout, Concurrency & Pre-Upload Staging Guard
# ==============================================================================
echo "[Test 11] Auditing Workflows & Reproducing Pre-Upload Staging Symlink Escape Prevention..."
WORKFLOW_DIR="${REPO_ROOT}/.github/workflows"

# 11a. Check minimal permissions & full 40-char SHA action pinning across all 4 workflows
for wf in ci.yml deploy-sandbox.yml deploy-production.yml rollback.yml; do
  WF_PATH="${WORKFLOW_DIR}/${wf}"
  grep -q "contents: read" "${WF_PATH}" || { echo "Fail: minimal permission 'contents: read' missing in ${wf}"; exit 1; }

  while IFS= read -r uses_line; do
    if [ -z "${uses_line}" ]; then
      continue
    fi
    if [[ ! "${uses_line}" =~ @[0-9a-f]{40}([[:space:]]|$) ]]; then
      echo "  ✗ FAIL: Unpinned action in ${wf}: ${uses_line}" >&2
      exit 1
    fi
  done < <(grep -E "^[[:space:]]*-?[[:space:]]*uses:" "${WF_PATH}")

  grep -q 'ref: ${{ github.sha }}' "${WF_PATH}" || { echo "Fail: immutable ref: \${{ github.sha }} missing in ${wf}"; exit 1; }
  grep -q 'git rev-parse --verify HEAD' "${WF_PATH}" || { echo "Fail: HEAD verification missing in ${wf}"; exit 1; }

  if awk '
    /^[[:space:]]*run:[[:space:]]*\|/ { in_run=1; run_indent=match($0, /[^ ]/); next }
    in_run {
      if ($0 ~ /^[[:space:]]*$/) next
      cur_indent=match($0, /[^ ]/)
      if (cur_indent <= run_indent) { in_run=0 }
      else if ($0 ~ /\$\{\{/) { found=1; exit 1 }
    }
    END { exit found ? 1 : 0 }
  ' "${WF_PATH}"; then
    :
  else
    echo "  ✗ FAIL: Direct \${{ ... }} interpolation found inside a run: block in ${wf}!" >&2
    exit 1
  fi
done
echo "  ✓ All workflows enforce contents:read permissions, 40-char SHA pinned actions, immutable github.sha checkout, and zero \${{ }} inside run: blocks."

# 11b. Reproduce immutable checkout HEAD verification failure when EXPECTED_SHA != HEAD
if (
  EXPECTED_SHA="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  ACTUAL_HEAD="$(git -C "${REPO_ROOT}" rev-parse --verify HEAD 2>/dev/null || echo "uncommitted")"
  [ "${ACTUAL_HEAD}" = "${EXPECTED_SHA}" ]
); then
  echo "  ✗ FAIL: Mismatched HEAD check unexpectedly succeeded!" >&2
  exit 1
fi
echo "  ✓ Immutable checkout HEAD guard rejects mismatched commit state."

# 11c. Verify shared deployment concurrency group across deploy-sandbox, deploy-production, and rollback
for wf in deploy-sandbox.yml deploy-production.yml rollback.yml; do
  WF_PATH="${WORKFLOW_DIR}/${wf}"
  grep -q "^  group: gba-deployment$" "${WF_PATH}" || { echo "Fail: shared concurrency group 'gba-deployment' missing in ${wf}"; exit 1; }
  grep -q "^  cancel-in-progress: false$" "${WF_PATH}" || { echo "Fail: cancel-in-progress: false missing in ${wf}"; exit 1; }
done
echo "  ✓ All deployment and rollback workflows share concurrency group 'gba-deployment'."

# 11d. Verify unified staging path, explicit SSH/SCP keepalive options, and execute extracted pre-upload staging reservation script against symlink escape probes
for wf in deploy-sandbox.yml deploy-production.yml rollback.yml; do
  WF_PATH="${WORKFLOW_DIR}/${wf}"
  grep -q "SSH_KNOWN_HOSTS" "${WF_PATH}" || { echo "Fail: SSH_KNOWN_HOSTS missing from ${wf}"; exit 1; }
  grep -q "StrictHostKeyChecking=yes" "${WF_PATH}" || { echo "Fail: StrictHostKeyChecking=yes missing from ${wf}"; exit 1; }
  grep -q 'REMOTE_STAGE="/home/alibhatt/.gba-deploy-staging/${RELEASE_ID}"' "${WF_PATH}" || { echo "Fail: unified REMOTE_STAGE missing from ${wf}"; exit 1; }

  # Regression assertions: every SSH_OPTS and SCP_OPTS array in all remote workflows must include explicit keepalive and strict host-key options
  SSH_OPTS_LINES="$(grep -E '^[[:space:]]*SSH_OPTS=\(' "${WF_PATH}" || true)"
  SCP_OPTS_LINES="$(grep -E '^[[:space:]]*SCP_OPTS=\(' "${WF_PATH}" || true)"
  [ -n "${SSH_OPTS_LINES}" ] || { echo "  ✗ FAIL: SSH_OPTS array missing from ${wf}!" >&2; exit 1; }
  [ -n "${SCP_OPTS_LINES}" ] || { echo "  ✗ FAIL: SCP_OPTS array missing from ${wf}!" >&2; exit 1; }

  while IFS= read -r ssh_opt_line; do
    [ -n "${ssh_opt_line}" ] || continue
    for req_opt in '-i ~/.ssh/deploy_id' '-p "${SSH_PORT}"' '-o BatchMode=yes' '-o StrictHostKeyChecking=yes' '-o ServerAliveInterval=30' '-o ServerAliveCountMax=60' '-o TCPKeepAlive=yes'; do
      grep -F -q -- "${req_opt}" <<< "${ssh_opt_line}" || {
        echo "  ✗ FAIL: Required SSH option '${req_opt}' missing from SSH_OPTS in ${wf}: ${ssh_opt_line}" >&2
        exit 1
      }
    done
  done <<< "${SSH_OPTS_LINES}"

  while IFS= read -r scp_opt_line; do
    [ -n "${scp_opt_line}" ] || continue
    for req_opt in '-i ~/.ssh/deploy_id' '-P "${SSH_PORT}"' '-o BatchMode=yes' '-o StrictHostKeyChecking=yes' '-o ServerAliveInterval=30' '-o ServerAliveCountMax=60' '-o TCPKeepAlive=yes'; do
      grep -F -q -- "${req_opt}" <<< "${scp_opt_line}" || {
        echo "  ✗ FAIL: Required SCP option '${req_opt}' missing from SCP_OPTS in ${wf}: ${scp_opt_line}" >&2
        exit 1
      }
    done
  done <<< "${SCP_OPTS_LINES}"

  # Ensure every ssh/scp invocation in the workflow uses "${SSH_OPTS[@]}" / "${SCP_OPTS[@]}"
  if grep -E '^[[:space:]]*ssh[[:space:]]+' "${WF_PATH}" | grep -F -v '"${SSH_OPTS[@]}"'; then
    echo "  ✗ FAIL: Found ssh invocation not using \"\${SSH_OPTS[@]}\" in ${wf}!" >&2
    exit 1
  fi
  if grep -E '^[[:space:]]*scp[[:space:]]+' "${WF_PATH}" | grep -F -v '"${SCP_OPTS[@]}"'; then
    echo "  ✗ FAIL: Found scp invocation not using \"\${SCP_OPTS[@]}\" in ${wf}!" >&2
    exit 1
  fi

  grep -q 'mkdir -m 700 -- "${REMOTE_STAGE}"' "${WF_PATH}" || { echo "Fail: exclusive mkdir reservation missing from ${wf}"; exit 1; }
  grep -q "bash -s --" "${WF_PATH}" || { echo "Fail: positional bash -s -- SSH invocation missing from ${wf}"; exit 1; }
  grep -q "<<'EOF'" "${WF_PATH}" || { echo "Fail: single-quoted heredoc <<'EOF' missing from ${wf}"; exit 1; }
  if grep -qE "~/gba-|ssh-keyscan|StrictHostKeyChecking=accept-new|mkdir -p -- \"/home/alibhatt/\.gba-deploy-staging\" \"\$\{REMOTE_STAGE\}\"" "${WF_PATH}"; then
    echo "  ✗ FAIL: Legacy insecure staging mkdir -p or host key setting found in ${wf}!" >&2
    exit 1
  fi

  # Extract the pre-upload SSH reservation heredoc from the workflow and test it directly
  STAGE_SNIPPET="${TEST_ENV_DIR}/stage-snippet-${wf}.sh"
  awk '
    /Securing and reserving remote staging area before upload:/ { found_step=1; next }
    found_step && /<<\x27EOF\x27/ { in_eof=1; next }
    in_eof && /^[[:space:]]*EOF[[:space:]]*$/ { exit 0 }
    in_eof { sub(/^[[:space:]]{10}/, ""); print }
  ' "${WF_PATH}" > "${STAGE_SNIPPET}"

  [ -s "${STAGE_SNIPPET}" ] || { echo "  ✗ FAIL: Could not extract staging reservation snippet from ${wf}!" >&2; exit 1; }
  bash -n "${STAGE_SNIPPET}"

  TRANSPORT_STAGE="${TEST_ENV_DIR}/transport-stage-${wf}"
  OUTSIDE_STAGE="${TEST_ENV_DIR}/outside-stage-${wf}"
  mkdir -p "${TRANSPORT_STAGE}" "${OUTSIDE_STAGE}"
  ln -s "${OUTSIDE_STAGE}" "${TRANSPORT_STAGE}/release"

  # Probe 1: Pre-existing symlink at REMOTE_STAGE pointing outside staging root MUST be rejected before SCP
  if TEST_MODE="1" GBA_STAGE_ROOT_OVERRIDE="${TRANSPORT_STAGE}" bash "${STAGE_SNIPPET}" "${TRANSPORT_STAGE}/release" "release" 2>/dev/null; then
    echo "  ✗ FAIL: Pre-upload staging in ${wf} accepted symlinked stage path '${TRANSPORT_STAGE}/release'!" >&2
    exit 1
  fi
  [ -z "$(ls -A "${OUTSIDE_STAGE}")" ] || { echo "  ✗ FAIL: Outside stage directory was modified!" >&2; exit 1; }
  rm -f "${TRANSPORT_STAGE}/release"

  # Probe 2: Pre-existing directory at REMOTE_STAGE MUST be rejected by exclusive reservation
  mkdir -p "${TRANSPORT_STAGE}/existing-rel"
  if TEST_MODE="1" GBA_STAGE_ROOT_OVERRIDE="${TRANSPORT_STAGE}" bash "${STAGE_SNIPPET}" "${TRANSPORT_STAGE}/existing-rel" "existing-rel" 2>/dev/null; then
    echo "  ✗ FAIL: Pre-upload staging in ${wf} accepted already-existing stage directory!" >&2
    exit 1
  fi

  # Probe 3: Symlinked staging root MUST be rejected
  SYMLINK_STAGE_ROOT="${TEST_ENV_DIR}/sym-stage-root-${wf}"
  ln -s "${TRANSPORT_STAGE}" "${SYMLINK_STAGE_ROOT}"
  if TEST_MODE="1" GBA_STAGE_ROOT_OVERRIDE="${SYMLINK_STAGE_ROOT}" bash "${STAGE_SNIPPET}" "${SYMLINK_STAGE_ROOT}/fresh" "fresh" 2>/dev/null; then
    echo "  ✗ FAIL: Pre-upload staging in ${wf} accepted symlinked staging root!" >&2
    exit 1
  fi
  rm -f "${SYMLINK_STAGE_ROOT}"

  # Probe 4: Valid fresh stage reservation succeeds and creates mode 700 directory
  TEST_MODE="1" GBA_STAGE_ROOT_OVERRIDE="${TRANSPORT_STAGE}" bash "${STAGE_SNIPPET}" "${TRANSPORT_STAGE}/fresh-rel" "fresh-rel" >/dev/null
  [ -d "${TRANSPORT_STAGE}/fresh-rel" ] && [ ! -L "${TRANSPORT_STAGE}/fresh-rel" ] || {
    echo "  ✗ FAIL: Pre-upload staging in ${wf} did not create '${TRANSPORT_STAGE}/fresh-rel'!" >&2
    exit 1
  }
  rm -rf "${TRANSPORT_STAGE}" "${OUTSIDE_STAGE}" "${STAGE_SNIPPET}"
done
echo "  ✓ All remote workflows enforce explicit SSH/SCP keepalives (ServerAliveInterval=30, ServerAliveCountMax=60, TCPKeepAlive=yes), reserve /home/alibhatt/.gba-deploy-staging/<release-id> exclusively before SCP, and block symlink escapes."

echo "================================================================================"
echo "ALL RELEASE SCAFFOLDING TESTS PASSED (11/11)"
echo "================================================================================"
