import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Returns [source] behind a subscription that [ref] owns, so disposing the
/// provider always cancels [source].
///
/// Every `StreamProvider` body must return its stream through this (or own
/// the upstream subscription the same way by hand). Riverpod 2.6 does not
/// cancel a StreamProvider's source when an `autoDispose` provider is disposed
/// before the source emitted its first value: `handleStream` keeps a second
/// listener for `provider.future` that is only released when the source
/// completes, and a Supabase Realtime stream never completes. Each such
/// provider therefore kept its Realtime channel joined for the rest of the
/// session. Scrolling a 400-board Olympiad round or swiping through boards
/// disposes many providers before their first snapshot arrives, so phones
/// accumulated channels until Supabase refused new joins at its limit of
/// 100 channels per connection (`ChannelRateLimitReached: Too many channels`)
/// and newly visible boards stopped updating live.
///
/// Values, errors and completion are forwarded unchanged, and a provider
/// rebuild cancels the previous source exactly as before.
/// `test/owned_stream_test.dart` pins both halves of this.
Stream<T> ownedStream<T>(Ref ref, Stream<T> source) {
  final controller = StreamController<T>();
  final subscription = source.listen(
    controller.add,
    onError: controller.addError,
    onDone: controller.close,
  );
  ref.onDispose(() {
    unawaited(subscription.cancel());
    unawaited(controller.close());
  });
  return controller.stream;
}
