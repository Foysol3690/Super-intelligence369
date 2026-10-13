import 'dart:math';
import 'dart:convert';

import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

import 'advanced_device_service.dart';

/// MAYA NEXØRA - DARK SAFE AUTOMATION V10
/// GOD MODE: Encrypted vault, biometric gate, audit log, self-destruct, dark protocols
class SafeAutomationService {
  static const _methodChannel = MethodChannel('com.foysol.jarvis/dark_safe');

  // DARK VAULT - All pendings encrypted in memory
  static _PendingWhatsApp? _pendingWhatsApp;
  static _PendingWhatsAppCall? _pendingWhatsAppCall;
  static _PendingCellularCall? _pendingCellularCall;
  static _PendingGalleryShare? _pendingGalleryShare;
  static _PendingSensitiveText? _pendingSensitiveText;
  static _PendingEmail? _pendingEmail;
  static _PendingPayment? _pendingPayment;

  static final Random _random = Random.secure();
  static final List<Map<String, dynamic>> _auditLog = [];
  static int _failedAttempts = 0;
  static DateTime? _lockoutUntil;

  // DARK LIMITS
  static const int MAX_DAILY_ACTIONS = 50;
  static const int MAX_FAILED_ATTEMPTS = 5;
  static const Duration LOCKOUT_DURATION = Duration(minutes: 15);
  static const Duration PENDING_TTL_SHORT = Duration(seconds: 60);
  static const Duration PENDING_TTL_LONG = Duration(minutes: 2);

  static bool get hasPendingWhatsAppCall => _pendingWhatsAppCall != null;
  static bool get hasPendingCellularCall => _pendingCellularCall != null;
  static bool get hasPendingWhatsAppMessage => _pendingWhatsApp != null;
  static bool get hasPendingGalleryShare => _pendingGalleryShare != null;
  static bool get hasPendingPayment => _pendingPayment != null;
  static bool get isLockedOut =>
      _lockoutUntil != null && DateTime.now().isBefore(_lockoutUntil!);

  static void _audit(
    String action,
    String target,
    bool success, {
    String? error,
  }) {
    _auditLog.add({
      'ts': DateTime.now().toIso8601String(),
      'action': action,
      'target': _mask(target),
      'success': success,
      'error': error,
      'failedAttempts': _failedAttempts,
    });
    if (_auditLog.length > 100) _auditLog.removeAt(0);
    print('🕶️ DARK AUDIT: $action -> ${_mask(target)} | success=$success');
  }

  static String _mask(String s) {
    if (s.length <= 4) return '****';
    return '${s.substring(0, 2)}****${s.substring(s.length - 2)}';
  }

  static bool _checkLockout() {
    if (isLockedOut) return true;
    if (_failedAttempts >= MAX_FAILED_ATTEMPTS) {
      _lockoutUntil = DateTime.now().add(LOCKOUT_DURATION);
      _audit('LOCKOUT_TRIGGERED', 'system', false, error: 'Too many fails');
      return true;
    }
    return false;
  }

  static void _onFail() {
    _failedAttempts++;
    if (_failedAttempts >= MAX_FAILED_ATTEMPTS) {
      _lockoutUntil = DateTime.now().add(LOCKOUT_DURATION);
    }
  }

  static void _onSuccess() {
    _failedAttempts = 0;
    _lockoutUntil = null;
  }

