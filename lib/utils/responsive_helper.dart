import 'package:flutter/material.dart';
import 'dart:math';

class ResponsiveHelper {
  // Base design dimensions
  static const double baseWidth = 393.0;
  static const double baseHeight = 852.0;

  // Tablet layout constraints
  static const double tabletContentMaxWidth = 1200.0;
  static const double tabletSplitMasterMinWidth = 320.0;
  static const double tabletSplitDetailMinWidth = 400.0;

  static late double _screenWidth;
  static late double _screenHeight;
  static late double _scaleWidth;
  static late double _scaleHeight;
  static late DeviceType _deviceType;
  static late Orientation _orientation;

  static void init(BuildContext context) {
    final size = MediaQuery.of(context).size;
    _screenWidth = size.width;
    _screenHeight = size.height;
    _orientation = MediaQuery.of(context).orientation;

    // Calculate scale factors
    _scaleWidth = _screenWidth / baseWidth;
    _scaleHeight = _screenHeight / baseHeight;

    // Determine device type
    _deviceType = _getDeviceType();
  }

  static DeviceType _getDeviceType() {
    final diagonal = sqrt(pow(_screenWidth, 2) + pow(_screenHeight, 2));
    final aspectRatio = _screenWidth / _screenHeight;

    // iPad/Tablet detection (larger diagonal, different aspect ratio)
    if (diagonal > 1100 || (_screenWidth > 600 && aspectRatio > 0.6)) {
      return DeviceType.tablet;
    }
    // Phone detection
    else if (_screenWidth < 600) {
      return DeviceType.phone;
    }
    // Default to tablet for edge cases
    else {
      return DeviceType.tablet;
    }
  }

  // Scale width based on device type
  static double width(double size) {
    switch (_deviceType) {
      case DeviceType.phone:
        return size * _scaleWidth;
      case DeviceType.tablet:
        // For tablets, use a more conservative scaling to prevent oversized elements
        return size * min(_scaleWidth, 1.5);
    }
  }

  // Scale height based on device type
  static double height(double size) {
    switch (_deviceType) {
      case DeviceType.phone:
        return size * _scaleHeight;
      case DeviceType.tablet:
        // For tablets, use a more conservative scaling
        return size * min(_scaleHeight, 1.5);
    }
  }

  // Font scaling with device-specific multipliers
  static double font(double size) {
    double scaledSize;

    switch (_deviceType) {
      case DeviceType.phone:
        // For phones, scale normally but with limits
        scaledSize = size * min(_scaleWidth, _scaleHeight);
        break;
      case DeviceType.tablet:
        // For tablets, increase font size but not linearly
        scaledSize = size * (1 + (min(_scaleWidth, _scaleHeight) - 1) * 0.7);
        break;
    }

    // Ensure minimum readable size and maximum reasonable size
    return scaledSize.clamp(10.0, 40.0);
  }

  // Padding/margin scaling
  static double spacing(double size) {
    switch (_deviceType) {
      case DeviceType.phone:
        return size * min(_scaleWidth, _scaleHeight);
      case DeviceType.tablet:
        // More generous spacing on tablets
        return size * min(_scaleWidth, _scaleHeight) * 1.2;
    }
  }

  // Icon scaling
  static double icon(double size) {
    switch (_deviceType) {
      case DeviceType.phone:
        return size * min(_scaleWidth, _scaleHeight);
      case DeviceType.tablet:
        return size * min(_scaleWidth, _scaleHeight) * 1.1;
    }
  }

  // Border radius scaling
  static double borderRadius(double size) {
    switch (_deviceType) {
      case DeviceType.phone:
        return size * min(_scaleWidth, _scaleHeight);
      case DeviceType.tablet:
        // Slightly more pronounced border radius on tablets for better visual appeal
        return size * min(_scaleWidth, _scaleHeight) * 1.15;
    }
  }

  // Getters for device info
  static DeviceType get deviceType => _deviceType;

  static double get screenWidth => _screenWidth;

  static double get screenHeight => _screenHeight;

  static bool get isPhone => _deviceType == DeviceType.phone;

  static bool get isTablet => _deviceType == DeviceType.tablet;

  // Orientation getters
  static bool get isLandscape => _orientation == Orientation.landscape;

  static bool get isPortrait => _orientation == Orientation.portrait;

  static Orientation get orientation => _orientation;

