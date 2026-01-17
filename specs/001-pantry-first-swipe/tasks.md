---
description: "Task list for implementing Personalized Pantry-First Swipe Engine"
---

# Tasks: Personalized Pantry-First Swipe Engine

**Input**: Design documents from [specs/001-pantry-first-swipe/](.)

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prep the repo for feature work (structure, dependencies, baseline signals).

- [x] T001 Capture baseline `flutter analyze` + `flutter test` results in specs/001-pantry-first-swipe/quickstart.md
- [x] T002 [P] Add `crypto` dependency for signature hashing in pubspec.yaml
- [x] T003 [P] Create swipe feature scaffolding in lib/features/swipe/services/pantry_first_swipe_deck_service.dart
- [x] T004 [P] Create swipe feature scaffolding in lib/features/swipe/providers/pantry_first_swipe_deck_provider.dart
- [x] T005 [P] Create swipe feature scaffolding in lib/features/swipe/widgets/recipe_preview_card.dart

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented.

- [x] T006 Add pantry discovery toggle defaults to user creation in lib/core/services/user_service.dart
- [x] T007 [P] Extend user preferences model to include pantry discovery toggles in lib/core/models/user_profile.dart
- [x] T008 [P] Add a typed model for pantry discovery settings in lib/core/models/pantry_discovery_settings.dart
- [x] T009 [P] Add provider(s) to expose pantry discovery settings in lib/core/providers/user_data_providers.dart
- [x] T010 [P] Implement assumed-seasonings helper (for 3-item gate) in lib/core/config/assumed_seasonings.dart
- [x] T011 [P] Implement swipe input signature builder in lib/features/swipe/services/swipe_inputs_signature.dart
- [x] T012 Implement signature update helper in lib/core/services/user_service.dart
- [x] T013 Update pantry CRUD to bump swipe signature on add/update/delete in lib/core/services/pantry_service.dart
- [x] T014 Implement `ideaKey` builder utility in lib/features/swipe/services/idea_key.dart
- [x] T015 Implement deck generation/refill logic (6 initial, refill 5 at 3 remaining) in lib/features/swipe/services/pantry_first_swipe_deck_service.dart
- [x] T016 Implement persistence wiring for `swipeDeck` + `ideaKeyHistory` in lib/services/database/database_service.dart
- [x] T017 Implement a Riverpod deck controller provider in lib/features/swipe/providers/pantry_first_swipe_deck_provider.dart
- [x] T018 [P] Add unit tests for `ideaKey` + signature stability in test/features/swipe/idea_key_test.dart
- [x] T019 [P] Add unit tests for deck batching/refill rules in test/features/swipe/pantry_first_swipe_deck_service_test.dart

**Checkpoint**: Foundational complete; user stories can now be built/tested.

---

## Phase 3: User Story 1 — Pantry Gate Before Discovery (Priority: P1) 🎯 MVP

**Goal**: Show a clear empty state and prevent AI discovery until the user has at least 3 non-seasoning pantry items.

**Independent Test**: With 0–2 pantry items (excluding assumed seasonings), Swipe shows the gate state and does not attempt deck generation.

### Tests

- [x] T020 [P] [US1] Add widget test for pantry gate empty state in test/features/swipe/pantry_gate_widget_test.dart
- [x] T021 [P] [US1] Add unit test for non-seasoning pantry count in test/core/config/assumed_seasonings_test.dart

### Implementation

- [x] T022 [US1] Add pantry gate UI state in lib/features/swipe/screens/swipe_screen.dart
- [x] T023 [US1] Gate deck generation calls behind pantry size check in lib/features/swipe/screens/swipe_screen.dart
- [x] T024 [US1] Ensure guest users are handled explicitly for gate behavior in lib/features/swipe/screens/swipe_screen.dart

**Checkpoint**: US1 passes independently (no AI calls; clear guidance).

---

## Phase 4: User Story 2 — Personalized Swipe Deck by Energy Level (Priority: P1)

**Goal**: Replace global recipe pool swiping with a per-user, per-energy, pantry-first deck of AI previews using the 6-3-5 rule.

**Independent Test**: With 3+ pantry items, Swipe shows previews for each energy level 0–4, swipes are instant, and refill triggers in background.

