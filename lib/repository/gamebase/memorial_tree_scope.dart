const String memorialTreeScopePrefix = 'memorial-source:';

String memorialTreeScopeKey(String sourceIdentity) =>
    '$memorialTreeScopePrefix${Uri.encodeComponent(sourceIdentity.trim())}';

String? memorialSourceIdentityFromTreeScope(String scopeKey) {
  if (!scopeKey.startsWith(memorialTreeScopePrefix)) return null;
  final encoded = scopeKey.substring(memorialTreeScopePrefix.length);
  if (encoded.isEmpty) return null;
  final decoded = Uri.decodeComponent(encoded).trim();
  return decoded.isEmpty ? null : decoded;
}
