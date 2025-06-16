import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../localization/locale_provider.dart';
import 'settings_card.dart';
import 'settings_dialog.dart';
import 'settings_item.dart';

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
        name: 'French',
        locale: Locale('fr'),
        isAvailable: false,
      ),
      const LanguageOption(
        name: 'German',
        locale: Locale('de'),
        isAvailable: false,
      ),
      const LanguageOption(
        name: 'Spanish',
        locale: Locale('es'),
        isAvailable: false,
      ),
      const LanguageOption(
        name: 'Italian',
        locale: Locale('it'),
        isAvailable: false,
      ),
      const LanguageOption(
        name: 'Russian',
        locale: Locale('ru'),
        isAvailable: false,
      ),
      const LanguageOption(
        name: 'Chinese',
        locale: Locale('zh'),
        isAvailable: false,
      ),
    ];

    return SettingsDialog(
      title: 'Language',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SettingsCard(
            children:
                supportedLanguages.map((language) {
                  final isSelected =
                      currentLocale.languageCode ==
                      language.locale.languageCode;

                  return SettingsItem(
                    icon: _getLanguageIcon(language.locale),
                    title: language.name,
                    trailing:
                        language.isAvailable
                            ? (isSelected
                                ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.cyan,
                                  size: 20,
                                )
                                : null)
                            : const Text(
                              'Coming soon',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                    onTap:
                        language.isAvailable
                            ? () {
                              ref
                                  .read(localeProvider.notifier)
                                  .setLocale(language.locale);
                              Navigator.of(context).pop();
                            }
                            : null,
                    showDivider: language != supportedLanguages.last,
                  );
                }).toList(),
          ),

          const SizedBox(height: 16),

          // Button to close dialog without changing language
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.grey),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Cancel', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to get appropriate icon for each language
  IconData _getLanguageIcon(Locale locale) {
    switch (locale.languageCode) {
      case 'en':
        return Icons.language;
      case 'fr':
        return Icons.language;
      case 'de':
        return Icons.language;
      case 'es':
        return Icons.language;
      case 'it':
        return Icons.language;
      case 'ru':
        return Icons.language;
      case 'zh':
        return Icons.language;
      default:
        return Icons.language;
    }
  }
}
