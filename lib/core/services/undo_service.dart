import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Represents an undoable operation
class UndoableOperation {
  final String id;
  final String description;
  final Future<void> Function() undoAction;
  final DateTime createdAt;
  final Duration timeout;

  UndoableOperation({
    required this.id,
    required this.description,
    required this.undoAction,
    Duration? timeout,
  }) : createdAt = DateTime.now(),
       timeout = timeout ?? const Duration(seconds: 5);

  bool get isExpired => DateTime.now().difference(createdAt) > timeout;
}

/// Service for managing undo operations on critical actions
class UndoService extends StateNotifier<UndoableOperation?> {
  Timer? _expirationTimer;

  UndoService() : super(null);

  /// Register an undoable operation and show snackbar
  void registerUndo({
    required String id,
    required String description,
    required Future<void> Function() undoAction,
    required BuildContext context,
    Duration timeout = const Duration(seconds: 5),
  }) {
    // Cancel any existing timer
    _expirationTimer?.cancel();

    // Create the operation
    final operation = UndoableOperation(
      id: id,
      description: description,
      undoAction: undoAction,
      timeout: timeout,
    );

    state = operation;

    // Show undo snackbar
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(description),
        duration: timeout,
        action: SnackBarAction(
          label: 'UNDO',
          textColor: Colors.amber,
          onPressed: () => executeUndo(context),
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    // Set expiration timer
    _expirationTimer = Timer(timeout, () {
      if (state?.id == id) {
        state = null;
      }
    });
  }

  /// Execute the undo action
  Future<void> executeUndo(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final operation = state;
    if (operation == null || operation.isExpired) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Undo expired'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      await operation.undoAction();
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: const Text('✓ Action undone'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.green[700],
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to undo: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      state = null;
      _expirationTimer?.cancel();
    }
  }

  /// Clear any pending undo operation
  void clearUndo() {
    _expirationTimer?.cancel();
    state = null;
  }

  @override
  void dispose() {
    _expirationTimer?.cancel();
    super.dispose();
  }
}

/// Provider for the undo service
final undoServiceProvider =
    StateNotifierProvider<UndoService, UndoableOperation?>((ref) {
      return UndoService();
    });
