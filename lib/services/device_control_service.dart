import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:torch_light/torch_light.dart';

import 'advanced_device_service.dart';
import 'safe_automation_service.dart';
import 'futuristic_core_service.dart';

class DeviceControlService {
  static final _notifications = FlutterLocalNotificationsPlugin();
  static bool _notificationsReady = false;

  /// Provider-neutral action protocol so every fallback model can use the
  /// same real Android controls, not only Gemini Live function calling.
  static const String actionSystemPrompt =
      'You are Maya, a warm Android assistant. Use exactly one leading action tag when the user clearly requests a device action, then give one short natural confirmation. Never speak the raw tag. Supported tags: '
      '[ACTION:FLASHLIGHT_ON], [ACTION:FLASHLIGHT_OFF], [ACTION:BRIGHTNESS:0-100], '
      '[ACTION:VOLUME:0-100], [ACTION:VOLUME_UP:1-10], [ACTION:VOLUME_DOWN:1-10], '
      '[ACTION:RINGER:normal|vibrate|silent], [ACTION:OPEN_APP:package.name], '
      '[ACTION:SEARCH_WEB:query], [ACTION:PLAY_YOUTUBE:query or URL], '
      '[ACTION:READ_SCREEN], [ACTION:CLICK_TEXT:visible text], [ACTION:TYPE_TEXT:text], [ACTION:SENSITIVE_TEXT_CONFIRM], '
      '[ACTION:LOCK], [ACTION:UNLOCK_REQUEST], [ACTION:NOTIFY:Title|Body], [ACTION:ANSWER_CALL] to answer the '
      'current incoming call, [ACTION:REJECT_CALL] to decline it — use these only when the user clearly says so '
      'while a call is ringing; the spoken command itself is the authorization, never ask for a second confirmation. '
      'For WhatsApp, messages are always two-step. First use '
      '[ACTION:WHATSAPP_PREPARE:recipient name or number|full message] and explicitly ask the user to confirm the shown recipient and message. Only after the user clearly says confirm/send, use [ACTION:WHATSAPP_CONFIRM]. Use [ACTION:WHATSAPP_CANCEL] if they cancel. For WhatsApp calls, use [ACTION:WHATSAPP_CALL_PREPARE:audio or video|recipient] first, read back the exact contact and call type, then ask for immediate confirmation. Only after a clear confirmation use [ACTION:WHATSAPP_CALL_CONFIRM]. Use [ACTION:WHATSAPP_CALL_CANCEL] if cancelled. For SIM calls use [ACTION:SIM_CALL_PREPARE:recipient], then after exact contact/number readback and clear confirmation use [ACTION:SIM_CALL_CONFIRM]; cancel with [ACTION:SIM_CALL_CANCEL]. For gallery sharing use [ACTION:GALLERY_WHATSAPP_PREPARE:recipient|latest or file name], read back recipient and selected file, then after clear confirmation use [ACTION:GALLERY_WHATSAPP_CONFIRM]; cancel with [ACTION:GALLERY_WHATSAPP_CANCEL]. '
      'UNLOCK_REQUEST may be used only after the user explicitly confirms an unlock request. It wakes the display and opens Android’s official fingerprint, face, PIN, or password authentication; it never bypasses the keyguard. TYPE_TEXT automatically stages passwords, OTPs, card/bank/payment/billing values instead of typing them. After it reports sensitive data and the user explicitly confirms on the next turn, use [ACTION:SENSITIVE_TEXT_CONFIRM]. Never automate purchase submission, account changes, posting, deletion, or private-data sharing without immediate explicit confirmation. Never claim success before the action result. Reply in the user’s language.';

  static final RegExp _actionTag =
      RegExp(r'^\[ACTION:([A-Z_]+)(?::([^\]]*))?\]\s*', caseSensitive: false);

  static Future<void> initNotifications() async {
    if (_notificationsReady) return;
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    try {
      await _notifications.initialize(settings);
      _notificationsReady = true;
    } catch (e) {
      print('[DeviceControl] Notification init error: $e');
    }
  }

