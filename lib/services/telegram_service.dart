import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../secure_config_manager.dart';
import '../unified_ai_gateway.dart';
import 'advanced_device_service.dart';
import 'maya_settings_service.dart';
import 'futuristic_core_service.dart';
import 'device_control_service.dart';

/// Telegram owner bridge for Maya.
///
/// The bot uses long polling only while the Maya process is alive. It removes
/// stale webhooks, validates the token, persists the update offset, restricts
/// control to one encrypted owner chat ID, and routes AI action tags through
/// the same device-control safety layer used by the in-app fallback assistant.
class TelegramService {
  static final TelegramService _instance = TelegramService._internal();
  factory TelegramService() => _instance;
  TelegramService._internal();

  final SecureConfigManager _config = SecureConfigManager();
  final MayaSettingsService _settings = MayaSettingsService();
  final FuturisticCoreService _core = FuturisticCoreService();
  final UnifiedAIGateway _gateway = UnifiedAIGateway();

  bool _running = false;
  int _offset = 0;
  int _generation = 0;
  String _status = 'Telegram is not started.';
  String _botName = 'Maya';

  bool get isRunning => _running;
  String get status => _status;

  Future<bool> start() async {
    if (_running) return true;
    final token = (await _config.getTelegramToken())?.trim() ?? '';
    if (token.isEmpty) {
      _status = 'Telegram token is missing in GOD-MODE Providers.';
      return false;
    }

    _status = 'Validating Telegram bot…';
    final identity = await _api(token, 'getMe', const {});
    if (identity == null || identity['ok'] != true) {
      _status = 'Telegram token was rejected. Check the BotFather token.';
      return false;
    }
    final result = identity['result'];
    if (result is Map) {
      _botName = result['username']?.toString() ??
          result['first_name']?.toString() ??
          'Maya';
    }

    // getUpdates cannot work while a webhook is configured. Removing it is
    // the most common fix for bots that appear completely silent.
    final webhook = await _api(token, 'deleteWebhook', {
      'drop_pending_updates': false,
    });
    if (webhook == null || webhook['ok'] != true) {
      _status = 'Could not disable the Telegram webhook.';
      return false;
    }

    _offset = await _config.getTelegramUpdateOffset();
    if (_offset <= 0) await _initializeOffset(token);
    _running = true;
    final generation = ++_generation;
    _status = '@$_botName connected • owner-only long polling active';
    unawaited(_pollLoop(token, generation));

    final owner = (await _config.getTelegramChatId())?.trim() ?? '';
    if (owner.isNotEmpty) {
      await _sendMessage(
        token,
        owner,
        '✅ MAYA Telegram bridge online.\n'
        'Device controls and AI replies are ready while the Maya app process is running.\n'
        'Send /help to see commands.',
      );
    }
    return true;
  }

  Future<bool> restart() async {
    stop();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return start();
  }

  void stop() {
    _running = false;
    _generation++;
    _status = 'Telegram stopped.';
  }

  Future<void> _initializeOffset(String token) async {
    final data = await _api(token, 'getUpdates', {
      'offset': -1,
      'limit': 1,
      'timeout': 0,
      'allowed_updates': ['message'],
    });
    final updates = data?['result'];
    if (updates is List && updates.isNotEmpty && updates.last is Map) {
      final id = (updates.last as Map)['update_id'];
      if (id is int) {
        _offset = id + 1;
        await _config.setTelegramUpdateOffset(_offset);
      }
    }
  }