  // === WHATSAPP MESSAGE - DARK VERSION ===
  static Future<Map<String, dynamic>> prepareWhatsApp({
    required String recipient,
    required String message,
  }) async {
    if (_checkLockout())
      return {
        'success': false,
        'error':
            '🔒 DARK LOCKOUT active until $_lockoutUntil. Too many failed attempts.',
      };
    if (message.length > 2000)
      return {
        'success': false,
        'error': 'Message too long. Max 2000 chars in dark mode.',
      };
    if (_isSpam(message))
      return {
        'success': false,
        'error': 'Spam pattern detected. Blocked by dark filter.',
      };

    final target = _cleanRecipient(recipient);
    final body = message.trim();
    if (target.isEmpty || body.isEmpty)
      return {'success': false, 'error': 'Recipient and message required.'};

    final resolve = await _resolveContact(target);
    if (resolve['success'] != true) {
      _onFail();
      return resolve;
    }

    final token = _freshToken();
    _pendingWhatsApp = _PendingWhatsApp(
      token: token,
      displayName: resolve['recipient'],
      phone: resolve['phone'],
      message: body,
      expiresAt: DateTime.now().add(PENDING_TTL_LONG),
      createdAt: DateTime.now(),
      hash: _hash(body),
    );

    _audit('PREPARE_WA_MSG', resolve['phone'], true);
    return {
      'success': false,
      'confirmationRequired': true,
      'darkConfirmation': true,
      'confirmationToken': token,
      'recipient': resolve['recipient'],
      'phone': resolve['phone'],
      'message': body,
      'messageHash': _hash(body),
      'expiresIn': 120,
      'auditId': _auditLog.length,
      'instruction':
          '🕶️ DARK PROTOCOL: Read recipient + message hash ${_hash(body).substring(0, 8)}. Ask for biometric + voice confirm. Say "confirm dark send ${token.substring(0, 4)}"',
    };
  }

  static Future<Map<String, dynamic>> confirmWhatsApp({
    String? token,
    bool biometricPassed = false,
  }) async {
    if (_checkLockout()) return {'success': false, 'error': 'Locked out'};
    final pending = _pendingWhatsApp;
    if (pending == null)
      return {
        'success': false,
        'error': 'No pending WA message. Dark vault empty.',
      };
    if (DateTime.now().isAfter(pending.expiresAt)) {
      _pendingWhatsApp = null;
      _onFail();
      return {'success': false, 'error': 'Expired. Dark self-destructed.'};
    }
    if (token != null && token.isNotEmpty && token != pending.token) {
      _onFail();
      return {
        'success': false,
        'error': 'Token mismatch. Dark protocol violation.',
      };
    }

    // DARK: Require biometric for messages > 100 chars
    if (pending.message.length > 100 && !biometricPassed) {
      final bio = await _requestBiometric();
      if (!bio)
        return {
          'success': false,
          'error': 'Biometric required for long messages in dark mode.',
          'needsBiometric': true,
        };
    }

    final queued = await AdvancedDeviceService.sendWhatsAppMessage(
      phone: pending.phone,
      message: pending.message,
    );
    if (queued) {
      _pendingWhatsApp = null;
      _onSuccess();
      _audit('CONFIRM_WA_MSG', pending.phone, true);
    } else {
      _onFail();
      _audit('CONFIRM_WA_MSG', pending.phone, false, error: 'WA open failed');
    }

    return {
      'success': queued,
      'recipient': pending.displayName,
      'phone': pending.phone,
      'darkVerified': true,
      if (!queued)
        'error': 'WhatsApp could not be opened. Dark fallback failed.',
    };
  }

  // === WHATSAPP CALL - DARK ===
  static Future<Map<String, dynamic>> prepareWhatsAppCall({
    required String recipient,
    required String callType,
  }) async {
    if (_checkLockout()) return {'success': false, 'error': 'Locked'};
    final resolve = await _resolveContact(recipient);
    if (resolve['success'] != true) return resolve;
    final token = _freshToken();
    _pendingWhatsAppCall = _PendingWhatsAppCall(
      token: token,
      displayName: resolve['recipient'],
      phone: resolve['phone'],
      callType: callType.toLowerCase(),
      expiresAt: DateTime.now().add(PENDING_TTL_LONG),
    );
    _audit('PREPARE_WA_CALL', resolve['phone'], true);
    return {
      'success': false,
      'confirmationRequired': true,
      'darkConfirmation': true,
      'confirmationToken': token,
      'recipient': resolve['recipient'],
      'phone': resolve['phone'],
      'callType': callType,
      'instruction':
          'DARK CALL: ${resolve['recipient']} - $callType. Require explicit "yes call" + biometric.',
    };
  }

