import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// When the Inbox and the discovery dots may ask for someone's attention.
///
/// Shared by both so a person meets one rule, not two: an account does not
/// inherit what was published before it existed, its first week is quiet, and
/// something left unseen for a month stops asking (Trello #1319).

/// How long a new account goes without an Inbox badge or a discovery dot.
/// Whatever is published in that week is absorbed, never held back: holding
/// it would only move the flood to day eight.
const newAccountQuietPeriod = Duration(days: 7);

/// How long an unseen announcement keeps asking for attention.
const announcementShelfLife = Duration(days: 30);

/// The clock these rules read. Tests replace it.
final attentionClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// When the account in use was created, guests included (their anonymous
/// account); null while nobody is signed in.
final accountCreatedAtProvider = Provider<DateTime?>(
  (ref) => ref.watch(currentUserProvider.select((user) => user?.createdAt)),
);

/// Whether something published at [publishedAt] predates the account. That is
/// news for the people who were here then, not for someone just arriving.
bool isBeforeAccount(DateTime publishedAt, DateTime? accountCreatedAt) =>
    accountCreatedAt != null && publishedAt.isBefore(accountCreatedAt);

/// Whether something published at [publishedAt] may still ask for attention:
/// it came after the account's quiet first week, and within its shelf life.
bool mayAskForAttention({
  required DateTime publishedAt,
  required DateTime? accountCreatedAt,
  required DateTime now,
}) {
  if (now.difference(publishedAt) > announcementShelfLife) return false;
  if (accountCreatedAt == null) return true;
  return !publishedAt.isBefore(accountCreatedAt.add(newAccountQuietPeriod));
}

/// Whether the account is still in its quiet first week.
bool isQuietAccount(DateTime accountCreatedAt, DateTime now) =>
    now.isBefore(accountCreatedAt.add(newAccountQuietPeriod));
