# Quickstart — Personalized Pantry-First Swipe Engine

This is a developer quickstart for verifying the feature in [specs/001-pantry-first-swipe/spec.md](spec.md).

## Prerequisites

- Flutter SDK installed
- Firebase project configured (existing app setup)
- AI key configured for preview/full recipe generation
  - Ensure `.env` (or whatever the repo uses) contains `GEMINI_API_KEY`

## Run

From the repo root:

- `flutter pub get`
- `flutter run`

## Baseline (pre-implementation)

Captured on 2026-01-16.

- `flutter analyze` → No issues found
- `flutter test` → All tests passed

## Latest automated validation (post-implementation)

Captured on 2026-01-17.

- `flutter analyze` → No issues found
- `flutter test` → All tests passed

## Manual verification checklist

### 1) Pantry gate (>=3 ingredients)

1. Sign in with a test user.
2. Ensure Pantry has 0–2 non-seasoning items.
3. Navigate to Swipe.

Expected:

- An explicit empty state: “Add at least 3 ingredients to start”.
- No deck generation attempt.

Notes:

- “Non-seasoning” excludes the canonical assumed seasonings defined in `spec.md` → Domain Logic.

Result (2026-01-17): PASS.

### 2) Initial deck generation (6 per energy, 5 energies)

1. Add pantry items until you have at least 3 non-seasoning items.
2. Navigate to Swipe.

Expected:

- Each energy level `0..4` has at least 6 cards.
- Total initial generation ~30 previews.
- Swiping feels immediate; no pauses between cards.

Result (2026-01-17): PASS.

### 3) Refill behavior (when 3 remain)

1. Select an energy level.
2. Swipe until exactly 3 cards remain.

Expected:

- A background refill begins and eventually adds 5 more cards for that energy level.
- The user is never blocked from swiping.

Result (2026-01-17): FAIL — when reaching exactly 3 remaining, the remaining 3 disappear and Swipe becomes empty until new cards finish generating.

Update (2026-01-17): Implemented a fix to avoid refreshing the deck mid-swipe and to trigger refills based on the visible remaining count; re-run this checklist step to confirm.

Re-test (2026-01-17): PASS.

### 4) Toggle invalidation

1. Go to Pantry.
2. Toggle Include Basics / Willing to Shop.
3. Return to Swipe.

Expected:

- The deck is regenerated from the new toggle state (no stale cards).
- `ideaKey` history is not cleared; repeats should not appear.

Result (2026-01-17): PASS.

### 5) Unlock flow (carrot spend on success)

1. Ensure user has carrots remaining (free user) or is premium.
2. On Swipe, tap “Show Directions” or swipe right.

Expected:

- Full recipe generation happens.
- If successful: one carrot is spent (free user), recipe appears in cookbook, and the swipe card is removed.
- If generation fails: no carrot is spent.

Optional verification (free user):

- Firestore `users/{uid}.carrots.current` decreases by exactly 1.
- A deterministic ledger entry exists at `users/{uid}/transactions/{recipeId}` with `amount == -1`.
- `users/{uid}/savedRecipes/{recipeId}` exists and includes `unlockTxId == recipeId`.

Already-unlocked behavior:

- Tap “Show Directions” again for an already unlocked recipe.
- Directions open without decrementing carrots again.

Result (2026-01-17): PARTIAL PASS — unlock succeeds, but does not auto-navigate to the recipe details page on success.

Update (2026-01-17): Implemented immediate navigation after carrot spend/reserve and placeholder recipe creation, with shimmer placeholders shown until the full recipe finishes generating and is persisted; re-run this checklist step to confirm.

Re-test (2026-01-17): PASS.

### 6) Economy reset compatibility (GitHub Actions)

1. Ensure a free test user has `carrots.current = 0`.
2. Attempt an unlock (Swipe right / Show Directions).

Expected:

- Unlock is blocked due to insufficient carrots.

3. Simulate a weekly reset by manually editing the user doc in Firestore: set `carrots.current` from 0 → 5.
4. Return to Swipe and attempt an unlock again.

Expected:

- The UI/state reflects the updated carrot balance without requiring an app restart.
- The unlock flow becomes available immediately.

Result (2026-01-17): PASS — unlock became available immediately after 0 → 5 without restart.

## Debug tips

- If Swipe is empty with >=3 pantry items, verify the preview generation call path and Firestore write permissions.
- If carrots can be spent without creating a saved recipe (or vice versa), re-check the transactional write set and the tightened rules described in `contracts/security-rules-notes.md`.
