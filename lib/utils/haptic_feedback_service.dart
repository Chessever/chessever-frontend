import 'package:flutter/services.dart';

/// A centralized service for managing haptic feedback throughout the app
/// Provides different levels of haptic feedback for various user interactions
class HapticFeedbackService {
  HapticFeedbackService._();

  /// Light haptic feedback for subtle interactions
  /// Use for: hover effects, minor state changes, list item highlights
  static Future<void> light() async {
    await HapticFeedback.lightImpact();
  }

  /// Medium haptic feedback for standard interactions
  /// Use for: button taps, card selections, menu item taps
  static Future<void> medium() async {
    await HapticFeedback.mediumImpact();
  }

  /// Heavy haptic feedback for significant interactions
  /// Use for: important actions, confirmations, major state changes
  static Future<void> heavy() async {
    await HapticFeedback.heavyImpact();
  }

  /// Selection feedback for picker/selector interactions
  /// Use for: dropdown selections, slider changes, segmented controls
  static Future<void> selection() async {
    await HapticFeedback.selectionClick();
  }

  /// Vibration feedback for long press interactions
  /// Use for: context menus, drag operations, important long-press actions
  static Future<void> vibrate() async {
    await HapticFeedback.vibrate();
  }

  // Convenience methods for specific use cases

  /// Haptic for card/list item taps
  static Future<void> cardTap() => light();

  /// Haptic for button presses (very subtle for frequent use)
  static Future<void> buttonPress() => light();

  /// Haptic for navigation actions
  static Future<void> navigation() => light();

  /// Haptic for chess piece moves
  static Future<void> chessPieceMove() => light();

  /// Haptic for successful actions (like capturing a piece)
  static Future<void> success() => medium();

  /// Haptic for toggle switches
  static Future<void> toggle() => selection();

  /// Haptic for dropdown/menu selections
  static Future<void> dropdownSelect() => selection();

  /// Haptic for pin/favorite actions
  static Future<void> pin() => light();

  /// Haptic for long press context menu
  static Future<void> contextMenu() => vibrate();

  /// Haptic for board flip
  static Future<void> boardFlip() => medium();

  /// Haptic for error or invalid action
  static Future<void> error() => heavy();
}
