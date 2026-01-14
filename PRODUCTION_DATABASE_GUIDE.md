# 📖 PRODUCTION DATABASE GUIDE

## Single Source of Truth for Supper Swipe Firestore Schema

**Version:** 3.0 | **Last Updated:** January 14, 2026

---

## 1. Collections Overview

| Collection                  | Type | Document ID Strategy              | Purpose                             |
| --------------------------- | ---- | --------------------------------- | ----------------------------------- |
| `users`                     | Root | Firebase Auth UID                 | User profiles, carrots, preferences |
| `users/{uid}/pantry`        | Sub  | Auto-generated                    | User's pantry items                 |
| `users/{uid}/savedRecipes`  | Sub  | Recipe ID (mirror)                | Unlocked/saved recipes              |
| `users/{uid}/transactions`  | Sub  | Auto-generated                    | Carrot economy ledger               |
| `users/{uid}/pantry_logs`   | Sub  | Auto-generated                    | Consumption audit trail             |
| `users/{uid}/meal_plans`    | Sub  | Date string (YYYY-MM-DD)          | Meal planning                       |
| `users/{uid}/shoppingLists` | Sub  | Auto-generated                    | Shopping lists                      |
| `recipes`                   | Root | Auto-generated / client-generated | Global recipe pool (swipe feed)     |
| `recipe_secrets`            | Root | Same as `recipes/{id}`            | Protected instructions              |
| `ingredients`               | Root | Normalized name                   | Master ingredient database          |
| `ai_recipe_requests`        | Root | Auto-generated                    | AI generation requests              |
| `user_quotas`               | Root | Firebase Auth UID                 | Vision API quotas                   |

---

## 2. Detailed Field Mapping

### 2.1 `users/{uid}`

| Field                             | Type                   | Required | Description                           |
| --------------------------------- | ---------------------- | -------- | ------------------------------------- |
| `uid`                             | String                 | ✅       | Firebase Auth UID                     |
| `email`                           | String                 | ❌       | User email (nullable for anonymous)   |
| `displayName`                     | String                 | ✅       | Display name                          |
| `photoURL`                        | String                 | ❌       | Profile photo URL                     |
| `isAnonymous`                     | Boolean                | ✅       | Guest account flag                    |
| `subscriptionStatus`              | String                 | ✅       | `free` \| `premium`                   |
| `subscriptionExpiresAt`           | Timestamp              | ❌       | Premium expiration                    |
| `carrots`                         | Map                    | ✅       | Carrot economy state                  |
| `carrots.current`                 | Number                 | ✅       | Current carrot balance (0-5 for free) |
| `carrots.max`                     | Number                 | ✅       | Max carrots (5 free, 999 premium)     |
| `carrots.lastResetAt`             | Timestamp              | ✅       | Last weekly reset timestamp           |
| `preferences`                     | Map                    | ✅       | User preferences                      |
| `preferences.dietaryRestrictions` | Array\<String\>        | ❌       | ["vegetarian", "gluten-free"]         |
| `preferences.allergies`           | Array\<String\>        | ❌       | ["nuts", "dairy"]                     |
| `preferences.defaultEnergyLevel`  | Number                 | ❌       | 0-3 default filter                    |
| `preferences.preferredCuisines`   | Array\<String\>        | ❌       | ["italian", "mexican"]                |
| `preferences.pantryFlexibility`   | String                 | ❌       | `strict` \| `lenient`                 |
| `appState`                        | Map                    | ✅       | UI state tracking                     |
| `appState.hasSeenOnboarding`      | Boolean                | ✅       | Onboarding completion                 |
| `appState.hasSeenTutorials`       | Map\<String, Boolean\> | ❌       | Tutorial states                       |
| `stats`                           | Map                    | ✅       | User statistics                       |
| `stats.recipesUnlocked`           | Number                 | ✅       | Total recipes unlocked                |
| `stats.totalCarrotsSpent`         | Number                 | ✅       | Lifetime carrots spent                |
| `stats.scanCount`                 | Number                 | ✅       | AI scan usage count                   |
| `accountCreatedAt`                | Timestamp              | ✅       | Account creation time                 |
| `lastLoginAt`                     | Timestamp              | ✅       | Last login timestamp                  |
| `updatedAt`                       | Timestamp              | ✅       | Last update timestamp                 |