  Future<void> _pollLoop(String token, int generation) async {
    var delaySeconds = 2;
    var consecutiveFailures = 0;
    while (_running && generation == _generation) {
      try {
        final data = await _api(
          token,
          'getUpdates',
          {
            'offset': _offset,
            'timeout': 25,
            'allowed_updates': ['message'],
          },
          timeout: const Duration(seconds: 32),
        );
        if (!_running || generation != _generation) return;
        if (data == null || data['ok'] != true) {
          final description = data?['description']?.toString() ?? 'No response';
          consecutiveFailures++;
          if (data?['error_code'] == 401) {
            _status = 'Telegram token rejected. Update the BotFather token.';
            _running = false;
            return;
          }
          if (description.toLowerCase().contains('conflict')) {
            _status =
                'Telegram conflict detected • repairing webhook transport';
            await _repairTransport(token);
          } else {
            _status = 'Telegram polling failed: $description';
            if (consecutiveFailures >= 3) await _repairTransport(token);
          }
          await Future<void>.delayed(Duration(seconds: delaySeconds));
          delaySeconds = (delaySeconds * 2).clamp(2, 30).toInt();
          continue;
        }

        delaySeconds = 2;
        consecutiveFailures = 0;
        _status = '@$_botName connected • listening';
        final updates = data['result'];
        if (updates is! List) continue;
        for (final raw in updates.whereType<Map>()) {
          final update =
              raw.map((key, value) => MapEntry(key.toString(), value));
          final id = update['update_id'];
          if (id is int) {
            _offset = id + 1;
            await _config.setTelegramUpdateOffset(_offset);
          }
          await _handleUpdate(update, token);
        }
      } catch (error) {
        _status = 'Telegram network error: ${_short(error)}';
        await Future<void>.delayed(Duration(seconds: delaySeconds));
        delaySeconds = (delaySeconds * 2).clamp(2, 30).toInt();
      }
    }
  }

  Future<void> _repairTransport(String token) async {
    // Safe and idempotent self-healing: long polling and webhooks cannot be
    // active together. This does not bypass a real second polling process,
    // but recovers stale webhook state and confirms whether the token lives.
    final identity = await _api(token, 'getMe', const {});
    if (identity == null || identity['ok'] != true) return;
    await _api(token, 'deleteWebhook', {'drop_pending_updates': false});
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }

  Future<void> _handleUpdate(Map<String, dynamic> update, String token) async {
    final rawMessage = update['message'] ?? update['edited_message'];
    if (rawMessage is! Map) return;
    final message =
        rawMessage.map((key, value) => MapEntry(key.toString(), value));
    final rawChat = message['chat'];
    if (rawChat is! Map) return;
    final chatId = rawChat['id']?.toString() ?? '';
    final text = message['text']?.toString().trim() ?? '';
    if (chatId.isEmpty || text.isEmpty) return;

    final savedChatId = (await _config.getTelegramChatId())?.trim() ?? '';
    if (savedChatId.isEmpty) {
      _status =
          'Telegram owner is not paired. Save the displayed chat ID inside Maya.';
      await _sendMessage(
        token,
        chatId,
        '🔒 Maya rejected automatic owner pairing.\n'
        'Your chat ID is: $chatId\n\n'
        'For security, open Maya on the phone → GOD-MODE → Providers → '
        'Telegram Owner Chat ID, save this number, then restart Telegram.',
      );
      return;
    }
    if (savedChatId != chatId) {
      _status = 'Blocked unauthorized Telegram chat $chatId';
      return;
    }

    await _sendChatAction(token, chatId, 'typing');
    try {
      final direct = await _runCommand(text, chatId);
      if (direct != null) {
        await _core.record('telegram_${text.split(RegExp(r'\s+')).first}', {
          'success': !direct.startsWith('❌'),
          'message': direct,
        });
        await _sendMessage(token, chatId, direct);
        return;
      }

      const telegramPrompt =
          'You are Maya AI responding through Foysol’s private Telegram owner chat. '
          'You have the same provider intelligence and approved Android device actions as the in-app fallback assistant. '
          'Use a real action tag only for a clear command and never claim an action succeeded before execution. '
          'Messages, calls, purchases, deletion, posting, account changes, and private-data sharing require immediate explicit confirmation. '
          'Keep Telegram responses concise and readable.';
      final aiRequest = text.toLowerCase().startsWith('/maya ')
          ? text.substring(text.indexOf(' ') + 1).trim()
          : text;
      final response = await _gateway.query(
        aiRequest,
        systemPrompt:
            '$telegramPrompt\n\n${DeviceControlService.actionSystemPrompt}',
      );
      final cleaned = await DeviceControlService.parseAndExecute(response);
      await _sendMessage(
        token,
        chatId,
        cleaned.trim().isEmpty ? 'The action completed.' : cleaned,
      );
    } catch (error) {
      _status = 'Telegram command failed: ${_short(error)}';
      await _sendMessage(
          token, chatId, '❌ Maya command failed: ${_short(error)}');
    }
  }

