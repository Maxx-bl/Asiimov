/// Helpers for reading report reasons stored in Firestore report documents.
class ReportReasonsHelper {
  static List<Map<String, String>> parseReportReasons(
    Map<String, dynamic> reportData,
  ) {
    final results = <Map<String, String>>[];
    final seenUserIds = <String>{};

    void addEntry(String username, String reason, {String? userId}) {
      final trimmed = reason.trim();
      if (trimmed.isEmpty) return;
      if (userId != null && seenUserIds.contains(userId)) return;
      if (userId != null) seenUserIds.add(userId);
      results.add({'username': username, 'reason': trimmed});
    }

    final reporterReasons = reportData['reporterReasons'];
    if (reporterReasons is List) {
      for (final entry in reporterReasons) {
        if (entry is! Map) continue;
        final userId = entry['userId'] as String?;
        addEntry(
          entry['username'] as String? ?? 'Anonymous',
          entry['reason'] as String? ?? '',
          userId: userId,
        );
      }
    }

    // Legacy / primary field when reporterReasons is absent
    final legacyReason = reportData['reportReason'] as String?;
    if (legacyReason != null && legacyReason.trim().isNotEmpty) {
      final reporter =
          reportData['reportedByUsername'] as String? ?? 'Anonymous';
      final reporterId = reportData['reportedById'] as String?;
      addEntry(reporter, legacyReason, userId: reporterId);
    }

    return results;
  }
}
