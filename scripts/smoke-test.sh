#!/usr/bin/env bash
# ==============================================================================
# GBA Furniture — Public HTTP Smoke Test Suite
#
# Usage:
#   EXPECTED_METADATA_FILE=<PATH> EXPECTED_ASSET_ROOT=<DIR> \
#     ./scripts/smoke-test.sh <BASE_URL> [CURL_EXTRA_ARGS...]
#
# Mandatory Trusted Bindings (required for all runs; always supplied by deploy scripts):
#   EXPECTED_METADATA_FILE — Canonical symlink-free path to checksum-verified
#                            release-metadata.json (<EXPECTED_ASSET_ROOT>/release-metadata.json)
#   EXPECTED_ASSET_ROOT    — Canonical symlink-free path to checksum-verified
#                            staged/release asset root for authoritative exact
#                            byte-length & SHA256 verification across every
#                            local public endpoint (underlying & versioned)
#
# Optional Release Identity Bindings (enforced when set by deployment scripts):
#   EXPECTED_RELEASE_ID    — Exact release_id required in /release-metadata.json
#   EXPECTED_GIT_SHA       — Exact git_sha required in /release-metadata.json
#   EXPECTED_TREE_SHA256   — Exact tree_sha256 required in /release-metadata.json
#
# Enforces:
#   - Strict URL format validation before making requests.
#   - Mandatory preflight & per-endpoint validation of EXPECTED_METADATA_FILE and
#     EXPECTED_ASSET_ROOT: fails immediately before the first HTTP fetch when either is
#     absent or mismatched, if ANY existing path component/ancestor is a symlink before
#     canonicalization, or if the recursive lstat/find scan of the complete
#     EXPECTED_ASSET_ROOT tree encounters any symlink anywhere (including unreferenced
#     nested files/directories, without following it).
#   - Preflight verification that 'node --check' is available on PATH.
#   - Separate curl exit status capture for every endpoint and /release-metadata.json
#     fetch (never swallowing nonzero exit codes such as incomplete transfer 18
#     or concatenating fallback strings into curl metadata).
#   - HTTP 200 OK for HTML, CSS, JS, JSON, release-metadata.json, SVGs, PNGs, and JPEGs.
#   - Authoritative exact trusted-byte verification (exact byte length, SHA256, and
#     byte equality against the checksum-verified file under EXPECTED_ASSET_ROOT)
#     paired with strict Content-Type media-type checks and defense-in-depth format checks:
#       * HTML: text/html + <!DOCTYPE html>/<html>/<body> structure
#       * CSS:  text/css + string/comment-aware markup rejection (rejecting any generic
#               HTML/XML-like tag token including <div>, closing tags, declarations/
#               processing instructions, and <!-- / --> outside CSS strings and
#               /* ... */ comments while allowing literal markup in strings/comments) +
#               string/comment-aware structural delimiter checks with an ordered
#               parenthesis/bracket stack rejecting crossed nesting such as rgb([)]
#               (accepting valid CSS string/comment values containing literal markup and
#               allowing the last declaration before '}' to omit its optional semicolon)
#       * JS:   application/javascript or text/javascript + HTML rejection + node --check
#       * JSON: application/json + strict JSON parser rejecting duplicate keys & NaN/Infinity
#       * SVG:  image/svg+xml + XML parser requiring root local-name 'svg' and no HTML root
#       * PNG:  image/png + complete chunk structure/CRC32, positive IHDR dimensions,
#               zlib-verified IDAT stream, and terminal IEND
#       * JPEG: image/jpeg + complete marker structure, SOI, valid SOF with positive
#               dimensions, SOS entropy scan, and terminal EOI
#   - Cryptographic & exact identity verification of public /release-metadata.json.
#   - Fails fast with non-zero exit code if any binding, asset, or identity check fails.
# ==============================================================================

set -euo pipefail

export LC_ALL=C

BASE_URL="${1:-}"
if [ -z "${BASE_URL}" ]; then
  echo "Usage: EXPECTED_METADATA_FILE=<PATH> EXPECTED_ASSET_ROOT=<DIR> $0 <BASE_URL> [CURL_ARGS...]" >&2
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

# Require BOTH EXPECTED_METADATA_FILE and EXPECTED_ASSET_ROOT, reject any symlink component/ancestor before canonicalization,
# and recursively scan the complete EXPECTED_ASSET_ROOT tree with lstat/find semantics before the first HTTP fetch
if [ -z "${EXPECTED_METADATA_FILE:-}" ] || [ -z "${EXPECTED_ASSET_ROOT:-}" ]; then
  echo "CRITICAL ERROR: Mandatory trusted asset binding missing: both EXPECTED_METADATA_FILE and EXPECTED_ASSET_ROOT must be set." >&2
  exit 1
fi

BINDING_PREFLIGHT_ERR=""
if ! BINDING_PREFLIGHT_ERR="$(
  python3 - "${EXPECTED_METADATA_FILE}" "${EXPECTED_ASSET_ROOT}" 2>&1 <<'PYEOF'
import os, stat, sys

meta_file_arg = os.fsencode(sys.argv[1]).decode("utf-8", errors="surrogateescape").strip()
asset_root_arg = os.fsencode(sys.argv[2]).decode("utf-8", errors="surrogateescape").strip()

def validate_no_symlink_ancestors(raw_path, label):
    if not raw_path or "\x00" in raw_path:
        raise ValueError(f"{label} is required and must be a non-empty path")
    trimmed = raw_path.rstrip("/") if raw_path != "/" else "/"
    if not trimmed:
        raise ValueError(f"{label} is empty: {raw_path!r}")
    if "//" in trimmed:
        raise ValueError(f"{label} contains empty path segment: {raw_path!r}")
    if trimmed.startswith("/"):
        parts = [p for p in trimmed.split("/") if p]
        cur = ""
    else:
        for cwd_cand in {os.environ.get("PWD") or "", os.getcwd()}:
            if not cwd_cand:
                continue
            c_cur = ""
            for seg in [p for p in cwd_cand.split("/") if p]:
                c_cur = f"{c_cur}/{seg}"
                if os.path.islink(c_cur):
                    raise ValueError(f"{label} ancestor is a symlink: {c_cur!r} (from working directory {cwd_cand!r})")
        base_cwd = (os.environ.get("PWD") or os.getcwd()).rstrip("/")
        parts = [p for p in trimmed.split("/") if p]
        cur = base_cwd

    for seg in parts:
        if seg in (".", ".."):
            raise ValueError(f"{label} contains non-canonical dot segment {seg!r}: {raw_path!r}")
        cur = f"{cur}/{seg}" if cur else f"/{seg}"
        if os.path.islink(cur):
            raise ValueError(f"{label} path component or ancestor is a symlink: {cur!r} (from {raw_path!r})")
        if not os.path.lexists(cur):
            raise ValueError(f"{label} missing path component: {cur!r} (from {raw_path!r})")

    canon = os.path.realpath(cur)
    if canon != cur:
        raise ValueError(f"{label} canonical realpath {canon!r} does not match {cur!r} (symlink ancestor rejected)")
    return canon

