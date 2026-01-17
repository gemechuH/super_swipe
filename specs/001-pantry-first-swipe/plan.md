# Implementation Plan: Personalized Pantry-First Swipe Engine

**Branch**: `001-pantry-first-swipe` | **Date**: 2026-01-16 | **Spec**: [specs/001-pantry-first-swipe/spec.md](spec.md)
**Input**: Feature specification from [specs/001-pantry-first-swipe/spec.md](spec.md)

## Summary

Replace the current Swipe experience (global `recipes` pool) with a fully personalized, pantry-first swipe deck that:

- Gates discovery until the user has at least 3 non-seasoning pantry items.
- Maintains separate decks for 5 energy levels (0–4), generated as lightweight AI previews.
- Uses 6-3-5 batching: 6 initial ideas per energy level, refill 5 when 3 remain.
- Ensures “no repeats ever per energy level” via a persisted `ideaKey` history.
- Generates full recipes only on unlock (swipe-right / “Show Directions”), charging carrots only after a successful unlock.
- Enforces carrot spend + unlock ledger via Firestore rules + transactional writes.

## Technical Context

**Language/Version**: Dart (Flutter)  
**Primary Dependencies**: Flutter, Riverpod, GoRouter, Firebase Auth, Cloud Firestore  
**AI**: `AiRecipeService` (Gemini) supports preview batching + full recipe generation  
**Storage**: Cloud Firestore (offline cache enabled by Firebase SDK)  
**Testing**: `flutter test` (widget/unit) + `flutter analyze`  
**Target Platform**: iOS + Android  
**Performance Goals**: instant swipes; background-only deck refills; no UI stalls on energy change  
**Constraints**: no paid schedulers; cost-bounded AI calls; tamper-resistant carrot economy

**Relevant existing code**:

- Swipe UI currently reads global recipes: [lib/features/swipe/screens/swipe_screen.dart](../../lib/features/swipe/screens/swipe_screen.dart)
- Per-user swipe deck persistence exists (not wired to Swipe UI yet): [lib/services/database/database_service.dart](../../lib/services/database/database_service.dart)
- AI preview batching + full recipe generation: [lib/services/ai/ai_recipe_service.dart](../../lib/services/ai/ai_recipe_service.dart)
- Firestore rules (currently permissive for `savedRecipes` writes): [firestore.rules](../../firestore.rules)

**Open items (resolved)**:

- Pantry toggles persistence: Persist on the user profile (typed model) and include in the swipe input signature/invalidation flow. See [specs/001-pantry-first-swipe/spec.md](spec.md) and [specs/001-pantry-first-swipe/research.md](research.md).
- Transactional unlock enforcement: Enforce carrot decrement + unlock + ledger as a single atomic write and tighten rules accordingly. See [specs/001-pantry-first-swipe/contracts/firestore.md](contracts/firestore.md) and [specs/001-pantry-first-swipe/contracts/security-rules-notes.md](contracts/security-rules-notes.md).
- Energy levels: Standardize on 5 levels (0–4) per the spec, and centralize constants/labels to avoid UI drift. See [specs/001-pantry-first-swipe/spec.md](spec.md) and [specs/001-pantry-first-swipe/tasks.md](tasks.md).

## Constitution Check

_GATE: Must pass before Phase 0 research. Re-check after Phase 1 design._

- Alignment: Feature matches “Performance Is a Feature” and “Cost-Controlled Personalization” (previews batch, full recipe only on unlock).
- Security: Plan requires tightening [firestore.rules](../../firestore.rules) so `savedRecipes` cannot be written without a matching carrot decrement + ledger entry in the same transaction.
- UX responsiveness: Swipe interactions remain local; refills and unlock generation are async and must not block navigation.
- Testing: Add focused tests for pantry gate + deck generation triggers + unlock charging behavior.

Status: PASS (with mandatory rules changes in Phase 2).

## Project Structure

### Documentation (this feature)

```text
specs/001-pantry-first-swipe/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
└── contracts/
```

### Source Code (expected touch points)

```text
lib/features/pantry/
lib/features/swipe/
lib/core/models/
lib/core/providers/
lib/services/ai/
lib/services/database/
firestore.rules
```

**Structure Decision**: Keep feature logic within existing `pantry` + `swipe` feature modules, using `DatabaseService` + `AiRecipeService` as the integration boundary.

## Complexity Tracking

No constitution violations planned.

## Phases

### Phase 0 — Research (output: research.md)

- Confirm current swipe + unlock flows and identify all global-pool dependencies.
- Decide Firestore schema for:
  - per-user swipe cards (previews)
  - `ideaKey` history per energy level
  - unlock ledger/event documents
- Decide the invalidation mechanism (pantry + toggles) that refreshes decks without clearing `ideaKey` history.
- Decide and document the Firestore rules approach for transactional unlock enforcement.

### Phase 1 — Design & Contracts (outputs: data-model.md, contracts/\*, quickstart.md)

- Define entities, fields, and invariants (including “no repeats per energy level”).
- Define AI payload contracts for preview batch + full recipe generation.
- Define Firestore write contracts/transactions for:
  - initial deck generation and refills
  - consume/dislike card events
  - unlock + carrot spend + ledger
- Provide a quickstart/manual verification flow.

### Phase 2 — Implementation Outline (not executed in /speckit.plan)

- Pantry: add Include Basics + Willing to Shop toggles; increment a cache-buster on pantry/toggle changes.
- Swipe deck: load cards from per-user swipe deck (not global `recipes`), one deck per energy level.
- Generator: initial 6 per energy level, refill 5 when 3 remain, all in background.
- Uniqueness: compute/store `ideaKey`; persist history; never re-issue an `ideaKey` for the same user+energy.
- Unlock: generate full recipe, then transactionally spend carrots + write ledger + save recipe + mark card consumed.
- Rules: tighten `savedRecipes`/unlock writes to require a matching decrement + ledger in the same transaction.
- Tests: pantry gate; generation triggers; refill trigger; unlock charging only on success.

## Constitution Check (Post-Phase-1)

- UX/performance: Deck generation/refill is background-only; swipes remain instant.
- Cost control: Preview batching is the default; full recipes only on unlock.
- Security: `contracts/security-rules-notes.md` specifies required rule tightening (must be implemented + deployed before shipping).
- Testing: Quickstart includes manual verification; Phase 2 requires automated coverage for the core business rules.

Status: PASS for design completeness; implementation must satisfy the security + test gates.