  Future<String?> _runCommand(String text, String chatId) async {
    final parts = text.split(RegExp(r'\s+'));
    final command = parts.first.toLowerCase().split('@').first;
    final argument = text.length > parts.first.length
        ? text.substring(parts.first.length).trim()
        : '';

    switch (command) {
      case '/start':
      case '/help':
        return _helpText;
      case '/ping':
        return '✅ Maya is online • ${DateTime.now().toIso8601String()}';
      case '/whoami':
        return '🔐 Authorized owner chat ID: $chatId';
      case '/status':
        final accessibility =
            await AdvancedDeviceService.isAccessibilityEnabled();
        return 'MAYA STATUS\n'
            '• Telegram: $_status\n'
            '• Accessibility: ${accessibility ? 'ENABLED' : 'DISABLED'}\n'
            '• Update offset: $_offset\n'
            '• Security: owner-only';
      case '/screen':
        final screen = await AdvancedDeviceService.readScreen();
        return screen['status'] == 'ok'
            ? '📱 ${screen['packageName'] ?? 'Active app'} • ${screen['nodeCount'] ?? 0} readable nodes${screen['treeTruncated'] == true ? ' • truncated' : ''}'
            : '❌ ${screen['message'] ?? 'No readable screen content.'}';
      case '/notifications':
        if (!await _settings.get<bool>('readNotifications', false)) {
          return '❌ Notification reading is disabled in Maya GOD-MODE.';
        }
        final items = await AdvancedDeviceService.recentNotifications();
        if (items.isEmpty) return 'No recent notifications are available.';
        return items.take(8).map((item) => '• ${_short(item, 240)}').join('\n');
      case '/torch':
        final enabled = {'on', '1', 'true'}.contains(argument.toLowerCase());
        if (!enabled &&
            !{'off', '0', 'false'}.contains(argument.toLowerCase())) {
          return 'Usage: /torch on or /torch off';
        }
        await DeviceControlService.toggleFlashlight(enabled);
        return '🔦 Flashlight ${enabled ? 'on' : 'off'}.';
      case '/volume':
        if (argument.toLowerCase() == 'up' ||
            argument.toLowerCase() == 'down') {
          final value = await AdvancedDeviceService.adjustMediaVolume(
              argument.toLowerCase());
          return '🔊 Media volume: $value%';
        }
        final value = int.tryParse(argument);
        if (value == null)
          return 'Usage: /volume 0-100, /volume up, or /volume down';
        final success = await AdvancedDeviceService.setMediaVolume(value);
        return success
            ? '🔊 Media volume set to ${value.clamp(0, 100)}%.'
            : '❌ Volume change failed.';
      case '/search':
        if (argument.isEmpty) return 'Usage: /search your query';
        final success = await AdvancedDeviceService.searchWeb(argument);
        return success
            ? '🌐 Search opened on the phone.'
            : '❌ Search could not be opened.';
      case '/youtube':
        if (argument.isEmpty) return 'Usage: /youtube video name or URL';
        final result = await AdvancedDeviceService.playYouTube(argument);
        if (result['success'] != true) return '❌ YouTube could not be opened.';
        return result['direct'] == true
            ? '▶️ Resolved and opened the video directly in YouTube.'
            : '🔎 YouTube search opened; direct resolution was unavailable.';
      case '/open':
        if (argument.isEmpty)
          return 'Usage: /open chrome|youtube|whatsapp|package.name';
        final packageName = _packageFor(argument);
        final success = await AdvancedDeviceService.openApp(packageName);
        return success ? '📲 Opened $argument.' : '❌ App not found: $argument';
      case '/lock':
        if (argument.toLowerCase() != 'confirm')
          return 'Sensitive action. Send exactly: /lock confirm';
        final lockAuth = await AdvancedDeviceService.biometricConfirm(
          'Authorize remote Telegram request to lock this phone',
        );
        if (lockAuth['authenticated'] != true) {
          return '❌ Physical biometric/device authentication was not completed on the phone.';
        }
        final success = await AdvancedDeviceService.lockScreen();
        return success
            ? '🔒 Phone locked.'
            : '❌ Lock failed. Enable Maya Accessibility.';
      case '/unlock':
        if (argument.toLowerCase() != 'confirm') {
          return 'Sensitive action. Send exactly: /unlock confirm';
        }
        final unlockAuth = await AdvancedDeviceService.biometricConfirm(
          'Authorize remote Telegram secure-unlock request',
        );
        if (unlockAuth['authenticated'] != true) {
          return '❌ Physical biometric/device authentication was not completed on the phone.';
        }
        final result = await AdvancedDeviceService.requestSecureUnlock();
        return result['alreadyUnlocked'] == true
            ? '🔓 Phone is already unlocked.'
            : result['requested'] == true
                ? '🔐 Screen awakened. Complete Android fingerprint, face, PIN, or password authentication on the phone.'
                : '❌ ${result['message'] ?? 'Android authentication request failed.'}';
      case '/vision':
        return '👁️ Camera vision must remain visible for privacy. Open Maya and say “Omega Vision ${argument.toLowerCase() == 'back' ? 'back' : 'front'} camera.”';
      case '/maya':
        if (argument.isEmpty) return 'Usage: /maya your request';
        return null;
      default:
        return text.startsWith('/') ? 'Unknown command. Send /help.' : null;
    }
  }

