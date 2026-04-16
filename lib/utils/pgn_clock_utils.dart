final RegExp pgnClockRegex = RegExp(r'\[%clk (\d+:)?(\d+:\d+)(?:\.\d+)?\]');

String? extractPgnClockStringFromComment(String comment) {
  final match = pgnClockRegex.firstMatch(comment);
  if (match == null) return null;

  final hours = match.group(1) ?? '';
  final rest = match.group(2) ?? '';
  final clock = '$hours$rest'.trim();
  return clock.isEmpty ? null : clock;
}

List<String> extractPgnClockStringsFromText(String text) {
  return pgnClockRegex
      .allMatches(text)
      .map((match) {
        final hours = match.group(1) ?? '';
        final rest = match.group(2) ?? '';
        return '$hours$rest';
      })
      .where((clock) => clock.trim().isNotEmpty)
      .toList(growable: false);
}

int? parsePgnClockToSeconds(String? clock) {
  final trimmed = clock?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;

  final parts = trimmed.split(':').map((part) => part.trim()).toList();
  if (parts.length == 2) {
    final minutes = int.tryParse(parts[0]);
    final seconds = int.tryParse(parts[1].split('.').first);
    if (minutes == null || seconds == null) return null;
    return (minutes * 60) + seconds;
  }

  if (parts.length == 3) {
    final hours = int.tryParse(parts[0]);
    final minutes = int.tryParse(parts[1]);
    final seconds = int.tryParse(parts[2].split('.').first);
    if (hours == null || minutes == null || seconds == null) return null;
    return (hours * 3600) + (minutes * 60) + seconds;
  }

  return null;
}

String formatPgnClockForDisplay(String clock) {
  final trimmed = clock.trim();
  if (trimmed.isEmpty) return trimmed;

  final parts = trimmed.split(':').map((part) => part.trim()).toList();
  if (parts.length == 2) {
    final minutes = int.tryParse(parts[0]);
    final seconds = int.tryParse(parts[1].split('.').first);
    if (minutes == null || seconds == null) return trimmed;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  if (parts.length == 3) {
    final hours = int.tryParse(parts[0]);
    final minutes = int.tryParse(parts[1]);
    final seconds = int.tryParse(parts[2].split('.').first);
    if (hours == null || minutes == null || seconds == null) return trimmed;
    if (hours == 0) {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  return trimmed;
}

String formatClockDisplayFromSeconds(int totalSeconds) {
  if (totalSeconds <= 0) return '00:00';

  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final minuteString = minutes.toString().padLeft(2, '0');
  final secondString = seconds.toString().padLeft(2, '0');

  if (hours == 0) {
    return '$minuteString:$secondString';
  }

  return '$hours:$minuteString:$secondString';
}

bool hasUsableClockDisplay(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return false;
  return trimmed != '--:--' && trimmed != '-:--:--' && trimmed != '-';
}

String normalizeChessFenForComparison(String? fen) {
  if (fen == null) return '';
  final parts = fen.trim().split(RegExp(r'\s+'));
  return parts.take(4).join(' ');
}

bool isShowingLiveBoardPosition({
  required String? currentFen,
  required String? liveFen,
  required int currentMoveIndex,
  required int latestMainlineIndex,
  required bool isInAnalysisVariation,
}) {
  if (isInAnalysisVariation) {
    return false;
  }

  final normalizedCurrent = normalizeChessFenForComparison(currentFen);
  final normalizedLive = normalizeChessFenForComparison(liveFen);
  if (normalizedCurrent.isNotEmpty && normalizedLive.isNotEmpty) {
    return normalizedCurrent == normalizedLive;
  }

  return currentMoveIndex == latestMainlineIndex;
}