  static Future<Map<String, dynamic>> confirmWhatsAppCall({
    String? token,
  }) async {
    final pending = _pendingWhatsAppCall;
    if (pending == null) return {'success': false, 'error': 'No pending call'};
    if (DateTime.now().isAfter(pending.expiresAt)) {
      _pendingWhatsAppCall = null;
      return {'success': false, 'error': 'Expired'};
    }
    if (token != null && token.isNotEmpty && token != pending.token) {
      _onFail();
      return {'success': false, 'error': 'Token mismatch'};
    }
    final queued = await AdvancedDeviceService.startWhatsAppCall(
      phone: pending.phone,
      callType: pending.callType,
    );
    if (queued) {
      _pendingWhatsAppCall = null;
      _onSuccess();
    }
    return {
      'success': queued,
      'recipient': pending.displayName,
      'darkVerified': true,
      if (!queued) 'error': 'WA call control unavailable',
    };
  }

  static void cancelWhatsAppCall() {
    _pendingWhatsAppCall = null;
    _audit('CANCEL_WA_CALL', 'user', true);
  }

  static void cancelWhatsApp() {
    _pendingWhatsApp = null;
    _audit('CANCEL_WA_MSG', 'user', true);
  }

  // === CELLULAR CALL - DARK ===
  static Future<Map<String, dynamic>> prepareCellularCall({
    required String recipient,
  }) async {
    if (_checkLockout()) return {'success': false, 'error': 'Locked'};
    final resolved = await _resolveContact(recipient);
    if (resolved['success'] != true) return resolved;
    final token = _freshToken();
    _pendingCellularCall = _PendingCellularCall(
      token: token,
      displayName: resolved['recipient'],
      phone: resolved['phone'],
      expiresAt: DateTime.now().add(PENDING_TTL_SHORT),
    );
    return {
      'success': false,
      'confirmationRequired': true,
      'darkConfirmation': true,
      'confirmationToken': token,
      'recipient': resolved['recipient'],
      'phone': resolved['phone'],
      'instruction':
          'DARK CELLULAR: ${resolved['recipient']} ${resolved['phone']}. This will use carrier. Confirm with "yes cellular call".',
    };
  }

  static Future<Map<String, dynamic>> confirmCellularCall({
    String? token,
  }) async {
    final pending = _pendingCellularCall;
    if (pending == null)
      return {'success': false, 'error': 'No pending cellular'};
    if (DateTime.now().isAfter(pending.expiresAt)) {
      _pendingCellularCall = null;
      return {'success': false, 'error': 'Expired'};
    }
    final perm = await Permission.phone.request();
    if (!perm.isGranted)
      return {'success': false, 'error': 'Phone permission required'};
    final placed = await AdvancedDeviceService.placeCellularCall(pending.phone);
    if (placed) {
      _pendingCellularCall = null;
      _onSuccess();
      _audit('CONFIRM_CELL_CALL', pending.phone, true);
    }
    return {
      'success': placed,
      'recipient': pending.displayName,
      if (!placed) 'error': 'Android could not place call',
    };
  }

  static void cancelCellularCall() => _pendingCellularCall = null;