  String _packageFor(String value) {
    final normalized = value.toLowerCase().trim();
    const known = {
      'chrome': 'com.android.chrome',
      'youtube': 'com.google.android.youtube',
      'whatsapp': 'com.whatsapp',
      'whatsapp business': 'com.whatsapp.w4b',
      'telegram': 'org.telegram.messenger',
      'settings': 'com.android.settings',
    };
    return known[normalized] ?? value.trim();
  }

  Future<Map<String, dynamic>?> _api(
    String token,
    String method,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('https://api.telegram.org/bot$token/$method'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(timeout);
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final data =
            decoded.map((key, value) => MapEntry(key.toString(), value));
        if (response.statusCode != 200) {
          _status =
              'Telegram HTTP ${response.statusCode}: ${data['description'] ?? 'error'}';
        }
        return data;
      }
    } catch (error) {
      _status = 'Telegram API error: ${_short(error)}';
    }
    return null;
  }

  Future<void> _sendChatAction(
      String token, String chatId, String action) async {
    await _api(token, 'sendChatAction', {'chat_id': chatId, 'action': action});
  }

  Future<bool> _sendMessage(String token, String chatId, String text) async {
    final normalized = text.trim().isEmpty ? '…' : text.trim();
    final chunks = <String>[];
    var remaining = normalized;
    while (remaining.length > 3800) {
      var split = remaining.lastIndexOf('\n', 3800);
      if (split < 1000) split = 3800;
      chunks.add(remaining.substring(0, split));
      remaining = remaining.substring(split).trimLeft();
    }
    chunks.add(remaining);

    for (final chunk in chunks) {
      final result = await _api(token, 'sendMessage', {
        'chat_id': chatId,
        'text': chunk,
        'disable_web_page_preview': true,
      });
      if (result == null || result['ok'] != true) return false;
    }
    return true;
  }

  static String _short(Object? error, [int max = 120]) {
    final text = error?.toString().replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    return text.length <= max ? text : '${text.substring(0, max)}…';
  }

  static const String _helpText = 'MAYA TELEGRAM CONTROL\n\n'
      '/status — bot and Accessibility status\n'
      '/ping — connection test\n'
      '/whoami — owner chat ID\n'
      '/screen — active screen status\n'
      '/notifications — recent notifications\n'
      '/torch on|off\n'
      '/volume 0-100|up|down\n'
      '/search query\n'
      '/youtube query or URL\n'
      '/open chrome|youtube|whatsapp|package.name\n'
      '/lock confirm\n'
      '/unlock confirm — wake screen and open Android authentication\n'
      '/vision front|back — privacy-safe instructions\n'
      '/maya request — ask Maya AI\n\n'
      'Plain messages also go to Maya AI and can use approved device-action tags.';
}
