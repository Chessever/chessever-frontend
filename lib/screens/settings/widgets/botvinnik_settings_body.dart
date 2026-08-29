import 'package:chessever2/chat/botvinnik_provider.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/screens/settings/widgets/board_settings_body.dart';
import 'package:chessever2/screens/settings/widgets/settings_primitives.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class BotvinnikSettingsBody extends ConsumerWidget {
  const BotvinnikSettingsBody({super.key, required this.trackPersist});

  final TrackPersist trackPersist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(botvinnikEnabledProvider).valueOrNull ?? true;
    final quota = ref.watch(botvinnikQuotaProvider);
    final user = ref.watch(currentUserProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enable Botvinnik',
                      style: AppTypography.textMdMedium.copyWith(
                        color: context.colors.textPrimary,
                        fontSize: 13.f,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Show the chess assistant on the home screen.',
                      style: AppTypography.textSmRegular.copyWith(
                        color: context.colors.textSecondary,
                        fontSize: 11.f,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: enabled,
                onChanged: (value) {
                  trackPersist(
                    ref
                        .read(botvinnikEnabledProvider.notifier)
                        .setEnabled(value),
                  );
                },
              ),
            ],
          ),
        ),
        SizedBox(height: 18.h),
        SettingCard(
          child: Row(
            children: [
              Icon(Icons.data_usage_rounded, color: context.colors.iconPrimary),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Daily messages',
                      style: AppTypography.textMdMedium.copyWith(
                        color: context.colors.textPrimary,
                        fontSize: 13.f,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      user == null || user.isAnonymous
                          ? 'Sign in to view your message allowance.'
                          : quota.when(
                            data:
                                (value) =>
                                    value == null
                                        ? 'Message allowance unavailable.'
                                        : '${value.remaining} of ${value.limit} remaining today${value.isPremium ? ' · Pro' : ''}',
                            loading: () => 'Loading message allowance…',
                            error:
                                (error, stack) =>
                                    'Message allowance unavailable.',
                          ),
                      style: AppTypography.textSmRegular.copyWith(
                        color: context.colors.textSecondary,
                        fontSize: 11.f,
                      ),
                    ),
                  ],
                ),
              ),
              if (user != null && !user.isAnonymous)
                IconButton(
                  tooltip: 'Refresh question count',
                  onPressed:
                      () => ref.read(botvinnikQuotaProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh_rounded),
                ),
            ],
          ),
        ),
        SizedBox(height: 18.h),
        SettingCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Theme.of(context).colorScheme.tertiary,
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(
                  'Botvinnik can make mistakes. Check important information.',
                  style: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textSecondary,
                    fontSize: 11.f,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
