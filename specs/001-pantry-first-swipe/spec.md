# Feature Specification: Personalized Pantry-First Swipe Engine

**Feature Branch**: `001-pantry-first-swipe`  
**Created**: 2026-01-16  
**Status**: Draft  
**Input**: Replace the "Shared Community Pool" swipe logic with a personalized, pantry-first discovery engine with a 3-ingredient minimum, Pantry toggles, two-stage generation, and the 6-3-5 batching/refill rule.

## Clarifications

### Session 2026-01-16

- Q: How many energy levels exist for deck generation? → A: 5 energy levels (0–4)
- Q: When should swipe discovery cache invalidate? → A: On toggles change or any pantry add/remove/edit
- Q: How is uniqueness enforced within an energy level? → A: Stable `ideaKey` stored per user+energy level
- Q: What is the “server-side validation” mechanism for unlock/carrot spend? → A: Firestore Security Rules + transactional writes (decrement + ledger + unlock)
- Q: Should `ideaKey` history persist across cache invalidations? → A: Yes — keep history (no repeats ever per energy level)

## User Scenarios & Testing _(mandatory)_

### User Story 1 - Pantry Gate Before Discovery (Priority: P1)

As a user, I need clear guidance when my pantry is too small so I'm not shown random content or empty swipe cards.

**Why this priority**: This prevents wasted AI calls and avoids a broken first impression.

**Independent Test**: Can be tested by creating a user with 0-2 pantry ingredients and verifying that no personalized swipe deck is generated and the UI provides a clear next step.

**Acceptance Scenarios**:

1. **Given** a user has fewer than 3 pantry ingredients, **When** they open the Swipe screen, **Then** they see an explicit "Add at least 3 ingredients to start" state and the system does not initiate any recipe discovery requests.
2. **Given** a user has fewer than 3 pantry ingredients, **When** they add ingredients until they reach 3, **Then** the next Swipe screen visit starts personalized discovery.

---

### User Story 2 - Personalized Swipe Deck by Energy Level (Priority: P1)

As a user, I want swipe cards that feel made for me based on my pantry, dietary preferences, and toggles.

**Why this priority**: This is the core product promise: discovery should feel magical and relevant.

**Independent Test**: Can be tested by setting a pantry and preferences, then verifying that the initial deck is populated for each energy level with lightweight ideas and that swiping never blocks.

**Acceptance Scenarios**:

1. **Given** a user has at least 3 pantry ingredients, **When** they first open Swipe, **Then** the system generates 6 lightweight Recipe Ideas for each of 5 energy levels (0–4).
2. **Given** the user swipes through cards, **When** they swipe left or right, **Then** the next card appears immediately without waiting on background generation.
3. **Given** the user changes energy level, **When** they view that level's deck, **Then** it is curated for that level and does not depend on a shared community pool.

---

### User Story 3 - Pantry Toggles Control Results (Priority: P2)

As a user, I want control over whether ideas assume basics and whether suggestions may include items I need to shop for.

**Why this priority**: These toggles change the meaning of personalized and must reliably update results.

**Independent Test**: Can be tested by toggling values on the Pantry screen and confirming that the swipe deck refreshes and differs appropriately.

**Acceptance Scenarios**:

1. **Given** the user is on the Pantry screen, **When** they change Include Basics or Willing to Shop, **Then** the existing swipe cache is invalidated and the next deck generation uses the new settings.
2. **Given** the toggles have changed, **When** the user returns to Swipe, **Then** they are not shown stale cards generated under the previous toggle values.
3. **Given** the user adds, removes, or edits a pantry ingredient, **When** they return to Swipe, **Then** the existing swipe cache is invalidated and discovery results reflect the updated pantry.

---

### User Story 4 - Two-Stage Unlock With Carrot Cost (Priority: P2)

As a user, I want quick browsing via lightweight ideas, and only pay carrots (and wait) when I choose to unlock full cooking directions.

**Why this priority**: This controls cost while preserving a premium-feeling flow.

**Independent Test**: Can be tested by generating an idea deck, then unlocking an idea and verifying full recipe availability and correct carrot deduction.