### 2.2 `users/{uid}/pantry/{itemId}`

| Field                 | Type      | Required | Description                                              |
| --------------------- | --------- | -------- | -------------------------------------------------------- |
| `id`                  | String    | ✅       | Document ID (auto-generated)                             |
| `userId`              | String    | ✅       | Owner UID                                                |
| `name`                | String    | ✅       | Display name ("Whole Milk")                              |
| `normalizedName`      | String    | ✅       | Lowercase for search ("milk")                            |
| `category`            | String    | ✅       | `dairy` \| `produce` \| `protein` \| `grains` \| `other` |
| `quantity`            | Number    | ✅       | Amount (integer, >= 0)                                   |
| `unit`                | String    | ✅       | `pieces` \| `cups` \| `lbs` \| `oz`                      |
| `source`              | String    | ✅       | `manual` \| `scanned` \| `ai-suggested`                  |
| `detectionConfidence` | Number    | ❌       | 0.0-1.0 (if scanned)                                     |
| `expiresAt`           | Timestamp | ❌       | Expiration date                                          |
| `addedAt`             | Timestamp | ✅       | When added                                               |
| `createdAt`           | Timestamp | ✅       | Document creation                                        |
| `updatedAt`           | Timestamp | ✅       | Last modification                                        |

### 2.3 `users/{uid}/savedRecipes/{recipeId}`

| Field          | Type            | Required | Description                               |
| -------------- | --------------- | -------- | ----------------------------------------- |
| `recipeId`     | String          | ✅       | Reference to `recipes/{id}`               |
| `isUnlocked`   | Boolean         | ✅       | `true` if user paid carrot                |
| `unlockedAt`   | Timestamp       | ❌       | When unlocked                             |
| `title`        | String          | ✅       | Cached recipe title                       |
| `imageUrl`     | String          | ✅       | Cached image URL                          |
| `ingredients`  | Array\<String\> | ✅       | Cached ingredient list                    |
| `instructions` | Array\<String\> | ❌       | Copied from `recipe_secrets` after unlock |
| `energyLevel`  | Number          | ✅       | 0-3                                       |
| `timeMinutes`  | Number          | ✅       | Cook time                                 |
| `calories`     | Number          | ✅       | Calorie count                             |
| `currentStep`  | Number          | ❌       | Progress tracking (0 = not started)       |
| `lastStepAt`   | Timestamp       | ❌       | Progress timestamp                        |
| `savedAt`      | Timestamp       | ✅       | When saved/unlocked                       |

### 2.4 `users/{uid}/transactions/{txId}`

| Field          | Type      | Required | Description                                |
| -------------- | --------- | -------- | ------------------------------------------ |
| `type`         | String    | ✅       | `spend` \| `earn` \| `reset` \| `purchase` |
| `amount`       | Number    | ✅       | Change (+5 for reset, -1 for spend)        |
| `balanceAfter` | Number    | ✅       | Balance after transaction                  |
| `recipeId`     | String    | ❌       | Related recipe (if spend)                  |
| `description`  | String    | ❌       | Human-readable description                 |
| `timestamp`    | Timestamp | ✅       | Transaction time                           |

### 2.5 `recipes/{recipeId}` (Global Recipe Pool)

