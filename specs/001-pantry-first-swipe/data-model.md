# Phase 1 Design — Data Model

This data model supports the feature in [specs/001-pantry-first-swipe/spec.md](spec.md).

## Entities

### 1) User (`users/{uid}`)

**Existing**: identity, carrots, preferences, appState, stats.

**New/extended fields (this feature)**

- `preferences.pantryDiscovery.includeBasics`: `bool` (default: `true`)
- `preferences.pantryDiscovery.willingToShop`: `bool` (default: `false`)
- `appState.swipeInputsSignature`: `string` (derived; see below)
- `appState.swipeInputsUpdatedAt`: `timestamp`

**Derived values**

- `swipeInputsSignature` = stable hash of:
  - normalized pantry item names (excluding the canonical “Assumed Seasonings” set; see `spec.md` → Domain Logic)
  - `includeBasics`, `willingToShop`
  - prompt/version string (so prompt updates can invalidate caches intentionally)

**Assumed seasonings toggle interaction**

- Butter is considered “assumed” only when `includeBasics == true`.
- Therefore, butter should only be excluded from the gate/signature when `includeBasics == true`.

**Validation rules**

- Users cannot increase `carrots.current` via client writes unless premium (already enforced at the user-doc level; must remain true).

### 2) Pantry Item (`users/{uid}/pantry/{itemId}`)

**Existing**: item name, normalizedName, quantity, unit, etc.

**Invariants**

- Pantry edits (add/remove/update) MUST update `users/{uid}.appState.swipeInputsSignature` and `...swipeInputsUpdatedAt`.

### 3) Swipe Card / Recipe Idea (`users/{uid}/swipeDeck/{cardId}`)

This represents a lightweight “Recipe Idea” card.

**Document ID**

- `cardId`: recommended to equal `recipeId`/`ideaKey` (deterministic), so:
  - duplicates naturally upsert
  - unlock references a stable identifier

**Fields**

- `ideaKey`: `string` (stable, deterministic)
- `energyLevel`: `int` (0–4)
- Preview fields (compatible with `RecipePreview.toFirestore()`):

  - `title`: `string`
  - `vibeDescription`: `string`
  - `ingredients`: `array<string>` (no quantities)
  - `mainIngredients`: `array<string>`
  - `imageUrl`: `string?`
  - `estimatedTimeMinutes`: `int`
  - `calories`: `int`
  - `equipmentIcons`: `array<string>`
  - `mealType`: `string`
  - `cuisine`: `string`
  - `skillLevel`: `string`

- Card state:

  - `isConsumed`: `bool`
  - `isDisliked`: `bool` (optional)
  - `lastSwipeDirection`: `'left' | 'right'` (optional)
  - `lastSwipedAt`: `timestamp` (optional)
  - `consumedAt`: `timestamp` (optional)

- Generation metadata:
  - `inputsSignature`: `string` (copy of `users/{uid}.appState.swipeInputsSignature` at generation time)
  - `promptVersion`: `string`
  - `createdAt`: `timestamp`

**State transitions**

- `new` → `disliked` (left swipe): set `isDisliked=true`, `lastSwipeDirection='left'`, keep `isConsumed=false`.
- `new` → `consumed` (unlock): set `isConsumed=true`, `lastSwipeDirection='right'`, `consumedAt=now`.

### 4) Idea Key History (`users/{uid}/ideaKeyHistory/{historyId}`)

Persists uniqueness across time.

**Document ID**

- `historyId`: `e{energyLevel}_{ideaKey}`

**Fields**

- `ideaKey`: `string`
- `energyLevel`: `int` (0–4)
- `firstSeenAt`: `timestamp`
- Optional denormalization for debugging:
  - `title`: `string`
  - `ingredients`: `array<string>`

**Invariants**

- A given `(uid, energyLevel, ideaKey)` MUST be written at most once (doc ID enforces this).
- Cache invalidation MUST NOT delete this history.

### 5) Saved Recipe / Unlock Result (`users/{uid}/savedRecipes/{recipeId}`)

Unlocked recipes are stored here.

**Document ID**

- `recipeId`: recommended to be the same deterministic ID as the swipe card (`ideaKey`).

**Fields (existing + extended)**

- Public fields (already used in UI): title, description, imageUrl, ingredients, ingredientIds, timeMinutes, calories, equipment, etc.
- Full directions:
  - `instructions`: `array<string>`
- Unlock metadata:
  - `isUnlocked`: `bool` (true)
  - `unlockedAt`: `timestamp`
  - `unlockSource`: `'swipe' | 'directions'`
  - `unlockTxId`: `string` (deterministic; recommended equals `recipeId`)
  - `ideaKey`: `string`
  - `energyLevel`: `int`

### 6) Transaction Ledger (`users/{uid}/transactions/{txId}`)

Immutable auditable ledger entries.

**Unlock transaction ID strategy**

- For unlock spends, use `txId = recipeId` so rules can verify `existsAfter()` on a known path.

**Fields**

- `type`: `'spend' | 'grant' | ...` (unlock uses `'spend'`)
- `amount`: `-1`
- `balanceAfter`: `int`
- `recipeId`: `string`
- `description`: `string`
- `timestamp`: `timestamp`

## Relationships

- User has many Pantry Items.
- User has many Swipe Cards (ideas).
- User has many Saved Recipes (unlocked).
- User has many Transaction entries.
- User has many IdeaKeyHistory entries.

## Security-critical invariants

- Creating a `savedRecipes/{recipeId}` for a free user MUST require:
  - `users/{uid}.carrots.current` decreases by 1 in the same transaction
  - a matching immutable transaction ledger write exists (deterministic ID)

See `contracts/firestore.md` for the required write set and the expected rules checks.