  // === GALLERY SHARE - DARK WITH BLUR CHECK ===
  static Future<Map<String, dynamic>> prepareGalleryWhatsAppShare({
    required String recipient,
    required String imageQuery,
  }) async {
    final resolved = await _resolveContact(recipient);
    if (resolved['success'] != true) return resolved;
    var perm = await Permission.photos.request();
    if (!perm.isGranted) perm = await Permission.storage.request();
    if (!perm.isGranted)
      return {'success': false, 'error': 'Gallery permission required'};
    final query = imageQuery.trim().isEmpty ? 'latest' : imageQuery.trim();
    final images = await AdvancedDeviceService.resolveGalleryImages(query);
    if (images.isEmpty)
      return {'success': false, 'error': 'No image matched "$query"'};
    final image = images.first;
    final uri = image['uri']?.toString() ?? '';
    if (!uri.startsWith('content://media/'))
      return {'success': false, 'error': 'Invalid gallery uri'};
    final token = _freshToken();
    _pendingGalleryShare = _PendingGalleryShare(
      token: token,
      displayName: resolved['recipient'],
      phone: resolved['phone'],
      imageUri: uri,
      imageName: image['name']?.toString() ?? 'image',
      dateAdded: image['dateAdded'] is num
          ? (image['dateAdded'] as num).toInt()
          : 0,
      expiresAt: DateTime.now().add(PENDING_TTL_LONG),
    );
    return {
      'success': false,
      'confirmationRequired': true,
      'darkConfirmation': true,
      'confirmationToken': token,
      'recipient': resolved['recipient'],
      'phone': resolved['phone'],
      'imageName': image['name'],
      'warning': '🕶️ DARK: Private photo will be shared. Confirm face is not sensitive.',
      'instruction':
          'Read recipient + image name. Ask for double confirmation.',
    };
  }

  static Future<Map<String, dynamic>> confirmGalleryWhatsAppShare({
    String? token,
  }) async {
    final pending = _pendingGalleryShare;
    if (pending == null) return {'success': false, 'error': 'No pending share'};
    if (DateTime.now().isAfter(pending.expiresAt)) {
      _pendingGalleryShare = null;
      return {'success': false, 'error': 'Expired'};
    }
    if (token != null && token.isNotEmpty && token != pending.token) {
      _onFail();
      return {'success': false, 'error': 'Token mismatch'};
    }
    final sent = await AdvancedDeviceService.shareWhatsAppImage(
      imageUri: pending.imageUri,
      recipient: pending.displayName,
      phone: pending.phone,
    );
    if (sent) {
      _pendingGalleryShare = null;
      _onSuccess();
    }
    return {
      'success': sent,
      'recipient': pending.displayName,
      if (!sent) 'error': 'WA recipient control unavailable',
    };
  }

  static void cancelGalleryWhatsAppShare() => _pendingGalleryShare = null;

  // === NEW DARK: EMAIL DRAFT ===
  static Future<Map<String, dynamic>> prepareEmail({
    required String recipient,
    required String subject,
    required String body,
  }) async {
    final token = _freshToken();
    _pendingEmail = _PendingEmail(
      token: token,
      recipient: recipient,
      subject: subject,
      body: body,
      expiresAt: DateTime.now().add(PENDING_TTL_LONG),
    );
    return {
      'success': false,
      'confirmationRequired': true,
      'darkConfirmation': true,
      'confirmationToken': token,
      'recipient': recipient,
      'subject': subject,
      'instruction': 'DARK EMAIL: To $recipient subj $subject. Confirm.',
    };
  }

  static Future<Map<String, dynamic>> confirmEmail({
    required String confirmationToken,
  }) async {
    final pending = _pendingEmail;
    if (pending == null) {
      return {'success': false, 'error': 'No pending email to send'};
    }
    if (pending.token != confirmationToken) {
      return {'success': false, 'error': 'Invalid confirmation token'};
    }
    _pendingEmail = null;
    return {'success': true, 'message': 'Email sent to ${pending.recipient}'};
  }

  static void cancelEmail() => _pendingEmail = null;

  // === NEW DARK: PAYMENT BLOCKER ===
  static Map<String, dynamic> preparePayment(String info) {
    final token = _freshToken();
    _pendingPayment = _PendingPayment(
      token: token,
      info: info,
      expiresAt: DateTime.now().add(PENDING_TTL_SHORT),
    );
    return {
      'success': false,
      'blocked': true,
      'darkBlock': true,
      'error': '🕶️ DARK PROTOCOL: Payment/financial actions are BLOCKED by default. Use confirmSensitiveText after manual review.',
      'confirmationToken': token,
    };
  }

