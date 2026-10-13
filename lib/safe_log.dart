import 'package:flutter/foundation.dart';

/// Debug-only logger which removes common credentials and key-bearing URLs.
///
/// Production builds intentionally emit nothing through this helper.
class MayaSafeLog {
  static final _patterns = <RegExp>[
    RegExp(
      r'(authorization\s*[:=]\s*bearer\s+)[^\s,;}]+',
      caseSensitive: false,
    ),
    RegExp(
      r'([?&](?:key|api_key|token)=)[^&\s]+',
      caseSensitive: false,
    ),
    RegExp(r'\bAIza[0-9A-Za-z_-]{20,}\b', caseSensitive: false),
    RegExp(
      r'\bsk-(?:proj-|ant-|or-)?[0-9A-Za-z_-]{12,}\b',
      caseSensitive: false,
    ),
    RegExp(r'\b\d{6,12}:[0-9A-Za-z_-]{20,}\b'),
  ];

  static String redact(Object? value, {int max = 320}) {
    var text = value?.toString() ?? '';
    for (final pattern in _patterns) {
      text = text.replaceAllMapped(pattern, (match) {
        final prefix = match.groupCount > 0 ? match.group(1) ?? '' : '';
        return '${prefix}[REDACTED]';
      });
    }
    text = text.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    return text.length <= max ? text : '${text.substring(0, max)}…';
  }

  static void debug(String area, Object? message) {
    if (!kDebugMode) return;
    debugPrint('[${redact(area, max: 40)}] ${redact(message)}');
  }
}
