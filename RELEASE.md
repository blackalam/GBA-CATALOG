# GBA Furniture — Release & Deployment Architecture

This document describes the release engineering, automated deployment workflows, security controls, and rollback procedures for the static **GBA Furniture** website.

---

## 1. Architecture & Hosting Topology

- **Site Type:** Zero-dependency static catalogue (HTML5, responsive CSS, vanilla JavaScript, structured JSON).
- **Target Host Document Root:** `/home/alibhatt/web/gbafurniture.com`
- **Sandbox Preview Directory (Outside Docroot):** `/home/alibhatt/sandbox/gbafurniture`
- **Sandbox Recovery Root (Outside Docroot):** `/home/alibhatt/sandbox/.gba-sandbox-recovery`
- **Backup Directory (Outside Docroot):** `/home/alibhatt/backups/gbafurniture`
- **Releases Directory (Outside Docroot):** `/home/alibhatt/releases/gbafurniture`
- **Unified Remote Staging Path:** `/home/alibhatt/.gba-deploy-staging/<release-id>`
- **Shared Host Deployment Lock File:** `/home/alibhatt/.gba-deploy.lock` (with separate atomic metadata `/home/alibhatt/.gba-deploy.lock.meta`)

### Exhaustive Static-Only Allowlist & Safe Packaging
To guarantee zero clutter and prevent server-side code execution in both production and sandbox environments, `scripts/package-artifact.sh`, `scripts/remote-deploy-production.sh`, and `scripts/remote-deploy-sandbox.sh` enforce an **exhaustive static-only allowlist** of 4 directories (`.`, `./data`, `./assets`, `./assets/placeholders`) and 20 files (18 static payload files plus `release-metadata.json` and `checksums.sha256`):
1. `index.html` (Semantic, accessible showroom catalogue referencing `assets/gba-logo-official-transparent.png`, confirmed opening hours, WhatsApp `https://wa.me/442088880322`, Instagram `@gba_furniture`, and TikTok `@gbafurniture`)
2. `styles.css` (Editorial styling, CSS variables, reduced-motion rules)
3. `script.js` (Client-side catalogue rendering and enquiry prefill)
4. `release-metadata.json` (Static non-secret release identity file binding `release_id`, `git_sha`, and `tree_sha256` across the 18 static payload files)
5. `checksums.sha256` (Per-file SHA256 manifest verified on the remote host)
6. `data/products.json` (Catalogue pricing and specifications)
7. `assets/current-banner.jpg`, `assets/gba-logo-official-transparent.png` (official transparent production logo), `assets/gba-logo-web.png` (retained legacy web logo), `assets/gba-logo.png` (retained master logo), and the 10 vector placeholders in `assets/placeholders/*.svg`

All development scripts (`serve.js`, `test-site.js`, `generate-placeholders.js`), documentation (`README.md`, `RELEASE.md`), reference PDFs, intermediate/source logo working files (`gba-logo-official-transparent-original.png`, `gba-logo-official-cropped.jpg`, `gba-logo-replacement-original.jpg`), screenshots, PHP/server-executable files (`*.php*`, `*.phtml`, `*.phar`, `*.cgi`, `*.pl`, `*.py`, `*.sh`, `*.fcgi`, `*.htaccess`, etc.), files containing server-executable code tags (`<?php`, `<?=`, `<script language="php"`, `#!`), executable file modes (`0644` enforced on all files, `0755` on directories), symlinks, and macOS AppleDouble resource forks (`COPYFILE_DISABLE=1`) are strictly rejected at both packaging and deployment time. `scripts/package-artifact.sh` validates `dist/` and ancestor canonical paths before arming cleanup traps, acquires an OS-held nonblocking `flock` on canonical regular lock file `dist/.gba-package.lock` before duplicate checks and holds it through all publication and latest-pointer steps (failing closed if `flock` is unavailable), rejects symlinked `dist` or `dist/staging` and any duplicate/pre-existing tarball, checksum, staging, or release output paths under the lock, stages all outputs in exclusively created (`O_CREAT | O_EXCL`) invocation-owned same-filesystem temporary files in `dist/`, publishes the tarball and checksum via kernel-atomic NO-CLOBBER hardlinks (`os.link` + `os.unlink`), preserves any pre-existing `dist/latest-artifact.txt` if a step fails, and atomically updates `dist/latest-artifact.txt` only after complete success.

---

## 2. Environments, Concurrency & Immutable Checkout

