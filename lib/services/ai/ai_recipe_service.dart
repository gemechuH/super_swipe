import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:super_swipe/core/config/swipe_constants.dart';
import 'package:super_swipe/core/models/recipe.dart';
import 'package:super_swipe/core/models/recipe_preview.dart';

/// Google Gemini Powered AI Recipe Service
/// Migrated from OpenAI to resolve quota issues.
class AiRecipeService {
  AiRecipeService({void Function(String message)? onStatus})
    : _onStatus = onStatus;

  final void Function(String message)? _onStatus;

  // Global Gemini call limiter
  // Swipe deck generation and single-recipe generation must share the same
  // limiter so we don't burst requests and trigger 429 / parsing instability.
  static const int _maxConcurrentGeminiCalls = 1;
  static int _activeGeminiCalls = 0;
  static final Queue<Completer<void>> _geminiWaitQueue =
      Queue<Completer<void>>();

  static Future<void> _acquireGeminiPermit() {
    if (_activeGeminiCalls < _maxConcurrentGeminiCalls) {
      _activeGeminiCalls++;
      return Future.value();
    }
    final c = Completer<void>();
    _geminiWaitQueue.add(c);
    return c.future;
  }

  static void _releaseGeminiPermit() {
    final next = _geminiWaitQueue.isNotEmpty
        ? _geminiWaitQueue.removeFirst()
        : null;
    if (next != null) {
      next.complete();
      return;
    }
    _activeGeminiCalls = (_activeGeminiCalls - 1).clamp(0, 1 << 30);
  }

  // Gemini API Configuration
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  // Gemini Models
  static const String _previewModel = 'gemini-2.5-flash';
  static const String _fullRecipeModel =
      'gemini-2.5-flash'; // Fallback to Flash due to Pro quota

  String get _apiKey => dotenv.get('GEMINI_API_KEY', fallback: '');

  /// Michelin-star Zero-Waste Chef system instruction with strict guardrails
  static const String _systemPromptPreview = '''
You are a Michelin-star Executive Chef and Culinary Logic Guardrail.
Your goal is to suggest a delicious, realistic, and culturally coherent meal based on available ingredients.

CRITICAL CULINARY RULES (STRICT ENFORCEMENT):
1. REALISM OVER PANTRY USAGE: Do NOT force all pantry items into a dish if they don't belong together.
   - Example FAIL: "Beef & Frosted Flakes Curry" -> REJECT.
   - Example PASS: "Pan-Seared Beef", ignoring the Frosted Flakes.
2. FLAVOR SAFETY:
   - NEVER pair sweet breakfast cereals (Froot Loops, Frosted Flakes) with savory proteins (Chicken, Beef, Fish).
   - NEVER pair candy/chocolate with savory main courses unless it is a recognized Mole sauce.
3. LOGICAL PAIRING:
   - If ingredients are incompatible, choose the subset that makes a classic dish. It is better to ignore an ingredient than to ruin the meal.
4. VIBE CHECK: The dish must sound appetizing to a sane human.

Return JSON with this exact format:
{
  "title": "Recipe Name",
  "vibe_description": "Brief enticing description of the dish vibe",
  "ingredients": ["ingredient 1", "ingredient 2", "ingredient 3"],
  "estimated_time_minutes": 25,
  "calories": 450,
  "equipment_icons": ["pan", "pot"],
  "meal_type": "dinner",
  "cuisine": "italian",
  "skill_level": "beginner",
  "energy_level": 2
}
''';

