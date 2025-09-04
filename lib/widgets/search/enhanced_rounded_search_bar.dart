import 'dart:async';
import 'package:chessever2/repository/local_storage/sesions_manager/session_manager.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/search/search_overlay_widget.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../screens/group_event/providers/group_event_screen_provider.dart';

class EnhancedRoundedSearchBar extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final Function(String)? onChanged;
  final Function(GroupEventCardModel)? onTournamentSelected;
  final String hintText;
  final bool autofocus;
  final Function(SearchPlayer)? onPlayerSelected;
  final VoidCallback? onFilterTap;
  final VoidCallback? onProfileTap;
  final bool showProfile;
  final bool showFilter;
  final FocusNode? focusNode;

  const EnhancedRoundedSearchBar({
    super.key,
    required this.controller,
    this.onPlayerSelected,
    this.onChanged,
    this.onTournamentSelected,
    this.hintText = 'Search tournaments or players',
    this.autofocus = false,
    this.onFilterTap,
    this.onProfileTap,
    this.showProfile = true,
    this.showFilter = true,
    this.focusNode,
  });

  @override
  ConsumerState<EnhancedRoundedSearchBar> createState() =>
      _EnhancedRoundedSearchBarState();
}

class _EnhancedRoundedSearchBarState
    extends ConsumerState<EnhancedRoundedSearchBar>
    with TickerProviderStateMixin {
  bool _showOverlay = false;
  final FocusNode _internalFocusNode = FocusNode();
  late final FocusNode _effectiveNode;

  late AnimationController _overlayController;
  late AnimationController _searchBarController;
  late Animation<double> _overlayAnimation;
  late Animation<double> _searchBarScaleAnimation;

  @override
  void initState() {
    super.initState();
    _effectiveNode = widget.focusNode ?? _internalFocusNode;
    _effectiveNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChange);

    _overlayController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _searchBarController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _overlayAnimation = CurvedAnimation(
      parent: _overlayController,
      curve: Curves.easeInOut,
    );

    _searchBarScaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.02,
    ).animate(
      CurvedAnimation(
        parent: _searchBarController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _effectiveNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) _internalFocusNode.dispose();
    widget.controller.removeListener(_onTextChange);
    _overlayController.dispose();
    _searchBarController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    print('Focus changed: ${_effectiveNode.hasFocus}');
    ref.read(isSearchingProvider.notifier).state = _effectiveNode.hasFocus;
    setState(() {
      _showOverlay =
          _effectiveNode.hasFocus && widget.controller.text.isNotEmpty;
    });

    if (_effectiveNode.hasFocus) {
      _searchBarController.forward();
      if (widget.controller.text.isNotEmpty) {
        _overlayController.forward();
      }
    } else {
      _searchBarController.reverse();
      _overlayController.reverse();
    }
  }

  void _onTextChange() {
    final hasText = widget.controller.text.isNotEmpty;
    ref.read(isSearchingProvider.notifier).state = hasText;
    if (hasText != _showOverlay && _effectiveNode.hasFocus) {
      setState(() {
        _showOverlay = hasText;
      });

      if (hasText) {
        _overlayController.forward();
      } else {
        _overlayController.reverse();
      }
    }
    widget.onChanged?.call(widget.controller.text);
  }

  void _hideOverlay() {
    setState(() {
      _showOverlay = false;
    });
    _effectiveNode.unfocus();
    _searchBarController.reverse();
  }

  void _onTournamentSelected(GroupEventCardModel tournament) {
    _hideOverlay();
    widget.onTournamentSelected?.call(tournament);
  }

  void _onPlayerSelected(SearchPlayer player) {
    _hideOverlay();
    widget.onPlayerSelected?.call(player);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (_showOverlay)
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                if (_effectiveNode.hasFocus) {
                  _effectiveNode.unfocus();
                }
                _hideOverlay();
              },
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.transparent),
            ),
          ),
        Column(
          children: [
            AnimatedPadding(
              padding: EdgeInsets.symmetric(
                horizontal: _effectiveNode.hasFocus ? 12.w : 0,
              ),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: AnimatedBuilder(
                animation: _searchBarController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _searchBarScaleAnimation.value,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12.br),
                        border: Border.all(
                          color:
                              _effectiveNode.hasFocus
                                  ? kPrimaryColor.withOpacity(0.5)
                                  : Colors.transparent,
                          width: 2.0,
                        ),
                        boxShadow:
                            _effectiveNode.hasFocus
                                ? [
                                  BoxShadow(
                                    color: kPrimaryColor.withOpacity(0.15),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                                : [],
                      ),
                      child: _buildSearchBar(),
                    ),
                  );
                },
              ),
            ),
            AnimatedBuilder(
              animation: _overlayAnimation,
              builder: (context, child) {
                return ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: _overlayAnimation.value,
                    child: Container(
                      margin: EdgeInsets.only(top: 12.sp),
                      child: Transform.translate(
                        offset: Offset(0, (1 - _overlayAnimation.value) * -20),
                        child: Opacity(
                          opacity: _overlayAnimation.value,
                          child: SearchOverlay(
                            query: widget.controller.text,
                            onTournamentTap: _onTournamentSelected,
                            onPlayerTap: _onPlayerSelected,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Row(
      children: [
        if (widget.showProfile) ...[
          _buildProfileAvatar(),
          SizedBox(width: 16.w),
        ],
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(12.br),
            ),
            child: _buildSearchInput(),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileAvatar() {
    final sessionManager = ref.read(sessionManagerProvider);
    return FutureBuilder<String?>(
      future: sessionManager.getUserInitials(),
      builder: (context, snapshot) {
        final initials = snapshot.data ?? '';
        return GestureDetector(
          onTap: widget.onProfileTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 44.w,
            height: 44.h,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: kProfileInitialsGradient,
              boxShadow: [
                BoxShadow(
                  color: kPrimaryColor.withAlpha(7),
                  blurRadius: 4.br,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                initials.toUpperCase(),
                style: AppTypography.textMdBold,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchInput() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 4.sp),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedRotation(
            turns: _effectiveNode.hasFocus ? 0.25 : 0,
            duration: const Duration(milliseconds: 300),
            child: SvgWidget(
              SvgAsset.searchIcon,
              height: 20.h,
              width: 20.w,
              colorFilter: ColorFilter.mode(
                _effectiveNode.hasFocus ? kPrimaryColor : Colors.grey[400]!,
                BlendMode.srcIn,
              ),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _effectiveNode,
              autofocus: widget.autofocus,
              style: AppTypography.textMdRegular,
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: AppTypography.textMdRegular,
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          // Show clear icon only when search bar has focus
          if (_effectiveNode.hasFocus) ...[
            GestureDetector(
              onTap: () {
                widget.controller.clear();
                _hideOverlay();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: EdgeInsets.all(4.sp),
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close,
                  size: 16.ic,
                  color: kWhiteColor,
                ),
              ),
            ),
          ],
          if (widget.showFilter && widget.onFilterTap != null) ...[
            SizedBox(width: 8.w),
            GestureDetector(
              onTap: widget.onFilterTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: EdgeInsets.all(8.sp),
                decoration: BoxDecoration(
                  color: kDarkGreyColor.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8.br),
                ),
                child: SvgWidget(
                  SvgAsset.listFilterIcon,
                  height: 20.h,
                  width: 20.w,
                  colorFilter: ColorFilter.mode(
                    _effectiveNode.hasFocus ? kPrimaryColor : Colors.grey[400]!,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
