# Swipe + Directions Reliability & Product Enhancements — Implementation Plan

**Date:** 2026-01-24  
**Scope owner:** Engineering  
**Primary goal:** Make Swipe reliable (never “stops loading”), make Directions always show correctly after unlock/generation, and implement the new deck rule: **generate 10 AI preview cards per filter combination, then reach end (exhausted)**.

---

## 0) Inputs & Constraints

### Inputs consolidated (client feedback + your findings)

**Client feedback (UX/behavior):**

- Swipe sometimes **stops loading** after a few swipes.
- Directions can **hang/loading forever**.
- Directions can be **generated but not displayed**.
- Swipe UI should **match the Recipes page** more closely (filters, layout parity, etc.).
- Card/title presentation issues (e.g., **title truncation**).
- Navigation parity issue: **Swipe is not in bottom navigation** (hard to find / doesn’t feel like a primary area).
- “Recipe quality mismatch” perception between Swipe vs another page (likely different sources/modes).

**Your explicit product requirements:**

- Deck sizing rule: **For each filter combination**, generate:
  - `maxCards = 10` (total cards for that filter combination)
- When the user reaches the end (all swiped), show a guided message with actions:
  - Add more pantry items
  - Try other energy levels
  - Navigate to recipe generation page

**Observed mismatch vs current repo behavior (important for planning):**

- Pantry-first preview deck currently generates **6 initial** and refills **+5** when `remaining ≤ 3`.
- There is no “10 initial + 10 refill at 5th card” behavior in the current code.

### Hard constraints

- **Do not change auth logic.** (Auth is used widely; this plan only adjusts Swipe, deck generation, UI, and recipe detail data flow.)
- Keep Firestore cost/index requirements reasonable.
- Ensure UX never blocks indefinitely (no infinite spinners).

---

## 1) Current Implementation Snapshot (What’s Happening Today)

### Pantry-first “Swipe Ideas” deck (AI previews)

**Key code paths:**

- Deck generation & refill logic: `PantryFirstSwipeDeckService` in `lib/features/swipe/services/pantry_first_swipe_deck_service.dart`
  - `ensureInitialDeck()` uses `const missing = 6`
  - `maybeTriggerRefill()` triggers when `remaining ≤ 3` and generates `count: 5`
- Deck controller (Riverpod): `PantryFirstSwipeDeckController` in `lib/features/swipe/providers/pantry_first_swipe_deck_provider.dart`
- Persistence: Firestore subcollection `users/{uid}/swipeDeck` via `DatabaseService` in `lib/services/database/database_service.dart`

**Important behaviors:**

- Cards are stored as documents in `users/{uid}/swipeDeck/{ideaKey}`.
- “Left swipe” marks `isDisliked = true` and is filtered out.
- “Right swipe” (unlock) reserves carrots immediately and writes a placeholder saved recipe, then finalizes later.

### Recipe detail screen / directions rendering

**Key code paths:**

- UI: `RecipeDetailScreen` in `lib/features/recipes/screens/recipe_detail_screen.dart`
- Data: `savedRecipeProvider(recipeId)` in `lib/core/providers/recipe_providers.dart`

**High-risk bug:**

- `savedRecipeProvider` returns `Stream.empty()` while `savedRecipesProvider` is loading.
- A `StreamProvider` that never emits can cause **permanent loading**, which matches the “directions load forever” symptom.

### Unlock + generation flow for AI previews

**Key code paths:**

- Reserve unlock (charges carrot for free users immediately): `DatabaseService.reserveSwipePreviewUnlock()`
  - Writes `users/{uid}/savedRecipes/{recipeId}` with `generationStatus: 'pending'` and `instructions: []`
- Finalize (after successful AI generation): `DatabaseService.upsertUnlockedSavedRecipeForSwipePreview()`
  - Updates `savedRecipes/{recipeId}` with full recipe + `generationStatus: 'ready'`

**Implication:**

- If generation fails or the UI never receives the updated saved recipe stream event, users may see no directions.

### Navigation / UI parity

**Key code paths:**

- Swipe route is currently **outside** the bottom-nav `ShellRoute`: `AppRoutes.swipe` is defined as a top-level `GoRoute`.
- Bottom nav (MainWrapper) contains Home/Pantry/Recipes/Settings only: `lib/features/shell/main_wrapper.dart`.

---

## 2) Target Outcomes (Acceptance Criteria)

### A) Swipe deck never “stops loading”

- When user swipes down to low remaining, the deck refills predictably.
- If AI preview generation fails, the UI shows a **recoverable error state** with retry and “Go to Pantry / Change Energy / Generate Recipe” options.
- Deck refill must be **based on remaining cards the user can still see**, not just raw stored card count.

### B) Directions never hang

- Recipe detail must never show a spinner forever.
- If directions are pending generation, the user sees a clear “Generating…” state.
- If generation fails or yields empty instructions, the UI shows “Couldn’t generate directions” + Retry.

### C) New deck cap rule

For every unique filter combination:

- `maxCards = 10`
- Generation stops at 10 total; the deck becomes **exhausted**.
- When exhausted and the user swipes all cards, show a guided message:
  - Add pantry items (link to Pantry)
  - Try other energy levels
  - Go to AI generation (`/ai-generate`)

### D) Swipe UI parity

- Swipe is accessible as a primary destination (bottom nav tab).
- Filters/controls are consistent with the Recipes page (at minimum: energy level; ideally meal type + cuisine + dietary).
- Titles are readable (avoid over-truncation).

---

## 3) Proposed Solution (Best-Practice Approach)

This plan is intentionally split into **Phase 1 (reliability fixes)** and **Phase 2 (10-per-combo deck + UX)** so the most painful bugs are eliminated first.

### Phase 1 — Fix “directions hang” and improve refill reliability (fast, high-impact)

#### 1. Fix the provider that can produce infinite loading

**Change:** Replace the `savedRecipeProvider` implementation so it always emits.

**Recommended implementation:**

- Add a single-document stream in the service layer (best):
  - `RecipeService.watchSavedRecipe(userId, recipeId)` → `Stream<Recipe?>`
- Or query Firestore directly in the provider.

**Why:**

- Returning `Stream.empty()` during loading can cause `StreamProvider` to never transition out of loading.

**Result:**

- Recipe detail screen always gets a value (null/recipe) and can render error/empty/generating states without hanging.

#### 2. Make RecipeDetailScreen generation states explicit

**Change:** Key off `generationStatus` (already written by reserve/finalize).

**UI states (explicit messaging; no silent spinners):**

- `generationStatus == 'pending'` and `instructions.isEmpty` → Show:
  - “Generating directions…”
  - Helper text: “This usually takes ~10–30 seconds. We’ll update automatically.”
  - Skeleton placeholders for steps
  - CTA: “Retry” (after a timeout) and “Back to Swipe”
- `generationStatus == 'ready'` and `instructions.isEmpty` → Show:
  - “Directions aren’t available for this recipe yet.”
  - CTA: “Regenerate directions” (optional future enhancement)
- Consider adding `generationError` on failures so we can display a useful message and enable retry.

#### 3. Improve refill trigger correctness

**Change:** Ensure refill uses the _visible remaining_ after swipe, not just deck length.

Today:

- `_onPreviewSwipeEnd()` computes `remainingAfterSwipe = deck.length - 1`.

Improvements:

- Calculate remaining as: `remaining = (visibleDeck.length - (previousIndex + 1))`.
  - This avoids edge cases where swipe index is not 0-based visible consumption.
- If any refill remains in the implementation, trigger earlier (e.g. `remaining ≤ 5`) to hide latency.

#### 4. Show appropriate message while the AI is generating ideas

**Goal:** Users should never interpret “AI is generating” as “Swipe is broken”.

**Deck-level UX states (pantry-first mode):**

- **Initial load + generating (no cards yet):**
  - Title: “Creating your next ideas…”
  - Body: “We’re generating 10 recipes for this filter combo.”
  - Spinner / skeleton cards
  - Actions: “Change energy”, “Go to Pantry”, “Generate a recipe”
- **Generating failed:**
  - Title: “Couldn’t generate ideas right now”
  - Body: brief error + next steps
  - Actions: Retry, Change energy, Go to Pantry
- **Generating in background (some cards still visible):**
  - Non-blocking banner/snackbar: “Generating…” (only if background generation exists)

---

### Phase 2 — Implement “10 per filter combination” decks + exhaustion UX

#### 1. Define “filter combination” (DeckKey)

We need a deterministic key for “per filter combination”.

**DeckKey should include** (normalized, stable ordering):

- Energy level
- Meal type
- Preferred cuisines
- Dietary restrictions + allergies
- includeBasics
- willingToShop
- Prompt version (so future prompt changes invalidate old decks)
- Pantry signature (already hashed) — but must be the _non-seasoning_ normalized pantry list

**Implementation detail:**

- Extend `buildSwipeInputsSignature()` (currently only pantry + 2 toggles) to include the above.

#### 2. Compute cap

**Rule:** `maxCards = 10`

Notes:

- Keep the existing pantry gate (at least 3 non-seasoning ingredients).
- Deck size is independent of pantry count; pantry influences quality, not quantity.

#### 3. Persist deck state with exhaustion

**Recommended data model (scalable, clear):**

- `users/{uid}/swipeDecks/{deckKey}` (metadata)
  - `deckKey`
  - `energyLevel`
  - `inputsSignature`
  - `maxCards`
  - `generatedCount`
  - `exhausted: bool`
  - `createdAt`, `updatedAt`
- `users/{uid}/swipeDecks/{deckKey}/cards/{cardId}`
  - all `RecipePreview` fields
  - `isConsumed`, `isDisliked`
  - `createdAt`

**Why this is best:**

- Avoids mixing multiple filter decks in one collection and reduces client-side filtering.
- Enables simple queries like: `where(isConsumed == false).limit(…)` inside a single deck.

**Alternative (minimal-change) model:**

- Keep `users/{uid}/swipeDeck` and add `deckKey` field on each card.
- Continue querying only by `isConsumed` and filter client-side to avoid composite indexes.
- This is less clean, but is lower migration effort.

