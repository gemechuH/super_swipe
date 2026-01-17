# Phase 0 Research — Personalized Pantry-First Swipe Engine

This document resolves planning unknowns and records key technical decisions for implementing the feature in [specs/001-pantry-first-swipe/spec.md](spec.md).

## Current-State Notes (repo reality)

- Swipe UI currently pages global `recipes` by `energyLevel` and does not use per-user swipe-state.
- A per-user swipe deck persistence layer already exists in `DatabaseService` under `users/{uid}/swipeDeck`.
- AI supports two-stage generation today:
  - Preview batch generation: `AiRecipeService.generateRecipePreviewsBatch(...)`
  - Full recipe generation: `AiRecipeService.generateFullRecipe(...)`
- Firestore rules currently allow `users/{uid}/savedRecipes/*` writes without enforcing a matching carrot decrement (must be tightened to meet the spec + constitution).

## Decisions

### 1) Swipe deck storage

- Decision: Use the existing `users/{uid}/swipeDeck` collection to store lightweight swipe cards.
- Rationale: It already exists in the codebase, and it avoids a migration/parallel system.
- Implementation note: Cards will be `RecipePreview`-shaped plus additional metadata fields (see `data-model.md`).
- Alternatives considered:
  - Per-energy subcollections (e.g., `swipeDeckByEnergy/{energy}/cards/*`) to simplify querying.
    - Rejected (for now): more schema + more reads; current limits (30–60 cards) make client-side filtering cheap.

### 2) Query strategy (avoid composite indexes)

- Decision: Read unconsumed cards by querying only `isConsumed == false` and filter by `energyLevel` client-side.
- Rationale: Existing `DatabaseService.getUnconsumedSwipeCards()` explicitly avoids composite indexes; card counts are small.
- Alternatives considered:
  - `where('energyLevel', isEqualTo: X).where('isConsumed', isEqualTo: false)`.
    - Rejected: will require indexes and adds operational overhead.

### 3) Pantry toggles persistence location

- Decision: Store the two new discovery toggles under the existing user profile document in a nested map:
  - `users/{uid}.preferences.pantryDiscovery.includeBasics` (bool)
  - `users/{uid}.preferences.pantryDiscovery.willingToShop` (bool)
- Rationale: Single document read (already loaded via `userProfileProvider`) and easy invalidation rules.
- Alternatives considered:
  - Separate `users/{uid}/settings/pantryDiscovery` doc.
    - Rejected: extra reads and providers for minimal benefit.

### 4) Cache invalidation mechanism

- Decision: Maintain a single derived signature of discovery inputs and store it on the user doc:

  - `users/{uid}.appState.swipeInputsSignature` (string)
  - `users/{uid}.appState.swipeInputsUpdatedAt` (timestamp)

  The signature should change whenever:

  - Pantry add/remove/edit occurs
  - Either toggle changes

  On Swipe entry, if the locally computed signature differs from the stored signature, the app clears the current swipe deck and regenerates.

- Rationale: Deterministic, observable invalidation without needing background jobs.
- Alternatives considered:
  - “Always regenerate” on every Swipe entry.
    - Rejected: wasteful and increases AI cost.

**Assumed seasonings (canonical)**

- Decision: Use the canonical “Assumed Seasonings” list defined in the feature spec under “Domain Logic”.
- Rule: These items are ignored when calculating the “Minimum 3 Ingredients” gate and when computing the swipe input signature.
- Note: Butter is only considered “assumed” when `includeBasics == true`.

### 5) Energy levels 0–4

- Decision: Treat energy levels as `0..4` for discovery and deck management.
- Rationale: Spec requirement and product clarity.
- Follow-up: Audit any UI/models using `0..3` (e.g., sliders/labels) during implementation, and centralize constants/labels during implementation to satisfy the constitution single-source-of-truth requirement.

### 6) Uniqueness: stable ideaKey + history

- Decision: Compute a deterministic `ideaKey` on-device for each preview (per energy level) and persist history per user+energy.

  Proposed `ideaKey` inputs:

  - energyLevel
  - normalized title
  - normalized, sorted ingredient names

  Proposed storage:

  - `users/{uid}/ideaKeyHistory/{energyLevel}_{ideaKey}` (or nested structure; see `data-model.md`)

- Rationale: “No repeats ever per energy level” requires persistence that can grow unbounded; arrays in a single doc won’t scale.
- Alternatives considered:
  - Store history as a single array on the user document.
    - Rejected: document size limits, write contention.

### 7) Unlock transaction: charge only on successful unlock

- Decision: Generate the full recipe first, then perform a single Firestore transaction that:

  - decrements carrots (free users)
  - writes a spend ledger entry
  - writes the unlocked recipe to `savedRecipes`
  - marks the swipe card consumed

- Rationale: Prevent charging carrots if AI generation fails; still satisfies “atomic decrement + ledger + unlock” requirement.
- Alternatives considered:
  - Deduct carrots first, then generate.
    - Rejected: hard to safely refund without a trusted backend.

### 8) Firestore rules strategy for tamper resistance

- Decision: Tighten rules so a `savedRecipes/{recipeId}` create is only allowed if, in the same transaction:

  - `users/{uid}.carrots.current` decreases by 1 (unless premium)
  - a matching immutable ledger entry exists

- Practical implementation detail:

  - Use deterministic IDs for unlock spend ledger docs (e.g., `transactions/{recipeId}`) and store `unlockTxId` on the saved recipe.
  - This allows security rules to check `existsAfter()` on a known path.

- Alternatives considered:
  - Keep current permissive rules and rely on client honesty.
    - Rejected: violates constitution + spec.

### 9) Weekly carrot reset (external automation compatibility)

- Decision: Weekly carrot resets continue to be performed externally (e.g., GitHub Actions/admin process), not by the client.
- Requirement: The app must react gracefully to external updates of `users/{uid}.carrots.current` (e.g., unlock becomes available immediately after reset without an app restart).

## Additional Best Practices (selected)

- AI cost bounding: cap regeneration attempts per energy refill (e.g., max 2 retries) and fall back to a clear “Couldn’t generate right now” UI.
- Performance: never block swipes on writes; card consume/dislike writes should be best-effort.
- Observability: log counts of preview generation calls and unlock success/failure.

## Outputs Produced Next

- `data-model.md`: Firestore entities, fields, invariants
- `contracts/*`: AI payload shapes + Firestore transaction contract
- `quickstart.md`: local run + manual test checklist
