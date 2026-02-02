import 'package:chessever2/repository/local_storage/local_eval/local_eval_cache.dart';
import 'package:chessever2/repository/supabase/evals/evals_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// DANGER: Clears ALL evaluation caches (local + Supabase)
/// Use this when:
/// - Fixing evaluation perspective bugs
/// - Clearing stale/corrupted data
/// - After major changes to evaluation logic
Future<void> clearAllEvaluationCaches(WidgetRef ref) async {
  print('🧹 CLEARING ALL EVALUATION CACHES...');

  try {
    // 1. Clear SQLite local cache
    print('🧹 Clearing local SQLite cache...');
    final localCache = ref.read(localEvalCacheProvider);
    await localCache.clear();
    print('✅ Local cache cleared');

    // 2. Clear Supabase evals table
    print('🧹 Clearing Supabase evals table...');
    final evalsRepo = ref.read(evalsRepositoryProvider);
    await evalsRepo.clearAll();
    print('✅ Supabase evals cleared');

    print('✅ ALL EVALUATION CACHES CLEARED SUCCESSFULLY');
  } catch (e) {
    print('❌ Error clearing caches: $e');
    rethrow;
  }
}
