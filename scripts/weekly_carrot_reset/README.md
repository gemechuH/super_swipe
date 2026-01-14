# Weekly Carrot Reset (No Billing)

This folder contains a small admin script used by GitHub Actions to reset weekly carrots for **non-premium** users.

Schedule: **Monday 00:00 UTC** (GitHub Actions cron).

## Required GitHub Secrets

Create these repo secrets:

- `FIREBASE_PROJECT_ID`
- `FIREBASE_SERVICE_ACCOUNT_JSON`
  - Paste the full service account JSON (one-line or multi-line).
  - The service account should have permission to update Firestore (e.g., Firebase Admin SDK).

### Using your local `.env`

This repo already has a `.env` at the workspace root with `WEB_PROJECT_ID` / `ANDROID_PROJECT_ID` / `IOS_PROJECT_ID`.

You can set `FIREBASE_PROJECT_ID` from that file using GitHub CLI:

- Bash: `./scripts/weekly_carrot_reset/set_github_secrets_from_env.sh`
- PowerShell: `./scripts/weekly_carrot_reset/set_github_secrets_from_env.ps1`

These scripts do **not** print secret values.

### Service account JSON

`FIREBASE_SERVICE_ACCOUNT_JSON` cannot be derived from `.env`.

1. In Firebase Console → Project settings → Service accounts → **Generate new private key**
2. Download the JSON file
3. Set the secret:

- Bash: `./scripts/weekly_carrot_reset/set_github_secrets_from_env.sh path/to/service-account.json`
- PowerShell: `./scripts/weekly_carrot_reset/set_github_secrets_from_env.ps1 -ServiceAccountJsonPath path\\to\\service-account.json`

## Local run (optional)

From this folder:

- `npm install`
- `node reset_weekly_carrots.js`

Environment variables:

- `FIREBASE_PROJECT_ID` (required)
- `SERVICE_ACCOUNT_JSON` (required)
- `DRY_RUN` (optional, `true|false`)
- `PAGE_SIZE` (optional, default `200`, max `500`)

Example:

- `DRY_RUN=true node reset_weekly_carrots.js`
