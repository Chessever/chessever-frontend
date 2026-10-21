import 'package:chessever2/screens/my_prep/data/prep_favorites.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/services/fide_photo_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final prepFidePhotoProvider = FutureProvider.autoDispose
    .family<String?, String>(
      (ref, fideId) => FidePhotoService.getPhotoUrlOrNull(fideId),
    );

/// Resolve visible saved profiles, including ones saved before photos were
/// captured. Image bytes use CachedNetworkImage's existing disk cache.
final prepProfilePhotoProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, profileId) async {
      final profile = ref.watch(prepProfileProvider(profileId));
      if (profile == null) return null;
      var active = true;
      ref.onDispose(() => active = false);

      void save(PrepAccount account, String url) {
        if (!active) return;
        final profiles = ref.read(prepProfilesProvider.notifier);
        final current = profiles.byId(profileId);
        final live = current?.accounts
            .where((a) => a.key == account.key)
            .firstOrNull;
        // A lookup must never resurrect a detached source or overwrite a
        // concurrent edit, download, or a newer photo.
        if (current == null ||
            live == null ||
            live.avatarUrl?.trim().isNotEmpty == true) {
          return;
        }
        profiles.update(current.replaceAccount(live.copyWith(avatarUrl: url)));
      }

      final fideId = prepFavoriteFide(profile);
      if (fideId != null) {
        String? photo;
        try {
          photo = await ref.watch(prepFidePhotoProvider(fideId).future);
        } catch (_) {
          // Keep trying the attached providers if the portrait service fails.
        }
        if (!active) return null;
        if (photo != null && photo.isNotEmpty) {
          final database = profile.databaseAccount;
          if (database != null) save(database, photo);
          return photo;
        }
      }
      final saved = profile.avatarUrl?.trim();
      if (saved != null && saved.isNotEmpty) return saved;
      for (final account in profile.accounts.where((a) => a.source.online)) {
        try {
          final photo = await ref
              .read(prepRepositoryProvider)
              .lookupPhoto(account);
          if (!active) return null;
          if (photo != null && photo.isNotEmpty) {
            save(account, photo);
            return photo;
          }
        } catch (_) {
          // Photos are optional. A failed provider must not block the card
          // or prevent trying the player's other attached account.
        }
      }
      return null;
    });
