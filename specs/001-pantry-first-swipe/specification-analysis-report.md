---
description: "Specification analysis report for Personalized Pantry-First Swipe Engine"
updated: 2026-01-16
---

## Specification Analysis Report (Updated)

This report reflects remediations applied after the initial analysis (A1, G1, C1, I1) and a sync pass across supporting design/contract docs.

### Open Findings

| ID  | Category           | Severity | Location(s)                                                                                                   | Summary                                                                                                                        | Recommendation                                                                                                                                            |
| --- | ------------------ | -------- | ------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A2  | Ambiguity          | MEDIUM   | [specs/001-pantry-first-swipe/spec.md](spec.md#L99-L103) [specs/001-pantry-first-swipe/spec.md](spec.md#L188) | “Swipes must be immediate” and “users perceive instant” are not operationalized (no budget/measurement definition).            | Define a concrete target (e.g., p95 next-card-visible under X ms, refills never block) and how it will be validated (tests + lightweight timing/logging). |
| D1  | Duplication        | LOW      | [specs/001-pantry-first-swipe/spec.md](spec.md#L141-L145)                                                     | FR-011 (“no repeats…within energy level”) and FR-012 (“across time”) overlap; the distinction is implied rather than explicit. | Consider merging or rewording to clarify “across time per energy” as the primary guarantee and “within current deck” as a subset.                         |
| U2  | Underspecification | MEDIUM   | [specs/001-pantry-first-swipe/spec.md](spec.md#L135)                                                          | Preview requirement (ingredients list without amounts) can drift if AI returns quantities unless validated.                    | Add a unit test/schema validation asserting preview parsing rejects/strips amounts and ensure prompts/contracts enforce “no quantities” for previews.     |

### Resolved Findings (Applied)

| ID  | Category               | Status                      | Location(s)                                                 | What changed                                                                                                                                             |
| --- | ---------------------- | --------------------------- | ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| I1  | Inconsistency          | RESOLVED                    | [specs/001-pantry-first-swipe/plan.md](plan.md#L35-L39)     | Updated the plan to remove “NEEDS CLARIFICATION” language and replace it with resolved decisions + doc links.                                            |
| A1  | Ambiguity              | RESOLVED                    | [specs/001-pantry-first-swipe/spec.md](spec.md#L105-L116)   | Added a canonical “Assumed Seasonings” list plus the explicit rule: these are ignored for the minimum-3-ingredients gate.                                |
| U1  | Underspecification     | RESOLVED                    | [specs/001-pantry-first-swipe/spec.md](spec.md#L81-L98)     | Replaced question-style edge cases with concrete “Given/When/Then” behaviors, clarifying expected outcomes for outages, carrots, and refill races.       |
| G1  | Coverage Gap           | RESOLVED                    | [specs/001-pantry-first-swipe/tasks.md](tasks.md#L139-L147) | Added Phase 6 “Economy & Action Compatibility” tasks (T056–T058) to ensure external GitHub Actions resets are supported and reflected in UI/unlock flow. |
| C1  | Constitution Alignment | RESOLVED (PLANNED VIA TASK) | [specs/001-pantry-first-swipe/tasks.md](tasks.md#L147)      | Added T059 to centralize energy-level constants in a single source of truth to prevent 0–3 vs 0–4 drift.                                                 |

### Coverage Summary (Post-Modification)

| Requirement Key                                       | Has Task? | Task IDs               | Notes                                                                                                                 |
| ----------------------------------------------------- | --------- | ---------------------- | --------------------------------------------------------------------------------------------------------------------- |
| deprecate-shared-community-pool                       | Yes       | T028, T033             | Replaces global recipe pool usage.                                                                                    |
| gate-discovery-until-3-ingredients                    | Yes       | T020–T024              | Gate + tests.                                                                                                         |
| assume-seasonings-available                           | Yes       | T010, T021             | Canonical list now defined in spec (A1 resolved).                                                                     |
| support-pantry-toggles                                | Yes       | T006–T009, T036–T039   | Model + UI + persistence.                                                                                             |
| invalidate-cache-on-toggle-change                     | Yes       | T012, T040, T041       | Signature bump + deck refresh.                                                                                        |
| invalidate-cache-on-pantry-change                     | Yes       | T013, T041             | Pantry CRUD bumps signature.                                                                                          |
| separate-decks-per-energy-level                       | Yes       | T015, T017, T031       | Service + provider + UI switching.                                                                                    |
| support-5-energy-levels                               | Yes       | T015, T031, T059       | T059 prevents drift via centralized constants.                                                                        |
| generate-6-ideas-per-energy-initial                   | Yes       | T015, T026             | 6-per-energy behavior tested.                                                                                         |
| generate-30-ideas-total-initial                       | Yes       | T015, T026             | Derived from above.                                                                                                   |
| preview-includes-title-concept-ingredients-no-amounts | Partial   | T029                   | Add validation test (U2).                                                                                             |
| refill-5-ideas-when-3-remain                          | Yes       | T015, T027             | Refill trigger covered.                                                                                               |
| refills-non-blocking                                  | Yes       | T032, T062             | Perf hardening exists.                                                                                                |
| no-repeats-per-energy-over-time                       | Yes       | T014, T016, T018, T042 | Utility + persistence + tests.                                                                                        |
| full-recipe-only-on-unlock                            | Yes       | T045, T047             |                                                                                                                       |
| charge-carrots-only-on-success                        | Yes       | T043, T045             |                                                                                                                       |
| save-unlocked-and-remove-from-deck                    | Yes       | T045, T046             |                                                                                                                       |
| weekly-allowance-reset-and-max-enforcement            | Yes       | T056–T058              | Weekly reset is handled externally (GitHub Actions); tasks verify compatibility, UI refresh, and security boundaries. |
| tamper-resistant-carrot-unlock                        | Yes       | T046, T049, T056       | Transaction shape + rules hardening + service-account reset allowance.                                                |
| atomic-transaction-decrement-ledger-unlock            | Yes       | T046                   |                                                                                                                       |
| rules-prevent-invalid-unlock-writes                   | Yes       | T049                   |                                                                                                                       |
| record-auditable-unlock-event                         | Yes       | T046, T049             | Ledger requirement present.                                                                                           |

### Metrics (Post-Modification)

- Total Functional Requirements: 28
- Total Tasks: 59 (IDs range T001–T064; some IDs unused after renumbering)
- Coverage Status: 28/28 requirements mapped to at least one task
- Conflict Resolution: economy work is “Verify External Action Compatibility” (GitHub Actions) rather than building a new reset service

### Notes

- The weekly reset schedule (Mondays 00:00 UTC) remains a dependency on the existing GitHub Actions automation; this report treats it as an infrastructure concern and focuses coverage on security + client compatibility with externally-updated carrot balances.
