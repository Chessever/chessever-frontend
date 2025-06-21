import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/theme/app_theme.dart';
import '../localization/locale_provider.dart';

// Create a model class for language options to ensure type safety
class LanguageOption {
  final String name;
  final Locale locale;
  final bool isAvailable;

  const LanguageOption({
    required this.name,
    required this.locale,
    required this.isAvailable,
  });
}

class LanguageSettingsDialog extends ConsumerWidget {
  const LanguageSettingsDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(localeProvider);

    // Languages that would be supported
    final List<LanguageOption> supportedLanguages = [
      const LanguageOption(
        name: 'English',
        locale: Locale('en'),
        isAvailable: true,
      ),
      const LanguageOption(
        name: 'Deutsch',
        locale: Locale('de'),
        isAvailable: true,
      ),
      const LanguageOption(name: '中文', locale: Locale('zh'), isAvailable: true),
      const LanguageOption(
        name: 'Español',
        locale: Locale('es'),
        isAvailable: true,
      ),
      const LanguageOption(
        name: 'Français',
        locale: Locale('fr'),
        isAvailable: true,
      ),
    ];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 24.0,
        vertical: 24.0,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: kPopUpColor.withOpacity(0.95),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: supportedLanguages.length,
          separatorBuilder:
              (context, index) => const Divider(
                height: 1,
                thickness: 0.5,
                color: Color(0xFF2C2C2E),
              ),
          itemBuilder: (context, index) {
            final language = supportedLanguages[index];
            final isSelected =
                currentLocale.languageCode == language.locale.languageCode;

            return ListTile(
              contentPadding: const EdgeInsets.only(left: 12),
              minLeadingWidth: 40,
              horizontalTitleGap: 4,
              title: Text(
                language.name,
                style: AppTypography.textSmMedium.copyWith(
                  color: isSelected ? kPrimaryColor : kWhiteColor,
                ),
              ),
              trailing:
                  isSelected
                      ? const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: Icon(
                          Icons.check,
                          color: kPrimaryColor,
                          size: 24,
                        ),
                      )
                      : null,
              onTap: () {
                // UI selection - you'll handle the logic later
                ref.read(localeProvider.notifier).setLocale(language.locale);
                Navigator.of(context).pop();
              },
            );
          },
        ),
      ),
    );
  }
}