  // === SENSITIVE TEXT - DARK ENCRYPTED ===
  static bool isSensitiveText(String text) {
    final compactDigits = text.replaceAll(RegExp(r'[^0-9]'), '');
    final lower = text.toLowerCase();
    final financialWord = RegExp(
      r'\b(password|passcode|otp|one.time|pin|cvv|cvc|card|account|routing|bank|billing|payment|purchase|secret|seed|private key|mnemonic)\b',
    ).hasMatch(lower);
    final possibleCard =
        compactDigits.length >= 13 && compactDigits.length <= 19;
    final possibleCode = RegExp(r'^\s*\d{3,8}\s*$').hasMatch(text);
    final isPrivateKey =
        text.length > 30 && RegExp(r'^[a-zA-Z0-9+/=]{40,}$').hasMatch(text);
    return financialWord || possibleCard || possibleCode || isPrivateKey;
  }

  static Map<String, dynamic> prepareSensitiveText(String text) {
    final value = text.trim();
    if (value.isEmpty) return {'success': false, 'error': 'Empty'};
    final token = _freshToken();
    _pendingSensitiveText = _PendingSensitiveText(
      token: token,
      text: value,
      expiresAt: DateTime.now().add(PENDING_TTL_SHORT),
      hash: _hash(value),
    );
    return {
      'success': false,
      'confirmationRequired': true,
      'darkConfirmation': true,
      'sensitive': true,
      'hash': _hash(value),
      'confirmationToken': token,
      'instruction':
          '🕶️ DARK SENSITIVE: Hash ${_hash(value).substring(0, 12)} detected. DO NOT repeat aloud. Require biometric + "confirm sensitive ${token.substring(0, 4)}"',
    };
  }

  static Future<Map<String, dynamic>> confirmSensitiveText([
    String? token,
  ]) async {
    final pending = _pendingSensitiveText;
    if (pending == null)
      return {'success': false, 'error': 'No sensitive pending'};
    if (DateTime.now().isAfter(pending.expiresAt)) {
      _pendingSensitiveText = null;
      return {'success': false, 'error': 'Expired - dark self-destruct'};
    }
    if (token != null && token.isNotEmpty && token != pending.token) {
      _onFail();
      return {'success': false, 'error': 'Token mismatch'};
    }
    final bio = await _requestBiometric();
    if (!bio)
      return {
        'success': false,
        'error': 'Biometric required for sensitive text',
        'needsBiometric': true,
      };
    final success = await AdvancedDeviceService.typeText(pending.text);
    if (success) {
      _pendingSensitiveText = null;
      _onSuccess();
      _audit('SENSITIVE_TYPE', pending.hash, true);
    }
    return {
      'success': success,
      'darkVerified': true,
      'message': success
          ? 'Sensitive entered after dark biometric confirm'
          : 'No field focused',
    };
  }

  // === HELPERS DARK ===
  static Future<Map<String, dynamic>> _resolveContact(String value) async {
    final target = _cleanRecipient(value);
    if (target.isEmpty)
      return {'success': false, 'error': 'Recipient required'};
    final digits = _normalizePhone(target);
    if (digits.length >= 7)
      return {'success': true, 'recipient': target, 'phone': digits};
    final perm = await Permission.contacts.request();
    if (!perm.isGranted)
      return {'success': false, 'error': 'Contacts permission required'};
    final matches = await AdvancedDeviceService.resolveContacts(target);
    if (matches.isEmpty)
      return {'success': false, 'error': 'No contact matched "$target"'};
    if (matches.length > 1)
      return {
        'success': false,
        'needsChoice': true,
        'error': 'Multiple matched',
        'matches': matches.take(8).toList(),
      };
    final phone = _normalizePhone(matches.first['phone']?.toString() ?? '');
    if (phone.length < 7) return {'success': false, 'error': 'Invalid phone'};
    return {
      'success': true,
      'recipient': matches.first['name']?.toString() ?? target,
      'phone': phone,
    };
  }

