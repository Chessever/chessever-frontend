import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/screens/onboarding/player_selection_screen.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/blur_background.dart';
import 'package:chessever2/widgets/country_dropdown.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final Curve _onboardingSpring = Motion.smoothSpring().toCurve;

class OnboardingFlowScreen extends HookConsumerWidget {
  const OnboardingFlowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageController = usePageController();
    final currentPage = useState(0);
    final countryState = ref.watch(countryDropdownProvider);
    final topPadding = MediaQuery.of(context).padding.top;

    useEffect(() {
      ref.read(countryDropdownProvider);
      return null;
    }, const []);

    Future<void> goToPage(int index) async {
      await pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
      );
    }

    final stepTitles = ['Welcome', 'Country', 'Favorites'];

    return ScreenWrapper(
      child: Scaffold(
        backgroundColor: kBackgroundColor,
        body: SafeArea(
          top: false,
          bottom: false,
          child: Stack(
            children: [
              const Positioned.fill(child: BlurBackground()),
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.04),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                  left: 16.sp,
                  right: 16.sp,
                  top: topPadding + 12.h,
                ),
                child: Column(
                  children: [
                    _FlowHeader(
                      titles: stepTitles,
                      currentIndex: currentPage.value,
                    ),
                  Expanded(
                    child: PageView(
                      controller: pageController,
                      physics: const ClampingScrollPhysics(),
                      onPageChanged: (index) => currentPage.value = index,
                      children: [
                        _WelcomeStep(onNext: () => goToPage(1)),
                        _CountryStep(
                          countryState: countryState,
                          onNext: () => goToPage(2),
                          onRetry: () => ref.invalidate(countryDropdownProvider),
                        ),
                        PlayerSelectionContent(
                          title: 'Follow at least 3 players to get started',
                          subtitle:
                              'Build your feed with the players you love — we started with picks from {country}.',
                          actionLabel: 'Finish setup',
                          badgeLabel: 'Step 3 of 3',
                          onComplete: () => _handleCompletion(context, ref),
                        ),
                      ],
                    ),
                  ),
                    SizedBox(height: 12.h),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _handleCompletion(BuildContext context, WidgetRef ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user != null) {
    await markOnboardingComplete(context, ref);
    return;
  }

  final proceedAsGuest = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => const _AccountChoiceDialog(),
  );

  if (proceedAsGuest == true) {
    await markOnboardingComplete(context, ref);
  } else {
    if (context.mounted) {
      Navigator.pushReplacementNamed(context, '/auth_screen');
    }
  }
}

class _FlowHeader extends StatelessWidget {
  const _FlowHeader({
    required this.titles,
    required this.currentIndex,
  });

  final List<String> titles;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 10.h, bottom: 12.h),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
            decoration: BoxDecoration(
              color: kWhiteColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12.br),
              border: Border.all(
                color: kWhiteColor.withValues(alpha: 0.12),
              ),
            ),
            child: Text(
              'Step ${currentIndex + 1} of ${titles.length}',
              style: AppTypography.textXsMedium.copyWith(
                color: kWhiteColor,
              ),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(
                titles.length,
                (index) => Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: EdgeInsets.symmetric(horizontal: 4.w),
                    height: 6.h,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12.br),
                      color:
                          index <= currentIndex
                              ? kPrimaryColor
                              : kWhiteColor.withValues(alpha: 0.15),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 18.sp, vertical: 20.sp),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22.br),
                      gradient: LinearGradient(
                        colors: [
                          kPrimaryColor.withValues(alpha: 0.26),
                          kBlack2Color.withValues(alpha: 0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: kWhiteColor.withValues(alpha: 0.08)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 24,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome to ChessEver',
                          style: AppTypography.textXlBold.copyWith(color: kWhiteColor),
                        ).animate().fadeIn(duration: 320.ms, curve: _onboardingSpring),
                        SizedBox(height: 8.h),
                        Text(
                          'Two quick moves: country + players.',
                          style: AppTypography.textSmRegular.copyWith(
                            color: kWhiteColor.withValues(alpha: 0.82),
                          ),
                        )
                            .animate()
                            .fadeIn(duration: 320.ms, curve: _onboardingSpring)
                            .move(begin: const Offset(0, 8)),
                        SizedBox(height: 14.h),
                        _BrandingVisual()
                            .animate()
                            .fadeIn(duration: 420.ms, curve: _onboardingSpring)
                            .move(begin: const Offset(0, 10)),
                        SizedBox(height: 12.h),
                        Wrap(
                          spacing: 10.w,
                          runSpacing: 10.h,
                          children: const [
                            _Pill(text: 'Personalized games', icon: Icons.auto_awesome),
                            _Pill(text: 'Your players & events', icon: Icons.favorite_rounded),
                            _Pill(text: 'Keep it in sync', icon: Icons.cloud_sync_rounded),
                          ],
                        )
                            .animate()
                            .fadeIn(duration: 380.ms, curve: _onboardingSpring)
                            .move(begin: const Offset(0, 6)),
                        SizedBox(height: 12.h),
                        _HighlightStrip()
                            .animate()
                            .fadeIn(duration: 360.ms, curve: _onboardingSpring)
                            .move(begin: const Offset(0, 6)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16.h),
          SizedBox(
            width: double.infinity,
            height: 52.h,
            child: ElevatedButton(
              onPressed: onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: kWhiteColor,
                foregroundColor: kBlackColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.br),
                ),
                elevation: 0,
              ),
              child: Text(
                'Start setup',
                style: AppTypography.textMdMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BulletRow extends StatelessWidget {
  const _BulletRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8.sp),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kWhiteColor.withValues(alpha: 0.06),
          ),
          child: Icon(icon, size: 16.ic, color: kWhiteColor),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Text(
            label,
            style: AppTypography.textSmMedium.copyWith(
              color: kWhiteColor.withValues(alpha: 0.82),
            ),
          ),
        ),
      ],
    );
  }
}