**Acceptance Scenarios**:

1. **Given** a swipe card is a lightweight idea, **When** the user swipes right, **Then** the system triggers full recipe generation and applies the carrot cost only upon successful unlock.
2. **Given** a swipe card is a lightweight idea, **When** the user taps Show Directions, **Then** the system triggers full recipe generation and applies the carrot cost only upon successful unlock.
3. **Given** the user has already unlocked that recipe, **When** they open directions again, **Then** directions open without an additional carrot charge.

### Edge Cases

1. **Discovery outage / AI failure**

   - **Given** a user has ≥3 non-seasoning pantry items, **When** initial deck generation fails due to a transient error, **Then** Swipe shows a clear retryable empty/error state and does not show partial/blank cards.
   - **Given** deck generation is failing, **When** the user retries, **Then** the app re-attempts generation with bounded retries and does not block navigation.

2. **Insufficient carrots at unlock**

   - **Given** a free user has 0 carrots, **When** they swipe right or tap Show Directions, **Then** unlock is blocked with an explicit “Not enough carrots” state and no unlock transaction runs.

3. **Toggles change during background refill**

   - **Given** a background refill is in progress, **When** the user changes Include Basics or Willing to Shop, **Then** any refill results generated under the previous `inputsSignature` are discarded/ignored and the deck regenerates using the new signature without clearing `ideaKey` history.

4. **Only seasonings present**

   - **Given** a user’s pantry contains only items from the Canonical Seasoning Set, **When** they open Swipe, **Then** they are treated as having 0 non-seasoning items and see the pantry gate UI (no discovery requests).

5. **Refill finishes after deck exhaustion**
   - **Given** a user reaches 0 remaining cards for an energy level, **When** a pending refill completes, **Then** cards appear as soon as the write completes and Swipe recovers without requiring an app restart; **If** the refill fails, show a retryable empty/error state for that energy level.

### Performance, Cost, and Security Notes _(mandatory)_

- **Performance**: Swipes must be immediate; any deck refills occur in the background without interrupting interaction.
- **AI Cost Control**: Generate lightweight ideas in batches; generate full recipes only on unlock (swipe-right or Show Directions).
- **Security/Data Integrity**: Carrot deduction and unlock must be validated in a trusted environment; users cannot grant themselves carrots.

## Domain Logic

### Canonical Seasoning Set (Assumed Available)

**Canonical Seasoning Set (Assumed Available):**

- **Basic Salts**: Table Salt, Sea Salt.
- **Basic Peppers**: Black Pepper, White Pepper.
- **Basic Oils**: Olive Oil, Vegetable/Canola Oil, Butter (if "Basics" toggle is ON).
- **Pantry Spices**: Garlic Powder, Onion Powder, Dried Oregano, Red Pepper Flakes.

**Logic Rule**: These items are ignored when calculating the "Minimum 3 Ingredients" gate.

## Requirements _(mandatory)_

### Functional Requirements

- **FR-001**: The system MUST deprecate shared community pool swipe discovery; swipe results MUST be personalized per user.
- **FR-002**: The system MUST NOT trigger any AI discovery until the user has added at least 3 pantry ingredients (excluding assumed seasonings).
- **FR-003**: The system MUST treat the **Canonical Seasoning Set (Assumed Available)** (see **Domain Logic**) as always available for discovery and pantry-gate calculations.
- **FR-004**: The system MUST support Include Basics and Willing to Shop toggles on the Pantry screen.
- **FR-005**: Changing either toggle MUST invalidate any existing swipe discovery cache so future results reflect the new settings.
- **FR-005a**: Adding, removing, or editing pantry ingredients MUST invalidate any existing swipe discovery cache so future results reflect the updated pantry.
- **FR-006**: The system MUST maintain separate decks per energy level.
- **FR-006a**: The system MUST support 5 energy levels (0–4) for discovery and deck management.

**6-3-5 batching and refill**