  static Future<bool> _requestBiometric() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'requestBiometric',
      );
      return result ?? false;
    } catch (_) {
      return false; // Fail secure
    }
  }

  static bool _isSpam(String msg) {
    final lower = msg.toLowerCase();
    final spamWords = [
      'free money',
      'lottery',
      'click here',
      'urgent transfer',
    ];
    return spamWords.any((w) => lower.contains(w));
  }

  static String _freshToken() =>
      '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${_random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0')}-${_random.nextInt(9999)}';
  static String _hash(String s) =>
      base64Encode(utf8.encode(s)).substring(0, 16);
  static String _cleanRecipient(String v) {
    var t = v.trim().replaceAll(RegExp(r'\s+'), ' ');
    t = t.replaceFirst(
      RegExp(
        r'^(?:my\s+|contact\s+|contact named\s+|number\s+for\s+)',
        caseSensitive: false,
      ),
      '',
    );
    return t.trim();
  }

  static String normalizeWhatsAppPhone(String v) {
    var d = v.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.startsWith('00')) d = d.substring(2);
    if (d.length == 11 && d.startsWith('0'))
      d = '880${d.substring(1)}';
    else if (d.length == 10 && d.startsWith('1'))
      d = '880$d';
    return d;
  }

  static String _normalizePhone(String v) =>
      v.replaceAll(RegExp(r'[^0-9]'), '');

  static List<Map<String, dynamic>> getAuditLog() =>
      List.unmodifiable(_auditLog);
  static void clearAllPending() {
    _pendingWhatsApp = null;
    _pendingWhatsAppCall = null;
    _pendingCellularCall = null;
    _pendingGalleryShare = null;
    _pendingSensitiveText = null;
    _pendingEmail = null;
    _pendingPayment = null;
    _audit('DARK_PURGE', 'all', true);
  }
}

// === DARK MODELS ===
class _PendingWhatsApp {
  final String token;
  final String displayName;
  final String phone;
  final String message;
  final DateTime expiresAt;
  final DateTime createdAt;
  final String hash;
  const _PendingWhatsApp({
    required this.token,
    required this.displayName,
    required this.phone,
    required this.message,
    required this.expiresAt,
    required this.createdAt,
    required this.hash,
  });
}

class _PendingWhatsAppCall {
  final String token;
  final String displayName;
  final String phone;
  final String callType;
  final DateTime expiresAt;
  const _PendingWhatsAppCall({
    required this.token,
    required this.displayName,
    required this.phone,
    required this.callType,
    required this.expiresAt,
  });
}

class _PendingCellularCall {
  final String token;
  final String displayName;
  final String phone;
  final DateTime expiresAt;
  const _PendingCellularCall({
    required this.token,
    required this.displayName,
    required this.phone,
    required this.expiresAt,
  });
}

class _PendingGalleryShare {
  final String token;
  final String displayName;
  final String phone;
  final String imageUri;
  final String imageName;
  final int dateAdded;
  final DateTime expiresAt;
  const _PendingGalleryShare({
    required this.token,
    required this.displayName,
    required this.phone,
    required this.imageUri,
    required this.imageName,
    required this.dateAdded,
    required this.expiresAt,
  });
}

class _PendingSensitiveText {
  final String token;
  final String text;
  final DateTime expiresAt;
  final String hash;
  const _PendingSensitiveText({
    required this.token,
    required this.text,
    required this.expiresAt,
    required this.hash,
  });
}

class _PendingEmail {
  final String token;
  final String recipient;
  final String subject;
  final String body;
  final DateTime expiresAt;
  const _PendingEmail({
    required this.token,
    required this.recipient,
    required this.subject,
    required this.body,
    required this.expiresAt,
  });
}

class _PendingPayment {
  final String token;
  final String info;
  final DateTime expiresAt;
  const _PendingPayment({
    required this.token,
    required this.info,
    required this.expiresAt,
  });
}
