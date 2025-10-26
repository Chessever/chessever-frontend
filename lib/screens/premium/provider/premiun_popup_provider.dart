import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class PremiumPopupNotifier extends StateNotifier<PremiumPopupState> {
  PremiumPopupNotifier() : super(const PremiumPopupState());

  /// Show the premium popup
  void show({bool isDismissible = true}) {
    state = state.copyWith(
      isVisible: true,
      isDismissible: isDismissible,
    );
  }

  /// Hide the premium popup
  void hide() {
    state = state.copyWith(isVisible: false);
  }

  /// Toggle popup visibility
  void toggle() {
    state = state.copyWith(isVisible: !state.isVisible);
  }
}

// ============================================================================
// PROVIDERS
// ============================================================================

/// Main premium popup provider
final premiumPopupProvider =
    StateNotifierProvider<PremiumPopupNotifier, PremiumPopupState>(
      (ref) => PremiumPopupNotifier(),
    );

/// Convenient provider to check if popup is visible
final isPremiumPopupVisibleProvider = Provider<bool>((ref) {
  final popupState = ref.watch(premiumPopupProvider);
  return popupState.isVisible;
});

@immutable
class PremiumPopupState {
  const PremiumPopupState({
    this.isVisible = false,
    this.title,
    this.description,
    this.isDismissible = true,
  });

  final bool isVisible;
  final String? title;
  final String? description;
  final bool isDismissible;

  PremiumPopupState copyWith({
    bool? isVisible,
    String? title,
    String? description,
    bool? isDismissible,
  }) {
    return PremiumPopupState(
      isVisible: isVisible ?? this.isVisible,
      title: title ?? this.title,
      description: description ?? this.description,
      isDismissible: isDismissible ?? this.isDismissible,
    );
  }
}
