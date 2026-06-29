import 'package:chessever2/providers/player_backfill_provider.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// [FederationFlag] variant that resolves the flag from Supabase's
/// `chess_players` table when the supplied federation is missing.
///
/// Imported PGNs frequently carry `[WhiteFideId]`/`[BlackFideId]` but omit
/// `[WhiteFed]`/`[BlackFed]`, which would otherwise leave the card without a
/// flag. When [fideId] is present we look up the player's country and render the
/// real flag once it loads. Explicit `FID`/`FIDE` federations are preserved so
/// official FIDE-event rows show the FIDE flag instead of being backfilled to a
/// country or hidden.
class BackfilledFederationFlag extends ConsumerWidget {
  const BackfilledFederationFlag({
    super.key,
    required this.federation,
    required this.fideId,
    this.width,
    this.height,
    this.borderRadius,
  });

  final String? federation;
  final int? fideId;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  bool _needsBackfill(String value) {
    if (value.isEmpty) return true;
    final upper = value.toUpperCase();
    return upper == '?';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raw = (federation ?? '').trim();
    var resolved = raw;

    if (_needsBackfill(raw) && fideId != null && fideId! > 0) {
      final async = ref.watch(chessPlayerByFideIdProvider(fideId));
      final country = async.valueOrNull?.country?.trim() ?? '';
      if (country.isNotEmpty) resolved = country;
    }

    return FederationFlag(
      federation: resolved,
      width: width,
      height: height,
      borderRadius: borderRadius,
    );
  }
}
