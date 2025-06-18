import 'app_user.dart';

enum AppAuthStatus { initial, loading, authenticated, unauthenticated, error }

class AppAuthState {
  final AppAuthStatus status;
  final AppUser? user;
  final String? errorMessage;

  const AppAuthState({required this.status, this.user, this.errorMessage});

  const AppAuthState.initial() : this(status: AppAuthStatus.initial);

  const AppAuthState.loading() : this(status: AppAuthStatus.loading);

  const AppAuthState.authenticated(AppUser user)
    : this(status: AppAuthStatus.authenticated, user: user);

  const AppAuthState.unauthenticated() : this(status: AppAuthStatus.unauthenticated);

  const AppAuthState.error(String message)
    : this(status: AppAuthStatus.error, errorMessage: message);

  bool get isAuthenticated =>
      status == AppAuthStatus.authenticated && user != null;

  bool get isLoading => status == AppAuthStatus.loading;

  bool get hasError => status == AppAuthStatus.error;

  AppAuthState copyWith({
    AppAuthStatus? status,
    AppUser? user,
    String? errorMessage,
  }) {
    return AppAuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
