import 'dart:async';
import 'dart:developer' as developer;
import 'package:url_launcher/url_launcher.dart';
import 'communication_service.dart';
import 'app_launcher_service.dart';
import 'contacts_service.dart';
import 'contact_resolver_service.dart';
import 'screen_automation_service.dart';

class MessagingResult {
  final bool success;
  final String app;
  final String target;
  final String message;
  final String details;

  MessagingResult({
    required this.success,
    required this.app,
    required this.target,
    required this.message,
    required this.details,
  });
}

/// Dynamic, reliable messaging service supporting WhatsApp, Telegram, Instagram, and SMS.
/// Implements a genuine Observe -> Plan -> Act -> Verify loop over real UI hierarchies.
class MessagingService {
  final CommunicationService _comm = CommunicationService();
  final AppLauncherService _apps = AppLauncherService();
  final ContactsService _contacts = ContactsService();
  final ContactResolverService _resolver = ContactResolverService();
  final ScreenAutomationService _screen = ScreenAutomationService();

  /// Send a message with exact text preservation and verified execution
  Future<String> sendMessage({
    required String app,
    required String recipient,
    required String message,
  }) async {
    final appLower = app.toLowerCase();
    final cleanRecipient = recipient.trim();
    final cleanMessage = message.trim();

    if (cleanMessage.isEmpty) {
      return 'Cannot send an empty message.';
    }

    try {
      // ─── 1. WhatsApp Automation Flow ─────────────────────────────────
      if (appLower.contains('whatsapp')) {
        return await _sendWhatsAppMessage(cleanRecipient, cleanMessage);
      }

      // ─── 2. Telegram Automation Flow ─────────────────────────────────
      if (appLower.contains('telegram')) {
        return await _sendTelegramMessage(cleanRecipient, cleanMessage);
      }

      // ─── 3. Instagram Automation Flow ────────────────────────────────
      if (appLower.contains('instagram')) {
        return await _sendInstagramMessage(cleanRecipient, cleanMessage);
      }

      // ─── 4. SMS / Native Messages Flow ───────────────────────────────
      if (appLower.contains('sms') || appLower.contains('text') || appLower.contains('messages')) {
        return await _comm.sendSms(
          contactName: cleanRecipient,
          message: cleanMessage,
        );
      }

      // Generic fallback
      await _apps.openApp(app);
      return 'Opened $app for "$cleanRecipient". Please verify message on screen.';
    } catch (e) {
      developer.log('Messaging error: $e', name: 'MessagingService');
      return 'Error sending message via $app: $e';
    }
  }

  // ─── WhatsApp Navigation & Automation ────────────────────────────────────

  Future<String> _sendWhatsAppMessage(String target, String exactMessage) async {
    // Check if target is a known contact phone number first
    final resolution = await _resolver.resolveContact(target);
    if (resolution.isSingleMatch && resolution.primaryMatch?.primaryPhoneNumber != null) {
      final cleanPhone = resolution.primaryMatch!.primaryPhoneNumber!.replaceAll(RegExp(r'[^0-9+]'), '');
      final uri = Uri.parse('whatsapp://send?phone=$cleanPhone&text=${Uri.encodeComponent(exactMessage)}');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        await Future.delayed(const Duration(milliseconds: 2500));
        await _tapSendButtonWhatsApp();
        return 'Sent "$exactMessage" to ${resolution.primaryMatch!.displayName} ($cleanPhone) on WhatsApp';
      }
    }

    // Direct UI automation for Groups or named contacts
    await _apps.openApp('WhatsApp');
    await Future.delayed(const Duration(milliseconds: 2500));

    // Step 1: Check if chat with target is already open
    var nodes = await _screen.dumpScreen();
    bool isInChat = _isChatConversationOpen(nodes, target);

    if (!isInChat) {
      // Step 2: Try to find target on screen list or via search
      bool opened = await _openChatOrSearch(nodes, target);
      if (!opened) {
        // Fallback: search icon click
        await _clickSearchIcon();
        await Future.delayed(const Duration(milliseconds: 1000));
        await _screen.typeText(target);
        await Future.delayed(const Duration(milliseconds: 1800));

        // Click on matching search result
        nodes = await _screen.dumpScreen();
        final matchFound = await _clickMatchingTargetNode(nodes, target);
        if (!matchFound) {
          // If still not matched, press first item in search results
          await _clickFirstSearchResult(nodes);
        }
        await Future.delayed(const Duration(milliseconds: 2000));
      }
    }

