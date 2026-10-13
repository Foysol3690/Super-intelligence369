import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Typed bridge to user-approved Android controls.
class AdvancedDeviceService {
  static const _channel =
      MethodChannel('com.foysol.jarvis/accessibility_bridge');

  static Future<bool> isAccessibilityEnabled() async =>
      await _channel.invokeMethod<bool>('isServiceEnabled') ?? false;

  static Future<bool> openAccessibilitySettings() async =>
      await _channel.invokeMethod<bool>('openAccessibilitySettings') ?? false;

  static Future<bool> openNotificationAccessSettings() async =>
      await _channel.invokeMethod<bool>('openNotificationAccessSettings') ??
      false;

  static Future<bool> openApp(String packageName) async =>
      await _channel
          .invokeMethod<bool>('openApp', {'packageName': packageName}) ??
      false;

  static Future<bool> openUrl(String url) async =>
      await _channel.invokeMethod<bool>('openUrl', {'url': url}) ?? false;

  static Future<bool> searchWeb(String query) async =>
      await _channel.invokeMethod<bool>('searchWeb', {'query': query}) ?? false;

  static Future<Map<String, dynamic>> openPlayStore(
    String appName, {
    bool confirmedInstall = false,
  }) async {
    final spokenQuery = appName.trim();
    final query = spokenQuery
        .replaceFirst(RegExp(r'\s+app$', caseSensitive: false), '')
        .trim();
    if (query.isEmpty) {
      final opened = await openApp('com.android.vending');
      return {
        'success': opened,
        'detailsPage': false,
        'installAttempted': false,
        'message': opened
            ? 'Google Play Store opened'
            : 'Google Play Store is not installed',
      };
    }
    final known = <String, String>{
      'youtube': 'com.google.android.youtube',
      'whatsapp': 'com.whatsapp',
      'whatsapp business': 'com.whatsapp.w4b',
      'telegram': 'org.telegram.messenger',
      'facebook': 'com.facebook.katana',
      'messenger': 'com.facebook.orca',
      'instagram': 'com.instagram.android',
      'spotify': 'com.spotify.music',
      'chrome': 'com.android.chrome',
      'gmail': 'com.google.android.gm',
      'google maps': 'com.google.android.apps.maps',
    };
    String? packageName = known[query.toLowerCase()];
    if (packageName == null &&
        RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(?:\.[a-zA-Z0-9_]+)+$')
            .hasMatch(query)) {
      packageName = query;
    }
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'openPlayStore',
      {
        'query': query,
        if (packageName != null) 'packageName': packageName,
        'confirmedInstall': confirmedInstall,
      },
    );
    return raw?.map((key, value) => MapEntry(key.toString(), value)) ??
        {'success': false, 'error': 'Play Store could not be opened'};
  }

  /// Resolves a spoken YouTube search to a concrete video ID before opening
  /// Android. A direct watch intent is far more reliable than opening search
  /// results and guessing which private YouTube UI node should be tapped.
  static Future<Map<String, dynamic>> playYouTube(String query) async {
    final request = query.trim();
    if (request.isEmpty)
      return {'success': false, 'error': 'YouTube query is empty'};

    var videoId = _extractYouTubeVideoId(request);
    String? resolutionError;
    if (videoId == null) {
      try {
        videoId = await _resolveYouTubeVideoId(request);
        if (videoId == null) {
          resolutionError =
              'YouTube returned no playable video ID after multi-route resolution';
        }
      } catch (error) {
        resolutionError = 'YouTube search resolution failed: $error';
      }
    }

    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'playYouTube',
      {
        'query': request,
        if (videoId != null) 'videoId': videoId,
      },
    );
    final result = raw?.map((key, value) => MapEntry(key.toString(), value)) ??
        <String, dynamic>{'success': false};
    result['query'] = request;
    result['resolvedVideoId'] = videoId;
    result['resolutionMode'] =
        videoId == null ? 'accessibility_fallback' : 'direct_video_intent';
    if (resolutionError != null) result['resolutionWarning'] = resolutionError;
    return result;
  }

  static Future<String?> _resolveYouTubeVideoId(String query) async {
    final routes = <Uri>[
      Uri.https('www.youtube.com', '/results', {'search_query': query}),
      Uri.https('m.youtube.com', '/results', {'search_query': query}),
      Uri.https('music.youtube.com', '/search', {'q': query}),
    ];
    const headers = {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124 Mobile Safari/537.36',
      'Accept-Language': 'en-US,en;q=0.9',
      'Cookie': 'CONSENT=YES+cb; SOCS=CAI',
    };
    for (final uri in routes) {
      try {
        final response = await http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) continue;
        final body = response.body;
        final patterns = <RegExp>[
          RegExp(
            r'"videoRenderer"\s*:\s*\{[\s\S]{0,300}?"videoId"\s*:\s*"([A-Za-z0-9_-]{11})"',
          ),
          RegExp(
            r'\\"videoRenderer\\"[\s\S]{0,300}?\\"videoId\\"\s*:\s*\\"([A-Za-z0-9_-]{11})\\"',
          ),
          RegExp(r'watch\?v=([A-Za-z0-9_-]{11})'),
          RegExp(r'"videoId"\s*:\s*"([A-Za-z0-9_-]{11})"'),
        ];
        for (final pattern in patterns) {
          final id = pattern.firstMatch(body)?.group(1);
          if (id != null) return id;
        }
      } catch (_) {
        // Continue through independent YouTube web routes.
      }
    }
    // Final direct resolver: obtain YouTube's current public web client key at
    // runtime and use its own InnerTube search endpoint. No key is bundled.
    try {
      final bootstrap = await http
          .get(Uri.https('www.youtube.com', '/'), headers: headers)
          .timeout(const Duration(seconds: 8));
      final apiKey = RegExp(
        r'"INNERTUBE_API_KEY"\s*:\s*"([^"]+)"',
      ).firstMatch(bootstrap.body)?.group(1);
      final clientVersion = RegExp(
            r'"INNERTUBE_CLIENT_VERSION"\s*:\s*"([^"]+)"',
          ).firstMatch(bootstrap.body)?.group(1) ??
          '2.20260920.01.00';
      if (apiKey != null && apiKey.isNotEmpty) {
        final response = await http
            .post(
              Uri.https(
                'www.youtube.com',
                '/youtubei/v1/search',
                {'key': apiKey, 'prettyPrint': 'false'},
              ),
              headers: {...headers, 'Content-Type': 'application/json'},
              body: jsonEncode({
                'context': {
                  'client': {
                    'clientName': 'WEB',
                    'clientVersion': clientVersion,
                    'hl': 'en',
                    'gl': 'US',
                  },
                },
                'query': query,
              }),
            )
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final id = RegExp(
            r'"videoRenderer"\s*:\s*\{[\s\S]{0,300}?"videoId"\s*:\s*"([A-Za-z0-9_-]{11})"',
          ).firstMatch(response.body)?.group(1);
          if (id != null) return id;
        }
      }
    } catch (_) {
      // Native YouTube search + Accessibility remains the last fallback.
    }
    return null;
  }

  static String? _extractYouTubeVideoId(String value) {
    final input = value.trim();
    if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(input)) return input;
    final patterns = <RegExp>[
      RegExp(r'youtu\.be/([A-Za-z0-9_-]{11})'),
      RegExp(r'[?&]v=([A-Za-z0-9_-]{11})'),
      RegExp(r'youtube\.com/(?:shorts|embed)/([A-Za-z0-9_-]{11})'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(input);
      if (match != null) return match.group(1);
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> resolveGalleryImages(
      String query) async {
    final raw = await _channel.invokeMethod<List<dynamic>>(
          'resolveGalleryImages',
          {'query': query},
        ) ??
        const [];
    return raw.whereType<Map>().map((item) {
      return item.map((key, value) => MapEntry(key.toString(), value));
    }).toList();
  }

  static Future<bool> placeCellularCall(String phone) async =>
      await _channel
          .invokeMethod<bool>('placeCellularCall', {'phone': phone}) ??
      false;

  static Future<bool> shareWhatsAppImage({
    required String imageUri,
    required String recipient,
    required String phone,
  }) async =>
      await _channel.invokeMethod<bool>('shareWhatsAppImage', {
        'imageUri': imageUri,
        'recipient': recipient,
        'phone': phone,
      }) ??
      false;

  static Future<List<Map<String, dynamic>>> resolveContacts(
      String query) async {
    final raw = await _channel.invokeMethod<List<dynamic>>(
          'resolveContacts',
          {'query': query},
        ) ??
        const [];
    return raw.whereType<Map>().map((item) {
      return item.map((key, value) => MapEntry(key.toString(), value));
    }).toList();
  }

  static Future<bool> sendWhatsAppMessage({
    required String phone,
    required String message,
  }) async =>
      await _channel.invokeMethod<bool>('sendWhatsAppMessage', {
        'phone': phone,
        'message': message,
      }) ??
      false;

  static Future<bool> startWhatsAppCall({
    required String phone,
    required String callType,
  }) async =>
      await _channel.invokeMethod<bool>('startWhatsAppCall', {
        'phone': phone,
        'callType': callType,
      }) ??
      false;

  static Future<bool> setMediaVolume(int percent) async =>
      await _channel.invokeMethod<bool>(
        'setMediaVolume',
        {'percent': percent.clamp(0, 100)},
      ) ??
      false;

  static Future<int> adjustMediaVolume(String direction,
          {int steps = 1}) async =>
      await _channel.invokeMethod<int>('adjustMediaVolume', {
        'direction': direction,
        'steps': steps.clamp(1, 10),
      }) ??
      -1;

  static Future<bool> setRingerMode(String mode) async =>
      await _channel.invokeMethod<bool>('setRingerMode', {'mode': mode}) ??
      false;

  static Future<bool> openHotspotSettings() async =>
      await _channel.invokeMethod<bool>('openHotspotSettings') ?? false;

  static Future<Map<String, dynamic>> scheduleReminder({
    required String id,
    required String title,
    required String body,
    required int delayMinutes,
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'scheduleReminder',
      {
        'id': id,
        'title': title,
        'body': body,
        'delayMinutes': delayMinutes.clamp(1, 525600),
      },
    );
    return raw?.map((key, value) => MapEntry(key.toString(), value)) ??
        {'success': false, 'error': 'Reminder scheduling failed'};
  }

  static Future<bool> cancelReminder(String id) async =>
      await _channel.invokeMethod<bool>('cancelReminder', {'id': id}) ?? false;

  static Future<Map<String, dynamic>> biometricConfirm(String reason) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'biometricConfirm',
      {'reason': reason},
    );
    return raw?.map((key, value) => MapEntry(key.toString(), value)) ??
        {
          'success': false,
          'authenticated': false,
          'message': 'Authentication unavailable'
        };
  }

  static Future<bool> lockScreen() async =>
      await _channel.invokeMethod<bool>('lockScreen') ?? false;

  static Future<Map<String, dynamic>> requestSecureUnlock() async {
    final raw = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('requestSecureUnlock');
    return raw?.map((key, value) => MapEntry(key.toString(), value)) ??
        {
          'requested': false,
          'message': 'Android authentication request failed'
        };
  }

  static Future<bool> answerCall() async =>
      await _channel.invokeMethod<bool>('answerCall') ?? false;

  static Future<bool> rejectCall() async =>
      await _channel.invokeMethod<bool>('rejectCall') ?? false;

  static Future<Map<String, dynamic>> readScreen() async {
    final raw = await _channel.invokeMethod<String>('getScreenNodeTree') ??
        '{"status":"empty","message":"No screen data returned."}';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return {'status': 'error', 'message': 'Screen data was not valid JSON.'};
  }

  static Future<bool> clickText(String text) async =>
      await _channel.invokeMethod<bool>('clickText', {'text': text}) ?? false;

  static Future<bool> typeText(String text) async =>
      await _channel.invokeMethod<bool>('typeText', {'text': text}) ?? false;

  static Future<bool> tap(double x, double y) async =>
      await _channel.invokeMethod<bool>('tap', {'x': x, 'y': y}) ?? false;

  static Future<bool> swipe({
    required double startX,
    required double startY,
    required double endX,
    required double endY,
    int duration = 350,
  }) async =>
      await _channel.invokeMethod<bool>('dispatchGesture', {
        'startX': startX,
        'startY': startY,
        'endX': endX,
        'endY': endY,
        'duration': duration,
      }) ??
      false;

  static Future<List<dynamic>> recentNotifications() async =>
      await _channel.invokeMethod<List<dynamic>>('getRecentNotifications') ??
      const [];
}
