import 'dart:async';

import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/material.dart';

/// Animated hint text for search fields that cycles through different search
/// suggestions with smooth fade and slide transitions.
class AnimatedSearchHint extends StatefulWidget {
  /// Text color for the hint
  final Color textColor;

  /// Text style for the hint (color will be overridden)
  final TextStyle? textStyle;

  /// Phrases to cycle through
  final List<String> phrases;

  const AnimatedSearchHint({
    super.key,
    this.textColor = const Color(0xFFA1A1AA),
    this.textStyle,
    this.phrases = const [
      'Search books',
      'Find a book...',
    ],
  });

  @override
  State<AnimatedSearchHint> createState() => _AnimatedSearchHintState();
}

class _AnimatedSearchHintState extends State<AnimatedSearchHint>
    with SingleTickerProviderStateMixin {
  late final List<String> _hintPhrases;

  late AnimationController _controller;
  late Animation<double> _fadeOutAnimation;
  late Animation<double> _fadeInAnimation;
  late Animation<Offset> _slideOutAnimation;
  late Animation<Offset> _slideInAnimation;

  Timer? _phraseTimer;

  int _currentPhraseIndex = 0;
  int _nextPhraseIndex = 1;
  bool _showingNext = false;

  // Timing configurations
  static const Duration _displayDuration = Duration(milliseconds: 3000);
  static const Duration _transitionDuration = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    _hintPhrases = widget.phrases;

    _controller = AnimationController(
      vsync: this,
      duration: _transitionDuration,
    );

    // Current text fades out and slides up
    _fadeOutAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _slideOutAnimation =
        Tween<Offset>(begin: Offset.zero, end: const Offset(0, -0.5)).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    // Next text fades in and slides up into position
    _fadeInAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
      ),
    );

    _slideInAnimation =
        Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
      ),
    );

    _controller.addStatusListener(_onAnimationStatusChange);
    _startPhraseRotation();
  }

  void _onAnimationStatusChange(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      setState(() {
        _currentPhraseIndex = _nextPhraseIndex;
        _nextPhraseIndex = (_nextPhraseIndex + 1) % _hintPhrases.length;
        _showingNext = false;
      });
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _phraseTimer?.cancel();
    _controller.removeStatusListener(_onAnimationStatusChange);
    _controller.dispose();
    super.dispose();
  }

  void _startPhraseRotation() {
    _phraseTimer = Timer.periodic(_displayDuration, (_) {
      if (!mounted) return;
      setState(() => _showingNext = true);
      _controller.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle =
        widget.textStyle ??
        AppTypography.textSmRegular.copyWith(color: widget.textColor);

    final textStyle = baseStyle.copyWith(color: widget.textColor);

    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            children: [
              // Current phrase - fades out and slides up
              SlideTransition(
                position: _slideOutAnimation,
                child: Opacity(
                  opacity: _fadeOutAnimation.value,
                  child: Text(
                    _hintPhrases[_currentPhraseIndex],
                    style: textStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              // Next phrase - fades in and slides up
              if (_showingNext)
                SlideTransition(
                  position: _slideInAnimation,
                  child: Opacity(
                    opacity: _fadeInAnimation.value,
                    child: Text(
                      _hintPhrases[_nextPhraseIndex],
                      style: textStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