  // Tablet-specific layout helpers

  /// Returns true if the screen is wide enough for a split-view layout
  /// (master-detail pattern). Typically used in tablet landscape mode.
  static bool get shouldUseSplitView =>
      isTablet &&
      isLandscape &&
      _screenWidth >= (tabletSplitMasterMinWidth + tabletSplitDetailMinWidth);

  /// Returns the recommended number of grid columns for tablet layouts
  /// based on current orientation and screen width.
  /// Max 3 columns to keep content readable
  static int get tabletGridColumns {
    if (!isTablet) return 1;
    if (isLandscape) {
      // Max 3 columns for readability
      if (_screenWidth >= 900) return 3;
      return 2;
    } else {
      // Portrait - max 2 columns
      return 2;
    }
  }

  /// Returns appropriate grid cross-axis count for content lists
  /// (games, events, players, etc.)
  static int getGridCrossAxisCount({int phoneCount = 1}) {
    if (!isTablet) return phoneCount;
    return tabletGridColumns;
  }

  /// Returns max width constraint for content on tablets to prevent
  /// content from stretching too wide on large screens.
  static double get contentMaxWidth {
    if (!isTablet) return double.infinity;
    return tabletContentMaxWidth;
  }

  /// Returns horizontal padding for tablet to center content
  static double get tabletHorizontalPadding {
    if (!isTablet) return 0;
    final excessWidth = _screenWidth - tabletContentMaxWidth;
    return excessWidth > 0 ? excessWidth / 2 : 24.0;
  }

  /// Returns the master panel flex ratio for split-view layouts
  static int get splitViewMasterFlex => 2;

  /// Returns the detail panel flex ratio for split-view layouts
  static int get splitViewDetailFlex => 3;

  /// Returns an adaptive value based on device type
  /// Example: ResponsiveHelper.adaptive(phone: 16.0, tablet: 24.0)
  static T adaptive<T>({required T phone, required T tablet}) {
    return isTablet ? tablet : phone;
  }

  /// Returns an adaptive value based on device and orientation
  static T adaptiveOrientation<T>({
    required T phonePortrait,
    T? phoneLandscape,
    required T tabletPortrait,
    required T tabletLandscape,
  }) {
    if (isTablet) {
      return isLandscape ? tabletLandscape : tabletPortrait;
    }
    return isLandscape ? (phoneLandscape ?? phonePortrait) : phonePortrait;
  }

  /// Returns appropriate card width for grid layouts
  static double getCardWidth({double phoneWidth = double.infinity}) {
    if (!isTablet) return phoneWidth;
    // Calculate card width based on grid columns and spacing
    final availableWidth = min(_screenWidth, tabletContentMaxWidth);
    final spacing = 16.0 * (tabletGridColumns - 1);
    final padding = 32.0; // 16 on each side
    return (availableWidth - spacing - padding) / tabletGridColumns;
  }

  /// Returns appropriate aspect ratio for cards on tablets
  static double getCardAspectRatio({double phoneRatio = 1.0}) {
    if (!isTablet) return phoneRatio;
    // Slightly wider cards on tablet for better visual balance
    return phoneRatio * 1.1;
  }

  /// Returns BoxConstraints for bottom sheets on tablets.
  /// On tablets, sheets are constrained to a max width for better UX.
  /// On phones, no constraints are applied (full width).
  static BoxConstraints? get bottomSheetConstraints {
    if (!isTablet) return null;
    return const BoxConstraints(maxWidth: 500);
  }

  /// Returns the max width for bottom sheets on tablets (500px).
  /// Returns double.infinity on phones.
  static double get bottomSheetMaxWidth {
    return isTablet ? 500.0 : double.infinity;
  }
}

enum DeviceType {
  phone, // iPhone, Android phones
  tablet, // iPad, Android tablets
}

// Extension for easier usage
extension ResponsiveExtension on num {
  //for width
  double get w => ResponsiveHelper.width(toDouble());

  //for height
  double get h => ResponsiveHelper.height(toDouble());

  //for font Size
  double get f => ResponsiveHelper.font(toDouble());

  //for padding, margin - EdgeInsets
  double get sp => ResponsiveHelper.spacing(toDouble());

  //for icon sizing
  double get ic => ResponsiveHelper.icon(toDouble());

  //for border radius
  double get br => ResponsiveHelper.borderRadius(toDouble());
}
