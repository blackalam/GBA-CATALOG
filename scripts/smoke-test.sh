#!/usr/bin/env bash
# ==============================================================================
# GBA Furniture — Public HTTP Smoke Test Suite
#
# Usage:
#   ./scripts/smoke-test.sh <BASE_URL> [CURL_EXTRA_ARGS...]
#
# Optional Environment Bindings (enforced when set by deployment scripts):
#   EXPECTED_RELEASE_ID    — Exact release_id required in /release-metadata.json
#   EXPECTED_GIT_SHA       — Exact git_sha required in /release-metadata.json
#   EXPECTED_TREE_SHA256   — Exact tree_sha256 required in /release-metadata.json
#   EXPECTED_METADATA_FILE — Path to staged/deployed release-metadata.json for
#                            exact SHA256 & JSON field comparison
#
# Enforces:
#   - Strict URL format validation before making requests.
#   - HTTP 200 OK for HTML, CSS, JS, JSON, release-metadata.json, and images.
#   - Content integrity checks (presence of brand keywords, valid JSON).
#   - Cryptographic & exact identity verification of public /release-metadata.json
#     against expected release_id, git_sha, tree_sha256, and metadata file hash.
#   - Fails fast with non-zero exit code if any asset or identity check fails.
# ==============================================================================

set -euo pipefail

export LC_ALL=C

BASE_URL="${1:-}"
if [ -z "${BASE_URL}" ]; then
  echo "Usage: $0 <BASE_URL> [CURL_ARGS...]" >&2
  exit 1
fi
shift || true
EXTRA_ARGS=("$@")

# Normalize URL: strip trailing slash
BASE_URL="${BASE_URL%/}"

# Strictly validate URL format to reject shell metacharacters, quotes, spaces, or non-HTTP schemes
if [[ ! "${BASE_URL}" =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]{1,5})?(/[a-zA-Z0-9._/-]*)?$ ]]; then
  echo "CRITICAL ERROR: Invalid BASE_URL '${BASE_URL}'. Must match ^https?://[a-zA-Z0-9.-]+(:[0-9]{1,5})?(/[a-zA-Z0-9._/-]*)?$" >&2
  exit 1
fi

echo "================================================================================"
echo "GBA Furniture: Running Remote/Public Smoke Tests"
echo "Target URL: ${BASE_URL}"
echo "================================================================================"

TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
CURRENT_TMP=""
SIGNAL_EXIT_CODE=""
CLEANUP_IN_PROGRESS=0

handle_signal() {
  local sig_exit_code="$1"
  SIGNAL_EXIT_CODE="${sig_exit_code}"
  exit "${sig_exit_code}"
}

cleanup_tmp() {
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
  if [ -n "${CURRENT_TMP:-}" ] && [ -f "${CURRENT_TMP}" ]; then
    rm -f "${CURRENT_TMP}"
  fi
  exit "${exit_code}"
}
trap cleanup_tmp EXIT
trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM
trap 'handle_signal 129' HUP

check_endpoint() {
  local endpoint="$1"
  local expected_status="$2"
  local content_check="${3:-}"
  local desc="$4"

  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  local url="${BASE_URL}${endpoint}"
  CURRENT_TMP=$(mktemp)

  local http_code
  if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
    http_code=$(curl -sSL --max-time 15 -w "%{http_code}" "${EXTRA_ARGS[@]}" -o "${CURRENT_TMP}" -- "${url}" || echo "000")
  else
    http_code=$(curl -sSL --max-time 15 -w "%{http_code}" -o "${CURRENT_TMP}" -- "${url}" || echo "000")
  fi

  if [ "${http_code}" != "${expected_status}" ]; then
    echo "  ✗ FAIL: ${desc} -> Expected HTTP ${expected_status}, received ${http_code} at ${url}" >&2
    rm -f "${CURRENT_TMP}"
    CURRENT_TMP=""
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    return 1
  fi

  if [ -n "${content_check}" ]; then
    if ! grep -F -q -- "${content_check}" "${CURRENT_TMP}"; then
      echo "  ✗ FAIL: ${desc} -> Content verification failed (missing '${content_check}') at ${url}" >&2
      rm -f "${CURRENT_TMP}"
      CURRENT_TMP=""
      FAILED_CHECKS=$((FAILED_CHECKS + 1))
      return 1
    fi
  fi

  rm -f "${CURRENT_TMP}"
  CURRENT_TMP=""
  echo "  ✓ PASS: ${desc} (HTTP ${http_code})"
  PASSED_CHECKS=$((PASSED_CHECKS + 1))
  return 0
}

