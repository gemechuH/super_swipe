#!/usr/bin/env bash
set -euo pipefail

# Sets GitHub repo secrets from the workspace .env file.
# Requires: GitHub CLI (gh) installed and authenticated.

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: GitHub CLI (gh) is not installed or not on PATH." >&2
  echo "Install: https://cli.github.com/" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh is not authenticated. Run: gh auth login" >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${repo_root}" ]]; then
  echo "ERROR: Not in a git repository." >&2
  exit 1
fi

env_file="${repo_root}/.env"
if [[ ! -f "${env_file}" ]]; then
  echo "ERROR: .env not found at ${env_file}" >&2
  exit 1
fi

# Prefer WEB_PROJECT_ID, fallback to ANDROID_PROJECT_ID, then IOS_PROJECT_ID.
project_id="$(grep -E '^(WEB_PROJECT_ID|ANDROID_PROJECT_ID|IOS_PROJECT_ID)=' "${env_file}" | head -n 1 | cut -d= -f2- | tr -d '\r' || true)"

if [[ -z "${project_id}" ]]; then
  echo "ERROR: Could not find WEB_PROJECT_ID/ANDROID_PROJECT_ID/IOS_PROJECT_ID in .env" >&2
  exit 1
fi

echo "Setting secret: FIREBASE_PROJECT_ID (value hidden)"
# Use --body to avoid printing.
gh secret set FIREBASE_PROJECT_ID --body "${project_id}"

service_account_path="${1:-}"
if [[ -n "${service_account_path}" ]]; then
  if [[ ! -f "${service_account_path}" ]]; then
    echo "ERROR: Service account JSON file not found: ${service_account_path}" >&2
    exit 1
  fi

  echo "Setting secret: FIREBASE_SERVICE_ACCOUNT_JSON (value hidden)"
  gh secret set FIREBASE_SERVICE_ACCOUNT_JSON < "${service_account_path}"
else
  echo "NOTE: FIREBASE_SERVICE_ACCOUNT_JSON not set (no file provided)."
  echo "To set it, re-run with the downloaded service account JSON path, e.g.:"
  echo "  ./scripts/weekly_carrot_reset/set_github_secrets_from_env.sh path/to/service-account.json"
fi

echo "Done."
