import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:flutter/material.dart';

/// What an Events list (Past, Current or Upcoming) shows when its load failed
/// with nothing cached to fall back on: why, in user-facing words, and a Retry
/// that runs the load again.
///
/// Only a failed load lands here. A load that succeeds with no rows is an
/// empty state (Upcoming's "Nothing scheduled yet"), never this. The body
/// stays scrollable so the Events pull-to-refresh retries too.
class EventsLoadErrorState extends StatelessWidget {
  const EventsLoadErrorState({
    required this.error,
    required this.fallbackMessage,
    required this.onRetry,
    this.scrollController,
    super.key,
  });

  final Object? error;

  /// Copy for a failure [userFacingError] has no specific words for.
  final String fallbackMessage;
  final VoidCallback onRetry;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: GenericErrorWidget(
              message: userFacingError(error, fallback: fallbackMessage),
              onRetry: onRetry,
            ),
          ),
        );
      },
    );
  }
}