  static const String _systemPromptFullRecipe = '''
You are a Michelin-star Executive Chef creating professional-grade, physically possible recipes.

STRICT CULINARY GUARDRAILS:
1. INGREDIENT SANITY:
   - Do NOT use sweet cereals (Corn Flakes, Frosted Flakes, etc.) in savory dishes like pasta, stir-fry, or steak.
   - Do NOT use milk/cream in high-acid tomato sauces without explanation (curdling risk).
2. COOKING LOGIC:
   - Temperatures must be accurate (e.g., Chicken cooked to 165°F).
   - Techniques must be suitable for the ingredients (e.g., don't "grill" flour).
3. FALLBACK BEHAVIOR:
   - If the user asks for a combination that is culinary nonsense, ignore the bad ingredient and make the best dish possible with the rest.
   - Explain in the description: "I've focused on the [Main Ingredient] to ensure the best flavor profile."

Return JSON with this exact format:
{
  "title": "Recipe Name",
  "description": "Detailed appetizing description. If you excluded an ingredient for quality reasons, mention it here in a polite chef's voice.",
  "ingredients": ["1 cup ingredient with exact amount", "2 tbsp another ingredient"],
  "instructions": ["Detailed step 1 with temps", "Step 2 with technique"],
  "timeMinutes": 25,
  "calories": 450,
  "equipment": ["pan", "pot"],
  "prep_time": "10 min",
  "cook_time": "15 min",
  "temperatures": {"oven": "375°F", "stovetop": "medium-high"}
}
''';

  /// PHASE 1: Generate lightweight recipe preview (fast, low-cost)
  Future<RecipePreview> generateRecipePreview({
    required List<String> pantryItems,
    required List<String> allergies,
    required List<String> dietaryRestrictions,
    required String cravings,
    required int energyLevel,
    List<String> preferredCuisines = const [],
    String? mealType,
    bool strictPantryMatch = true,
    // Filter panel / discovery hints (Swipe-to-unlock spec)
    List<String> cuisines = const [],
    List<String> skillLevels = const [],
    List<String> equipmentPreferences = const [],
    int? maxMinutes,
    int? maxCalories,
    int? pantryMissingAllowed,
    String? customPreferences,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception('Kitchen is closed: GEMINI_API_KEY missing in .env');
    }

    final userPrompt = _buildPreviewPrompt(
      pantryItems: pantryItems,
      allergies: allergies,
      dietaryRestrictions: dietaryRestrictions,
      cravings: cravings,
      energyLevel: energyLevel,
      mealType: mealType,
      strictPantryMatch: strictPantryMatch,
      preferredCuisines: preferredCuisines,
      cuisines: cuisines,
      skillLevels: skillLevels,
      equipmentPreferences: equipmentPreferences,
      maxMinutes: maxMinutes,
      maxCalories: maxCalories,
      pantryMissingAllowed: pantryMissingAllowed,
      customPreferences: customPreferences,
    );

    final response = await _callGemini(
      userPrompt,
      model: _previewModel,
      systemPrompt: _systemPromptPreview,
    );

    return RecipePreview.fromJson(response).copyWith(
      energyLevel: energyLevel,
      mealType: mealType ?? response['meal_type'] ?? 'dinner',
    );
  }

  /// PHASE 1B: Generate multiple lightweight previews in one call.
  /// Used by Swipe deck to avoid bursting many concurrent requests.
  Future<List<RecipePreview>> generateRecipePreviewsBatch({
    required int count,
    required List<String> pantryItems,
    required List<String> allergies,
    required List<String> dietaryRestrictions,
    required String cravings,
    required int energyLevel,
    List<String> preferredCuisines = const [],
    String? mealType,
    bool strictPantryMatch = true,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception('Kitchen is closed: GEMINI_API_KEY missing in .env');
    }

    final userPrompt = _buildPreviewBatchPrompt(
      count: count,
      pantryItems: pantryItems,
      allergies: allergies,
      dietaryRestrictions: dietaryRestrictions,
      cravings: cravings,
      energyLevel: energyLevel,
      mealType: mealType,
      strictPantryMatch: strictPantryMatch,
      preferredCuisines: preferredCuisines,
    );

    final response = await _callGemini(
      userPrompt,
      model: _previewModel,
      systemPrompt: _systemPromptPreview,
    );

    // Expected format: { "previews": [ {preview json}, ... ] }
    final rawList = response['previews'];
    if (rawList is List) {
      return rawList
          .whereType<Map>()
          .map((m) => RecipePreview.fromJson(Map<String, dynamic>.from(m)))
          .map(
            (p) => p.copyWith(
              energyLevel: energyLevel,
              mealType: mealType ?? p.mealType,
            ),
          )
          .toList();
    }

    // Fallback: if model returned a single preview JSON.
    return [
      RecipePreview.fromJson(response).copyWith(
        energyLevel: energyLevel,
        mealType: mealType ?? response['meal_type'] ?? 'dinner',
      ),
    ];
  }

