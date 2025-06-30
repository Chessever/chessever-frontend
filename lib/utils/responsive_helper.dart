import 'package:flutter/material.dart';
import 'dart:math';

class ResponsiveHelper {
  // Base design dimensions
  static const double baseWidth = 393.0;
  static const double baseHeight = 852.0;

  static late double _screenWidth;
  static late double _screenHeight;
  static late double _scaleWidth;
  static late double _scaleHeight;
  static late DeviceType _deviceType;

  static void init(BuildContext context) {
    final size = MediaQuery.of(context).size;
    _screenWidth = size.width;
    _screenHeight = size.height;

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