| Field                   | Type            | Required | Description                                   |
| ----------------------- | --------------- | -------- | --------------------------------------------- |
| `id`                    | String          | ✅       | Document ID                                   |
| `title`                 | String          | ✅       | Recipe title                                  |
| `titleLowercase`        | String          | ✅       | Lowercase for search                          |
| `description`           | String          | ✅       | Short description                             |
| `imageUrl`              | String          | ✅       | Hero image                                    |
| `ingredients`           | Array\<String\> | ✅       | Ingredient names (FREE to view)               |
| `ingredientIds`         | Array\<String\> | ✅       | Normalized IDs for matching                   |
| `visibility`            | String          | ✅       | `public` \| `private`                         |
| `createdBy`             | String          | ❌       | Creator UID (for user-published recipes)      |
| `source`                | String          | ❌       | e.g. `seed` \| `ai_user`                      |
| `isActive`              | Boolean         | ✅       | Soft delete flag                              |
| `isPremium`             | Boolean         | ✅       | Premium-only recipe                           |
| `instructions`          | Array\<String\> | ✅       | Full steps (stored directly for global swipe) |
| `energyLevel`           | Number          | ✅       | 0 (Sleepy) to 3 (High)                        |
| `mealType`              | String          | ✅       | `breakfast` \| `lunch` \| `dinner` \| `snack` |
| `skillLevel`            | String          | ✅       | `beginner` \| `moderate` \| `advanced`        |
| `cuisine`               | String          | ✅       | `italian` \| `mexican` \| etc.                |
| `flavorProfile`         | Array\<String\> | ✅       | `sweet` \| `savory` \| `spicy`                |
| `prepTags`              | Array\<String\> | ✅       | `minimal-prep` \| `one-pan` \| `no-bake`      |
| `equipment`             | Array\<String\> | ✅       | `stovetop` \| `oven` \| `microwave`           |
| `dietaryTags`           | Array\<String\> | ✅       | `vegetarian` \| `vegan` \| `gluten-free`      |
| `timeMinutes`           | Number          | ✅       | Total cook time                               |
| `timeTier`              | String          | ✅       | `quick` \| `medium` \| `long`                 |
| `calories`              | Number          | ✅       | Calorie estimate                              |
| `servings`              | Number          | ❌       | Serving count                                 |
| `difficulty`            | String          | ❌       | `easy` \| `medium` \| `hard`                  |
| `totalNutrition`        | Map             | ❌       | Pre-calculated nutritional info               |
| `stats`                 | Map             | ✅       | Popularity metrics                            |
| `stats.likes`           | Number          | ✅       | Like count                                    |
| `stats.popularityScore` | Number          | ✅       | Ranking score                                 |
| `stats.unlocks`         | Number          | ✅       | Unlock count                                  |
| `createdAt`             | Timestamp       | ✅       | Creation time                                 |
| `updatedAt`             | Timestamp       | ✅       | Last update                                   |

### 2.6 `recipe_secrets/{recipeId}` (Protected - Optional)

This collection is optional if you keep all instructions public in `recipes`.
If you enforce a paywall with a split-collection pattern, store sensitive/full
instructions here and keep `recipes` as preview-only.

| Field                  | Type            | Required | Description              |
| ---------------------- | --------------- | -------- | ------------------------ |
| `recipeId`             | String          | ✅       | Same as parent recipe ID |
| `instructions`         | Array\<String\> | ✅       | Step-by-step directions  |
| `ingredientQuantities` | Array\<String\> | ❌       | Exact measurements       |
| `chefTips`             | String          | ❌       | Pro tips                 |
| `proprietaryData`      | Map             | ❌       | Any proprietary info     |

### 2.8 `ingredients/{ingredientId}`

| Field              | Type            | Required | Description                       |
| ------------------ | --------------- | -------- | --------------------------------- |
| `name`             | String          | ✅       | Display name                      |
| `category`         | String          | ✅       | `dairy` \| `produce` \| `protein` |
| `aliases`          | Array\<String\> | ❌       | Alternative names                 |
| `defaultUnit`      | String          | ✅       | Default unit                      |
| `isCommon`         | Boolean         | ✅       | Commonly available                |
| `isPerishable`     | Boolean         | ✅       | Needs refrigeration               |
| `shelfLifeDays`    | Number          | ❌       | Typical shelf life                |
| `nutritionPer100g` | Map             | ❌       | Nutritional data                  |
| `substitutes`      | Array\<String\> | ❌       | Substitute ingredient IDs         |

---

## 3. Indexing Requirements

### 3.1 Existing Indexes (Already Deployed)