  static Future<bool> toggleFlashlight(bool on) async {
    try {
      if (on) {
        await TorchLight.enableTorch();
      } else {
        await TorchLight.disableTorch();
      }
      return true;
    } catch (e) {
      print('[DeviceControl] Flashlight error: $e');
      return false;
    }
  }

  static Future<bool> setBrightness(int percent) async {
    try {
      await ScreenBrightness()
          .setScreenBrightness(percent.clamp(0, 100) / 100.0);
      return true;
    } catch (e) {
      print('[DeviceControl] Brightness error: $e');
      return false;
    }
  }

  static Future<bool> sendNotification(String title, String body) async {
    try {
      if (!_notificationsReady) await initNotifications();
      const androidDetails = AndroidNotificationDetails(
        'maya_actions',
        'Maya Actions',
        channelDescription: 'Notifications triggered by Maya AI',
        importance: Importance.high,
        priority: Priority.high,
      );
      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        const NotificationDetails(android: androidDetails),
      );
      return true;
    } catch (e) {
      print('[DeviceControl] Notification error: $e');
      return false;
    }
  }

  static Future<String> parseAndExecute(String aiResponse) async {
    final match = _actionTag.firstMatch(aiResponse);
    if (match == null) return aiResponse;
    final action = match.group(1)?.toUpperCase() ?? '';
    final arg = match.group(2) ?? '';
    var spoken = aiResponse.substring(match.end).trim();
    final core = FuturisticCoreService();
    final tool = switch (action) {
      'LOCK' => 'lock_screen',
      'UNLOCK_REQUEST' => 'request_secure_unlock',
      'TYPE_TEXT' || 'SENSITIVE_TEXT_CONFIRM' => 'type_text',
      'WHATSAPP_CONFIRM' => 'confirm_whatsapp_message',
      'WHATSAPP_CALL_CONFIRM' => 'confirm_whatsapp_call',
      'SIM_CALL_CONFIRM' => 'confirm_cellular_call',
      'GALLERY_WHATSAPP_CONFIRM' => 'confirm_whatsapp_gallery_share',
      'OPEN_APP' => 'open_app',
      'SEARCH_WEB' => 'open_url',
      'CLICK_TEXT' => 'click_text',
      'RINGER' => 'set_ringer_mode',
      _ => action.toLowerCase(),
    };
    if (await core.blockedBySafeMode(tool)) {
      return 'Maya Safe Mode blocked this action.';
    }
    var success = true;

    try {
      switch (action) {
        case 'FLASHLIGHT_ON':
          await toggleFlashlight(true);
          break;
        case 'FLASHLIGHT_OFF':
          await toggleFlashlight(false);
          break;
        case 'BRIGHTNESS':
          final value = int.tryParse(arg);
          if (value != null) await setBrightness(value);
          break;
        case 'VOLUME':
          final value = int.tryParse(arg);
          if (value != null) await AdvancedDeviceService.setMediaVolume(value);
          break;
        case 'VOLUME_UP':
        case 'VOLUME_DOWN':
          final steps = int.tryParse(arg) ?? 1;
          final percent = await AdvancedDeviceService.adjustMediaVolume(
            action == 'VOLUME_DOWN' ? 'down' : 'up',
            steps: steps,
          );
          spoken = 'Media volume is now $percent percent.';
          break;
        case 'RINGER':
          await AdvancedDeviceService.setRingerMode(arg);
          break;
        case 'ANSWER_CALL':
          final answered = await AdvancedDeviceService.answerCall();
          if (!answered) spoken = 'I could not answer the call.';
          break;
        case 'REJECT_CALL':
          final rejected = await AdvancedDeviceService.rejectCall();
          if (!rejected) spoken = 'I could not decline the call.';
          break;
        case 'OPEN_APP':
          await AdvancedDeviceService.openApp(arg);
          break;
        case 'SEARCH_WEB':
          await AdvancedDeviceService.searchWeb(arg);
          break;
        case 'PLAY_YOUTUBE':
          final result = await AdvancedDeviceService.playYouTube(arg);
          if (result['success'] != true) {
            spoken = 'I could not open that YouTube video.';
          } else if (result['direct'] == true) {
            spoken = 'I resolved the video and opened it directly in YouTube.';
          } else {
            spoken =
                'I opened YouTube search, but direct video resolution was unavailable.';
          }
          break;
        case 'READ_SCREEN':
          final screen = await AdvancedDeviceService.readScreen();
          spoken = screen['status'] == 'ok'
              ? 'I can read the accessibility tree for ${screen['packageName']}. ${screen['nodeCount']} nodes are available.'
              : (screen['message']?.toString() ??
                  'No readable screen content is available.');
          break;
        case 'CLICK_TEXT':
          final success = await AdvancedDeviceService.clickText(arg);
          if (!success)
            spoken = 'I could not find a clickable control named $arg.';
          break;
        case 'TYPE_TEXT':
          if (SafeAutomationService.isSensitiveText(arg)) {
            SafeAutomationService.prepareSensitiveText(arg);
            spoken =
                'Sensitive or financial information detected. I will not repeat it aloud. Say confirm typing to enter it into the focused field.';
          } else {
            final success = await AdvancedDeviceService.typeText(arg);
            if (!success) spoken = 'No editable field is focused.';
          }
          break;
        case 'SENSITIVE_TEXT_CONFIRM':
          final auth = await AdvancedDeviceService.biometricConfirm(
            'Authorize Maya to enter sensitive text',
          );
          if (auth['authenticated'] != true) {
            spoken =
                'Sensitive text was not entered because device authentication was cancelled.';
            break;
          }
          final result = await SafeAutomationService.confirmSensitiveText();
          spoken = result['message']?.toString() ??
              result['error']?.toString() ??
              'Sensitive text was not entered.';
          break;
        case 'LOCK':
          final auth = await AdvancedDeviceService.biometricConfirm(
            'Authorize Maya to lock this phone',
          );
          if (auth['authenticated'] != true) {
            spoken =
                'Phone lock cancelled because device authentication was not completed.';
            break;
          }
          final locked = await AdvancedDeviceService.lockScreen();
          if (!locked) spoken = 'Phone lock failed. Enable Maya Accessibility.';
          break;
        case 'UNLOCK_REQUEST':
          final auth = await AdvancedDeviceService.biometricConfirm(
            'Authorize Maya secure-unlock request',
          );
          if (auth['authenticated'] != true) {
            spoken =
                'Secure-unlock request cancelled because device authentication was not completed.';
            break;
          }
          final result = await AdvancedDeviceService.requestSecureUnlock();
          spoken = result['alreadyUnlocked'] == true
              ? 'The phone is already unlocked.'
              : result['requested'] == true
                  ? 'I woke the phone. Authenticate with Android fingerprint, face, PIN, or password to unlock.'
                  : (result['message']?.toString() ??
                      'Android authentication could not be opened.');
          break;
        case 'NOTIFY':
          final parts = arg.split('|');
          await sendNotification(
            parts.isNotEmpty ? parts.first : 'Maya',
            parts.length > 1 ? parts.sublist(1).join('|') : '',
          );
          break;
        case 'WHATSAPP_PREPARE':
          final separator = arg.indexOf('|');
          if (separator < 1)
            return 'Tell me both the WhatsApp recipient and message.';
          final result = await SafeAutomationService.prepareWhatsApp(
            recipient: arg.substring(0, separator),
            message: arg.substring(separator + 1),
          );
          if (result['confirmationRequired'] == true) {
            spoken =
                'Ready to send to ${result['recipient']} (${result['phone']}): “${result['message']}”. Say confirm send to send it now, or cancel.';
          } else if (result['needsChoice'] == true) {
            spoken = '${result['error']} ${result['matches']}';
          } else {
            spoken = result['error']?.toString() ??
                'I could not prepare the WhatsApp message.';
          }
          break;
        case 'WHATSAPP_CONFIRM':
          // The immediately preceding voice turn must explicitly confirm the
          // displayed recipient and complete message. The short-lived pending
          // action remains the authorization; no fingerprint is required.
          final result = await SafeAutomationService.confirmWhatsApp();
          spoken = result['success'] == true
              ? 'Confirmed. I opened WhatsApp and sent the message to ${result['recipient']}.'
              : (result['error']?.toString() ??
                  'I could not send the WhatsApp message.');
          break;
        case 'WHATSAPP_CANCEL':
          SafeAutomationService.cancelWhatsApp();
          spoken = 'The pending WhatsApp message was cancelled.';
          break;
        case 'WHATSAPP_CALL_PREPARE':
          final separator = arg.indexOf('|');
          if (separator < 1)
            return 'Tell me whether it is an audio or video call and who to call.';
          final result = await SafeAutomationService.prepareWhatsAppCall(
            callType: arg.substring(0, separator),
            recipient: arg.substring(separator + 1),
          );
          if (result['confirmationRequired'] == true) {
            spoken =
                'Ready to start a WhatsApp ${result['callType']} call with ${result['recipient']} (${result['phone']}). Say confirm call to start it now, or cancel.';
          } else if (result['needsChoice'] == true) {
            spoken = '${result['error']} ${result['matches']}';
          } else {
            spoken = result['error']?.toString() ??
                'I could not prepare the WhatsApp call.';
          }
          break;
        case 'WHATSAPP_CALL_CONFIRM':
          final result = await SafeAutomationService.confirmWhatsAppCall();
          spoken = result['success'] == true
              ? 'Confirmed. I opened WhatsApp and started the ${result['callType']} call with ${result['recipient']}.'
              : (result['error']?.toString() ??
                  'I could not start the WhatsApp call.');
          break;
        case 'WHATSAPP_CALL_CANCEL':
          SafeAutomationService.cancelWhatsAppCall();
          spoken = 'The pending WhatsApp call was cancelled.';
          break;
        case 'SIM_CALL_PREPARE':
          final result =
              await SafeAutomationService.prepareCellularCall(recipient: arg);
          spoken = result['confirmationRequired'] == true
              ? 'Ready to place a cellular call to ${result['recipient']} at ${result['phone']}. Say confirm call to place it, or cancel.'
              : (result['error']?.toString() ??
                  'I could not prepare the cellular call.');
          break;
        case 'SIM_CALL_CONFIRM':
          final result = await SafeAutomationService.confirmCellularCall();
          spoken = result['success'] == true
              ? 'Confirmed. I placed the cellular call to ${result['recipient']}.'
              : (result['error']?.toString() ??
                  'I could not place the cellular call.');
          break;
        case 'SIM_CALL_CANCEL':
          SafeAutomationService.cancelCellularCall();
          spoken = 'The pending cellular call was cancelled.';
          break;
        case 'GALLERY_WHATSAPP_PREPARE':
          final separator = arg.indexOf('|');
          if (separator < 1)
            return 'Tell me the WhatsApp recipient and which gallery photo to share.';
          final result =
              await SafeAutomationService.prepareGalleryWhatsAppShare(
            recipient: arg.substring(0, separator),
            imageQuery: arg.substring(separator + 1),
          );
          spoken = result['confirmationRequired'] == true
              ? 'Ready to share gallery image ${result['imageName']} with ${result['recipient']} on WhatsApp. Say confirm share to send it, or cancel.'
              : (result['error']?.toString() ??
                  'I could not prepare the gallery photo share.');
          break;
        case 'GALLERY_WHATSAPP_CONFIRM':
          final result =
              await SafeAutomationService.confirmGalleryWhatsAppShare();
          spoken = result['success'] == true
              ? 'Confirmed. I shared ${result['imageName']} with ${result['recipient']} on WhatsApp.'
              : (result['error']?.toString() ??
                  'I could not share the gallery photo.');
          break;
        case 'GALLERY_WHATSAPP_CANCEL':
          SafeAutomationService.cancelGalleryWhatsAppShare();
          spoken = 'The pending gallery photo share was cancelled.';
          break;
        default:
          print('[DeviceControl] Unknown action: $action');
      }
    } catch (e) {
      success = false;
      print('[DeviceControl] $action failed: $e');
      spoken = 'That action failed: $e';
    }
    if (spoken.toLowerCase().contains('could not') ||
        spoken.toLowerCase().contains('failed') ||
        spoken.toLowerCase().contains('cancelled')) {
      success = false;
    }
    await core.record('fallback_$tool', {
      'success': success,
      'message': spoken.isEmpty ? 'Action completed.' : spoken,
    });
    return spoken;
  }
}
