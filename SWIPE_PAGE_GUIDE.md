# Super Swipe - Swipe Page Guide

*Complete documentation of the Swipe page for client testing and feedback*

---

## Overview

The **Swipe page** is the core discovery experience where users browse AI-generated recipe ideas personalized to their pantry. Users swipe through recipe cards to discover, save, or skip recipes.

---

## App Bar (Top Navigation)

| Icon | Name | What It Does |
|------|------|--------------|
| ⚙️ (sliders) | **Filters** | Opens a filters panel to customize what recipes appear (cuisine, skill level, etc.) |
| 🔄 | **Refresh** | Fetches a fresh batch of new recipe ideas |
| 🌐 / ✨ | **Toggle Mode** | Switches between AI-personalized recipes (✨) and global community recipes (🌐) |

---

## Recipe Cards

Each card shows a recipe preview with:
- **Image** - Visual of the dish
- **Title** - Name of the recipe (max 2 lines)
- **Description** - Short "vibe" description (max 2 lines)
- **Tags/Chips** - Time, calories, skill level, cuisine
- **Main Ingredients** - Key ingredients used (if space permits)
- **"Show Directions" button** - Unlocks and opens full recipe immediately

---

## Swipe Gestures

| Gesture | Action | What Happens |
|---------|--------|--------------|
| **Swipe LEFT** ← | **Skip/Dislike** | Dismisses the card. Recipe is not saved. |
| **Swipe RIGHT** → | **Keep/Like** | Marks as liked, moves to next card. Recipe can be accessed later. |

---

## Bottom Action Buttons

From left to right:

| Button | Icon | Color | What It Does |
|--------|------|-------|--------------|
| **Dislike** | ✕ | Red | Same as swiping left - skips the current recipe |
| **Undo** | ↺ | Orange | Goes back to the previous card you just swiped |
| **Restart** | ⏮ | Teal | Returns to the first card in the current batch (start over) |
| **Info** | ℹ️ | Grey | Shows a tip: "Left = dislike, right = keep moving" |
| **Like** | → | Coral/Orange | Same as swiping right - keeps the recipe |

---

## Loading States

### 1. Initial Generation (First Time)

When the Swipe page loads for the first time:

**What User Sees:**
- Loading spinner
- Title: *"Creating your next ideas…"*
- Message: *"Finding recipes that match your pantry."*

**What's Happening Behind:**
- AI is generating personalized recipe ideas based on user's pantry items
- No action buttons shown - user just waits

---

### 2. Refill Generation (After Swiping ~20 Cards)

When user runs out of cards:

**What User Sees:**
- Loading spinner in a card
- Title: *"Creating more ideas…"*
- Message: *"Hold tight! New recipes tailored to your pantry are on the way."*
- Helper text: *"This usually takes a few seconds."*

**Action Buttons Available:**
| Button | What It Does |
|--------|--------------|
| **Generating...** / **Generate more ideas** | Shows generation progress (disabled during load) |
| **Update Pantry** | Navigate to Pantry page to add/remove ingredients |
| **My Idea** | Navigate to AI Generate page to create a custom recipe with your own prompt |

---

### 3. Background Refill (While Swiping)

When deck is running low but not empty:

**What User Sees:**
- Small dark banner at top: *"Creating fresh ideas…"*
- User can continue swiping normally

---

## Error States

### Rate Limit Error

**What User Sees:**
- Hourglass icon
- Title: *"Chef is a bit overwhelmed! 👨‍🍳"*
- Message: *"We hit the AI rate limit. Please wait a moment for the kitchen to cool down."*

**Actions:**
- **Try Again** - Retry generation
- **Upgrade to Pro** - (Future feature)

### General Error

**What User Sees:**
- Cloud-off icon
- Title: *"Couldn't generate ideas right now"*
- Message: *"Tap retry, or try changing energy level / pantry items."*

**Actions:**
- **Retry** - Try again
- **Go to Pantry** - Update ingredients

---

## Pantry Gate (Minimum Items Required)

If user has fewer than 3 ingredients:

**What Happens:**
- User is blocked from swiping
- Prompted to add at least 3 ingredients to pantry first

---

## Guest User Gate

If user is not logged in:

**What Happens:**
- User sees a gate screen
- Must sign in to access the Swipe feature

---

## Flow Summary

```
User Opens Swipe
       │
       ▼
   Pantry < 3 items? ──YES──► Show Pantry Gate
       │
       NO
       ▼
   First Load ──► Show "Creating your next ideas..." (no buttons)
       │
       ▼
   Cards Ready ──► User swipes through cards
       │
       ▼
   Cards Running Low ──► Background refill (banner shows)
       │
       ▼
   All Cards Done ──► Show "Creating more ideas..." + buttons:
                      • Update Pantry
                      • My Idea
```

---

## Key Points for Testing

1. **First load should be clean** - Only loading message, no action buttons
2. **After swiping all cards** - Both "Update Pantry" and "My Idea" buttons appear
3. **Undo button** - Should bring back the last swiped card
4. **Restart button** - Should go back to first card in batch
5. **"Show Directions"** - Should unlock and open full recipe
6. **All cards should fit screen** - No overflow regardless of title/description length

---

*Last updated: February 6, 2026*
