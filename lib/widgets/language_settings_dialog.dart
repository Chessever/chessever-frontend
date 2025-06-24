import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/theme/app_theme.dart';
import '../localization/locale_provider.dart';
import '../repository/local_storage/language_repository/language_repository.dart';

class LanguageSettingsDialog extends ConsumerWidget {
  const LanguageSettingsDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(localeProvider);

    // Get languages from the repository
    final languages = SupportedLanguage.values;

    return GestureDetector(
      // Close the dialog when tapping outside
      onTap: () => Navigator.of(context).pop(),
      child: Stack(
        children: [
          // Backdrop filter for blur effect
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(color: Colors.black.withOpacity(0.3)),
            ),
          ),
          // Dialog content
          Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 24.0,
            ),
            // Prevent dialog from closing when clicking on the dialog itself
            child: GestureDetector(
              onTap: () {}, // Absorb the tap
              child: Container(
                decoration: BoxDecoration(
                  color: kPopUpColor,
                  borderRadius: BorderRadius.circular(12),
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
                  itemCount: languages.length,
                  separatorBuilder:
                      (context, index) => const Divider(
                        height: 1,
                        thickness: 0.5,
                        color: Color(0xFF2C2C2E),
                      ),
                  itemBuilder: (context, index) {
                    final language = languages[index];
                    final isSelected =
                        currentLocale.languageCode ==
                        language.locale.languageCode;

                    return InkWell(
                      onTap: () {
                        ref
                            .read(localeProvider.notifier)
                            .setLocale(language.locale);
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        height: 36, // Fixed height of 36px as requested
                        padding: const EdgeInsets.all(
                          8,
                        ), // Updated to have 8px padding on all sides
                        alignment: Alignment.centerLeft,
                        child: Text(
                          language.name,
                          style: TextStyle(
                            fontFamily: 'InterDisplay',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isSelected ? kPrimaryColor : kWhiteColor,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
