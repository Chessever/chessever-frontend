import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:equatable/equatable.dart';

class AuthScreenState extends Equatable {
  final bool isLoading;
  final String? errorMessage;
  final AppUser? user;
  final bool showCountrySelection;

  const AuthScreenState({
    this.isLoading = false,
    this.errorMessage,
    this.user,
    this.showCountrySelection = false,
  });

  @override
  List<Object?> get props => [
    isLoading,
    errorMessage,
    user,
    showCountrySelection,
  ];

  AuthScreenState copyWith({
    bool? isLoading,
    String? errorMessage,
    AppUser? user,
    bool? showCountrySelection,
  }) {
    return AuthScreenState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
      user: user ?? this.user,
      showCountrySelection: showCountrySelection ?? this.showCountrySelection,
    );
  }
}