### Tests

- [x] T025 [P] [US2] Add widget test verifying deck renders previews (not global recipes) in test/features/swipe/swipe_deck_widget_test.dart
- [x] T026 [P] [US2] Add unit test verifying 6 initial previews per energy level in test/features/swipe/pantry_first_swipe_deck_service_test.dart
- [x] T027 [P] [US2] Add unit test verifying refill triggers when 3 remain in test/features/swipe/pantry_first_swipe_deck_service_test.dart

### Implementation

- [x] T028 [US2] Refactor SwipeScreen to use preview deck provider instead of global recipe paging in lib/features/swipe/screens/swipe_screen.dart
- [x] T029 [US2] Implement preview card UI for swipe deck in lib/features/swipe/widgets/recipe_preview_card.dart
- [x] T030 [US2] Update SwipeScreen swipe handlers to consume/dislike preview cards in lib/features/swipe/screens/swipe_screen.dart
- [x] T031 [US2] Ensure energy-level switching uses the per-energy deck (0–4) in lib/features/swipe/screens/swipe_screen.dart
- [x] T032 [US2] Implement background refill invocation (non-blocking) in lib/features/swipe/providers/pantry_first_swipe_deck_provider.dart
- [x] T033 [US2] Remove/stop using global swipe provider that fetches from `recipes` in lib/core/providers/recipe_providers.dart

**Checkpoint**: US2 works without US3/US4; decks populate; swipes stay instant.

---

## Phase 5: User Story 3 — Pantry Toggles Control Results (Priority: P2)

**Goal**: Add Include Basics + Willing to Shop toggles and invalidate swipe decks when toggles/pantry change (without clearing ideaKey history).

**Independent Test**: Changing either toggle or editing pantry updates the input signature; Swipe clears/regenerates the deck and does not repeat prior ideaKeys.

### Tests

- [x] T034 [P] [US3] Add widget test for toggles persistence + UI state in test/features/pantry/pantry_toggles_widget_test.dart
- [x] T035 [P] [US3] Add unit test for signature changing on toggle changes in test/features/swipe/swipe_inputs_signature_test.dart

### Implementation

- [x] T036 [US3] Add Include Basics toggle UI in lib/features/pantry/screens/pantry_screen.dart
- [x] T037 [US3] Add Willing to Shop toggle UI in lib/features/pantry/screens/pantry_screen.dart
- [x] T038 [US3] Persist toggles to Firestore user profile in lib/core/services/user_service.dart
- [x] T039 [US3] Expose toggles via Riverpod so Swipe can read them in lib/core/providers/user_data_providers.dart
- [x] T040 [US3] Apply invalidation on toggle change by updating signature in lib/core/services/user_service.dart
- [x] T041 [US3] Clear + regenerate swipe deck on signature mismatch in lib/features/swipe/services/pantry_first_swipe_deck_service.dart
- [x] T042 [US3] Ensure invalidation does NOT delete ideaKey history in lib/services/database/database_service.dart

**Checkpoint**: US3 toggles visibly affect results and refresh decks without repeats.

---

## Phase 6: User Story 4 — Two-Stage Unlock With Carrot Cost (Priority: P2)

**Goal**: Keep browsing lightweight previews, generate full recipe only on unlock, and charge carrots only after successful unlock with transactional enforcement.

**Independent Test**: Unlocking a card generates a full recipe, saves it, consumes the card, and decrements carrots only on success.

### Tests

- [x] T043 [P] [US4] Add unit test ensuring no carrot spend occurs if AI generation fails in test/features/swipe/unlock_flow_test.dart
- [x] T044 [P] [US4] Add widget test for “Show Directions” unlock flow (happy path) in test/features/swipe/unlock_widget_test.dart

### Implementation

