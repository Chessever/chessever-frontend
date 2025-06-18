import 'package:chessever2/repository/authentication/auth_provider.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:chessever2/screens/chessever_screen.dart';
import 'package:chessever2/screens/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return switch (authState.status) {
      AppAuthStatus.initial || AppAuthStatus.loading => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      AppAuthStatus.authenticated => const ChesseverScreen(),
      AppAuthStatus.unauthenticated ||
      AppAuthStatus.error => const SignInScreen(),
    };
  }
}