check_release_identity() {
  local url="${BASE_URL}/release-metadata.json"
  local desc="Public release identity (/release-metadata.json) delivery & binding"
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  CURRENT_TMP=$(mktemp)

  local http_code
  if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
    http_code=$(curl -sSL --max-time 15 -w "%{http_code}" "${EXTRA_ARGS[@]}" -o "${CURRENT_TMP}" -- "${url}" || echo "000")
  else
    http_code=$(curl -sSL --max-time 15 -w "%{http_code}" -o "${CURRENT_TMP}" -- "${url}" || echo "000")
  fi

  if [ "${http_code}" != "200" ]; then
    echo "  ✗ FAIL: ${desc} -> Expected HTTP 200, received ${http_code} at ${url}" >&2
    rm -f "${CURRENT_TMP}"
    CURRENT_TMP=""
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    return 1
  fi

  if ! python3 - "${CURRENT_TMP}" "${EXPECTED_RELEASE_ID:-}" "${EXPECTED_GIT_SHA:-}" "${EXPECTED_TREE_SHA256:-}" "${EXPECTED_METADATA_FILE:-}" <<'PYEOF'
import hashlib, json, os, re, sys

fetched_path, exp_rel, exp_sha, exp_tree, exp_meta_file = sys.argv[1:6]

def no_dups(pairs):
    obj = {}
    for k, v in pairs:
        if k in obj:
            raise ValueError(f"Duplicate key '{k}' in release-metadata.json")
        obj[k] = v
    return obj

with open(fetched_path, "rb") as f:
    fetched_bytes = f.read()

fetched_hash = hashlib.sha256(fetched_bytes).hexdigest()
meta = json.loads(fetched_bytes.decode("utf-8"), object_pairs_hook=no_dups)
if not isinstance(meta, dict):
    raise ValueError("release-metadata.json root must be a JSON object")

rel_id = meta.get("release_id", "")
git_sha = meta.get("git_sha", "")
tree_sha = meta.get("tree_sha256", "")

if not isinstance(rel_id, str) or not re.match(r"^[a-zA-Z0-9][a-zA-Z0-9._-]*$", rel_id) or ".." in rel_id:
    raise ValueError(f"Invalid release_id in public release-metadata.json: {rel_id!r}")
if not isinstance(git_sha, str) or not re.match(r"^[a-zA-Z0-9._-]+$", git_sha) or ".." in git_sha:
    raise ValueError(f"Invalid git_sha in public release-metadata.json: {git_sha!r}")

if exp_rel and rel_id != exp_rel:
    raise ValueError(f"Public release_id mismatch: expected {exp_rel!r}, got {rel_id!r}")
if exp_sha and exp_sha != "unspecified" and git_sha != exp_sha:
    raise ValueError(f"Public git_sha mismatch: expected {exp_sha!r}, got {git_sha!r}")
if exp_tree and tree_sha != exp_tree:
    raise ValueError(f"Public tree_sha256 mismatch: expected {exp_tree!r}, got {tree_sha!r}")

if exp_meta_file:
    if not os.path.isfile(exp_meta_file):
        raise ValueError(f"Expected metadata file missing: {exp_meta_file}")
    with open(exp_meta_file, "rb") as ef:
        exp_bytes = ef.read()
    exp_hash = hashlib.sha256(exp_bytes).hexdigest()
    exp_meta = json.loads(exp_bytes.decode("utf-8"), object_pairs_hook=no_dups)
    if fetched_hash != exp_hash or meta != exp_meta:
        raise ValueError(
            f"Public /release-metadata.json hash/content mismatch against deployed candidate "
            f"(expected sha256={exp_hash}, fetched sha256={fetched_hash})"
        )
PYEOF
  then
    echo "  ✗ FAIL: ${desc} -> Public release identity verification failed at ${url}" >&2
    rm -f "${CURRENT_TMP}"
    CURRENT_TMP=""
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    return 1
  fi

  rm -f "${CURRENT_TMP}"
  CURRENT_TMP=""
  echo "  ✓ PASS: ${desc} (HTTP ${http_code})"
  PASSED_CHECKS=$((PASSED_CHECKS + 1))
  return 0
}

# 1. Homepage index check
check_endpoint "" "200" "GBA Furniture" "Homepage index.html delivery & title"

# 2. Key contact facts check on homepage
check_endpoint "/index.html" "200" "020 8888 0322" "Contact telephone on index.html"
check_endpoint "/index.html" "200" "401 Lordship Lane" "Showroom address on index.html"

# 3. Core Stylesheet
check_endpoint "/styles.css" "200" "--color-petrol" "Stylesheet CSS delivery & brand root variables"

# 4. Core JavaScript
check_endpoint "/script.js" "200" "products" "Client catalogue JavaScript delivery"

# 5. Products Catalogue Data
check_endpoint "/data/products.json" "200" "beds-mattresses" "Catalog JSON data delivery & category check"

# 6. Official Transparent Brand Logo & Legacy Web Logo
check_endpoint "/assets/gba-logo-official-transparent.png" "200" "" "Official transparent brand logo delivery (gba-logo-official-transparent.png)"
check_endpoint "/assets/gba-logo-web.png" "200" "" "Brand logo image delivery (gba-logo-web.png)"

# 7. Banner Image
check_endpoint "/assets/current-banner.jpg" "200" "" "Showroom banner image delivery (current-banner.jpg)"

# 8. Vector Placeholder SVG
check_endpoint "/assets/placeholders/bed-divan.svg" "200" "<svg" "Vector placeholder SVG delivery (bed-divan.svg)"

# 9. Public Release Identity (/release-metadata.json)
check_release_identity

echo "--------------------------------------------------------------------------------"
echo "Smoke Tests Completed: ${PASSED_CHECKS}/${TOTAL_CHECKS} passed, ${FAILED_CHECKS} failed."
echo "--------------------------------------------------------------------------------"

if [ "${FAILED_CHECKS}" -gt 0 ]; then
  echo "ERROR: Smoke verification failed! Aborting release." >&2
  exit 1
fi

echo "All smoke verification checks passed successfully."