class _AccountChoiceCard extends StatelessWidget {
  const _AccountChoiceCard();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _BrandingVisual extends StatelessWidget {
  const _BrandingVisual();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14.sp),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.br),
        gradient: LinearGradient(
          colors: [
            kPrimaryColor.withValues(alpha: 0.18),
            kBlack2Color.withValues(alpha: 0.55),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: kWhiteColor.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your board, your people',
                style: AppTypography.textMdBold.copyWith(color: kWhiteColor),
              ),
              SizedBox(height: 8.h),
              Text(
                'We blend country picks, your favorites, and the formats you enjoy most.',
                style: AppTypography.textXsRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.8),
                ),
              ),
              SizedBox(height: 12.h),
              const _MiniBoardStripe(),
              SizedBox(height: 12.h),
              const _ModeTiles(),
            ],
          ),
        ),
          SizedBox(width: 12.w),
          Container(
            padding: EdgeInsets.all(10.sp),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kWhiteColor.withValues(alpha: 0.08),
              border: Border.all(color: kWhiteColor.withValues(alpha: 0.1)),
            ),
            child: Image.asset(
              PngAsset.newAppLogoCircle,
              height: 64.h,
              width: 64.w,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniBoardStripe extends StatelessWidget {
  const _MiniBoardStripe();

  @override
  Widget build(BuildContext context) {
    final darkSquare = kBlack2Color.withValues(alpha: 0.9);
    final lightSquare = kWhiteColor.withValues(alpha: 0.7);
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: List.generate(8, (index) {
        final isLight = index.isEven;
        return Container(
          margin: EdgeInsets.only(right: index == 7 ? 0 : 4.w),
          width: 16.w,
          height: 16.h,
          decoration: BoxDecoration(
            color: isLight ? lightSquare : darkSquare,
            borderRadius: BorderRadius.circular(4.br),
          ),
        );
      }),
    );
  }
}

class _ModeTiles extends StatelessWidget {
  const _ModeTiles();

  @override
  Widget build(BuildContext context) {
    final items = [
      (PngAsset.rapidIcon, 'Rapid'),
      (PngAsset.blitzIcon, 'Blitz'),
      (PngAsset.classicalIcon, 'Classical'),
    ];
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: items
          .map(
            (item) => Container(
              padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 10.sp),
              decoration: BoxDecoration(
                color: kWhiteColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12.br),
                border: Border.all(color: kWhiteColor.withValues(alpha: 0.08)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    item.$1,
                    height: 20.h,
                    width: 20.w,
                    fit: BoxFit.contain,
                  ),
                  SizedBox(width: 6.w),
                  Text(
                    item.$2,
                    style: AppTypography.textXsMedium.copyWith(
                      color: kWhiteColor,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _HighlightStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12.sp),
      decoration: BoxDecoration(
        color: kWhiteColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14.br),
        border: Border.all(color: kWhiteColor.withValues(alpha: 0.1)),
      ),
      child: Wrap(
        spacing: 10.w,
        runSpacing: 8.h,
        children: const [
          _HighlightTile(
            icon: Icons.flag_rounded,
            title: 'Country',
            subtitle: 'More from your people',
          ),
          _HighlightTile(
            icon: Icons.favorite_rounded,
            title: 'Players',
            subtitle: 'Keep them on top',
          ),
          _HighlightTile(
            icon: Icons.event_available_rounded,
            title: 'Events',
            subtitle: 'Less noise, more signal',
          ),
        ],
      ),
    );
  }
}