def validate_no_nested_symlinks(canon_root):
    root_st = os.lstat(canon_root)
    if stat.S_ISLNK(root_st.st_mode):
        raise ValueError(f"EXPECTED_ASSET_ROOT is a symlink: {canon_root!r}")
    if not stat.S_ISDIR(root_st.st_mode):
        raise ValueError(f"EXPECTED_ASSET_ROOT is not a directory: {canon_root!r}")
    stack = [canon_root]
    while stack:
        cur_dir = stack.pop()
        dir_st = os.lstat(cur_dir)
        if stat.S_ISLNK(dir_st.st_mode):
            rel = os.path.relpath(cur_dir, canon_root).replace(os.sep, "/")
            raise ValueError(
                f"Trusted asset path '{rel}' traverses symlink '{cur_dir}' inside EXPECTED_ASSET_ROOT '{canon_root}'"
            )
        with os.scandir(cur_dir) as it:
            entries = sorted(it, key=lambda e: e.name)
        for entry in entries:
            entry_path = os.path.join(cur_dir, entry.name)
            st = os.lstat(entry_path)
            if stat.S_ISLNK(st.st_mode) or entry.is_symlink():
                rel = os.path.relpath(entry_path, canon_root).replace(os.sep, "/")
                raise ValueError(
                    f"Trusted asset path '{rel}' traverses symlink '{entry_path}' inside EXPECTED_ASSET_ROOT '{canon_root}'"
                )
        for entry in reversed(entries):
            entry_path = os.path.join(cur_dir, entry.name)
            st = os.lstat(entry_path)
            if stat.S_ISDIR(st.st_mode) and not stat.S_ISLNK(st.st_mode):
                stack.append(entry_path)

try:
    if not meta_file_arg or not asset_root_arg:
        raise ValueError(
            "Mandatory trusted asset binding missing: both EXPECTED_METADATA_FILE and EXPECTED_ASSET_ROOT must be set"
        )
    canon_meta = validate_no_symlink_ancestors(meta_file_arg, "EXPECTED_METADATA_FILE")
    if os.path.islink(canon_meta) or not os.path.isfile(canon_meta):
        raise ValueError(f"EXPECTED_METADATA_FILE is not a regular file: {meta_file_arg!r}")
    canon_root = validate_no_symlink_ancestors(asset_root_arg, "EXPECTED_ASSET_ROOT")
    if os.path.islink(canon_root) or not os.path.isdir(canon_root):
        raise ValueError(f"EXPECTED_ASSET_ROOT is not a directory: {asset_root_arg!r}")
    expected_meta = os.path.join(canon_root, "release-metadata.json")
    if canon_meta != expected_meta:
        raise ValueError(
            f"EXPECTED_METADATA_FILE ({canon_meta!r}) and EXPECTED_ASSET_ROOT ({canon_root!r}) mismatch "
            f"(expected {expected_meta!r})"
        )
    validate_no_nested_symlinks(canon_root)
except Exception as exc:
    sys.stderr.write(str(exc))
    sys.exit(1)
PYEOF
)"; then
  echo "CRITICAL ERROR: ${BINDING_PREFLIGHT_ERR}" >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1 || ! printf 'void 0;\n' | node --check >/dev/null 2>&1; then
  echo "CRITICAL ERROR: Required 'node' runtime (with working 'node --check') is unavailable on PATH!" >&2
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
  local asset_kind="${5:-}"

  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  local url="${BASE_URL}${endpoint}"

  if [ -z "${asset_kind}" ]; then
    local clean_path="${endpoint%%#*}"
    clean_path="${clean_path%%\?*}"
    case "${clean_path}" in
      ""|"/"|*.html) asset_kind="html" ;;
      *.css)         asset_kind="css" ;;
      *.js)          asset_kind="js" ;;
      *.json)        asset_kind="json" ;;
      *.svg)         asset_kind="svg" ;;
      *.png)         asset_kind="png" ;;
      *.jpg|*.jpeg)  asset_kind="jpeg" ;;
      *)             asset_kind="unknown" ;;
    esac
  fi

  CURRENT_TMP=$(mktemp)

  local curl_meta=""
  local curl_rc=0
  if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
    curl_meta=$(curl -sSL --max-time 15 -w "%{http_code}\t%{content_type}" "${EXTRA_ARGS[@]}" -o "${CURRENT_TMP}" -- "${url}") || curl_rc=$?
  else
    curl_meta=$(curl -sSL --max-time 15 -w "%{http_code}\t%{content_type}" -o "${CURRENT_TMP}" -- "${url}") || curl_rc=$?
  fi

  if [ "${curl_rc}" -ne 0 ]; then
    echo "  ✗ FAIL: ${desc} -> curl transfer failed (exit ${curl_rc}) at ${url}" >&2
    rm -f "${CURRENT_TMP}"
    CURRENT_TMP=""
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    return 1
  fi

  if [[ "${curl_meta}" != *$'\t'* ]]; then
    echo "  ✗ FAIL: ${desc} -> Malformed curl metadata output at ${url}" >&2
    rm -f "${CURRENT_TMP}"
    CURRENT_TMP=""
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    return 1
  fi

  local http_code="${curl_meta%%$'\t'*}"
  local content_type="${curl_meta#*$'\t'}"

  if [ "${http_code}" != "${expected_status}" ]; then
    echo "  ✗ FAIL: ${desc} -> Expected HTTP ${expected_status}, received ${http_code} at ${url}" >&2
    rm -f "${CURRENT_TMP}"
    CURRENT_TMP=""
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    return 1
  fi

  local validation_err=""
  if ! validation_err="$(
    python3 - \
      "${CURRENT_TMP}" \
      "${asset_kind}" \
      "${content_type}" \
      "${content_check}" \
      "${endpoint}" \
      "${EXPECTED_METADATA_FILE:-}" \
      "${EXPECTED_ASSET_ROOT:-}" 2>&1 <<'PYEOF'
import hashlib, json, os, re, stat, struct, subprocess, sys, xml.etree.ElementTree as ET, zlib

body_path = os.fsencode(sys.argv[1]).decode("utf-8", errors="surrogateescape")
asset_kind = os.fsencode(sys.argv[2]).decode("utf-8", errors="replace").strip().lower()
raw_content_type = os.fsencode(sys.argv[3]).decode("utf-8", errors="replace").strip()
content_check_bytes = os.fsencode(sys.argv[4])
content_check = content_check_bytes.decode("utf-8", errors="replace")
raw_endpoint = os.fsencode(sys.argv[5]).decode("utf-8", errors="surrogateescape")
exp_meta_file = os.fsencode(sys.argv[6]).decode("utf-8", errors="surrogateescape").strip()
exp_asset_root = os.fsencode(sys.argv[7]).decode("utf-8", errors="surrogateescape").strip()

def resolve_local_public_relpath(ep):
    if "\x00" in ep or "\\" in ep:
        raise ValueError(f"Forbidden character in endpoint path {ep!r}")
    clean = ep.split("#", 1)[0].split("?", 1)[0]
    if re.search(r"%(?:2e|2f|5c|00)", clean, re.IGNORECASE):
        raise ValueError(f"Encoded path traversal or separator rejected in endpoint {ep!r}")
    if clean in ("", "/"):
        return "index.html"
    if not clean.startswith("/") or "//" in clean:
        raise ValueError(f"Malformed local public path {ep!r}")
    segments = clean.lstrip("/").split("/")
    if not segments:
        raise ValueError(f"Empty local public path {ep!r}")
    for seg in segments:
        if seg in ("", ".", "..") or not re.match(r"^[a-zA-Z0-9._-]+$", seg):
            raise ValueError(f"Path traversal or unsafe segment {seg!r} rejected in {ep!r}")
    return "/".join(segments)

