import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Convenience provider to get current user
final currentUserProvider = Provider<AppUser?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.maybeWhen(
    data: (AppAuthState state) => state.user,
    orElse: () => null,
  );
});

/// Convenience provider to check if user is authenticated
final isAuthenticatedProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.maybeWhen(
    data: (AppAuthState state) => state.isAuthenticated,
    orElse: () => false,
  );
});

/// The Lichess and Chess.com usernames linked on My Profile. Null fields are
/// "not linked".
typedef LinkedChessAccounts = ({String? lichess, String? chesscom});

/// The signed-in user's linked chess-site usernames, from auth
/// `user_metadata`.
///
/// Selected from [authStateProvider] as a record rather than read off
/// [currentUserProvider]: [AppUser] equality is by id alone, so
/// [currentUserProvider] stays quiet when only the metadata changes, while a
/// record compares field by field.
final linkedChessAccountsProvider = Provider<LinkedChessAccounts>((ref) {
  return ref.watch(
    authStateProvider.select((auth) {
      final user = auth.valueOrNull?.user;
      return (lichess: user?.lichessUsername, chesscom: user?.chesscomUsername);
    }),
  );
});