#### 4. Generation algorithm with cap

**Parameters (recommended defaults):**

- `initialBatch = 10` (single-shot generation for the combo)
- `refillBatch = 0` (no additional generation beyond the initial 10)

**Algorithm outline:**

1. Load deck metadata for `deckKey`.
2. If metadata missing → create with `maxCards = 10` and `generatedCount = 0`.
3. Load unconsumed cards for this deck.
4. If deck empty and `generatedCount == 0` → generate 10 previews (best-effort unique).
5. Persist previews, update `generatedCount` to the number of unique previews created.
6. Mark `exhausted = true` once generation completes (successfully or partially), because we do not generate beyond the initial set.

**Important UX implication:**

- If we can’t generate 10 unique cards (model repeats), we still end the deck once attempts are exhausted and show the end-state messaging.

**Uniqueness controls (keep existing logic):**

- Continue using `ideaKey = buildIdeaKey(energyLevel, title, ingredients)`.
- Keep a per-deck “history” to prevent repeats.

#### 5. Exhaustion UX (end-of-deck screen)

When visible deck is empty:

- If `exhausted == true` → show:
  - Title: “You’re reached end of ideas for this combo”
  - Body: “Add more pantry items, try another energy level, or generate a recipe.”
  - Buttons:
    - “Add pantry items” → go to Pantry
    - “Try another energy level” → keep on Swipe and highlight energy slider
    - “Generate a recipe” → go to AI generation (`/ai-generate`)

If `exhausted == false` but deck is empty:

- Show “Creating your ideas…” with retry.

---

## 4) Swipe UI Parity Improvements

### 1. Add Swipe to bottom navigation

**Current issue:** Swipe route is outside `ShellRoute`, and bottom nav has no Swipe tab.

**Plan:**

- Move `AppRoutes.swipe` inside the `ShellRoute` routes.
- Add a new `_NavItem` in `MainWrapper` for “Swipe”.
- Update selected-index logic to include `/swipe`.

### 2. Bring key filters into Swipe

Minimum:

- Keep energy slider (already present).

Recommended parity (incremental):

- Meal type selector
- Cuisine chips
- Dietary restrictions chips
- “Include basics” and “Willing to shop” toggles (already influence generation; ensure they’re visible and discoverable)

Ensure these filters are part of the DeckKey so changing them yields a new deck with its own cap.

Also ensure the empty-state copy aligns with the new rule:

- “You’ve reached the end for this filter combo (10 ideas). Try another energy level or add pantry items.”

### 3. Fix title truncation

Plan:

- Update the card widgets (`RecipePreviewCard` and legacy recipe card) to allow 2 lines, use `TextOverflow.ellipsis`, and ensure layout doesn’t clip on smaller devices.

---

## 5) Verification & Rollout

### Logging / Metrics (cheap but crucial)

Add structured logs around:

- DeckKey + maxCards + generatedCount
- Refill triggers (remaining at trigger)
- Generation attempts and created unique count
- Recipe detail: time-to-first-recipe, time-to-instructions-ready

### Manual QA checklist

- Pantry-first deck:
  - Change any filter combo → verify deck generates up to 10 ideas total.
  - Swipe all cards → see exhaustion message with 3 actions.
  - Change energy level → new deckKey, new cap, new cards.
- Directions:
  - Unlock preview and immediately open directions → see “Generating…” state.
  - Wait for generation → directions appear without leaving the page.
  - Simulate generation failure (disconnect network / force error) → no infinite spinner; show retry.
- Navigation:
  - Swipe appears in bottom nav and preserves shell UI.

### Rollout approach

- Ship Phase 1 fixes first (directions hang + refill correctness).
- Ship Phase 2 deckKey+cap/exhaustion after; it is a larger behavioral change.

---

## 6) Implementation Task Breakdown (Concrete Work Items)

### Phase 1 tasks

1. Replace `savedRecipeProvider` so it never returns `Stream.empty()`.
2. (Optional but recommended) Add a doc-level stream method in `RecipeService`.
3. Update `RecipeDetailScreen` to use `generationStatus` states.
4. Fix remaining-cards computation in `_onPreviewSwipeEnd()`.
5. Adjust refill thresholds (remaining trigger) to hide AI latency.

### Phase 2 tasks

1. Define `DeckKey` + extend `buildSwipeInputsSignature()`.
2. Add deck metadata persistence (new collection or minimal-change alternative).
3. Update persistence queries to load cards scoped to a deckKey.
4. Implement **single-shot generation of 10** and set `exhausted` when generation completes.
5. Implement “AI is generating ideas…” UI states and exhaustion UI with the required actions.
6. Move Swipe route into shell + add Swipe tab.
7. Add/align filter UI controls.

---

## 7) Notes / Risks

- Expanding the signature/deck key will invalidate prior cached decks (good), but ensure refresh/clear logic is robust.
- If using the “new swipeDecks collection” model, Firestore rules must allow per-user access. Keep it consistent with existing `users/{uid}/…` patterns.
- AI generation latency: refill should trigger early enough to avoid user-visible empty states.
