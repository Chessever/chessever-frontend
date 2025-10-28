import 'package:chessever2/main.dart';
import 'package:chessever2/screens/premium/premium_screen.dart';
import 'package:chessever2/screens/premium/provider/premiun_popup_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class PremiumPopupListener extends ConsumerStatefulWidget {
  const PremiumPopupListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PremiumPopupListener> createState() =>
      _PremiumPopupListenerState();
}

class _PremiumPopupListenerState extends ConsumerState<PremiumPopupListener> {
  bool _isBottomSheetOpen = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<PremiumPopupState>(premiumPopupProvider, (previous, next) {
      final currentContext = navigatorKey.currentState?.context;
      if (currentContext == null) return;

      if (next.isVisible && !_isBottomSheetOpen) {
        _isBottomSheetOpen = true;
        // Show popup when state becomes visible
        showModalBottomSheet(
          context: currentContext,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          barrierColor: kWhiteColor.withOpacity(0.5),
          builder: (_) => const PremiumScreen(),
        ).then((_) {
          _isBottomSheetOpen = false;
          ref.read(premiumPopupProvider.notifier).hide();
        });
      } else if (!next.isVisible && _isBottomSheetOpen) {
        Navigator.pop(currentContext);
        _isBottomSheetOpen = false;
      }
    });

    return widget.child;
  }
}
