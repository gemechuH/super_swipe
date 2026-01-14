Param(
  [Parameter(Mandatory=$false)]
  [string]$ServiceAccountJsonPath
)

$ErrorActionPreference = 'Stop'

function Require-Command($name) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "Missing required command: $name"
  }
}

Require-Command gh

# Ensure we're in repo root
$repoRoot = (git rev-parse --show-toplevel) 2>$null
if (-not $repoRoot) {
  throw "Not in a git repository."
}

# Ensure gh authenticated
try {
  gh auth status | Out-Null
} catch {
  throw "gh is not authenticated. Run: gh auth login"
}

$envFile = Join-Path $repoRoot '.env'
if (-not (Test-Path $envFile)) {
  throw ".env not found at $envFile"
}

# Prefer WEB_PROJECT_ID, fallback to ANDROID_PROJECT_ID, then IOS_PROJECT_ID.
$lines = Get-Content $envFile
$projectIdLine = $lines | Where-Object { $_ -match '^(WEB_PROJECT_ID|ANDROID_PROJECT_ID|IOS_PROJECT_ID)=' } | Select-Object -First 1
if (-not $projectIdLine) {
  throw "Could not find WEB_PROJECT_ID/ANDROID_PROJECT_ID/IOS_PROJECT_ID in .env"
}

$projectId = ($projectIdLine -split '=', 2)[1].Trim()
if (-not $projectId) {
  throw "Project ID line exists but value is empty."
}

Write-Host "Setting secret: FIREBASE_PROJECT_ID (value hidden)"
# Use --body so value isn't printed.
gh secret set FIREBASE_PROJECT_ID --body "$projectId" | Out-Null

if ($ServiceAccountJsonPath) {
  if (-not (Test-Path $ServiceAccountJsonPath)) {
    throw "Service account JSON file not found: $ServiceAccountJsonPath"
  }

  Write-Host "Setting secret: FIREBASE_SERVICE_ACCOUNT_JSON (value hidden)"
  Get-Content $ServiceAccountJsonPath -Raw | gh secret set FIREBASE_SERVICE_ACCOUNT_JSON | Out-Null
} else {
  Write-Host "NOTE: FIREBASE_SERVICE_ACCOUNT_JSON not set (no file provided)."
  Write-Host "To set it, re-run with the downloaded service account JSON path, e.g.:"
  Write-Host "  ./scripts/weekly_carrot_reset/set_github_secrets_from_env.ps1 -ServiceAccountJsonPath path\\to\\service-account.json"
}

Write-Host "Done."
