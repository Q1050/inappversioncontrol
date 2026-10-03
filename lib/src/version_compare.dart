/// Compares two dot-separated numeric version strings.
///
/// Returns a negative number when [a] is older than [b], zero when they are
/// equal, and a positive number when [a] is newer. Missing segments are treated
/// as zero, so `1.2` and `1.2.0` are equal.
int compareVersions(String a, String b) {
  final pa = _parseVersionSegments(a);
  final pb = _parseVersionSegments(b);

  final maxLen = pa.length > pb.length ? pa.length : pb.length;
  while (pa.length < maxLen) {
    pa.add(0);
  }
  while (pb.length < maxLen) {
    pb.add(0);
  }

  for (var i = 0; i < maxLen; i++) {
    if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
  }
  return 0;
}

List<int> _parseVersionSegments(String version) {
  if (version.trim().isEmpty) {
    throw FormatException('Version cannot be empty.', version);
  }

  final segments = version.split('.');
  return segments.map((segment) {
    if (segment.isEmpty) {
      throw FormatException(
        'Version contains an empty numeric segment.',
        version,
      );
    }

    final parsed = int.tryParse(segment);
    if (parsed == null) {
      throw FormatException('Version segments must be numeric.', version);
    }

    return parsed;
  }).toList();
}