def validate_no_symlink_ancestors(raw_path, label):
    if not raw_path or "\x00" in raw_path:
        raise ValueError(f"{label} is required and must be a non-empty path")
    trimmed = raw_path.rstrip("/") if raw_path != "/" else "/"
    if not trimmed:
        raise ValueError(f"{label} is empty: {raw_path!r}")
    if "//" in trimmed:
        raise ValueError(f"{label} contains empty path segment: {raw_path!r}")
    if trimmed.startswith("/"):
        parts = [p for p in trimmed.split("/") if p]
        cur = ""
    else:
        for cwd_cand in {os.environ.get("PWD") or "", os.getcwd()}:
            if not cwd_cand:
                continue
            c_cur = ""
            for seg in [p for p in cwd_cand.split("/") if p]:
                c_cur = f"{c_cur}/{seg}"
                if os.path.islink(c_cur):
                    raise ValueError(f"{label} ancestor is a symlink: {c_cur!r} (from working directory {cwd_cand!r})")
        base_cwd = (os.environ.get("PWD") or os.getcwd()).rstrip("/")
        parts = [p for p in trimmed.split("/") if p]
        cur = base_cwd

    for seg in parts:
        if seg in (".", ".."):
            raise ValueError(f"{label} contains non-canonical dot segment {seg!r}: {raw_path!r}")
        cur = f"{cur}/{seg}" if cur else f"/{seg}"
        if os.path.islink(cur):
            raise ValueError(f"{label} path component or ancestor is a symlink: {cur!r} (from {raw_path!r})")
        if not os.path.lexists(cur):
            raise ValueError(f"{label} missing path component: {cur!r} (from {raw_path!r})")

    canon = os.path.realpath(cur)
    if canon != cur:
        raise ValueError(f"{label} canonical realpath {canon!r} does not match {cur!r} (symlink ancestor rejected)")
    return canon

def validate_no_nested_symlinks(canon_root):
    root_st = os.lstat(canon_root)
    if stat.S_ISLNK(root_st.st_mode):
        raise ValueError(f"EXPECTED_ASSET_ROOT is a symlink: {canon_root!r}")
    if not stat.S_ISDIR(root_st.st_mode):
        raise ValueError(f"EXPECTED_ASSET_ROOT is not a directory: {canon_root!r}")
    stack = [canon_root]
    while stack:
        cur_dir = stack.pop()
        dir_st = os.lstat(cur_dir)
        if stat.S_ISLNK(dir_st.st_mode):
            rel = os.path.relpath(cur_dir, canon_root).replace(os.sep, "/")
            raise ValueError(
                f"Trusted asset path '{rel}' traverses symlink '{cur_dir}' inside EXPECTED_ASSET_ROOT '{canon_root}'"
            )
        with os.scandir(cur_dir) as it:
            entries = sorted(it, key=lambda e: e.name)
        for entry in entries:
            entry_path = os.path.join(cur_dir, entry.name)
            st = os.lstat(entry_path)
            if stat.S_ISLNK(st.st_mode) or entry.is_symlink():
                rel = os.path.relpath(entry_path, canon_root).replace(os.sep, "/")
                raise ValueError(
                    f"Trusted asset path '{rel}' traverses symlink '{entry_path}' inside EXPECTED_ASSET_ROOT '{canon_root}'"
                )
        for entry in reversed(entries):
            entry_path = os.path.join(cur_dir, entry.name)
            st = os.lstat(entry_path)
            if stat.S_ISDIR(st.st_mode) and not stat.S_ISLNK(st.st_mode):
                stack.append(entry_path)

def load_trusted_file(rel_path, meta_file_arg, asset_root_arg):
    if not meta_file_arg or not asset_root_arg:
        raise ValueError(
            "Mandatory trusted asset binding missing: both EXPECTED_METADATA_FILE and EXPECTED_ASSET_ROOT must be set"
        )
    canon_meta = validate_no_symlink_ancestors(meta_file_arg, "EXPECTED_METADATA_FILE")
    if os.path.islink(canon_meta) or not os.path.isfile(canon_meta):
        raise ValueError(f"EXPECTED_METADATA_FILE is not a regular file: {meta_file_arg!r}")
    canon_root = validate_no_symlink_ancestors(asset_root_arg, "EXPECTED_ASSET_ROOT")
    if os.path.islink(canon_root) or not os.path.isdir(canon_root):
        raise ValueError(f"EXPECTED_ASSET_ROOT is not a directory: {asset_root_arg!r}")
    expected_meta = os.path.join(canon_root, "release-metadata.json")
    if canon_meta != expected_meta:
        raise ValueError(
            f"EXPECTED_METADATA_FILE ({canon_meta!r}) and EXPECTED_ASSET_ROOT ({canon_root!r}) mismatch "
            f"(expected {expected_meta!r})"
        )
    validate_no_nested_symlinks(canon_root)

    cur = canon_root
    for seg in rel_path.split("/"):
        cur = os.path.join(cur, seg)
        if os.path.islink(cur):
            raise ValueError(f"Trusted asset path '{rel_path}' traverses symlink '{cur}'")
    canon_target = os.path.realpath(cur)
    if os.path.commonpath([canon_root, canon_target]) != canon_root or canon_target == canon_root or canon_target != cur:
        raise ValueError(f"Trusted asset path '{rel_path}' escapes trusted asset root '{canon_root}'")
    if not os.path.isfile(canon_target):
        raise ValueError(f"Trusted on-disk asset missing for '{rel_path}' at '{canon_target}'")
    with open(canon_target, "rb") as tf:
        t_bytes = tf.read()
    return t_bytes, len(t_bytes), hashlib.sha256(t_bytes).hexdigest()

try:
    rel_path = resolve_local_public_relpath(raw_endpoint)
    trusted_bytes, trusted_len, trusted_sha256 = load_trusted_file(rel_path, exp_meta_file, exp_asset_root)
except Exception as exc:
    sys.stderr.write(str(exc))
    sys.exit(1)

with open(body_path, "rb") as f:
    raw_bytes = f.read()

fetched_len = len(raw_bytes)
fetched_sha256 = hashlib.sha256(raw_bytes).hexdigest()

def fail(msg):
    if fetched_len != trusted_len or fetched_sha256 != trusted_sha256:
        msg = (
            f"{msg} [trusted byte mismatch for '{rel_path}': "
            f"expected len={trusted_len} sha256={trusted_sha256}, "
            f"got len={fetched_len} sha256={fetched_sha256}]"
        )
    sys.stderr.write(msg)
    sys.exit(1)

media_type = raw_content_type.split(";", 1)[0].strip().lower()
if not media_type:
    fail("Missing Content-Type header")

if not raw_bytes:
    fail("Empty response body")

def decode_utf8(data, label):
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError as exc:
        fail(f"Invalid UTF-8 in {label} body: {exc}")

def reject_html_document(text, label, forbid_svg_tag=False):
    stripped = text.lstrip("\ufeff \t\r\n")
    lower = stripped.lower()
    if lower.startswith("<"):
        fail(f"{label} body starts with markup '<' (HTML/XML fallback rejected)")
    if re.search(r"<\s*(!doctype\b|html\b|head\b|body\b|\?xml\b)", lower) or "</html" in lower or "</body" in lower:
        fail(f"{label} body contains HTML/XML document tags (fallback rejected)")
    if forbid_svg_tag and re.search(r"<\s*svg\b", lower):
        fail(f"{label} body contains <svg> markup (fallback rejected)")