The deployment pipeline mandates two distinct **GitHub Environments**:
1. **`sandbox`**: Used exclusively by `.github/workflows/deploy-sandbox.yml`.
2. **`production`**: Used by `.github/workflows/deploy-production.yml` and `.github/workflows/rollback.yml`.

All remote deployment and rollback workflows (`deploy-sandbox.yml`, `deploy-production.yml`, and `rollback.yml`) share both:
- A GitHub Actions concurrency lock (`group: gba-deployment`, `cancel-in-progress: false`).
- A host-side OS-held lock (`/home/alibhatt/.gba-deploy.lock`) acquired nonblockingly via `flock` on a canonical regular lock file with a stable file descriptor held for the process lifetime and owner metadata written separately and atomically to `/home/alibhatt/.gba-deploy.lock.meta` (failing closed if `flock` is unavailable rather than reclaiming with a race).

| Environment | Branch Guard | Workflow | Trigger | Target Path | Smoke Verification URL |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **CI Testing** | Any branch / PR | `.github/workflows/ci.yml` | `push`, `pull_request` | N/A (Ubuntu Runner) | Ephemeral Local Server |
| **`sandbox`** | `main` | `.github/workflows/deploy-sandbox.yml` | `push` to `main`, `workflow_dispatch` | `/home/alibhatt/sandbox/gbafurniture` | `https://gbafurniture.com/release-preview` |
| **`production`** | `master` strictly | `.github/workflows/deploy-production.yml` | `workflow_dispatch` on `master` (requires `release_id`) | `/home/alibhatt/web/gbafurniture.com` | `https://gbafurniture.com` |
| **`production` (Rollback)** | `master` strictly | `.github/workflows/rollback.yml` | `workflow_dispatch` on `master` (requires `release_id`) | `/home/alibhatt/web/gbafurniture.com` | `https://gbafurniture.com` |

> [!IMPORTANT]
> - Every workflow enforces minimal `permissions: contents: read` and pins all GitHub Actions (`actions/checkout`, `actions/setup-node`) to full 40-character commit SHAs.
> - Every workflow checks out the immutable commit `ref: ${{ github.sha }}` and verifies `git rev-parse --verify HEAD == EXPECTED_SHA` before running tests or packaging artifacts.

---

## 3. GitHub Secrets & Strict SSH Authentication

Dynamic host-key trust (`ssh-keyscan` during workflow execution and `StrictHostKeyChecking=accept-new`) is **strictly forbidden** to prevent Man-in-the-Middle (MITM) attacks. All SSH sessions require a pre-pinned, cryptographic `SSH_KNOWN_HOSTS` secret and `StrictHostKeyChecking=yes`. Every `SSH_OPTS` and `SCP_OPTS` array across `deploy-production.yml`, `rollback.yml`, and `deploy-sandbox.yml` also enforces explicit keepalive options (`-o ServerAliveInterval=30 -o ServerAliveCountMax=60 -o TCPKeepAlive=yes`) alongside `-o BatchMode=yes -o StrictHostKeyChecking=yes` so long-running remote validation, backup, and cutover operations do not drop on idle NAT/firewall state timeouts (`client_loop: send disconnect: Broken pipe`).

Configure the following secrets in **GitHub Repository Settings → Environments** (or repository-level secrets):

| Secret Name | Required | Description | Example / Format |
| :--- | :--- | :--- | :--- |
| `SSH_HOST` | **Yes** | Server hostname or IP address | `203.0.113.10` or `ssh.gbafurniture.com` |
| `SSH_USER` | **Yes** | Authorized UNIX account on server | `alibhatt` (Validated format: `^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$`) |
| `SSH_PORT` | Optional | SSH port (defaults to `22` if omitted) | Integer between `1` and `65535` |
| `SSH_KEY` | **Yes** | Private OpenSSH key (`ed25519` or `rsa`) | `-----BEGIN OPENSSH PRIVATE KEY-----...` |
| `SSH_KNOWN_HOSTS` | **Yes** | Pinned public host keys for `StrictHostKeyChecking=yes` | `[203.0.113.10]:22 ssh-ed25519 AAAAC3NzaC1...` |
| `PRODUCTION_URL` | Optional | Live site URL (defaults to `https://gbafurniture.com`) | Validated against `^https?://[a-zA-Z0-9.-]+(:[0-9]{1,5})?(/[a-zA-Z0-9._/-]*)?$` |
| `PREVIEW_URL` | Optional | Sandbox URL (defaults to `https://gbafurniture.com/release-preview`) | Validated against `^https?://[a-zA-Z0-9.-]+(:[0-9]{1,5})?(/[a-zA-Z0-9._/-]*)?$` |

