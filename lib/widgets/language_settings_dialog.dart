import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/blur_background.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/theme/app_theme.dart';
import '../localization/locale_provider.dart';
import '../repository/local_storage/language_repository/language_repository.dart';

class LanguageSettingsDialog extends ConsumerWidget {
  const LanguageSettingsDialog({super.key});

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
            child: BlurBackground(),
          ),
          // Dialog content
          Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.symmetric(
              horizontal: 24.sp,
              vertical: 24.sp,
            ),
            // Prevent dialog from closing when clicking on the dialog itself
            child: GestureDetector(
              onTap: () {}, // Absorb the tap
              child: Container(
                decoration: BoxDecoration(
                  color: kPopUpColor,
                  borderRadius: BorderRadius.circular(12.br),
                  boxShadow: [
                    BoxShadow(
                      color: kDividerColor,
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: languages.length,
                  separatorBuilder: (context, index) => Divider(),
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
                        height: 36.h, // Fixed height of 36px as requested
                        padding: EdgeInsets.all(
                          8.sp,
                        ), // Updated to have 8px padding on all sides
                        alignment: Alignment.centerLeft,
                        child: Text(
                          language.name,
                          style: AppTypography.textXsRegular,
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