def validate_css_stylesheet(text):
    non_comment = []
    outside_strings_and_comments = []
    i = 0
    n = len(text)
    brace_depth = 0
    delimiter_stack = []
    in_string = None
    top_level_blocks = 0
    saw_token_since_block_end = False
    saw_any_non_ws = False
    block_stack = []

    while i < n:
        ch = text[i]
        if in_string is not None:
            non_comment.append(ch)
            if ch == "\\":
                if i + 1 >= n:
                    fail("CSS body missing expected stylesheet rule structure (trailing escape in string)")
                if text[i + 1] == "\r" and i + 2 < n and text[i + 2] == "\n":
                    non_comment.append(text[i + 1 : i + 3])
                    i += 3
                else:
                    non_comment.append(text[i + 1])
                    i += 2
                continue
            if ch in ("\n", "\r"):
                fail("CSS body missing expected stylesheet rule structure (unescaped newline in string)")
            if ch == in_string:
                outside_strings_and_comments.append(ch)
                in_string = None
            i += 1
            continue

        if ch == "/" and i + 1 < n and text[i + 1] == "*":
            end = text.find("*/", i + 2)
            if end == -1:
                fail("CSS body missing expected stylesheet rule structure (unclosed /* comment)")
            non_comment.append(" ")
            outside_strings_and_comments.append(" ")
            i = end + 2
            continue

        if ch == "*" and i + 1 < n and text[i + 1] == "/":
            fail("CSS body missing expected stylesheet rule structure (stray */ comment delimiter)")

        if ch in ("'", '"'):
            in_string = ch
            saw_any_non_ws = True
            if brace_depth == 0:
                saw_token_since_block_end = True
            else:
                cb = block_stack[-1]
                cb["cur_seg_has_token"] = True
                if not cb["cur_seg_saw_any_colon"]:
                    cb["cur_seg_has_prop_before_colon"] = True
                elif cb["cur_seg_has_colon"]:
                    cb["cur_seg_has_value_after_colon"] = True
            non_comment.append(ch)
            outside_strings_and_comments.append(ch)
            i += 1
            continue

        if not saw_any_non_ws:
            if ch not in ("\ufeff", " ", "\t", "\r", "\n"):
                if ch == "<":
                    fail("CSS body starts with markup '<' (HTML/XML fallback rejected)")
                saw_any_non_ws = True

        if text.startswith("<!--", i) or text.startswith("-->", i):
            fail("CSS body missing expected stylesheet rule structure (HTML comment delimiters rejected)")

        if ch == "<":
            if re.match(r"<\s*(?:/\s*)?(?:[A-Za-z][A-Za-z0-9:_-]*\b|[!?])", text[i:]):
                fail("CSS body contains HTML/XML markup (fallback rejected)")

        if ch == "{":
            if bool(delimiter_stack):
                fail("CSS body missing expected stylesheet rule structure (unbalanced parentheses/brackets before '{')")
            if brace_depth == 0:
                if not saw_token_since_block_end:
                    fail("CSS body missing expected stylesheet rule structure (missing selector or prelude before '{')")
            else:
                pb = block_stack[-1]
                if not pb["cur_seg_has_token"]:
                    fail("CSS body missing expected stylesheet rule structure (missing selector or prelude before nested '{')")
                pb["has_nested_block"] = True
                pb["cur_seg_has_token"] = False
                pb["cur_seg_saw_any_colon"] = False
                pb["cur_seg_has_prop_before_colon"] = False
                pb["cur_seg_has_colon"] = False
                pb["cur_seg_colon_count"] = 0
                pb["cur_seg_has_value_after_colon"] = False
            block_stack.append({
                "has_nested_block": False,
                "declaration_count": 0,
                "cur_seg_has_token": False,
                "cur_seg_saw_any_colon": False,
                "cur_seg_has_prop_before_colon": False,
                "cur_seg_has_colon": False,
                "cur_seg_colon_count": 0,
                "cur_seg_has_value_after_colon": False,
            })
            brace_depth += 1
        elif ch == "}":
            if bool(delimiter_stack):
                fail("CSS body missing expected stylesheet rule structure (unbalanced parentheses/brackets before '}')")
            brace_depth -= 1
            if brace_depth < 0 or not block_stack:
                fail("CSS body missing expected stylesheet rule structure (unbalanced closing brace '}')")
            cb = block_stack.pop()
            if cb["cur_seg_has_token"]:
                if not (
                    cb["cur_seg_has_prop_before_colon"]
                    and cb["cur_seg_has_colon"]
                    and cb["cur_seg_colon_count"] == 1
                    and cb["cur_seg_has_value_after_colon"]
                ):
                    fail("CSS body missing expected stylesheet rule structure (rule block missing declaration ':' or ';')")
                cb["declaration_count"] += 1
            if cb["declaration_count"] < 1 and not cb["has_nested_block"]:
                fail("CSS body missing expected stylesheet rule structure (rule block missing declaration ':' or ';')")
            if brace_depth == 0:
                top_level_blocks += 1
                saw_token_since_block_end = False
        elif ch == "(":
            delimiter_stack.append(ch)
            if brace_depth == 0:
                saw_token_since_block_end = True
            else:
                cb = block_stack[-1]
                cb["cur_seg_has_token"] = True
                if not cb["cur_seg_saw_any_colon"]:
                    cb["cur_seg_has_prop_before_colon"] = True
                elif cb["cur_seg_has_colon"]:
                    cb["cur_seg_has_value_after_colon"] = True
        elif ch == ")":
            if not delimiter_stack or delimiter_stack[-1] != "(":
                fail("CSS body missing expected stylesheet rule structure (crossed or unbalanced closing parenthesis ')')")
            delimiter_stack.pop()
            if brace_depth == 0:
                saw_token_since_block_end = True
            else:
                cb = block_stack[-1]
                cb["cur_seg_has_token"] = True
                if not cb["cur_seg_saw_any_colon"]:
                    cb["cur_seg_has_prop_before_colon"] = True
                elif cb["cur_seg_has_colon"]:
                    cb["cur_seg_has_value_after_colon"] = True
        elif ch == "[":
            delimiter_stack.append(ch)
            if brace_depth == 0:
                saw_token_since_block_end = True
            else:
                cb = block_stack[-1]
                cb["cur_seg_has_token"] = True
                if not cb["cur_seg_saw_any_colon"]:
                    cb["cur_seg_has_prop_before_colon"] = True
                elif cb["cur_seg_has_colon"]:
                    cb["cur_seg_has_value_after_colon"] = True
        elif ch == "]":
            if not delimiter_stack or delimiter_stack[-1] != "[":
                fail("CSS body missing expected stylesheet rule structure (crossed or unbalanced closing bracket ']')")
            delimiter_stack.pop()
            if brace_depth == 0:
                saw_token_since_block_end = True
            else:
                cb = block_stack[-1]
                cb["cur_seg_has_token"] = True
                if not cb["cur_seg_saw_any_colon"]:
                    cb["cur_seg_has_prop_before_colon"] = True
                elif cb["cur_seg_has_colon"]:
                    cb["cur_seg_has_value_after_colon"] = True
        elif ch == ":" and brace_depth > 0:
            cb = block_stack[-1]
            cb["cur_seg_has_token"] = True
            if not delimiter_stack:
                cb["cur_seg_saw_any_colon"] = True
                cb["cur_seg_colon_count"] += 1
                if cb["cur_seg_has_prop_before_colon"] and cb["cur_seg_colon_count"] == 1:
                    cb["cur_seg_has_colon"] = True
            else:
                if not cb["cur_seg_saw_any_colon"]:
                    cb["cur_seg_has_prop_before_colon"] = True
                elif cb["cur_seg_has_colon"]:
                    cb["cur_seg_has_value_after_colon"] = True
        elif ch == ";":
            if bool(delimiter_stack):
                fail("CSS body missing expected stylesheet rule structure (unbalanced parentheses/brackets before ';')")
            if brace_depth == 0:
                if not saw_token_since_block_end:
                    fail("CSS body missing expected stylesheet rule structure (empty top-level statement before ';')")
                saw_token_since_block_end = False
            else:
                cb = block_stack[-1]
                if not (
                    cb["cur_seg_has_token"]
                    and cb["cur_seg_has_prop_before_colon"]
                    and cb["cur_seg_has_colon"]
                    and cb["cur_seg_colon_count"] == 1
                    and cb["cur_seg_has_value_after_colon"]
                ):
                    fail("CSS body missing expected stylesheet rule structure (rule block missing declaration ':' or ';')")
                cb["declaration_count"] += 1
                cb["cur_seg_has_token"] = False
                cb["cur_seg_saw_any_colon"] = False
                cb["cur_seg_has_prop_before_colon"] = False
                cb["cur_seg_has_colon"] = False
                cb["cur_seg_colon_count"] = 0
                cb["cur_seg_has_value_after_colon"] = False
        elif not ch.isspace():
            if brace_depth == 0:
                saw_token_since_block_end = True
            else:
                cb = block_stack[-1]
                cb["cur_seg_has_token"] = True
                if not cb["cur_seg_saw_any_colon"]:
                    cb["cur_seg_has_prop_before_colon"] = True
                elif cb["cur_seg_has_colon"]:
                    cb["cur_seg_has_value_after_colon"] = True

        non_comment.append(ch)
        outside_strings_and_comments.append(ch)
        i += 1

    if in_string is not None:
        fail("CSS body missing expected stylesheet rule structure (unclosed string literal)")
    if brace_depth != 0:
        fail(f"CSS body missing expected stylesheet rule structure (unbalanced braces, depth={brace_depth})")
    if bool(delimiter_stack):
        fail("CSS body missing expected stylesheet rule structure (unbalanced parentheses/brackets)")

    outside_clean = "".join(outside_strings_and_comments)
    outside_lower = outside_clean.lstrip("\ufeff \t\r\n").lower()
    if outside_lower.startswith("<"):
        fail("CSS body starts with markup '<' (HTML/XML fallback rejected)")
    if "<!--" in outside_lower or "-->" in outside_lower:
        fail("CSS body missing expected stylesheet rule structure (HTML comment delimiters rejected)")
    if re.search(r"<\s*(?:/\s*)?(?:[A-Za-z][A-Za-z0-9:_-]*\b|[!?])", outside_clean):
        fail("CSS body contains HTML/XML markup (fallback rejected)")

    clean = "".join(non_comment)
    stripped_clean = outside_clean.strip()
    if not stripped_clean or top_level_blocks < 1 or saw_token_since_block_end or not stripped_clean.endswith("}"):
        fail("CSS body missing expected stylesheet rule structure (must end with closed rule block '}')")
    if not re.search(r":root\s*\{[^}]*--color-petrol\s*:\s*#[0-9a-fA-F]{3,8}\s*(?:;|\})", outside_clean):
        fail("CSS body missing expected stylesheet rule structure (:root { --color-petrol: ...; })")
    return clean