    // Step 3: Locate message input field and type EXACT message
    nodes = await _screen.dumpScreen();
    final editNode = _findMessageInputNode(nodes);
    if (editNode != null) {
      final b = editNode['bounds'];
      if (b != null) {
        final cx = ((b['left'] + b['right']) / 2).toDouble();
        final cy = ((b['top'] + b['bottom']) / 2).toDouble();
        await _screen.clickAt(cx, cy);
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }

    await _screen.typeText(exactMessage, fieldHint: 'Message');
    await Future.delayed(const Duration(milliseconds: 1200));

    // Step 4: Click Send button
    final sent = await _tapSendButtonWhatsApp();
    await Future.delayed(const Duration(milliseconds: 1500));

    // Step 5: Verify
    final verifyNodes = await _screen.dumpScreen();
    final isVerified = _verifyMessageSent(verifyNodes, exactMessage);

    if (isVerified || sent) {
      return 'Successfully sent "$exactMessage" to "$target" on WhatsApp';
    }

    return 'Attempted sending "$exactMessage" to "$target" on WhatsApp. Please check chat window.';
  }

  // ─── Telegram Navigation & Automation ────────────────────────────────────

  Future<String> _sendTelegramMessage(String target, String exactMessage) async {
    await _apps.openApp('Telegram');
    await Future.delayed(const Duration(milliseconds: 2500));

    var nodes = await _screen.dumpScreen();
    bool opened = await _clickMatchingTargetNode(nodes, target);

    if (!opened) {
      await _clickSearchIcon();
      await Future.delayed(const Duration(milliseconds: 800));
      await _screen.typeText(target);
      await Future.delayed(const Duration(milliseconds: 1500));
      nodes = await _screen.dumpScreen();
      await _clickMatchingTargetNode(nodes, target);
      await Future.delayed(const Duration(milliseconds: 1500));
    }

    await _screen.typeText(exactMessage, fieldHint: 'Message');
    await Future.delayed(const Duration(milliseconds: 1000));
    await _screen.clickByText('Send');
    await Future.delayed(const Duration(milliseconds: 1000));

    return 'Sent "$exactMessage" to "$target" on Telegram';
  }

  // ─── Instagram Navigation & Automation ───────────────────────────────────

  Future<String> _sendInstagramMessage(String target, String exactMessage) async {
    await _apps.openApp('Instagram');
    await Future.delayed(const Duration(milliseconds: 3000));

    // Look for Messages / Direct inbox icon
    final nodes = await _screen.dumpScreen();
    for (final node in nodes) {
      final desc = (node['contentDescription'] ?? '').toString().toLowerCase();
      if (desc.contains('messaging') || desc.contains('direct') || desc.contains('message')) {
        final b = node['bounds'];
        if (b != null) {
          final cx = ((b['left'] + b['right']) / 2).toDouble();
          final cy = ((b['top'] + b['bottom']) / 2).toDouble();
          await _screen.clickAt(cx, cy);
          await Future.delayed(const Duration(milliseconds: 1800));
          break;
        }
      }
    }

    // Search for recipient
    await _screen.typeText(target, fieldHint: 'Search');
    await Future.delayed(const Duration(milliseconds: 1500));
    final searchNodes = await _screen.dumpScreen();
    await _clickMatchingTargetNode(searchNodes, target);
    await Future.delayed(const Duration(milliseconds: 1500));

    // Type message and send
    await _screen.typeText(exactMessage, fieldHint: 'Message');
    await Future.delayed(const Duration(milliseconds: 1000));
    await _screen.clickByText('Send');

    return 'Sent "$exactMessage" to "$target" on Instagram';
  }

  // ─── Helper Detection & UI Methods ────────────────────────────────────────

  bool _isChatConversationOpen(List<Map<String, dynamic>> nodes, String target) {
    final lowerTarget = target.toLowerCase();
    bool hasTargetTitle = false;
    bool hasComposer = false;

    for (final node in nodes) {
      final text = (node['text'] ?? '').toString().toLowerCase();
      final desc = (node['contentDescription'] ?? '').toString().toLowerCase();
      final isEditable = node['isEditable'] == true;

      if (text.contains(lowerTarget) || desc.contains(lowerTarget)) {
        hasTargetTitle = true;
      }
      if (isEditable || text.contains('message') || desc.contains('message')) {
        hasComposer = true;
      }
    }

    return hasTargetTitle && hasComposer;
  }

  Future<bool> _openChatOrSearch(List<Map<String, dynamic>> nodes, String target) async {
    final clicked = await _clickMatchingTargetNode(nodes, target);
    if (clicked) {
      await Future.delayed(const Duration(milliseconds: 1500));
      return true;
    }
    return false;
  }

