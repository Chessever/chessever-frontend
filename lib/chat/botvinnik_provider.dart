import 'dart:async';

import 'package:chessever2/chat/chat_api.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final botvinnikEnabledProvider =
    AsyncNotifierProvider<BotvinnikEnabledNotifier, bool>(
      BotvinnikEnabledNotifier.new,
    );

class BotvinnikEnabledNotifier extends AsyncNotifier<bool> {
  static const _key = 'botvinnik_enabled';

  @override
  Future<bool> build() async {
    try {
      return await AppDatabase.instance.getBool(_key) ?? true;
    } catch (error) {
      debugPrint('[Botvinnik] Failed to load enabled setting: $error');
      return true;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    state = AsyncData(enabled);
    try {
      await AppDatabase.instance.setBool(_key, enabled);
    } catch (error) {
      debugPrint('[Botvinnik] Failed to persist enabled setting: $error');
    }
  }
}

final botvinnikQuotaProvider =
    AsyncNotifierProvider<BotvinnikQuotaNotifier, ChatQuotaStatus?>(
      BotvinnikQuotaNotifier.new,
    );

class BotvinnikQuotaNotifier extends AsyncNotifier<ChatQuotaStatus?> {
  Timer? _resetTimer;
  int _generation = 0;
  @override
  Future<ChatQuotaStatus?> build() async {
    _resetTimer?.cancel();
    ref.onDispose(() {
      _generation++;
      _resetTimer?.cancel();
    });
    final user = ref.watch(currentUserProvider);
    if (user == null || user.isAnonymous) return null;
    return _fetch();
  }

  Future<ChatQuotaStatus> _fetch() async {
    final generation = _generation;
    final api = ChatApi();
    try {
      final quota = await api.quota();
      if (generation == _generation) _scheduleReset(quota);
      return quota;
    } finally {
      api.close();
    }
  }

  Future<void> refresh() async {
    final user = ref.read(currentUserProvider);
    if (user == null || user.isAnonymous) {
      state = const AsyncData(null);
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  void setQuota(ChatQuotaStatus quota) {
    state = AsyncData(quota);
    _scheduleReset(quota);
  }

  void _scheduleReset(ChatQuotaStatus quota) {
    _resetTimer?.cancel();
    final resetsAt = quota.resetsAt;
    if (quota.limit <= 0 || quota.remaining > 0 || resetsAt == null) return;
    final delay =
        resetsAt.difference(DateTime.now()) + const Duration(seconds: 1);
    _resetTimer = Timer(
      delay.isNegative ? const Duration(seconds: 30) : delay,
      () => unawaited(refresh()),
    );
  }
}