- [x] T045 [US4] Implement unlock orchestration (generate full recipe then transact writes) in lib/features/swipe/services/pantry_first_swipe_deck_service.dart
- [x] T046 [US4] Add DatabaseService method for atomic unlock write set in lib/services/database/database_service.dart
- [x] T047 [US4] Update SwipeScreen right-swipe + “Show Directions” to unlock previews in lib/features/swipe/screens/swipe_screen.dart
- [x] T048 [US4] Ensure unlocked recipes open directions without recharging in lib/features/recipes/screens/recipe_detail_screen.dart
- [x] T049 [US4] Tighten saved recipe + ledger rules as described in specs/001-pantry-first-swipe/contracts/security-rules-notes.md by updating firestore.rules
- [x] T050 [US4] Update quickstart manual steps for unlock validation in specs/001-pantry-first-swipe/quickstart.md

**Checkpoint**: US4 end-to-end unlock works; security rules block client self-unlocks.

---

## Phase 6: Economy & Action Compatibility

**Purpose**: Ensure the new Swipe/unlock flow behaves correctly when carrots are reset externally (GitHub Actions), without requiring an app restart and without weakening security.

- [x] T056 [P] Verify Firestore Security Rules allow the GitHub Action service account to reset carrots while blocking standard users from doing the same in firestore.rules
- [x] T057 [P] Unit Test: Ensure PantryFirstSwipeDeckProvider correctly reacts and refreshes the UI when the carrots field is updated externally by the GitHub Action in test/features/swipe/pantry_first_swipe_deck_provider_test.dart
- [x] T058 [P] Manual Verification: Simulate a GitHub Action reset (manually edit Firestore carrots from 0 to 5) and confirm the "Right Swipe" unlock flow immediately becomes available without a manual app restart (document steps/results in specs/001-pantry-first-swipe/quickstart.md)

- [x] T059 [P] Create lib/core/config/swipe_constants.dart defining an EnergyLevel enum (0–4) and associated labels/metadata. Update all services, the AI prompt generator, and UI filters to use this central enum.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Hardening, cleanup, performance, and documentation.

- [x] T060 [P] Add developer documentation notes for new Firestore fields in SYSTEM_DOCUMENTATION.md
- [x] T061 [P] Add developer documentation notes for swipe deck schema in README.md
- [x] T062 Performance pass: avoid rebuild/jank in swipe deck rendering in lib/features/swipe/screens/swipe_screen.dart
- [x] T063 Add logging for deck generation + unlock failures (no secrets) in lib/features/swipe/services/pantry_first_swipe_deck_service.dart
- [x] T064 Run full validation checklist from specs/001-pantry-first-swipe/quickstart.md

---

## Dependencies & Execution Order

### Phase Dependencies

- Phase 1 (Setup) → Phase 2 (Foundational) → User Stories (Phase 3+)
- Phase 7 (Polish) depends on whichever user stories are in scope.

### User Story Dependency Graph

- US1 (P1) → enables a clean “no pantry” experience.
- US2 (P1) depends on Foundational; uses the gate logic from US1.
- US3 (P2) depends on US2 (needs deck generation to observe invalidation).
- US4 (P2) depends on US2 (needs preview deck + stable IDs).

Recommended completion order: US1 → US2 → (US3 + US4 in parallel).

## Parallel Execution Examples

### US1 parallelizable tasks

- [P] Write gate widget test in test/features/swipe/pantry_gate_widget_test.dart
- [P] Write seasoning-count unit test in test/core/config/assumed_seasonings_test.dart

### US2 parallelizable tasks

- [P] Build preview card widget in lib/features/swipe/widgets/recipe_preview_card.dart
- [P] Write deck service tests in test/features/swipe/pantry_first_swipe_deck_service_test.dart
- [P] Write widget test in test/features/swipe/swipe_deck_widget_test.dart

### US4 parallelizable tasks

- [P] Write unlock unit test in test/features/swipe/unlock_flow_test.dart
- [P] Draft rules update plan in firestore.rules (then implement after code is ready)

## Implementation Strategy

### MVP scope (recommended)

- Implement US1 + US2 only.
- Validate swipe UX + AI cost behavior.

### Incremental delivery

- Add US3 next (toggles + invalidation).
- Add US4 after (unlock + rules hardening).

### Format validation

All tasks above follow the required checklist format:

- `- [ ] T###` task IDs are unique and monotonically increasing (some IDs may be unused after insertions)
- `[P]` only where parallelizable
- `[US#]` labels only on user story tasks
- Every task includes a concrete file path
