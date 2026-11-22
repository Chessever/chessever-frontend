import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A reader with a session (a guest counts). Links and pushes open only for
/// one: with none they wait for sign-in (DeepLinkService._readyToOpen).
class SignedInAuth extends AuthController {
  @override
  Future<AppAuthState> build() async =>
      const AppAuthState(status: AppAuthStatus.authenticated);
}

/// A reader with no session: a cold start signed out, or onboarding.
class SignedOutAuth extends AuthController {
  @override
  Future<AppAuthState> build() async =>
      const AppAuthState(status: AppAuthStatus.unauthenticated);
}

/// The override that signs the test reader in.
Override signedInAuthOverride() =>
    authStateProvider.overrideWith(SignedInAuth.new);