class _HighlightTile extends StatelessWidget {
  const _HighlightTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 10.sp),
      decoration: BoxDecoration(
        color: kWhiteColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kWhiteColor.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18.ic, color: kWhiteColor),
          SizedBox(width: 8.w),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
              ),
              Text(
                subtitle,
                style: AppTypography.textXsRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallBullet extends StatelessWidget {
  const _SmallBullet({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 6.w,
          height: 6.h,
          margin: EdgeInsets.only(top: 4.h, right: 6.w),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kWhiteColor.withValues(alpha: 0.8),
          ),
        ),
        Expanded(
          child: Text(
            label,
            style: AppTypography.textXsRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.75),
            ),
          ),
        ),
      ],
    );
  }
}

class _AccountChoiceDialog extends StatelessWidget {
  const _AccountChoiceDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kBlack2Color.withValues(alpha: 0.95),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.br)),
      title: Text(
        'Save your progress?',
        style: AppTypography.textMdBold.copyWith(color: kWhiteColor),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Signing in keeps your favorites, board settings, and saved game analyses across devices.',
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.8),
            ),
          ),
          SizedBox(height: 12.h),
          Text(
            'Guest mode limits',
            style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
          ),
          SizedBox(height: 6.h),
          const _SmallBullet(label: 'Favorites stored only on this device'),
          SizedBox(height: 4.h),
          const _SmallBullet(label: 'Saved analyses won\'t sync'),
        ],
      ),
      actionsPadding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Sign in / link',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: kWhiteColor,
            foregroundColor: kBlackColor,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.br),
            ),
          ),
          child: Text(
            'Continue as guest',
            style: AppTypography.textSmMedium,
          ),
        ),
      ],
    );
  }
}

class _CountryStep extends HookConsumerWidget {
  const _CountryStep({
    required this.countryState,
    required this.onNext,
    required this.onRetry,
  });

  final AsyncValue<Country> countryState;
  final VoidCallback onNext;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(18.sp),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20.br),
              color: kBlack2Color.withValues(alpha: 0.85),
              border: Border.all(color: kWhiteColor.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 6.sp),
                  decoration: BoxDecoration(
                    color: kPrimaryColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10.br),
                  ),
                  child: Text(
                    'Step 2 · Countryman',
                    style: AppTypography.textXsMedium.copyWith(
                      color: kWhiteColor,
                    ),
                  ),
                ),
                SizedBox(height: 12.h),
                Text(
                  'Where do you play from?',
                  style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
                ),
                SizedBox(height: 8.h),
                Text(
                  'Pick your country to boost local broadcasts in For You. You can change this anytime.',
                  style: AppTypography.textSmRegular.copyWith(
                    color: kWhiteColor.withValues(alpha: 0.75),
                  ),
                ),
                SizedBox(height: 18.h),
                Container(
                  padding: EdgeInsets.all(14.sp),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14.br),
                    color: kWhiteColor.withValues(alpha: 0.04),
                    border: Border.all(color: kWhiteColor.withValues(alpha: 0.06)),
                  ),
                  child: countryState.when(
                    loading: () => CountryDropdown(
                      selectedCountryCode: '',
                      onChanged: (_) {},
                      isLoading: true,
                      hintText: 'Finding your country...',
                    ),
                    error: (_, __) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Couldn\'t fetch your location.',
                          style: AppTypography.textSmMedium.copyWith(
                            color: kWhiteColor,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        TextButton(
                          onPressed: onRetry,
                          child: Text(
                            'Retry',
                            style: AppTypography.textSmMedium.copyWith(
                              color: kPrimaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    data: (country) => CountryDropdown(
                      selectedCountryCode: country.countryCode,
                      onChanged: (Country newCountry) {
                        ref
                            .read(countryDropdownProvider.notifier)
                            .selectCountry(newCountry.countryCode);
                      },
                    ),
                  ),
                ),
                SizedBox(height: 18.h),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        countryState.isLoading
                            ? null
                            : () {
                                onNext();
                              },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kWhiteColor,
                      foregroundColor: kBlackColor,
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.br),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Save and continue',
                      style: AppTypography.textMdMedium,
                    ),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 360.ms, curve: _onboardingSpring).move(begin: const Offset(0, 10)),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: 120.w, maxWidth: 180.w),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
        decoration: BoxDecoration(
          color: kWhiteColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14.br),
          border: Border.all(color: kWhiteColor.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14.ic, color: kWhiteColor),
              SizedBox(width: 6.w),
            ],
            Flexible(
              child: Text(
                text,
                style: AppTypography.textXsMedium.copyWith(
                  color: kWhiteColor,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
