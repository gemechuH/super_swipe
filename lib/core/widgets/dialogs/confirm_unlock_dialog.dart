import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:super_swipe/core/models/recipe_preview.dart';
import 'package:super_swipe/core/theme/app_theme.dart';
import 'package:super_swipe/core/widgets/loading/app_loading.dart';

/// Reusable dialog for confirming recipe unlock with carrot spend.
/// Shows recipe preview, carrot balance, and unlock/cancel actions.
/// Includes a "Do not show again" option persisted by the caller.
class ConfirmUnlockDialog extends StatefulWidget {
  final RecipePreview preview;
  final int currentCarrots;
  final int maxCarrots;
  final VoidCallback onCancel;
  final VoidCallback onUnlock;
  final ValueChanged<bool>? onDoNotShowAgainChanged;
  final bool initialDoNotShowAgain;
  final bool isLoading;

  const ConfirmUnlockDialog({
    super.key,
    required this.preview,
    required this.currentCarrots,
    required this.maxCarrots,
    required this.onCancel,
    required this.onUnlock,
    this.onDoNotShowAgainChanged,
    this.initialDoNotShowAgain = false,
    this.isLoading = false,
  });

  @override
  State<ConfirmUnlockDialog> createState() => _ConfirmUnlockDialogState();
}

class _ConfirmUnlockDialogState extends State<ConfirmUnlockDialog> {
  late bool _doNotShowAgain;

  @override
  void initState() {
    super.initState();
    _doNotShowAgain = widget.initialDoNotShowAgain;
  }

  @override
  Widget build(BuildContext context) {
    final hasCarrots = widget.currentCarrots > 0;
    final maxDialogHeight = MediaQuery.of(context).size.height * 0.85;

    final headerGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        AppTheme.primaryColor.withValues(alpha: 0.95),
        AppTheme.primaryColor.withValues(alpha: 0.75),
      ],
    );

    final cardBg = hasCarrots
        ? const Color(0xFFFFF6EB)
        : const Color(0xFFFFECEC);
    final cardBorder = hasCarrots
        ? const Color(0xFFFFD8A8)
        : const Color(0xFFFFBDBD);
    final accent = hasCarrots
        ? const Color(0xFFB45309)
        : const Color(0xFFB91C1C);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Container(
        constraints: BoxConstraints(maxWidth: 400, maxHeight: maxDialogHeight),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with gradient
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              decoration: BoxDecoration(
                gradient: headerGradient,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    child: const Center(
                      child: Text('🥕', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Unlock Recipe',
                    style: GoogleFonts.dmSerifDisplay(
                      fontSize: 20,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Recipe title
                    Text(
                      widget.preview.title,
                      style: GoogleFonts.dmSerifDisplay(
                        fontSize: 22,
                        height: 1.1,
                        color: const Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Unlock prompt
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cardBorder),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: cardBorder),
                                ),
                                child: Center(
                                  child: Text(
                                    '🥕',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: accent,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  hasCarrots
                                      ? 'Unlock for 1 carrot'
                                      : 'No carrots remaining',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: accent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            hasCarrots
                                ? 'Confirm to unlock full instructions and save this recipe to My Recipes.'
                                : 'Weekly carrots reset automatically. You can try again after the next reset.',
                            textAlign: TextAlign.left,
                            style: GoogleFonts.inter(
                              color: const Color(0xFF374151),
                              height: 1.35,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Carrot balance indicator
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: cardBorder),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  '🥕',
                                  style: TextStyle(fontSize: 16, color: accent),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'This week',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: const Color(0xFF6B7280),
                                    ),
                                  ),
                                ),
                                Text(
                                  '${widget.currentCarrots} / ${widget.maxCarrots}',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: accent,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Do not show again
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: _doNotShowAgain,
                                  onChanged: widget.isLoading
                                      ? null
                                      : (v) {
                                          final next = v ?? false;
                                          setState(
                                            () => _doNotShowAgain = next,
                                          );
                                          widget.onDoNotShowAgainChanged?.call(
                                            next,
                                          );
                                        },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Do not show again',
                                  softWrap: true,
                                  style: GoogleFonts.inter(
                                    color: const Color(0xFF6B7280),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: hasCarrots && !widget.isLoading
                          ? widget.onUnlock
                          : null,
                      icon: widget.isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: AppInlineLoading(
                                size: 18,
                                baseColor: Color(0xFFEFEFEF),
                                highlightColor: Color(0xFFFFFFFF),
                              ),
                            )
                          : const Icon(Icons.lock_rounded, size: 20),
                      label: Text(
                        widget.isLoading ? 'Unlocking…' : 'Unlock',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: hasCarrots
                            ? AppTheme.primaryColor
                            : Colors.grey.shade400,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: widget.isLoading ? null : widget.onCancel,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
