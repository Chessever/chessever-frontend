import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseProvider = Provider<SupabaseClient>((ref) {
  return SupabaseClient(
    dotenv.env['SUPABASE_URL']!,
    dotenv.env['SUPABASE_ANON_KEY']!,
  );
});
