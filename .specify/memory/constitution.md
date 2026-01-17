<!--
Sync Impact Report

- Version change: N/A (template placeholders) -> 1.0.0
- Modified principles: N/A (initial ratification from template)
- Added sections: N/A (sections existed as placeholders; now fully defined)
- Removed sections: N/A
- Templates requiring updates:
  - Updated: .specify/templates/plan-template.md
  - Updated: .specify/templates/spec-template.md
  - Updated: .specify/templates/tasks-template.md
  - Updated: .specify/templates/checklist-template.md
- Deferred items / TODOs: None
-->

# Super Swipe Constitution

## Core Principles

### 1) User-First UX Consistency

Super Swipe MUST keep user-facing flows consistent and predictable across screens.

- Navigation MUST be intent-driven (e.g., when a user taps “Show Directions”, the details view opens
  directions without flashing a locked state).
- Empty/error/loading states MUST be explicit and non-blocking.
- UI components that exist in multiple places (e.g., energy filter) MUST share a single source of
  truth for ranges/labels to prevent mismatched behavior.

Rationale: In a swipe-first app, trust is built by predictability and visual stability.

### 2) Performance Is a Feature

The app MUST stay responsive and smooth.

- User actions MUST navigate immediately; slow work MUST run in the background or be streamed.
- Rendering MUST avoid layout overflows and jank (prefer responsive layouts and wraps).
- Network and AI calls MUST be bounded (timeouts, retries with backoff where appropriate).

Rationale: Swipe UX is extremely sensitive to latency and frame drops.

### 3) Security & Data Integrity by Default

Client code MUST NOT be able to grant itself value.

- Firestore rules MUST prevent privilege escalation (e.g., clients cannot increase carrots).
- Scheduled/administrative changes (e.g., weekly carrot reset) MUST be performed by an admin
  process, not the client.
- Secrets (API keys, service accounts) MUST NOT be committed; use environment/secrets.

Rationale: The carrot economy and unlock mechanics depend on trustable state.

### 4) Test the Behavior We Ship

Changes that affect user-visible behavior or business rules MUST be covered by tests unless there
is a documented exception.

- `flutter analyze` MUST be clean.
- `flutter test` MUST pass.
- Bug fixes MUST add a regression test when feasible.
- Exceptions MUST be justified in the feature plan under “Complexity Tracking”.

Rationale: Swipe/unlock flows are easy to regress; tests protect velocity.

### 5) Cost-Controlled Personalization

AI usage MUST be designed to be cost-bounded and cacheable.

- Prefer lightweight, per-user previews; generate full recipes only when the user commits (e.g.,
  swipe-right / unlock).
- Cache AI outputs keyed by user + pantry/preferences + prompt version.
- Provide a graceful fallback when pantry input is insufficient (clear empty state + guidance).

Rationale: Personalization is core value, but cost must stay predictable.

## Additional Constraints

- **Stack**: Flutter (Dart), Riverpod, GoRouter, Firebase Auth, Cloud Firestore.
- **No paid schedulers**: recurring backend maintenance MUST use free/owned automation
  (e.g., GitHub Actions + admin scripts) unless explicitly approved.
- **Offline-first bias**: where practical, key user flows SHOULD remain usable with cached data.
- **Data model discipline**: shared collections vs per-user collections MUST be chosen intentionally
  to meet personalization requirements.

## Development Workflow

### Branching & Changes

- Work in small, reviewable increments.
- Each change MUST have a clear rollback story (feature flags, guarded writes, or safe defaults).

### Review Gates (PRs)

- Confirm the change complies with the Core Principles.
- Confirm no client write can increase carrots or bypass unlock state.
- Confirm UI states: loading/empty/error are present and responsive.
- Confirm tests + analyzer are green.

### Definition of Done

- Code compiles.
- No new analyzer warnings.
- Tests updated/added appropriately.
- Any schema/rules changes documented and deployed intentionally.

## Governance

<!-- Example: Constitution supersedes all other practices; Amendments require documentation, approval, migration plan -->

This constitution supersedes all other engineering guidance in this repository.

### Amendments

- Any change to this document MUST update the version.
- Versioning follows semantic versioning:
  - **MAJOR**: removing/redefining a principle or weakening a gate.
  - **MINOR**: adding a new principle/section or materially expanding obligations.
  - **PATCH**: clarifications/wording without changing obligations.
- Amendments MUST include a brief “why” in the PR description.

### Compliance Review Expectations

- Feature plans MUST include a “Constitution Check” section.
- If a gate is intentionally violated, it MUST be recorded in the plan with rationale.

**Version**: 1.0.0 | **Ratified**: 2026-01-16 | **Last Amended**: 2026-01-16
