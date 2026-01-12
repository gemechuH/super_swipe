import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:super_swipe/core/providers/firestore_providers.dart';
import 'package:super_swipe/core/providers/user_data_providers.dart';
import 'package:super_swipe/core/widgets/loading/app_loading.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';

/// Test screen to verify Firestore connection
class FirestoreTestScreen extends ConsumerWidget {
  const FirestoreTestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final userProfile = ref.watch(userProfileProvider);
    final pantryItems = ref.watch(pantryItemsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Firestore Connection Test'),
        backgroundColor: Colors.deepPurple,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatusCard(
            title: '🔥 Firestore Status',
            subtitle: 'Checking connection...',
            child: FutureBuilder(
              future: _testFirestoreConnection(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: AppInlineLoading());
                }
                if (snapshot.hasError) {
                  return Text(
                    '❌ Error: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red),
                  );
                }
                return const Text(
                  '✅ Connected successfully!',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          _buildStatusCard(
            title: '👤 Authentication',
            subtitle: authState.isSignedIn
                ? 'Signed in as: ${authState.user?.displayName ?? "Anonymous"}'
                : 'Not signed in',
            child: authState.isSignedIn
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('UID: ${authState.user?.uid}'),
                      Text('Email: ${authState.user?.email ?? "N/A"}'),
                      Text(
                        'Anonymous: ${authState.user?.isAnonymous.toString() ?? "N/A"}',
                      ),
                    ],
                  )
                : const Text('Please sign in to test user profile'),
          ),
          const SizedBox(height: 16),
          _buildStatusCard(
            title: '📁 User Profile',
            subtitle: 'Firestore user document',
            child: userProfile.when(
              data: (profile) {
                if (profile == null) {
                  return const Text('No profile found');
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Name: ${profile.displayName}'),
                    Text('Email: ${profile.email ?? "N/A"}'),
                    Text(
                      'Carrots: ${profile.carrots.current}/${profile.carrots.max}',
                    ),
                    Text('Subscription: ${profile.subscriptionStatus}'),
                    Text('Recipes unlocked: ${profile.stats.recipesUnlocked}'),
                  ],
                );
              },
              loading: () => const Center(child: AppInlineLoading()),
              error: (error, stack) => Text(
                'Error: $error',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildStatusCard(
            title: '🥗 Pantry Items',
            subtitle: 'Firestore pantry sub-collection',
            child: pantryItems.when(
              data: (items) {
                if (items.isEmpty) {
                  return const Text('No pantry items yet. Add some!');
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total items: ${items.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ...items
                        .take(5)
                        .map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '• ${item.name} (${item.quantity} ${item.unit}) [${item.category}]',
                            ),
                          ),
                        ),
                    if (items.length > 5)
                      Text('... and ${items.length - 5} more'),
                  ],
                );
              },
              loading: () => const Center(child: AppInlineLoading()),
              error: (error, stack) => Text(
                'Error: $error',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (authState.isSignedIn)
            ElevatedButton.icon(
              onPressed: () => _testAddPantryItem(ref),
              icon: const Icon(Icons.add),
              label: const Text('Test: Add Sample Pantry Item'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Future<void> _testFirestoreConnection() async {
    // Try to read from Firestore
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc('test_user_123')
        .get();

    if (!doc.exists) {
      throw Exception(
        'Test document not found. Did you create it in Firebase Console?',
      );
    }
  }

  Future<void> _testAddPantryItem(WidgetRef ref) async {
    try {
      final authState = ref.read(authProvider);
      if (authState.user == null) return;

      final pantryService = ref.read(pantryServiceProvider);
      await pantryService.addPantryItem(
        authState.user!.uid,
        'Test Item ${DateTime.now().millisecondsSinceEpoch}',
        quantity: 1,
        category: 'test',
        source: 'manual',
      );

      // debugPrint('✅ Test pantry item added successfully!');
    } catch (e) {
      // debugPrint('❌ Error adding test item: $e');
    }
  }
}