- **FR-007**: On first access to Swipe with a valid pantry (>=3 ingredients), the system MUST generate 6 lightweight Recipe Ideas for each available energy level.
- **FR-007a**: With 5 energy levels (0–4), initial load MUST generate 30 total lightweight ideas (6 x 5).
- **FR-008**: A lightweight Recipe Idea MUST include: title, short concept, and an ingredients list without amounts.
- **FR-009**: When only 3 un-swiped ideas remain within a specific energy level, the system MUST trigger a background request to generate 5 additional lightweight ideas for that energy level only.
- **FR-010**: Background refills MUST NOT block swipe interactions or introduce a visible pause between cards.

**Uniqueness**

- **FR-011**: The system MUST ensure no meal/idea is repeated for a user within the same energy level.
- **FR-011a**: Each idea MUST have a stable uniqueness key (`ideaKey`) used for de-duplication within an energy level.
- **FR-011b**: The system MUST persist per-user, per-energy-level `ideaKey` history so uniqueness holds across time.
- **FR-011c**: Cache invalidation MUST NOT clear `ideaKey` history; invalidation refreshes the deck but does not allow repeats within an energy level.
- **FR-012**: The uniqueness guarantee MUST apply across time (not just within the currently visible deck).

**Two-stage generation and unlock**

- **FR-013**: Full recipe generation MUST occur only when the user swipes right or taps Show Directions.
- **FR-014**: A full recipe MUST include ingredient quantities and step-by-step directions.
- **FR-015**: Carrot cost MUST be applied only on successful unlock of a full recipe.
- **FR-016**: Unlocked recipes MUST be saved to the user's cookbook and removed from their swipe deck.

**Economy alignment**

- **FR-017**: The weekly allowance MUST remain 5 carrots and reset Mondays at 00:00 UTC.
- **FR-018**: The user MUST be prevented from exceeding the weekly maximum.

**Security**

- **FR-019**: Carrot deductions and unlock state MUST be validated in a trusted way and MUST be tamper-resistant from the client.
- **FR-019a**: Unlock + carrot spend MUST be performed via a single atomic write (e.g., a transaction) that decrements carrots and writes both unlock state and an unlock ledger/event.
- **FR-019b**: Security rules MUST prevent clients from increasing carrots and MUST prevent unlock state/ledger writes that are not consistent with a valid decrement.
- **FR-020**: The system MUST record an auditable unlock event per recipe unlock (who, what, when, cost).

### Assumptions & Dependencies

- **Assumption**: "Include Basics" refers to additional common staple ingredients beyond the always-assumed seasonings.
- **Assumption**: "Available energy levels" means the energy level options presented to the user in the app.
- **Dependency**: The product must have a trusted validation mechanism for carrot deduction and unlock state.

### Key Entities _(include if feature involves data)_

- **Pantry Ingredient**: A user-provided ingredient used to personalize discovery.
- **Pantry Toggles**: User settings that influence discovery (Include Basics, Willing to Shop).
- **Energy Level**: A user selection that scopes the deck and the types of ideas generated.
- **Recipe Idea**: Lightweight, unlockable card content (title, concept, ingredients list).
- **Full Recipe**: Unlocked content (quantities + directions).
- **Swipe Deck (Per Energy Level)**: The set of un-swiped/swiped recipe ideas for a user.
- **Unlock Event**: An auditable record that a user spent carrots to unlock a recipe.

## Success Criteria _(mandatory)_

### Measurable Outcomes

- **SC-001**: 0 discovery requests occur for users with fewer than 3 pantry ingredients (measured via logs/telemetry).
- **SC-002**: In a usability test, 90%+ of participants report the Swipe deck feels personalized (not random) after setting a pantry.
- **SC-003**: For 95% of swipe interactions, users perceive the next card as instant (no visible loading pause between cards).
- **SC-004**: For each energy level, 95% of refills complete before the user reaches 0 remaining cards in that energy level.
- **SC-005**: 0 repeated meals appear within the same energy level for a user over the most recent 100 generated ideas.

### Quality Gates

- Automated checks pass (static analysis and automated tests) with no regressions.
- The feature meets the security/data-integrity requirements (clients cannot self-grant carrots or unlocks).
