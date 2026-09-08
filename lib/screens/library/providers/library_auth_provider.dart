import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final libraryFolderAuthenticatedUserIdProvider = Provider.autoDispose<String?>((
  ref,
) {
  // AuthController is the reactive signal; the SDK owns the session. A
  // cancelled account upgrade can report an auth error with a valid session.
  ref.watch(authStateProvider);
  return Supabase.instance.client.auth.currentUser?.id;
});