  /// PHASE 2: Generate full recipe from preview (deep thinking)
  Future<Recipe> generateFullRecipe({
    required RecipePreview preview,
    required List<String> pantryItems,
    required List<String> allergies,
    required List<String> dietaryRestrictions,
    required bool showCalories,
    bool strictPantryMatch = true,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception('Kitchen is closed: GEMINI_API_KEY missing in .env');
    }

    final userPrompt = _buildFullRecipePrompt(
      preview: preview,
      pantryItems: pantryItems,
      allergies: allergies,
      dietaryRestrictions: dietaryRestrictions,
      strictPantryMatch: strictPantryMatch,
    );

    final response = await _callGemini(
      userPrompt,
      model: _fullRecipeModel,
      systemPrompt: _systemPromptFullRecipe,
    );

    return _mapJsonToRecipe(
      response,
      preview.energyLevel,
      showCalories,
      existingImageUrl: preview.imageUrl,
      forcedId: preview.id,
      fallbackEquipment: preview.equipmentIcons,
      fallbackIngredientIds: preview.ingredients.isNotEmpty
          ? preview.ingredients
          : preview.mainIngredients,
    );
  }

  /// Legacy: Generate complete recipe in one step (for AI Hub flow)
  Future<Recipe> generateRecipe({
    required List<String> pantryItems,
    required List<String> allergies,
    required List<String> dietaryRestrictions,
    required String cravings,
    required int energyLevel,
    required bool showCalories,
    List<String> preferredCuisines = const [],
    String? mealType,
    bool strictPantryMatch = true,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception('Kitchen is closed: GEMINI_API_KEY missing in .env');
    }

    final userPrompt = _buildGenerationPrompt(
      pantryItems: pantryItems,
      allergies: allergies,
      dietaryRestrictions: dietaryRestrictions,
      cravings: cravings,
      energyLevel: energyLevel,
      mealType: mealType,
      strictPantryMatch: strictPantryMatch,
    );

    final response = await _callGemini(
      userPrompt,
      model: _fullRecipeModel,
      systemPrompt: _systemPromptFullRecipe,
    );

    return _mapJsonToRecipe(response, energyLevel, showCalories);
  }

  /// REFINE: Recipe refinement
  Future<Recipe> refineRecipe({
    required Recipe originalRecipe,
    required String refinementText,
    required bool showCalories,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception('Kitchen is closed: GEMINI_API_KEY missing in .env');
    }

    final userPrompt = _buildRefinementPrompt(
      originalRecipe: originalRecipe,
      refinementText: refinementText,
    );

    final response = await _callGemini(
      userPrompt,
      model: _fullRecipeModel,
      systemPrompt: _systemPromptFullRecipe,
    );

    return _mapJsonToRecipe(
      response,
      originalRecipe.energyLevel,
      showCalories,
      existingImageUrl: originalRecipe.imageUrl,
    );
  }

  /// Make API call to Google Gemini
  Future<Map<String, dynamic>> _callGemini(
    String userPrompt, {
    required String model,
    required String systemPrompt,
  }) async {
    if (kDebugMode) {
      debugPrint('AI Chef using model: $model');
    }

    final url = Uri.parse('$_baseUrl/$model:generateContent?key=$_apiKey');
    final body = {
      'contents': [
        {
          'parts': [
            {'text': userPrompt},
          ],
        },
      ],
      'system_instruction': {
        'parts': [
          {'text': systemPrompt},
        ],
      },
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': 8192,
        'response_mime_type': 'application/json',
      },
    };

    const maxRetries = 2;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      var acquiredPermit = false;
      try {
        await _acquireGeminiPermit();
        acquiredPermit = true;

        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        );