```
pantry: (userId, normalizedName)
pantry: (userId, category, createdAt DESC)
recipes: (isActive, energyLevel, stats.popularityScore DESC)
recipes: (isActive, dietaryTags ARRAY, stats.popularityScore DESC)
recipes: (isActive, timeTier, stats.popularityScore DESC)
savedRecipes: (userId, savedAt DESC)
```

### 3.2 New Indexes Required

| Collection     | Fields                                                                    | Purpose                |
| -------------- | ------------------------------------------------------------------------- | ---------------------- |
| `recipes`      | `(visibility, isActive, energyLevel, stats.popularityScore DESC)`         | Swipe feed by energy   |
| `recipes`      | `(visibility, isActive, flavorProfile ARRAY, stats.popularityScore DESC)` | Flavor filter          |
| `recipes`      | `(visibility, isActive, prepTags ARRAY, stats.popularityScore DESC)`      | Prep style filter      |
| `recipes`      | `(visibility, isActive, equipment ARRAY, stats.popularityScore DESC)`     | Equipment filter       |
| `recipes`      | `(visibility, isActive, mealType, stats.popularityScore DESC)`            | Meal type filter       |
| `recipes`      | `(visibility, ownerId, createdAt DESC)`                                   | User's private recipes |
| `pantry`       | `(userId, expiresAt)`                                                     | Expiring soon queries  |
| `transactions` | `(userId, timestamp DESC)`                                                | Wallet history         |

---

## 4. Security Rules Summary

| Collection                   | Read                                 | Write               |
| ---------------------------- | ------------------------------------ | ------------------- |
| `users/{uid}`                | Owner only                           | Owner only          |
| `users/{uid}/pantry/*`       | Owner only                           | Owner only          |
| `users/{uid}/savedRecipes/*` | Owner only                           | Owner only          |
| `users/{uid}/transactions/*` | Owner only                           | Owner only (create) |
| `recipes`                    | Public (if `visibility == 'public'`) | Admin only          |
| `recipe_secrets`             | Premium OR Unlocked OR Owner         | Admin only          |
| `ingredients`                | Authenticated                        | Admin only          |

---

## 5. Guest Mode Strategy

| Scenario                | Data Location                 | Persistence  |
| ----------------------- | ----------------------------- | ------------ |
| Guest browses recipes   | Firestore (public)            | N/A          |
| Guest adds pantry item  | Local State (Riverpod)        | Session only |
| Guest swipes left/right | Local State                   | Session only |
| Guest tries to unlock   | Redirect to Sign Up           | N/A          |
| User signs up           | Batch write Local → Firestore | Permanent    |

---

## 6. Client Handover Guide

### 6.1 Setting a User to "Premium" in Firebase Console

To manually grant a user Premium status:

1. **Open Firebase Console**: https://console.firebase.google.com/project/super-swipe-erin-2025/firestore
2. **Navigate to Users Collection**: Click on `users` → find the user by UID
3. **Update Fields**:
   - Set `subscriptionStatus` to `"premium"`
   - Set `subscriptionExpiresAt` to a future date (e.g., `2026-01-01`)
   - Set `carrots.max` to `999` (unlimited)
   - Set `carrots.current` to `999`
4. **Save Changes**

### 6.2 Adding New Recipes

1. **Create Recipe Document** in `recipes` collection:

   - Set `visibility` to `"public"`
   - Set `isActive` to `true`
   - Fill in all required fields (see Section 2.5)

2. **Create Matching Secret** in `recipe_secrets` with SAME document ID:
   - Add `instructions` array with step-by-step directions

### 6.3 Deployment Commands

```bash
# Deploy Firestore rules and indexes
firebase deploy --only firestore

# Deploy only rules
firebase deploy --only firestore:rules

# Deploy only indexes
firebase deploy --only firestore:indexes
```

### 6.4 Monitoring & Analytics

- **Firestore Usage**: Firebase Console → Firestore → Usage
- **User Activity**: Query `users/{uid}/transactions` for carrot history
- **Recipe Popularity**: Check `recipes/{id}/stats.unlocks`
