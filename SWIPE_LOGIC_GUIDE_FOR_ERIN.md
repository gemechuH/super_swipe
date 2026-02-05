# Swipe Page - Feature Logic Guide for Erin

---

## Filters (Top Bar)

**Why it exists:**  
Users have different preferences - some want quick meals, some want specific cuisines, some are beginners. Filters let users narrow down what AI shows them so they get more relevant recipes faster.

---

## Update Pantry Button

**The Problem:**  
AI generates recipes based ONLY on what's in the user's pantry. If the pantry has few ingredients, AI has limited options and will eventually run out of good ideas.

**Why this button exists:**  
After swiping through many cards, if the user isn't finding what they like, it's often because their pantry is too limited. This button reminds them: *"Add more ingredients = better recipe ideas."*

**When it appears:**  
Shows during the "Creating more ideas" loading screen - the perfect moment to suggest expanding their pantry.

---

## My Idea Button

**The Problem:**  
Sometimes a user has enough ingredients, but AI still isn't showing what they want. The AI is guessing what the user might like, but it can't read minds.

**Why this button exists:**  
This lets the user take control. Instead of hoping AI guesses correctly, they can write exactly what they want:
- *"I want something spicy"*
- *"Make a breakfast dish"*
- *"Something kid-friendly"*

**When it appears:**  
Shows alongside Update Pantry - giving users two paths when AI alone isn't enough.

---

## Back One (Undo Button)

**The Problem:**  
Users swipe fast. Sometimes they accidentally swipe left on a recipe they actually wanted.

**Why this button exists:**  
Simple undo. Brings back the last card they swiped so they can reconsider. Everyone makes mistakes - this prevents frustration.

---

## Back to First (Restart Button)

**The Problem:**  
After swiping through 15-20 cards quickly, users might realize they were too picky. Or they want to show the recipes to someone else. Or they changed their mind about what they want.

**Why this button exists:**  
Lets users start fresh with the same batch of recipes. They don't have to wait for AI to generate new ones - they can simply review the same cards again with fresh eyes.

---

## Important: AI API Limitation (Testing Phase)

**Current Situation:**  
We are using **Google Gemini API on free trial** for recipe generation. Free tier has limited tokens per minute/day.

**What this means during testing:**
- You may see "Chef is overwhelmed" error if you swipe too fast or generate too many recipes
- If this happens, wait 1-2 minutes and try again
- We are currently using multiple API keys to extend testing capacity

**Future Plan:**  
Once we move to production, we will upgrade to **Pro/paid API tier** which has much higher limits. This limitation is temporary for testing only.

**Workaround for now:**  
If you hit the limit, take a short break and come back - the app will work again.

---

## Summary

| Feature | Logic |
|---------|-------|
| **Filters** | User controls what kind of recipes they see |
| **Update Pantry** | More ingredients = AI has more to work with = better ideas |
| **My Idea** | When AI guessing isn't enough, user tells AI exactly what they want |
| **Back One** | Undo accidental swipes |
| **Back to First** | Review the same batch again without waiting |

---

*All these features work together to make sure users find recipes they love - whether through AI discovery, their own guidance, or simply taking a second look.*
