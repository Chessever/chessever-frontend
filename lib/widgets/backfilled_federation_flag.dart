import 'package:chessever2/providers/player_backfill_provider.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// [FederationFlag] variant that resolves the flag from Supabase's
/// `chess_players` table when the supplied federation is missing.
///
/// Event/broadcast federation remains the source of truth when present and
/// valid. If the broadcast omits a flag (or sends a known placeholder such as
/// FIDE/?), we fall back to the matched ChessEver player profile by FIDE ID and
/// then by exact normalized name.
class BackfilledFederationFlag extends ConsumerWidget {
  const BackfilledFederationFlag({
    super.key,
    required this.federation,
    required this.fideId,
    this.playerName,
    this.width,
    this.height,
    this.borderRadius,
  });

  final String? federation;
  final int? fideId;
  final String? playerName;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  bool _needsBackfill(String value) {
    if (value.isEmpty) return true;
    final upper = value.toUpperCase();
    // Lichess returns placeholders for some broadcast rows; treat them as
    // missing so we backfill from ChessEver's player profile.
    return upper == 'FID' || upper == 'FIDE' || upper == '?';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raw = (federation ?? '').trim();
    var resolved = raw;

    if (_needsBackfill(raw)) {
      var country = '';
      if (fideId != null && fideId! > 0) {
        final async = ref.watch(chessPlayerByFideIdProvider(fideId));
        country = async.valueOrNull?.country?.trim() ?? '';
      }
      if (country.isEmpty && (playerName?.trim().isNotEmpty ?? false)) {
        final async = ref.watch(chessPlayerByNameProvider(playerName!.trim()));
        country = async.valueOrNull?.country?.trim() ?? '';
      }
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
