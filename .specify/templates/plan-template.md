# Implementation Plan: [FEATURE]

**Branch**: `[###-feature-name]` | **Date**: [DATE] | **Spec**: [link]
**Input**: Feature specification from `/specs/[###-feature-name]/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command.

## Summary

[Extract from feature spec: primary requirement + technical approach from research]

## Technical Context

<!--
  ACTION REQUIRED: Replace the content in this section with the technical details
  for the project. The structure here is presented in advisory capacity to guide
  the iteration process.
-->

**Language/Version**: Dart (Flutter 3.10.3+)  
**Primary Dependencies**: Flutter, Riverpod, GoRouter, Firebase (Auth/Firestore)  
**Storage**: Cloud Firestore (+ local cache/offline where applicable)  
**Testing**: `flutter test` (unit/widget), optional integration tests  
**Target Platform**: iOS + Android (mobile)  
**Project Type**: mobile  
**Performance Goals**: 60 fps swipe UX; fast perceived navigation  
**Constraints**: cost-controlled AI usage; no paid schedulers; secure client writes  
**Scale/Scope**: consumer mobile app (feature modules under `lib/features/`)

## Constitution Check

_GATE: Must pass before Phase 0 research. Re-check after Phase 1 design._

- Confirm alignment with `.specify/memory/constitution.md`.
- No client code can increase carrots or bypass unlock state.
- User action path remains responsive (no blocking network/AI on navigation).
- AI usage is bounded (cache + fallback + cost control noted).
- `flutter analyze` is clean and `flutter test` plan is defined (or exception justified).

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
lib/
├── core/
│   ├── config/
│   ├── models/
│   ├── providers/
│   ├── router/
│   ├── services/
│   ├── theme/
│   ├── utils/
│   └── widgets/
├── features/
│   └── [feature]/
│       ├── providers/
│       ├── services/
│       ├── screens/
│       └── widgets/
└── main.dart

test/
├── [unit + widget tests]
└── widget_test.dart

# Optional (if present/added)
integration_test/
```

**Structure Decision**: [Document the selected structure and reference the real
directories captured above]

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation                  | Why Needed         | Simpler Alternative Rejected Because |
| -------------------------- | ------------------ | ------------------------------------ |
| [e.g., 4th project]        | [current need]     | [why 3 projects insufficient]        |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient]  |