### Generating `SSH_KNOWN_HOSTS` Locally
Run this once from your trusted local workstation to generate the exact `known_hosts` entry before saving it to GitHub Secrets:
```bash
ssh-keyscan -p <SSH_PORT> -H <SSH_HOST>
```

---

## 4. Production Deployment & Cutover Pipeline

The production deployment (`.github/workflows/deploy-production.yml`) executes an automated, atomic migration from legacy WordPress to the static site:

```
[Trigger on master with Release ID]
               │
               ▼
[1. Checkout Immutable github.sha & Verify HEAD]
               │
               ▼
[2. Verify Test Suite & Package Artifact with Exhaustive Static Allowlist]
               │
               ▼
[3. Secure Remote Staging BEFORE Upload (/home/alibhatt/.gba-deploy-staging/<id>)]
     ├── Validate canonical symlink-free ancestors (/home, /home/alibhatt, staging root)
     ├── Reject any existing stage path & reserve with exclusive mkdir -m 700
     └── Verify realpath equals /home/alibhatt/.gba-deploy-staging/<id>, then SCP
               │
               ▼
[4. Acquire Shared Host OS-Held Lock (/home/alibhatt/.gba-deploy.lock) & Duplicate-ID Guard]
     ├── Complete error-checked symlink scan (find -type l -print with status/output)
     ├── Nonblocking flock on canonical regular file (fd 9) + separate atomic .meta
     └── Reject duplicate RELEASE_ID before any writes
               │
               ▼
[5. Verify Candidate Checksums, Static Allowlist & Bind release-metadata.json]
     ├── Outer archive SHA256 verification (ARTIFACT_SHA256 & .tar.gz.sha256)
     ├── Packaged files checksum verification (checksums.sha256)
     └── Strict JSON binding of release_id, git_sha & tree_sha256 to invocation inputs
               │
               ▼
[6. Validate SQL Identifiers & Dual-Verified Backups Outside Docroot]
     ├── Validate & backtick-quote DB_NAME (^[a-zA-Z0-9_$]{1,64}$)
     ├── WordPress DB dump   -> /home/alibhatt/backups/gbafurniture/<id>_db.sql.gz (gzip -t)
     ├── Docroot tar archive -> /home/alibhatt/backups/gbafurniture/<id>_files.tar.gz (tar -tzf)
     ├── Pre-cutover recovery tree & SHA256 tree digest
     └── Atomic strict JSON manifest -> /home/alibhatt/backups/gbafurniture/<id>_manifest.json
               │
               ▼
[7. Stage Candidate in /home/alibhatt/releases/gbafurniture/<id> & Cutover Docroot]
     └── Trap-driven transaction recovery active through smoke test, DB cleanup & final manifest
               │
               ▼
[8. Public Smoke Test & Public /release-metadata.json Identity Verification]
               │
         ┌─────┴──────────────────────────┐
      [PASS]                           [FAIL / ANY CUTOVER OR DB OR MANIFEST ERROR]
         │                                │
         ▼                                ▼
[9. Destructive DB Cleanup]     [Trap Restore Files (+ DB if DB Deletion Began) & Abort]
    ├── Attempt DROP DATABASE       ├── Restore docroot & verify tree SHA256 digest
    ├── Fallback table-by-table     ├── If DB deletion began, restore DB from verified dump
    └── Positively prove DB         ├── Preserve recovery archives (never delete sole copy)
        absent or 0 tables          └── Atomically update manifest status
               │
               ▼
[10. Atomically Write Final Audit Manifest (Same-Dir Temp + fsync + Strict JSON + Rename)]
```