def validate_png_binary(data):
    png_sig = bytes.fromhex("89504e470d0a1a0a")
    if len(data) < 33 or data[:8] != png_sig:
        fail(f"Invalid PNG binary signature (expected 89504e470d0a1a0a, got {data[:8].hex()})")

    offset = 8
    chunk_index = 0
    saw_ihdr = False
    idat_count = 0
    saw_iend = False
    decompressor = zlib.decompressobj()
    decompressed_len = 0

    while offset < len(data):
        if saw_iend:
            fail("Invalid PNG structure: trailing bytes after terminal IEND chunk")
        if offset + 12 > len(data):
            fail("Invalid PNG structure: truncated chunk header")
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        if not all((0x41 <= b <= 0x5A) or (0x61 <= b <= 0x7A) for b in chunk_type):
            fail(f"Invalid PNG chunk type {chunk_type!r}")
        if offset + 12 + length > len(data):
            fail(f"Invalid PNG structure: truncated chunk data for {chunk_type.decode('ascii', 'replace')}")
        chunk_data = data[offset + 8 : offset + 8 + length]
        expected_crc = struct.unpack(">I", data[offset + 8 + length : offset + 12 + length])[0]
        actual_crc = zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF
        if actual_crc != expected_crc:
            fail(
                f"Invalid PNG chunk CRC for {chunk_type.decode('ascii')}: "
                f"expected {expected_crc:08x}, got {actual_crc:08x}"
            )

        if chunk_index == 0:
            if chunk_type != b"IHDR" or length != 13:
                fail("Invalid PNG structure: first chunk must be 13-byte IHDR")
            width, height, bit_depth, color_type, comp, filt, interlace = struct.unpack(">IIBBBBB", chunk_data)
            if width <= 0 or height <= 0:
                fail(f"Invalid PNG IHDR dimensions: {width}x{height} (must be positive)")
            valid_depths = {
                0: (1, 2, 4, 8, 16),
                2: (8, 16),
                3: (1, 2, 4, 8),
                4: (8, 16),
                6: (8, 16),
            }
            if color_type not in valid_depths or bit_depth not in valid_depths[color_type]:
                fail(f"Invalid PNG IHDR bit_depth={bit_depth} for color_type={color_type}")
            if comp != 0 or filt != 0 or interlace not in (0, 1):
                fail("Invalid PNG IHDR compression/filter/interlace method")
            saw_ihdr = True
        else:
            if chunk_type == b"IHDR":
                fail("Invalid PNG structure: duplicate IHDR chunk")
            elif chunk_type == b"IDAT":
                if length <= 0:
                    fail("Invalid PNG structure: empty IDAT chunk")
                idat_count += 1
                try:
                    out_chunk = decompressor.decompress(chunk_data, 65536)
                    decompressed_len += len(out_chunk)
                    while decompressor.unconsumed_tail:
                        out_chunk = decompressor.decompress(decompressor.unconsumed_tail, 65536)
                        decompressed_len += len(out_chunk)
                except Exception as exc:
                    fail(f"Invalid PNG IDAT compressed stream: {exc}")
            elif chunk_type == b"IEND":
                if length != 0:
                    fail("Invalid PNG structure: non-empty IEND chunk")
                saw_iend = True

        offset += 12 + length
        chunk_index += 1

    if not saw_ihdr or idat_count <= 0 or not saw_iend:
        fail(
            f"Incomplete PNG structure (require IHDR, IDAT, and terminal IEND; "
            f"saw_ihdr={saw_ihdr}, idat_count={idat_count}, saw_iend={saw_iend})"
        )
    try:
        flushed = decompressor.flush()
        decompressed_len += len(flushed)
    except Exception as exc:
        fail(f"Invalid PNG IDAT stream finalization: {exc}")
    if not decompressor.eof or decompressor.unused_data or decompressed_len <= 0:
        fail("Incomplete or corrupted PNG IDAT zlib stream")

