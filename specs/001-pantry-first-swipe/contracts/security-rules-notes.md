# Contracts — Security Rules Notes

This feature requires stricter enforcement than the current baseline rules.

## Current gap

- `users/{uid}/savedRecipes/*` currently allows owner read/write without requiring any carrot decrement or ledger entry.
- This violates:
  - spec FR-019a/FR-019b
  - constitution “Client code MUST NOT be able to grant itself value”

## Required rule intent

For non-premium users, creating `savedRecipes/{recipeId}` MUST only be allowed when, in the same transaction:

- `users/{uid}.carrots.current` decreases by exactly 1
- a matching immutable ledger entry is created

## Recommended implementation approach

- Use a deterministic transaction doc ID for unlock spends:
  - `users/{uid}/transactions/{recipeId}`
- Include `unlockTxId = recipeId` on `savedRecipes/{recipeId}`.
- In `savedRecipes` write rules, validate:
  - `isOwner(uid)`
  - `isPremium()` OR
    - `getAfter(/users/{uid}).data.carrots.current == get(/users/{uid}).data.carrots.current - 1`
    - `existsAfter(/users/{uid}/transactions/{recipeId})`
    - `getAfter(...transactions...).data.amount == -1`

This leverages `getAfter()`/`existsAfter()` to confirm that other writes in the same transaction include the decrement + ledger.

## Notes

- This does not provide perfect economic security against all edge cases (e.g., replay attempts), but it materially raises the bar and matches the stated spec approach without requiring paid backend schedulers.

## Weekly carrot reset (GitHub Actions / admin automation)

The weekly reset is performed externally (GitHub Actions or another admin process), not by the client.

Rule implications:

- If the automation uses the Firebase Admin SDK with a service account, Firestore Security Rules are not evaluated for those writes (recommended).
- If the automation uses a rules-enforced client path (not recommended), it MUST authenticate with an identity that is distinguishable from normal users (e.g., custom claims like `admin=true`) so rules can allow carrot resets for that identity while still denying standard users.

Verification requirement:

- Ensure standard users cannot increase `users/{uid}.carrots.current`.
- Ensure the admin automation can reset carrots (either via Admin SDK bypass or an explicit, claim-based allow rule).
