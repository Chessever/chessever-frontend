import 'dart:async';

import 'package:chessever2/e2e/e2e_config.dart';
import 'package:chessever2/screens/splash/splash_screen_provider.dart';
import 'package:chessever2/services/deep_link_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  /// Error message to display when initialization fails
  String? _errorMessage;

  /// Whether we're currently retrying
  bool _isRetrying = false;

  @override
  void initState() {
    super.initState();
    // Pre-cache SVGs to improve performance in the app
    unawaited(SvgAsset.preCacheAll(context));
    _runInitialization();
  }

  Future<void> _runInitialization() async {
    if (!mounted) return;

    setState(() {
      _errorMessage = null;
      _isRetrying = false;
    });

    try {
      await ref
          .read(splashScreenProvider)
          .runAuthenticationPreProcessor(context);
      // Navigation happens inside runAuthenticationPreProcessor
      // Remove native splash right before navigating (handled there)
    } on NoNetworkException catch (e) {
      // Remove native splash to show error UI
      FlutterNativeSplash.remove();
      DeepLinkService.notifyAppReady();
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
        });
      }
    } catch (e) {
      // Remove native splash to show error UI
      FlutterNativeSplash.remove();
      DeepLinkService.notifyAppReady();
      if (mounted) {
        setState(() {
          _errorMessage = 'Something went wrong. Please try again.';
        });
      }
    }
  }

  Future<void> _retry() async {
    if (_isRetrying) return;

    setState(() {
      _isRetrying = true;
      _errorMessage = null;
    });

    // Brief delay for visual feedback
    await Future.delayed(const Duration(milliseconds: 300));

    await _runInitialization();

    if (mounted && _errorMessage != null) {
      setState(() {
        _isRetrying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenWrapper(
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Same background as native splash
            Image.asset(
              'assets/launch.webp',
              fit: BoxFit.cover,
              cacheWidth:
                  (MediaQuery.sizeOf(context).width *
                          MediaQuery.devicePixelRatioOf(context))
                      .toInt(),
              cacheHeight:
                  (MediaQuery.sizeOf(context).height *
                          MediaQuery.devicePixelRatioOf(context))
                      .toInt(),
            ),

            // Error UI overlay (only visible when there's an error)
            if (_errorMessage != null)
              Positioned(
                bottom: 80.h,
                left: 24.w,
                right: 24.w,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Error icon
                    Icon(
                      Icons.wifi_off_rounded,
                      color: context.colors.textPrimary.withValues(alpha: 0.7),
                      size: 32.h,
                    ),
                    SizedBox(height: 12.h),
                    // Error message
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.colors.textPrimary.withValues(alpha: 0.8),
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    SizedBox(height: 20.h),
                    // Retry button
                    SizedBox(
                      width: 160.w,
                      height: 44.h,
                      child: ElevatedButton(
                        onPressed: _isRetrying ? null : _retry,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryColor,
                          foregroundColor: kWhiteColor,
                          disabledBackgroundColor: kPrimaryColor.withOpacity(
                            0.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child:
                            _isRetrying
                                ? SizedBox(
                                  width: 20.w,
                                  height: 20.h,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: context.colors.textPrimary.withValues(alpha: 0.8),
                                  ),
                                )
                                : Text(
                                  'Retry',
                                  style: TextStyle(
                                    fontSize: 15.sp,
                                    fontWeight: FontWeight.w600,
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