def validate_jpeg_binary(data):
    jpeg_soi_prefix = bytes.fromhex("ffd8ff")
    if len(data) < 4 or data[:3] != jpeg_soi_prefix:
        fail(f"Invalid JPEG SOI binary signature (expected ffd8ff, got {data[:3].hex()})")

    sof_markers = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}
    offset = 2
    saw_sof = False
    saw_sos = False
    saw_eoi = False

    while offset < len(data):
        if data[offset] != 0xFF:
            fail(f"Invalid JPEG marker structure at offset {offset} (expected 0xff, got 0x{data[offset]:02x})")
        while offset < len(data) and data[offset] == 0xFF:
            offset += 1
        if offset >= len(data):
            fail("Truncated JPEG marker at end of stream")
        marker = data[offset]
        offset += 1

        if marker == 0x00:
            fail("Invalid JPEG marker 0xff00 outside entropy-coded scan (forged or truncated JPEG)")
        if marker == 0xD8:
            fail("Invalid JPEG structure: duplicate SOI (0xffd8) marker")
        if marker == 0xD9:
            if offset != len(data):
                fail("Invalid JPEG structure: trailing bytes after terminal EOI (0xffd9) marker")
            saw_eoi = True
            break
        if marker == 0x01 or (0xD0 <= marker <= 0xD7):
            continue

        if offset + 2 > len(data):
            fail(f"Truncated JPEG segment length for marker 0xff{marker:02x}")
        seg_len = struct.unpack(">H", data[offset : offset + 2])[0]
        if seg_len < 2 or offset + seg_len > len(data):
            fail(f"Invalid or truncated JPEG segment for marker 0xff{marker:02x} (len={seg_len})")
        seg_data = data[offset + 2 : offset + seg_len]

        if marker in sof_markers:
            if len(seg_data) < 6:
                fail("Truncated JPEG SOF segment")
            precision, height, width, num_comp = struct.unpack(">BHHB", seg_data[:6])
            if precision <= 0 or width <= 0 or height <= 0 or num_comp <= 0:
                fail(f"Invalid JPEG SOF dimensions/components ({width}x{height}, components={num_comp})")
            if len(seg_data) != 6 + 3 * num_comp:
                fail("Malformed JPEG SOF component table length")
            saw_sof = True

        offset += seg_len

        if marker == 0xDA:
            if not saw_sof:
                fail("Invalid JPEG structure: SOS (0xffda) scan encountered before SOF")
            if len(seg_data) < 4:
                fail("Truncated JPEG SOS segment")
            ns = seg_data[0]
            if ns <= 0 or len(seg_data) != 1 + 2 * ns + 3:
                fail("Malformed JPEG SOS component specification")
            scan_start = offset
            found_next_marker = False
            while offset < len(data):
                if data[offset] != 0xFF:
                    offset += 1
                    continue
                while offset < len(data) and data[offset] == 0xFF:
                    offset += 1
                if offset >= len(data):
                    fail("Truncated JPEG entropy scan data before terminal EOI (0xffd9)")
                nxt = data[offset]
                if nxt == 0x00 or (0xD0 <= nxt <= 0xD7):
                    offset += 1
                    continue
                if (offset - 1) <= scan_start:
                    fail("Invalid JPEG structure: empty SOS entropy scan data")
                offset -= 1
                found_next_marker = True
                saw_sos = True
                break
            if not found_next_marker:
                fail("Truncated JPEG SOS scan (missing terminal EOI 0xffd9)")

    if not (saw_sof and saw_sos and saw_eoi and offset == len(data) and data[-2:] == b"\xff\xd9"):
        fail(
            f"Incomplete JPEG structure (require SOI, SOF, SOS scan, and terminal EOI; "
            f"saw_sof={saw_sof}, saw_sos={saw_sos}, saw_eoi={saw_eoi})"
        )

if asset_kind == "html":
    if media_type != "text/html":
        fail(f"Expected Content-Type 'text/html', got '{raw_content_type}'")
    text = decode_utf8(raw_bytes, "HTML")
    stripped_lower = text.lstrip("\ufeff \t\r\n").lower()
    if not (stripped_lower.startswith("<!doctype html") or stripped_lower.startswith("<html")):
        fail("HTML body does not start with <!DOCTYPE html> or <html>")
    if "<html" not in stripped_lower or "</html>" not in stripped_lower or "<body" not in stripped_lower:
        fail("HTML body missing required <html>/<body> document structure")
    if content_check and content_check not in text:
        fail(f"Content verification failed (missing '{content_check}')")

elif asset_kind == "css":
    if media_type != "text/css":
        fail(f"Expected Content-Type 'text/css', got '{raw_content_type}'")
    text = decode_utf8(raw_bytes, "CSS")
    clean_css = validate_css_stylesheet(text)
    if not content_check:
        fail("CSS validation requires a non-empty expected CSS marker")
    if content_check not in clean_css:
        fail(f"CSS content verification failed (missing '{content_check}')")

elif asset_kind == "js":
    if media_type not in ("application/javascript", "text/javascript"):
        fail(
            f"Expected Content-Type 'application/javascript' or 'text/javascript', got '{raw_content_type}'"
        )
    text = decode_utf8(raw_bytes, "JavaScript")
    reject_html_document(text, "JavaScript", forbid_svg_tag=False)
    try:
        js_proc = subprocess.run(
            ["node", "--check"],
            input=raw_bytes,
            capture_output=True,
            timeout=10,
        )
    except Exception as exc:
        fail(f"JavaScript syntax check (node --check) execution failed: {exc}")
    if js_proc.returncode != 0:
        err_text = (js_proc.stderr or js_proc.stdout or b"").decode("utf-8", errors="replace")
        err_lines = [ln.strip() for ln in err_text.splitlines() if ln.strip()]
        detail = err_lines[0] if err_lines else f"exit {js_proc.returncode}"
        fail(
            f"JavaScript body missing expected script structure (node --check syntax check failed: {detail})"
        )
    if not ("CATALOGUE_DATA" in text and "function" in text and "{" in text and "}" in text and ";" in text):
        fail("JavaScript body missing expected script structure (CATALOGUE_DATA / function)")
    if not content_check:
        fail("JavaScript validation requires a non-empty expected JS marker")
    if content_check not in text:
        fail(f"JavaScript content verification failed (missing '{content_check}')")

elif asset_kind == "json":
    if media_type != "application/json":
        fail(f"Expected Content-Type 'application/json', got '{raw_content_type}'")
    text = decode_utf8(raw_bytes, "JSON")
    stripped = text.strip("\ufeff \t\r\n")
    if not (stripped.startswith("{") and stripped.endswith("}")):
        fail("Invalid JSON body: root is not a top-level JSON object")
    def no_dups(pairs):
        obj = {}
        for k, v in pairs:
            if k in obj:
                raise ValueError(f"Duplicate JSON key '{k}'")
            obj[k] = v
        return obj
    def no_constants(val):
        raise ValueError(f"Invalid JSON constant '{val}'")
    try:
        parsed = json.loads(text, object_pairs_hook=no_dups, parse_constant=no_constants)
    except Exception as exc:
        fail(f"Invalid JSON body: {exc}")
    if not isinstance(parsed, dict) or not parsed:
        fail("Invalid JSON body: root must be a non-empty JSON object")
    if not content_check:
        fail("JSON validation requires a non-empty expected JSON marker")
    if content_check not in text:
        fail(f"JSON content verification failed (missing '{content_check}')")