        if (response.statusCode != 200) {
          String errorMessage = 'Unknown error';
          try {
            final errorBody = jsonDecode(response.body);
            errorMessage =
                errorBody['error']?['message']?.toString() ?? errorMessage;
          } catch (_) {
            // ignore parse errors
          }

          if (response.statusCode == 429 && attempt < maxRetries) {
            _onStatus?.call('The Chef is preparing more ideas... one moment!');
            final seconds = Random().nextInt(3) + 2;
            await Future.delayed(Duration(seconds: seconds));
            continue;
          }

          // DEBUG: If 404, check available models
          if (response.statusCode == 404) {
            await _debugPrintAvailableModels();
          }

          if (response.statusCode == 429) {
            throw Exception(
              'The Chef is preparing more ideas... one moment! (Rate limited)',
            );
          }

          throw Exception('AI Error (${response.statusCode}): $errorMessage');
        }

        final responseBody = jsonDecode(response.body);
        final candidates = responseBody['candidates'] as List?;

        if (candidates == null || candidates.isEmpty) {
          throw Exception('Chef returned no recipes. The kitchen is empty.');
        }

        final contentParts = candidates[0]['content']?['parts'] as List?;
        final textContent = contentParts?[0]?['text'] as String?;

        if (textContent == null) {
          throw Exception('Chef returned an empty plate.');
        }

        // 1. Sanitize: Remove markdown backticks
        var cleanJson = textContent
            .replaceAll(RegExp(r'^```json\s*'), '')
            .replaceAll(RegExp(r'^```\s*'), '')
            .replaceAll(RegExp(r'\s*```$'), '')
            .trim();

        // 2. Extract: Find the first '{' and last '}' to ignore preamble/postscript
        final startIndex = cleanJson.indexOf('{');
        final endIndex = cleanJson.lastIndexOf('}');

