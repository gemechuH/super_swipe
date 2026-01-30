# Swipe Page Documentation

> Complete technical documentation of the Super Swipe recipe swiping feature

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Recipe Generation Flow](#recipe-generation-flow)
4. [Batch Sizes & Limits](#batch-sizes--limits)
5. [User Interaction Flow](#user-interaction-flow)
6. [State Management](#state-management)
7. [Duplicate Prevention](#duplicate-prevention)
8. [Database Schema](#database-schema)
9. [Empty Deck & User Feedback](#empty-deck--user-feedback) ⭐ **NEW**
10. [Error Handling](#error-handling)
11. [File Reference](#file-reference)

---

## Overview

The Swipe page provides a Tinder-like interface for discovering recipes. Users swipe through AI-generated recipe previews based on their **pantry items**, **dietary preferences**, and selected **energy level**.

### Key Features

| Feature | Description |
|---------|-------------|
| **Pantry-First Generation** | Recipes are generated based on ingredients the user actually has |
| **Energy Levels** | 3 levels (1=Quick, 2=Medium, 3=Complex) affecting recipe complexity |
| **Endless Scrolling** | Background refill ensures users never run out of cards |
| **Duplicate Prevention** | Idea Key system prevents showing the same recipe twice |
| **Two-Phase Unlock** | Preview generation (cheap) → Full recipe generation (on unlock) |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        SwipeScreen (UI)                         │
│   - Displays swipe cards using AppinioSwiper                    │
│   - Manages local dismissed card state                          │
│   - Triggers refill when cards run low                          │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│              PantryFirstSwipeDeckController (Provider)          │
│   - State management (Riverpod)                                 │
│   - Coordinates between UI and Service                          │
│   - Tracks refilling state                                      │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│              PantryFirstSwipeDeckService (Business Logic)       │
│   - Initial deck generation                                     │
│   - Background refill logic                                     │
│   - Recipe unlock flow                                          │
└─────────────────────────────────────────────────────────────────┘
                                │
                    ┌───────────┴───────────┐
                    ▼                       ▼
┌─────────────────────────────┐  ┌─────────────────────────────┐
│    AiRecipeService          │  │   DatabaseService           │
│   - Gemini AI integration   │  │   - Firebase Firestore      │
│   - Preview batch generation│  │   - Card persistence        │
│   - Full recipe generation  │  │   - Idea key history        │
└─────────────────────────────┘  └─────────────────────────────┘
```

---

## Recipe Generation Flow

### Phase 1: Initial Deck Generation

When a user first opens the Swipe page:

```
1. User opens Swipe page
        │
        ▼
2. Provider calls ensureInitialDeck()
        │
        ▼
3. Check existing deck count for this energy level + signature
        │
        ├── If count >= 20 → Done (use existing cards)
        │
        └── If count < 20 → Generate missing cards
                │
                ▼
4. AI generates RecipePreview batch
        │
        ▼
5. Filter duplicates using Idea Key
        │
        ▼
6. Persist to Firestore (swipeDeck collection)
        │
        ▼
7. Repeat up to 3 rounds if needed to reach 20
```

### Phase 2: Rolling Background Refill

As the user swipes:

```
User swipes card
        │
        ▼
Check remaining cards
        │
        ├── If remaining > 5 → Continue normally
        │
        └── If remaining <= 5 → Trigger background refill
                │
                ▼
        Generate 10 more previews (non-blocking)
                │
                ▼
        Append to existing deck
                │
                ▼
        User keeps swiping (uninterrupted)
```

### Phase 3: Recipe Unlock (Swipe Right)

When user swipes right to unlock:

```
User swipes right
        │
        ▼
Show confirmation dialog
        │
        ├── Cancel → Unswipe, restore card
        │
        └── Confirm → Reserve unlock
                │
                ▼
        Deduct 1 carrot (if non-premium)
                │
                ▼
        Mark card as consumed in database
                │
                ▼
        Navigate to Recipe Detail (with placeholder)
                │
                ▼
        Generate full recipe in background
                │
                ▼
        Save to user's savedRecipes collection
```

---

## Batch Sizes & Limits

### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `_initialDeckTarget` | **20** | Number of cards to generate on first load |
| `_refillBatchSize` | **10** | Number of cards generated per refill |
| `maxTopUpRounds` | **3** | Maximum retry rounds for initial deck |
| `maxAttempts` | **6** | Maximum AI call attempts per generation |
| Refill Trigger | **≤5 cards** | Remaining cards that triggers background refill |
| Cooldown | **3 seconds** | Minimum time between automatic refill attempts |

### Generation Summary

```
Initial Load:
  └── Target: 20 recipes
  └── AI calls: up to 3 rounds × 6 attempts = 18 max calls
  └── Actual: Usually 1-2 calls (20 unique recipes)

Per Refill:
  └── Target: 10 recipes
  └── AI calls: up to 6 attempts
  └── Triggered: When ≤5 cards remain

Total Per Session:
  └── No hard limit - endless generation
  └── Limited only by AI rate limits and duplicate exhaustion
```

---

## User Interaction Flow

### Swipe Actions

| Action | Result |
|--------|--------|
| **Swipe Left** | Discard recipe, mark as `isDisliked: true` in database |
| **Swipe Right** | Unlock flow: confirm → deduct carrot → generate full recipe |
| **Tap "View Ingredients"** | Show ingredient preview (no carrot cost) |
| **Tap "Show Directions"** | Same as swipe right (unlock required) |

### Energy Level Slider

```
Energy Level 1 (Quick):
  └── Simple recipes, ~15 minutes
  └── Basic techniques
  └── Minimal equipment

Energy Level 2 (Medium):
  └── Standard recipes, ~30 minutes
  └── Some multi-step processes

Energy Level 3 (Complex):
  └── Elaborate recipes, ~45+ minutes
  └── Advanced techniques
  └── More equipment required
```

Each energy level maintains its **own separate deck** with independent generation.

---

## State Management

### Provider Structure

```dart
// Main deck provider - one per energy level
final pantryFirstSwipeDeckProvider = 
    AutoDisposeAsyncNotifierProviderFamily<..., List<RecipePreview>, int>

// Refilling state - tracks background generation
final swipeDeckRefillingProvider = StateProvider.family<bool, int>

// Cooldown tracking - prevents rapid retries
final _swipeDeckLastRefillAttemptProvider = StateProvider.family<DateTime?, int>
```

### State Flow

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  AsyncLoading    │ ──► │  AsyncData       │ ──► │  AsyncData       │
│  (initial load)  │     │  (deck ready)    │     │  (refill done)   │
└──────────────────┘     └──────────────────┘     └──────────────────┘
                                  │
                                  ▼
                         ┌──────────────────┐
                         │  AsyncError      │
                         │  (generation     │
                         │   failed)        │
                         └──────────────────┘
```

### UI States

| State | UI Display |
|-------|------------|
| Loading (initial) | Shimmer skeleton + "Creating your next ideas…" |
| Error | Error icon + "Couldn't generate ideas" + Retry button |
| Empty (refilling) | Spinner + "Creating more ideas…" |
| Empty (not refilling) | Spinner + "Generate more ideas" button |
| Has cards | Swipeable card stack |
| Has cards + refilling | Card stack + subtle "Loading more…" badge |

---

## Duplicate Prevention

### Inputs Signature

A SHA-256 hash uniquely identifies the user's current configuration:

```dart
// Inputs that affect signature:
{
  "v": "pantry_first_swipe_v1",    // Prompt version
  "includeBasics": true,            // Include basic ingredients toggle
  "willingToShop": false,           // Willing to shop toggle
  "mealType": "dinner",             // Default meal type
  "allergies": ["peanuts"],         // User allergies
  "dietaryRestrictions": ["vegan"], // Dietary restrictions
  "preferredCuisines": ["italian"], // Preferred cuisines
  "pantry": ["chicken", "rice"]     // Sorted, normalized pantry items
}

// Result: "a1b2c3d4e5f6..." (64-char SHA-256 hash)
```

**When signature changes** (e.g., pantry updated), the deck is regenerated fresh.

### Idea Key

Each recipe preview gets a unique ID based on its content:

```dart
// Inputs for idea key:
{
  "energyLevel": 2,
  "title": "lemon herb chicken",        // Normalized
  "ingredients": ["chicken", "lemon"]   // Sorted, normalized
}

// Result: "f7g8h9i0j1k2..." (64-char SHA-256 hash)
```

### Duplicate Check Flow

```
AI generates preview
        │
        ▼
Build idea key from title + ingredients
        │
        ▼
Check ideaKeyHistory collection
        │
        ├── Key exists → Skip (duplicate)
        │
        └── Key doesn't exist → Accept
                │
                ▼
        Write to ideaKeyHistory
                │
                ▼
        Add to swipeDeck
```

---

## Database Schema

### Firestore Collections

```
users/{userId}/
├── swipeDeck/{cardId}           # Recipe previews for swiping
│   ├── id: string
│   ├── title: string
│   ├── vibeDescription: string
│   ├── ingredients: string[]
│   ├── energyLevel: number
│   ├── inputsSignature: string
│   ├── isConsumed: boolean
│   ├── isDisliked: boolean
│   ├── createdAt: timestamp
│   └── ...
│
├── ideaKeyHistory/{ideaKey}     # Prevents duplicates
│   ├── energyLevel: number
│   ├── inputsSignature: string
│   ├── title: string
│   ├── ingredients: string[]
│   └── createdAt: timestamp
│
└── savedRecipes/{recipeId}      # Unlocked full recipes
    ├── id: string
    ├── title: string
    ├── description: string
    ├── ingredients: string[]
    ├── instructions: string[]
    ├── isUnlocked: boolean
    └── ...
```

### Card Lifecycle

```
Created ──► Active ──► Consumed
                  │
                  └──► Disliked (swipe left)
                  └──► Unlocked (swipe right)
```

---

## Empty Deck & User Feedback

### What Happens When User Swipes All Cards?

When a user swipes through all available cards (10, 20, 30, or any number), the system **automatically handles it** and shows clear feedback.

### Scenario Flow

```
User swipes last card
        │
        ▼
Deck becomes empty (visiblePreviewDeck.length = 0)
        │
        ▼
System automatically triggers: forceRefillNow()
        │
        ▼
UI immediately shows: Empty Deck Loading State
        │
        ├── If generation succeeds → New cards appear
        │
        └── If generation fails/slow → User sees options
```

### UI States When Deck is Empty

#### State 1: Generating More Ideas (isRefilling = true)

```
┌─────────────────────────────────────────┐
│                                         │
│            ⟳ (spinner)                  │
│                                         │
│      "Creating more ideas…"             │
│                                         │
│   "Hold tight! New recipes tailored     │
│    to your pantry are on the way."      │
│                                         │
│   "This usually takes a few seconds."   │
│                                         │
│   ┌─────────────────────────────────┐   │
│   │   ⟳ Generating…                 │   │  ← Button DISABLED
│   └─────────────────────────────────┘   │
│                                         │
│   ┌─────────────────────────────────┐   │
│   │   🍳 Update Pantry              │   │  ← Go to Pantry page
│   └─────────────────────────────────┘   │
│                                         │
└─────────────────────────────────────────┘
```

#### State 2: Ready to Generate (isRefilling = false)

```
┌─────────────────────────────────────────┐
│                                         │
│            ⟳ (spinner)                  │
│                                         │
│    "Getting fresh recipes ready…"       │
│                                         │
│   "Our AI is cooking up personalized    │
│    ideas just for you."                 │
│                                         │
│   "This usually takes a few seconds."   │
│                                         │
│   ┌─────────────────────────────────┐   │
│   │   ✨ Generate more ideas        │   │  ← Tap to generate
│   └─────────────────────────────────┘   │
│                                         │
│   ┌─────────────────────────────────┐   │
│   │   🍳 Update Pantry              │   │  ← Go to Pantry page
│   └─────────────────────────────────┘   │
│                                         │
└─────────────────────────────────────────┘
```

### User Actions Available

| Action | What It Does |
|--------|--------------|
| **"Generate more ideas" button** | Forces immediate AI generation (bypasses cooldown) |
| **"Update Pantry" button** | Navigate to Pantry page to add more ingredients |
| **Wait** | System automatically generates in background |

### Messages Shown to User

| Situation | Title Message | Description |
|-----------|---------------|-------------|
| Generating | "Creating more ideas…" | "Hold tight! New recipes tailored to your pantry are on the way." |
| Ready to generate | "Getting fresh recipes ready…" | "Our AI is cooking up personalized ideas just for you." |
| Always shown | - | "This usually takes a few seconds." |

### Background Indicator (While Cards Still Visible)

When user has cards but more are being generated:

```
┌─────────────────────────────────────────┐
│  ┌─────────────────────────────────┐    │
│  │ ⟳ Loading more…                │    │  ← Subtle top badge
│  └─────────────────────────────────┘    │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │                                 │    │
│  │         RECIPE CARD             │    │
│  │                                 │    │
│  └─────────────────────────────────┘    │
│                                         │
└─────────────────────────────────────────┘
```

### Edge Cases & Recovery

| Situation | System Behavior | User Sees |
|-----------|-----------------|-----------|
| **AI returns 0 unique recipes** | Retry automatically, refresh UI | Loading state, can tap "Generate" |
| **AI request times out** | Cooldown (3s), then can retry | Loading state + active button |
| **Network error** | Error state shown | Error message + Retry button |
| **Rapid swiping** | Forces immediate generation on last card | Seamless transition to loading |

### Important: Never Blank Screen

The system guarantees:

✅ **Always shows feedback** - Spinner + message + buttons  
✅ **Always has action** - User can tap "Generate" or "Update Pantry"  
✅ **Auto-recovery** - System triggers generation automatically  
✅ **No frozen state** - If stuck, button forces new generation  

---

## Error Handling

### Recovery Mechanisms

| Error | Recovery |
|-------|----------|
| AI generation fails | Retry up to 6 times, then show error UI |
| Network timeout | Cooldown prevents rapid retries, user can tap retry |
| Out of carrots | Show message, restore card, cancel unlock |
| Empty deck | Auto-trigger refill, show loading UI |
| Generation returns 0 unique | Refresh UI, user can manually retry |

### Cooldown System

```
Automatic Refill:
  └── 3-second cooldown between auto-attempts
  └── Prevents hammering API on failure

User-Initiated Refill:
  └── No cooldown (forceRefillNow bypasses)
  └── User button always works immediately
```

---

## File Reference

| File | Purpose |
|------|---------|
| `lib/features/swipe/screens/swipe_screen.dart` | Main UI widget |
| `lib/features/swipe/providers/pantry_first_swipe_deck_provider.dart` | State management |
| `lib/features/swipe/services/pantry_first_swipe_deck_service.dart` | Business logic |
| `lib/features/swipe/services/swipe_inputs_signature.dart` | Signature generation |
| `lib/features/swipe/services/idea_key.dart` | Duplicate prevention keys |
| `lib/features/swipe/widgets/recipe_preview_card.dart` | Card UI component |
| `lib/services/ai/ai_recipe_service.dart` | Gemini AI integration |
| `lib/services/database/database_service.dart` | Firestore operations |

---

## Quick Reference

### Generation Numbers

```
┌────────────────────────────────────────────┐
│  INITIAL LOAD                              │
│  • Target: 20 recipe previews              │
│  • Per energy level                        │
│  • Retry up to 3 rounds                    │
└────────────────────────────────────────────┘

┌────────────────────────────────────────────┐
│  ROLLING REFILL                            │
│  • Triggered at: ≤5 cards remaining        │
│  • Generates: 10 new recipes               │
│  • Background (non-blocking)               │
│  • Endless (no hard limit)                 │
└────────────────────────────────────────────┘

┌────────────────────────────────────────────┐
│  RECIPE CONTENT                            │
│  • Preview: title + description +          │
│    ingredients (no amounts)                │
│  • Full: + instructions + tips + time      │
│  • Full generation: Only on unlock         │
└────────────────────────────────────────────┘
```

### Swipe Actions Summary

```
← LEFT SWIPE
  └── Disliked
  └── Never shown again
  └── No carrot cost

→ RIGHT SWIPE
  └── Unlock recipe
  └── 1 carrot cost (free users)
  └── Full recipe generated
  └── Saved to My Recipes
```

---

*Last updated: January 2026*