elif asset_kind == "svg":
    if media_type != "image/svg+xml":
        fail(f"Expected Content-Type 'image/svg+xml', got '{raw_content_type}'")
    text = decode_utf8(raw_bytes, "SVG")
    stripped = text.strip("\ufeff \t\r\n")
    lower = stripped.lower()
    if re.search(r"<\s*(!doctype\s+html\b|html\b|head\b|body\b)", lower) or "</html" in lower or "</body" in lower:
        fail("SVG body contains HTML document tags (HTML fallback rejected)")
    try:
        root = ET.fromstring(raw_bytes)
    except Exception as exc:
        if not (lower.startswith("<svg") or lower.startswith("<?xml")) or not lower.endswith("</svg>"):
            fail(f"SVG body must start with <svg (or <?xml) and end with </svg> (XML parse error: {exc})")
        fail(f"Invalid XML in SVG body: {exc}")
    root_tag = root.tag if isinstance(root.tag, str) else ""
    if root_tag.startswith("{"):
        ns_uri, root_local = root_tag[1:].split("}", 1)
    else:
        ns_uri, root_local = "", root_tag
    if root_local.lower() == "html":
        fail("SVG body contains HTML document tags (HTML root rejected)")
    if root_local != "svg" or ns_uri not in ("", "http://www.w3.org/2000/svg"):
        fail(f"Expected XML root local-name 'svg', got '{root_tag}'")
    if not (lower.startswith("<svg") or lower.startswith("<?xml")) or not lower.endswith("</svg>"):
        fail("SVG body must start with <svg (or <?xml) and end with </svg>")
    for elem in root.iter():
        local_name = elem.tag.split("}", 1)[-1].lower() if isinstance(elem.tag, str) else ""
        if local_name in ("html", "body", "head", "script", "iframe", "foreignobject"):
            fail(f"Forbidden element <{local_name}> inside SVG body")
    if content_check and content_check not in text and content_check_bytes not in raw_bytes:
        fail(f"SVG content verification failed (missing '{content_check}')")

elif asset_kind == "png":
    if media_type != "image/png":
        fail(f"Expected Content-Type 'image/png', got '{raw_content_type}'")
    validate_png_binary(raw_bytes)
    if content_check_bytes and content_check_bytes not in raw_bytes:
        fail(f"PNG content verification failed (missing '{content_check}')")

elif asset_kind in ("jpeg", "jpg"):
    if media_type != "image/jpeg":
        fail(f"Expected Content-Type 'image/jpeg', got '{raw_content_type}'")
    validate_jpeg_binary(raw_bytes)
    if content_check_bytes and content_check_bytes not in raw_bytes:
        fail(f"JPEG content verification failed (missing '{content_check}')")

else:
    fail(f"Fail-closed: unsupported or missing asset validation kind '{asset_kind}'")

if fetched_len != trusted_len or fetched_sha256 != trusted_sha256 or raw_bytes != trusted_bytes:
    sys.stderr.write(
        f"Trusted byte verification failed for '{rel_path}': "
        f"expected len={trusted_len} sha256={trusted_sha256}, "
        f"got len={fetched_len} sha256={fetched_sha256}"
    )
    sys.exit(1)
PYEOF
  )"; then
    echo "  ✗ FAIL: ${desc} -> ${validation_err} at ${url}" >&2
    rm -f "${CURRENT_TMP}"
    CURRENT_TMP=""
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    return 1
  fi

  rm -f "${CURRENT_TMP}"
  CURRENT_TMP=""
  echo "  ✓ PASS: ${desc} (HTTP ${http_code}, ${content_type%%;*})"
  PASSED_CHECKS=$((PASSED_CHECKS + 1))
  return 0
}

check_release_identity() {
  local url="${BASE_URL}/release-metadata.json"
  local desc="Public release identity (/release-metadata.json) delivery & binding"
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  CURRENT_TMP=$(mktemp)

  local curl_meta=""
  local curl_rc=0
  if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
    curl_meta=$(curl -sSL --max-time 15 -w "%{http_code}\t%{content_type}" "${EXTRA_ARGS[@]}" -o "${CURRENT_TMP}" -- "${url}") || curl_rc=$?
  else
    curl_meta=$(curl -sSL --max-time 15 -w "%{http_code}\t%{content_type}" -o "${CURRENT_TMP}" -- "${url}") || curl_rc=$?
  fi

  if [ "${curl_rc}" -ne 0 ]; then
    echo "  ✗ FAIL: ${desc} -> curl transfer failed (exit ${curl_rc}) at ${url}" >&2
    rm -f "${CURRENT_TMP}"
    CURRENT_TMP=""
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    return 1
  fi

  if [[ "${curl_meta}" != *$'\t'* ]]; then
    echo "  ✗ FAIL: ${desc} -> Malformed curl metadata output at ${url}" >&2
    rm -f "${CURRENT_TMP}"
    CURRENT_TMP=""
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    return 1
  fi

  local http_code="${curl_meta%%$'\t'*}"
  local content_type="${curl_meta#*$'\t'}"

  if [ "${http_code}" != "200" ]; then
    echo "  ✗ FAIL: ${desc} -> Expected HTTP 200, received ${http_code} at ${url}" >&2
    rm -f "${CURRENT_TMP}"
    CURRENT_TMP=""
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    return 1
  fi

  local identity_err=""
  if ! identity_err="$(
    python3 - \
      "${CURRENT_TMP}" \
      "${EXPECTED_RELEASE_ID:-}" \
      "${EXPECTED_GIT_SHA:-}" \
      "${EXPECTED_TREE_SHA256:-}" \
      "${EXPECTED_METADATA_FILE:-}" \
      "${EXPECTED_ASSET_ROOT:-}" \
      "${content_type}" 2>&1 <<'PYEOF'
import hashlib, json, os, re, stat, sys

fetched_path, exp_rel, exp_sha, exp_tree, exp_meta_file, exp_asset_root, raw_ct = sys.argv[1:8]

def validate_no_symlink_ancestors(raw_path, label):
    if not raw_path or "\x00" in raw_path:
        raise ValueError(f"{label} is required and must be a non-empty path")
    trimmed = raw_path.rstrip("/") if raw_path != "/" else "/"
    if not trimmed:
        raise ValueError(f"{label} is empty: {raw_path!r}")
    if "//" in trimmed:
        raise ValueError(f"{label} contains empty path segment: {raw_path!r}")
    if trimmed.startswith("/"):
        parts = [p for p in trimmed.split("/") if p]
        cur = ""
    else:
        for cwd_cand in {os.environ.get("PWD") or "", os.getcwd()}:
            if not cwd_cand:
                continue
            c_cur = ""
            for seg in [p for p in cwd_cand.split("/") if p]:
                c_cur = f"{c_cur}/{seg}"
                if os.path.islink(c_cur):
                    raise ValueError(f"{label} ancestor is a symlink: {c_cur!r} (from working directory {cwd_cand!r})")
        base_cwd = (os.environ.get("PWD") or os.getcwd()).rstrip("/")
        parts = [p for p in trimmed.split("/") if p]
        cur = base_cwd

    for seg in parts:
        if seg in (".", ".."):
            raise ValueError(f"{label} contains non-canonical dot segment {seg!r}: {raw_path!r}")
        cur = f"{cur}/{seg}" if cur else f"/{seg}"
        if os.path.islink(cur):
            raise ValueError(f"{label} path component or ancestor is a symlink: {cur!r} (from {raw_path!r})")
        if not os.path.lexists(cur):
            raise ValueError(f"{label} missing path component: {cur!r} (from {raw_path!r})")

    canon = os.path.realpath(cur)
    if canon != cur:
        raise ValueError(f"{label} canonical realpath {canon!r} does not match {cur!r} (symlink ancestor rejected)")
    return canon

def validate_no_nested_symlinks(canon_root):
    root_st = os.lstat(canon_root)
    if stat.S_ISLNK(root_st.st_mode):
        raise ValueError(f"EXPECTED_ASSET_ROOT is a symlink: {canon_root!r}")
    if not stat.S_ISDIR(root_st.st_mode):
        raise ValueError(f"EXPECTED_ASSET_ROOT is not a directory: {canon_root!r}")
    stack = [canon_root]
    while stack:
        cur_dir = stack.pop()
        dir_st = os.lstat(cur_dir)
        if stat.S_ISLNK(dir_st.st_mode):
            rel = os.path.relpath(cur_dir, canon_root).replace(os.sep, "/")
            raise ValueError(
                f"Trusted asset path '{rel}' traverses symlink '{cur_dir}' inside EXPECTED_ASSET_ROOT '{canon_root}'"
            )
        with os.scandir(cur_dir) as it:
            entries = sorted(it, key=lambda e: e.name)
        for entry in entries:
            entry_path = os.path.join(cur_dir, entry.name)
            st = os.lstat(entry_path)
            if stat.S_ISLNK(st.st_mode) or entry.is_symlink():
                rel = os.path.relpath(entry_path, canon_root).replace(os.sep, "/")
                raise ValueError(
                    f"Trusted asset path '{rel}' traverses symlink '{entry_path}' inside EXPECTED_ASSET_ROOT '{canon_root}'"
                )
        for entry in reversed(entries):
            entry_path = os.path.join(cur_dir, entry.name)
            st = os.lstat(entry_path)
            if stat.S_ISDIR(st.st_mode) and not stat.S_ISLNK(st.st_mode):
                stack.append(entry_path)

if not exp_meta_file or not exp_asset_root:
    raise ValueError(
        "Mandatory trusted asset binding missing: both EXPECTED_METADATA_FILE and EXPECTED_ASSET_ROOT must be set"
    )
canon_meta = validate_no_symlink_ancestors(exp_meta_file, "EXPECTED_METADATA_FILE")
if os.path.islink(canon_meta) or not os.path.isfile(canon_meta):
    raise ValueError(f"EXPECTED_METADATA_FILE is not a regular file: {exp_meta_file!r}")
canon_root = validate_no_symlink_ancestors(exp_asset_root, "EXPECTED_ASSET_ROOT")
if os.path.islink(canon_root) or not os.path.isdir(canon_root):
    raise ValueError(f"EXPECTED_ASSET_ROOT is not a directory: {exp_asset_root!r}")
expected_meta_path = os.path.join(canon_root, "release-metadata.json")
if canon_meta != expected_meta_path:
    raise ValueError(
        f"EXPECTED_METADATA_FILE ({canon_meta!r}) and EXPECTED_ASSET_ROOT ({canon_root!r}) mismatch "
        f"(expected {expected_meta_path!r})"
    )
validate_no_nested_symlinks(canon_root)

media_type = raw_ct.split(";", 1)[0].strip().lower()
if media_type != "application/json":
    raise ValueError(f"Expected Content-Type 'application/json' for /release-metadata.json, got {raw_ct!r}")

def no_dups(pairs):
    obj = {}
    for k, v in pairs:
        if k in obj:
            raise ValueError(f"Duplicate key '{k}' in release-metadata.json")
        obj[k] = v
    return obj

def no_constants(val):
    raise ValueError(f"Invalid JSON constant '{val}' in release-metadata.json")

with open(fetched_path, "rb") as f:
    fetched_bytes = f.read()

fetched_len = len(fetched_bytes)
fetched_hash = hashlib.sha256(fetched_bytes).hexdigest()
text = fetched_bytes.decode("utf-8")
stripped = text.strip("\ufeff \t\r\n")
if not (stripped.startswith("{") and stripped.endswith("}")):
    raise ValueError("release-metadata.json root must be a top-level JSON object")

meta = json.loads(text, object_pairs_hook=no_dups, parse_constant=no_constants)
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

with open(canon_meta, "rb") as ef:
    exp_bytes = ef.read()
exp_len = len(exp_bytes)
exp_hash = hashlib.sha256(exp_bytes).hexdigest()
exp_meta = json.loads(exp_bytes.decode("utf-8"), object_pairs_hook=no_dups, parse_constant=no_constants)
if fetched_len != exp_len or fetched_hash != exp_hash or fetched_bytes != exp_bytes or meta != exp_meta:
    raise ValueError(
        f"Public /release-metadata.json byte/hash/content mismatch against deployed candidate "
        f"(expected len={exp_len} sha256={exp_hash}, fetched len={fetched_len} sha256={fetched_hash})"
    )
PYEOF
  )"; then
    echo "  ✗ FAIL: ${desc} -> Public release identity verification failed (${identity_err}) at ${url}" >&2
    rm -f "${CURRENT_TMP}"
    CURRENT_TMP=""
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    return 1
  fi

  rm -f "${CURRENT_TMP}"
  CURRENT_TMP=""
  echo "  ✓ PASS: ${desc} (HTTP ${http_code}, ${content_type%%;*})"
  PASSED_CHECKS=$((PASSED_CHECKS + 1))
  return 0
}

