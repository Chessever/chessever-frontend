import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared Supabase access for Riverpod call sites.
///
/// Always returns the app singleton from [Supabase.initialize] — never a second
/// anonymous [SupabaseClient]. A second client (URL+anon only, no session /
/// shared HTTP stack) was the release-only Standings hang: Games used
/// [Supabase.instance] and worked, while [supabaseProvider] callers stalled
/// with no Sentry signal. Flavor URL validation already runs at boot in main.
final supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});