### Key Safety Controls Enforced:
1. **Pre-Upload Remote Staging Security:** All workflows validate canonical symlink-free ancestors (`/home`, `/home/alibhatt`, `/home/alibhatt/.gba-deploy-staging`), reject any existing release stage path, reserve `/home/alibhatt/.gba-deploy-staging/<release-id>` with exclusive `mkdir -m 700` (never `mkdir -p`), and verify its canonical realpath before uploading any files via `scp`.
2. **Error-Checked Symlink Scanning (No `pipefail` SIGPIPE Fail-Open):** Every directory and staging symlink check runs `find "${dir}" -type l -print` with captured output and exit status rather than `find | grep -q .`, preventing `SIGPIPE` (exit 141) from failing open on large symlink trees under `set -euo pipefail`.
3. **Shared Host-Side OS-Held Lock (`/home/alibhatt/.gba-deploy.lock`):** `remote-deploy-sandbox.sh`, `remote-deploy-production.sh`, and `rollback.sh` acquire a shared nonblocking `flock` lock on a canonical regular lock file held on a stable file descriptor for the process lifetime, with owner metadata written separately and atomically to `/home/alibhatt/.gba-deploy.lock.meta`. Any file-descriptor or `flock` diagnostic suppression is scoped strictly to the individual command/compound block (`{ exec 9...; } 2>/dev/null`), preserving parent shell `stderr` for all subsequent diagnostics. If `flock` is unavailable, scripts fail closed rather than reclaiming locks with a race.
4. **Release Identity Binding & Public Identity Verification:** `release-metadata.json` is bound to invocation `RELEASE_ID`, `GIT_SHA`, `TREE_SHA256`, and `ARTIFACT_SHA256` before deployment. `smoke-test.sh` fetches `${BASE_URL}/release-metadata.json` over HTTP and verifies that the live public endpoint serves the exact deployed release identity and hash.
5. **End-to-End Transaction Recovery Trap, Signal-Specific Nonzero Status & Atomic Manifests:**
   - All deployment and rollback scripts install signal-specific handlers (`TERM` -> `143`, `INT` -> `130`, `HUP` -> `129`) that force nonzero signal-specific exit status (never reusing the prior command's `0`) and funnel through **exactly one** `EXIT` recovery/cleanup handler.
   - In `remote-deploy-sandbox.sh`, the `.gba-sandbox-recovery` root is validated for canonical ancestry and scanned to reject symlinks on the root and all children; each invocation reserves an exclusive directory (`mkdir -m 700`), tracks ownership, and cleans only invocation-owned paths.
   - In `remote-deploy-production.sh`, transaction recovery remains active until **all** database cleanup and final manifest writes succeed (`CUTOVER_VERIFIED` is not set until finalization completes). If database deletion has begun and any later step fails, the trap restores both the original WordPress docroot files and the original WordPress database from verified backups; if `CREATE DATABASE IF NOT EXISTS` is denied, recovery positively queries `INFORMATION_SCHEMA.SCHEMATA` and imports the backup only if `SCHEMA_COUNT == 1` (failing recovery and preserving evidence if `0`, query error, or unexpected count).
   - All manifests are written via a same-directory temporary file, `fsync`ed, validated as strict JSON, and atomically renamed into place — never truncating the only valid manifest in place.
6. **Unsuppressed MySQL Verification:** MySQL cleanup and post-cleanup queries (`INFORMATION_SCHEMA.SCHEMATA`, `INFORMATION_SCHEMA.TABLES`, and `SHOW TABLES`) never suppress errors and positively prove that either `SCHEMA_COUNT == 0` or `TABLE_COUNT == 0`.
7. **SSH & SCP Keepalive Transport Hardening:** Every remote workflow (`deploy-production.yml`, `rollback.yml`, and `deploy-sandbox.yml`) configures `-o ServerAliveInterval=30 -o ServerAliveCountMax=60 -o TCPKeepAlive=yes` on both `SSH_OPTS` and `SCP_OPTS` arrays without weakening `BatchMode=yes` or `StrictHostKeyChecking=yes`.

### Release ID Retry Guidance After an Interrupted Deployment
Because both `deploy-production.yml` and `scripts/remote-deploy-production.sh` enforce strict duplicate-ID rejection before any writes, **the same `release_id` can only be retried after remote read-back verification positively proves that no release, backup, staging, or manifest paths exist** on the remote host:
- `/home/alibhatt/releases/gbafurniture/<release_id>`
- `/home/alibhatt/backups/gbafurniture/<release_id>_files.tar.gz`
- `/home/alibhatt/backups/gbafurniture/<release_id>_db.sql.gz`
- `/home/alibhatt/backups/gbafurniture/<release_id>_manifest.json`
- `/home/alibhatt/backups/gbafurniture/<release_id>_rollback_manifest.json`
- `/home/alibhatt/.gba-deploy-staging/<release_id>`
- `/home/alibhatt/web/gbafurniture.com/release-metadata.json` (confirming cutover did not occur)

If any of these paths exist on the server, do **not** delete backup or manifest evidence to force a retry; follow the rollback/recovery procedure or dispatch with a new unique `release_id`.
- **Verified Pre-Cutover Disconnect (GitHub Actions Run `39387862918`):** During run `39387862918`, the remote deployment validated the artifact and then the SSH connection broke after approximately 4.5 minutes with `client_loop: send disconnect: Broken pipe`. Remote read-back inspection proved that no backups, release directory, staging directory, or docroot `release-metadata.json` remain (cutover did not occur); this failed attempt has been verified clean and can safely be retried after the SSH keepalive fix.

---

## 5. Hardened Rollback Procedures

If an issue occurs after cutover, the site and database can be restored using either GitHub Actions or direct SSH.

`scripts/rollback.sh` enforces the following mandatory checks before reporting success:
- **Strict JSON Manifest Parsing & Binding:** Parses `/home/alibhatt/backups/gbafurniture/<id>_manifest.json` using Python's strict JSON parser with duplicate-key and constant rejection, validating `release_id`, canonical `docroot`, exact `<id>_files.tar.gz` and `<id>_db.sql.gz` paths, boolean `db_required` flag, SHA256 hashes, and database identities before any mutation.
- **Strict Pre-Rollback Schema Count & Pre-Rollback Snapshot/Recovery Tree:** Before creating any snapshot or mutating `DOCROOT` or the database, `rollback.sh` positively queries `INFORMATION_SCHEMA.SCHEMATA` when `db_required` is `true` and requires the output to be strictly `0` or `1` (aborting immediately on query error or any other count). It then creates and verifies an exclusive pre-rollback file snapshot, recovery tree, and (if `PRE_SCHEMA_COUNT == 1`) pre-rollback database snapshot. A single `EXIT` trap (funneling `TERM` 143, `INT` 130, `HUP` 129) covers every partial failure across `rsync`, `chmod`, database restore, file checks, post-rollback health checks, and final manifest publication — automatically restoring the previously live docroot files and pre-rollback database state, and preserving all recovery evidence if restoration fails.
- **Transactional Rollback Finalization & Unsuppressed Manifest Compensation:** Both `<id>_rollback_manifest.json` and the updated `<id>_manifest.json` (`status: "rolled_back"`) are staged in invocation-owned temporary files in the backup directory, `fsync`ed, and validated as strict JSON before publication; if publishing the second file fails after the first, `rollback.sh` compensates `<id>_rollback_manifest.json` and restores the original `<id>_manifest.json` and pre-rollback live state. `compensate_rollback_manifests` never suppresses errors and returns failure if either audit removal/restoration or original manifest restoration fails; cleanup treats any compensation failure as a transaction recovery failure, preserves both original-manifest snapshot files and all recovery evidence, emits explicit diagnostics, and deletes snapshots only after both live-state restoration and manifest compensation have been verified.
- **Mandatory Database Restoration:** Enforces database restoration whenever `db_required` is `true` (and rejects any manifest claiming `db_required: false` if `wp-config.php` or `<id>_db.sql.gz` exists), verifying restored table count `> 0`.
- **Every-Endpoint Fatal-Error & Content Health Verification:** Verifies HTTP `200`, non-empty content, and absence of fatal errors (`Fatal error:`, `Parse error:`, `Uncaught Error`, `Error establishing a database connection`, `500 Internal Server Error`, or raw unexecuted `<?php` tags) across **every** rollback endpoint including both `${VERIFY_URL}` and `${VERIFY_URL}/index.php` (or `${VERIFY_URL}/index.html`).

### Method A: Automated via GitHub Actions
1. Navigate to **GitHub Actions → Rollback Production**.
2. Ensure you are on the `master` branch.
3. Click **Run workflow** and enter the `release_id` to restore.

### Method B: Manual Fallback via SSH
```bash
ssh -p 22 alibhatt@<SSH_HOST>
/home/alibhatt/scripts/rollback.sh <RELEASE_ID> https://gbafurniture.com
```

---

## 6. Local Testing & Verification

The release scaffolding and website can be tested completely locally without requiring production servers or credentials:

```bash
# 1. Validate bash syntax of all release scripts
bash -n scripts/*.sh

# 2. Run catalogue content & DOM verification suite (127 checks)
node test-site.js

# 3. Run release scaffolding test suite (11 test groups including all independent security reproductions)
./scripts/test-deployment-scaffolding.sh
```