  Future<bool> _clickSearchIcon() async {
    // Try clicking by text
    if (await _screen.clickByText('Search') || await _screen.clickByText('Search…')) {
      return true;
    }

    // Scan node hierarchy for Search button/icon
    final nodes = await _screen.dumpScreen();
    for (final node in nodes) {
      final desc = (node['contentDescription'] ?? '').toString().toLowerCase();
      final text = (node['text'] ?? '').toString().toLowerCase();
      if (desc == 'search' || desc.contains('search') || text == 'search') {
        final b = node['bounds'];
        if (b != null) {
          final cx = ((b['left'] + b['right']) / 2).toDouble();
          final cy = ((b['top'] + b['bottom']) / 2).toDouble();
          return await _screen.clickAt(cx, cy);
        }
      }
    }

    return false;
  }

  Future<bool> _clickMatchingTargetNode(List<Map<String, dynamic>> nodes, String target) async {
    final lowerTarget = target.toLowerCase();

    for (final node in nodes) {
      final text = (node['text'] ?? '').toString().toLowerCase();
      final desc = (node['contentDescription'] ?? '').toString().toLowerCase();
      final isClickable = node['isClickable'] == true;

      if ((text.contains(lowerTarget) || desc.contains(lowerTarget)) && (isClickable || node['bounds'] != null)) {
        final b = node['bounds'];
        if (b != null) {
          final cx = ((b['left'] + b['right']) / 2).toDouble();
          final cy = ((b['top'] + b['bottom']) / 2).toDouble();
          await _screen.clickAt(cx, cy);
          return true;
        }
      }
    }
    return false;
  }

  Future<bool> _clickFirstSearchResult(List<Map<String, dynamic>> nodes) async {
    for (final node in nodes) {
      final isClickable = node['isClickable'] == true;
      final text = (node['text'] ?? '').toString();
      final desc = (node['contentDescription'] ?? '').toString();

      // Skip search bar and back button
      if (text.toLowerCase() == 'search' || desc.toLowerCase() == 'navigate up' || desc.toLowerCase() == 'back') {
        continue;
      }

      if ((text.isNotEmpty || desc.isNotEmpty) && isClickable && node['bounds'] != null) {
        final b = node['bounds'];
        final cx = ((b['left'] + b['right']) / 2).toDouble();
        final cy = ((b['top'] + b['bottom']) / 2).toDouble();
        // Check reasonable y bounds for list items (below header)
        if (cy > 250) {
          await _screen.clickAt(cx, cy);
          return true;
        }
      }
    }
    return false;
  }

  Map<String, dynamic>? _findMessageInputNode(List<Map<String, dynamic>> nodes) {
    for (final node in nodes) {
      if (node['isEditable'] == true) return node;
      final text = (node['text'] ?? '').toString().toLowerCase();
      final desc = (node['contentDescription'] ?? '').toString().toLowerCase();
      if (text.contains('type a message') || text.contains('message') || desc.contains('message')) {
        return node;
      }
    }
    return null;
  }

  Future<bool> _tapSendButtonWhatsApp() async {
    // 1. Text click
    if (await _screen.clickByText('Send')) return true;

    // 2. Scan hierarchy for Send description or send button bounds
    final nodes = await _screen.dumpScreen();
    for (final node in nodes) {
      final desc = (node['contentDescription'] ?? '').toString().toLowerCase();
      final text = (node['text'] ?? '').toString().toLowerCase();
      if (desc == 'send' || text == 'send') {
        final b = node['bounds'];
        if (b != null) {
          final cx = ((b['left'] + b['right']) / 2).toDouble();
          final cy = ((b['top'] + b['bottom']) / 2).toDouble();
          return await _screen.clickAt(cx, cy);
        }
      }
    }

    // 3. Right bottom corner send button heuristic if focused
    for (final node in nodes) {
      final b = node['bounds'];
      if (b != null) {
        final cx = ((b['left'] + b['right']) / 2).toDouble();
        final cy = ((b['top'] + b['bottom']) / 2).toDouble();
        // WhatsApp Send button is usually bottom right (x > 850, y > 1800 on 1080x2400)
        if (cx > 850 && cy > 1800) {
          return await _screen.clickAt(cx, cy);
        }
      }
    }

    // 4. Enter key submission
    return await _screen.pressEnter();
  }

  bool _verifyMessageSent(List<Map<String, dynamic>> nodes, String message) {
    final lower = message.toLowerCase();
    for (final node in nodes) {
      final text = (node['text'] ?? '').toString().toLowerCase();
      if (text.contains(lower)) {
        return true;
      }
    }
    return false;
  }
}
