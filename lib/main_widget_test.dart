import 'package:chessever2/l10n/app_localizations.dart';
import 'package:chessever2/localization/locale_provider.dart';
import 'package:chessever2/main.dart';
import 'package:chessever2/screens/favorites/favorite_screen.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/theme/theme_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  runApp(ProviderScope(child: const MainWidget()));
}

class MainWidget extends ConsumerWidget {
  const MainWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    ///Initializing  Responsive Unit
    ResponsiveHelper.init(context);
    return MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      // builder: DevicePreview.appBuilder,
      debugShowCheckedModeBanner: false,
      title: 'ChessEver',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      navigatorObservers: [routeObserver],
      initialRoute: '/',
      routes: {'/': (context) => const FavoriteScreen()},
    );
  }
}