# 1. Homepage index check
check_endpoint "" "200" "GBA Furniture" "Homepage index.html delivery & title" "html"

# 2. Key contact facts & cache-busted asset references on homepage
check_endpoint "/index.html" "200" "020 8888 0322" "Contact telephone on index.html" "html"
check_endpoint "/index.html" "200" "401 Lordship Lane" "Showroom address on index.html" "html"
check_endpoint "/index.html" "200" "styles.css?v=public-audit-20261020" "Cache-busted stylesheet reference on index.html" "html"
check_endpoint "/index.html" "200" "script.js?v=public-audit-20261020" "Cache-busted script reference on index.html" "html"

# 3. Core Stylesheet (underlying file & cache-busted URL)
check_endpoint "/styles.css" "200" "--color-petrol" "Stylesheet CSS delivery & brand root variables" "css"
check_endpoint "/styles.css?v=public-audit-20261020" "200" "--color-petrol" "Cache-busted stylesheet CSS delivery (styles.css?v=public-audit-20261020)" "css"

# 4. Core JavaScript (underlying file & cache-busted URL)
check_endpoint "/script.js" "200" "products" "Client catalogue JavaScript delivery" "js"
check_endpoint "/script.js?v=public-audit-20261020" "200" "v=public-audit-20261020" "Cache-busted client catalogue JavaScript delivery (script.js?v=public-audit-20261020)" "js"

# 5. Products Catalogue Data
check_endpoint "/data/products.json" "200" "beds-mattresses" "Catalog JSON data delivery & category check" "json"
check_endpoint "/data/products.json" "200" "v=public-audit-20261020" "Catalog JSON cache-busted placeholder SVG references" "json"

# 6. Official Transparent Brand Logo & Legacy Web Logo
check_endpoint "/assets/gba-logo-official-transparent.png" "200" "" "Official transparent brand logo delivery (gba-logo-official-transparent.png)" "png"
check_endpoint "/assets/gba-logo-web.png" "200" "" "Brand logo image delivery (gba-logo-web.png)" "png"

# 7. Banner Image
check_endpoint "/assets/current-banner.jpg" "200" "" "Showroom banner image delivery (current-banner.jpg)" "jpeg"

# 8. Vector Placeholder SVGs (all 10 underlying files & all 10 cache-busted URLs)
for svg_name in appliance bed-divan bed-frame bunk chest coffee-table dining-table sofa wardrobe; do
  check_endpoint "/assets/placeholders/${svg_name}.svg" "200" "Illustration only — not a product photograph" "Vector placeholder SVG delivery (${svg_name}.svg)" "svg"
  check_endpoint "/assets/placeholders/${svg_name}.svg?v=public-audit-20261020" "200" "Illustration only — not a product photograph" "Cache-busted placeholder SVG delivery (${svg_name}.svg?v=public-audit-20261020)" "svg"
done
check_endpoint "/assets/placeholders/van.svg" "200" "Furniture removal service" "Vector placeholder SVG delivery (van.svg)" "svg"
check_endpoint "/assets/placeholders/van.svg?v=public-audit-20261020" "200" "Furniture removal service" "Cache-busted placeholder SVG delivery (van.svg?v=public-audit-20261020)" "svg"

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
