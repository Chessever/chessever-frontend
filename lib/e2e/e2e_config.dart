class E2eConfig {
  static const bool isEnabled = bool.fromEnvironment(
    'E2E',
    defaultValue: false,
  );

  static const bool resetOnboarding = bool.fromEnvironment(
    'E2E_RESET_ONBOARDING',
    defaultValue: false,
  );

  static const bool _explicitPromptSuppression = bool.fromEnvironment(
    'E2E_SUPPRESS_PROMPTS',
    defaultValue: false,
  );

  static const bool suppressInterruptivePrompts =
      isEnabled || _explicitPromptSuppression;

  static const String testEmail = String.fromEnvironment(
    'E2E_TEST_EMAIL',
    defaultValue: '',
  );

  static const String testPassword = String.fromEnvironment(
    'E2E_TEST_PASSWORD',
    defaultValue: '',
  );

  static bool get hasCredentials =>
      testEmail.trim().isNotEmpty && testPassword.isNotEmpty;
}