        if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
          cleanJson = cleanJson.substring(startIndex, endIndex + 1);
        }

        try {
          return jsonDecode(cleanJson) as Map<String, dynamic>;
        } catch (e) {
          if (kDebugMode) {
            debugPrint('JSON parse error. Raw content:\n$cleanJson\n');
          }
          throw FormatException('Failed to parse recipe: $e');
        }
      } on http.ClientException catch (e) {
        throw Exception('Network Error: $e');
      } finally {
        if (acquiredPermit) {
          _releaseGeminiPermit();
        }
      }
    }

    throw Exception('Unexpected Error: exhausted retries');
  }

  /// DEBUG: Fetch and print available models
  Future<void> _debugPrintAvailableModels() async {
    try {
      if (kDebugMode) {
        debugPrint('Debugging: Fetching available models for this API key...');
      }
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models?key=$_apiKey',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = (data['models'] as List?)
            ?.map((m) => m['name'])
            .toList();
        if (kDebugMode) {
          debugPrint('AVAILABLE GEMINI MODELS:');
          models?.forEach((m) => debugPrint('  - $m'));
        }
      } else {
        if (kDebugMode) {
          debugPrint(
            'Failed to list models: ${response.statusCode} ${response.body}',
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to debug models: $e');
      }
    }
  }

  /// Build preview generation prompt
  String _buildPreviewPrompt({
    required List<String> pantryItems,
    required List<String> allergies,
    required List<String> dietaryRestrictions,
    required String cravings,
    required int energyLevel,
    String? mealType,
    bool strictPantryMatch = true,
    List<String> preferredCuisines = const [],
    List<String> cuisines = const [],
    List<String> skillLevels = const [],
    List<String> equipmentPreferences = const [],
    int? maxMinutes,
    int? maxCalories,
    int? pantryMissingAllowed,
    String? customPreferences,
  }) {
    final pantryRule = strictPantryMatch
        ? 'CRITICAL: Use ONLY these pantry ingredients: [${pantryItems.join(', ')}].'
        : 'Prioritize: [${pantryItems.join(', ')}], may add 1-2 common staples.';

    final effectiveCuisine = cuisines.isNotEmpty
        ? cuisines.join(', ')
        : (preferredCuisines.isNotEmpty ? preferredCuisines.join(', ') : 'Any');

    final pantryFlexNote = pantryMissingAllowed == null
        ? ''
        : 'Pantry flexibility: you may include up to $pantryMissingAllowed missing ingredients (common items).';

    final filterBlock =
        '''
  FILTER PANEL (SECOND PRIORITY):
  - Meal Type: ${mealType ?? 'Any'}
  - Cuisine: $effectiveCuisine
  - Skill Level: ${skillLevels.isNotEmpty ? skillLevels.join(', ') : 'Any'}
  - Equipment available/preferred: ${equipmentPreferences.isNotEmpty ? equipmentPreferences.join(', ') : 'Any'}
  - Max time: ${maxMinutes != null ? '$maxMinutes minutes' : 'Any'}
  - Max calories: ${maxCalories != null ? maxCalories.toString() : 'Any'}
  $pantryFlexNote
  ''';

    final customBlock =
        '''
  CUSTOM PREFERENCES (THIRD PRIORITY):
  - ${customPreferences != null && customPreferences.trim().isNotEmpty ? customPreferences.trim() : 'None'}
  ''';

    return '''
  $pantryRule

  $filterBlock

  $customBlock

Create a recipe PREVIEW (not full recipe) for:
- Cravings: ${cravings.isNotEmpty ? cravings : 'Surprise me!'}
- Allergies to AVOID: ${allergies.isNotEmpty ? allergies.join(', ') : 'None'}
- Dietary: ${dietaryRestrictions.isNotEmpty ? dietaryRestrictions.join(', ') : 'None'}
- Energy Level: $energyLevel/3 (0=ready-made, 3=elaborate)

  Return ONLY the JSON fields exactly as specified in the system format.
  IMPORTANT: "ingredients" MUST be a list of ingredient names with NO quantities.
''';
  }

  String _buildPreviewBatchPrompt({
    required int count,
    required List<String> pantryItems,
    required List<String> allergies,
    required List<String> dietaryRestrictions,
    required String cravings,
    required int energyLevel,
    String? mealType,
    bool strictPantryMatch = true,
    List<String> preferredCuisines = const [],
  }) {
    final pantryRule = strictPantryMatch
        ? 'CRITICAL: Use ONLY these pantry ingredients: [${pantryItems.join(', ')}].'
        : 'Prioritize: [${pantryItems.join(', ')}], may add 1-2 common staples.';

    final cuisineNote = preferredCuisines.isNotEmpty
        ? 'Preferred cuisines: ${preferredCuisines.join(', ')}'
        : 'Preferred cuisines: Any';

    return '''
$pantryRule

$cuisineNote
Meal Type: ${mealType ?? 'Any'}

Generate EXACTLY $count DISTINCT recipe previews.

Return JSON with this exact format:
{
  "previews": [
    {
      "title": "Recipe Name",
      "vibe_description": "Brief enticing description of the dish vibe",
      "ingredients": ["ingredient 1", "ingredient 2"],
      "estimated_time_minutes": 25,
      "calories": 450,
      "equipment_icons": ["pan", "pot"],
      "meal_type": "dinner",
      "cuisine": "italian",
      "skill_level": "beginner",
      "energy_level": 2
    }
  ]
}

Rules:
- No quantities in "ingredients".
- Titles must be unique.

Context:
- Cravings: ${cravings.isNotEmpty ? cravings : 'Surprise me!'}
- Allergies to AVOID: ${allergies.isNotEmpty ? allergies.join(', ') : 'None'}
- Dietary: ${dietaryRestrictions.isNotEmpty ? dietaryRestrictions.join(', ') : 'None'}
        - Energy Level: ${EnergyLevel.fromInt(energyLevel).promptLine}
''';
  }

  /// Build full recipe prompt from preview
  String _buildFullRecipePrompt({
    required RecipePreview preview,
    required List<String> pantryItems,
    required List<String> allergies,
    required List<String> dietaryRestrictions,
    bool strictPantryMatch = true,
  }) {
    final pantryRule = strictPantryMatch
        ? 'CRITICAL: Use ONLY these pantry ingredients: [${pantryItems.join(', ')}].'
        : 'Prioritize: [${pantryItems.join(', ')}], may add 1-2 common staples.';

    return '''
$pantryRule

Expand this recipe preview into a FULL professional recipe:
- Title: ${preview.title}
- Vibe: ${preview.vibeDescription}
- Main Ingredients: ${preview.mainIngredients.join(', ')}
- Target Time: ~${preview.estimatedTimeMinutes} minutes
- Energy Level: ${EnergyLevel.fromInt(preview.energyLevel).promptScale}

Allergies to AVOID: ${allergies.isNotEmpty ? allergies.join(', ') : 'None'}
Dietary: ${dietaryRestrictions.isNotEmpty ? dietaryRestrictions.join(', ') : 'None'}

Provide complete ingredients with amounts, detailed step-by-step instructions with temperatures,
and accurate calorie estimate. Make it Michelin-star quality.
''';
  }

  /// Build the generation prompt (legacy single-step)
  String _buildGenerationPrompt({
    required List<String> pantryItems,
    required List<String> allergies,
    required List<String> dietaryRestrictions,
    required String cravings,
    required int energyLevel,
    String? mealType,
    bool strictPantryMatch = true,
  }) {
    final pantryRule = strictPantryMatch
        ? 'CRITICAL RULE: Use ONLY these pantry ingredients: [${pantryItems.join(', ')}]. Do NOT add any other ingredients except water, salt, pepper, and oil.'
        : 'Prioritize ingredients from this list: [${pantryItems.join(', ')}], but you may add up to 2 common pantry staples (like onions, garlic, or butter) if it significantly improves the recipe.';

    return '''
$pantryRule

PREFERENCES:
- Cravings: ${cravings.isNotEmpty ? cravings : 'Surprise me!'}
- Allergies to AVOID: ${allergies.isNotEmpty ? allergies.join(', ') : 'None'}
- Dietary Restrictions: ${dietaryRestrictions.isNotEmpty ? dietaryRestrictions.join(', ') : 'None'}
- Meal Type: ${mealType ?? 'Any'}
    - Energy Level: ${EnergyLevel.fromInt(energyLevel).promptLine}
''';
  }

  /// Build the refinement prompt
  String _buildRefinementPrompt({
    required Recipe originalRecipe,
    required String refinementText,
  }) {
    return '''
Refine this existing recipe based on user feedback:

CURRENT RECIPE:
${jsonEncode({'title': originalRecipe.title, 'description': originalRecipe.description, 'ingredients': originalRecipe.ingredients, 'instructions': originalRecipe.instructions, 'timeMinutes': originalRecipe.timeMinutes, 'calories': originalRecipe.calories})}

USER REQUEST: $refinementText

Return an updated JSON version of this recipe incorporating the user's request.
Keep the title similar unless specifically asked to change it.
''';
  }

  /// Map parsed JSON to Recipe model
  Recipe _mapJsonToRecipe(
    Map<String, dynamic> data,
    int energy,
    bool showCals, {
    String? existingImageUrl,
    String? forcedId,
    List<String>? fallbackEquipment,
    List<String>? fallbackIngredientIds,
  }) {
    final rawEquipment = data['equipment'];
    final equipment = rawEquipment is List
        ? rawEquipment.map((e) => e.toString()).toList()
        : (fallbackEquipment ?? const <String>[]);

    final ingredients = List<String>.from(data['ingredients'] ?? []);
    final ingredientIds = (fallbackIngredientIds ?? const <String>[])
        .map((e) => e.toString().toLowerCase().trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return Recipe(
      id: forcedId ?? 'ai_${DateTime.now().millisecondsSinceEpoch}',
      title: data['title'] ?? 'Chef\'s Special',
      description: data['description'] ?? '',
      imageUrl:
          existingImageUrl ??
          'https://images.unsplash.com/photo-1737032571846-445ec57a41da?q=80',
      ingredients: ingredients,
      instructions: List<String>.from(data['instructions'] ?? []),
      timeMinutes: data['timeMinutes'] ?? 15,
      calories: showCals ? (data['calories'] ?? 0) : 0,
      equipment: equipment,
      energyLevel: energy,
      ingredientIds: ingredientIds,
    );
  }
}
