import 'dart:convert';
import 'dart:developer' as developer;
import 'package:intl/intl.dart';
import '../../models/agent_action.dart';
import '../../models/agent_action_schema.dart';
import 'local_inference_engine.dart';
import 'task_state_manager.dart';

class LocalTaskPlanner {
  final LocalInferenceEngine _engine = LocalInferenceEngine();
  final TaskStateManager _stateManager = TaskStateManager();

  static const String _systemPrompt = '''
You are CompanAI's local Android navigation controller.
You do not chat. You do not explain.
You select exactly ONE valid action.
Use only information present in TASK, STATE and UI.
Never invent contacts, phone numbers, buttons, prices or UI elements.
Return valid JSON only.
If task is complete, return finish.

Supported JSON format:
{"action": "click_text|click_at|type_text|scroll|press_enter|press_back|press_home|open_app|finish|wait", "params": {}, "reasoning": "1 sentence", "is_complete": false}
''';

  /// Analyzes a user query and returns an immediate structured action,
  /// or decomposes a complex goal into a multi-step task.
  Future<AgentAction> planUserCommand(String userInput) async {
    final cleanInput = userInput.trim();
    final lower = cleanInput.toLowerCase();

    // ─── 1. Check Multi-step / Compound task with 'then', 'and then', commas
    if (_isCompoundMultiStep(cleanInput)) {
      return AgentAction(
        action: 'execute_task',
        params: {'goal': cleanInput},
        response: 'Planning multi-step task: "$cleanInput"',
      );
    }

    // ─── 2. Product Search & Comparison across Amazon, Flipkart, Meesho ──
    final productAction = _tryExtractProductSearch(cleanInput);
    if (productAction != null) {
      return productAction;
    }

    // ─── 3. Natural Language Calendar Intent ─────────────────────────────
    final calendarAction = _tryExtractCalendarEvent(cleanInput);
    if (calendarAction != null) {
      return calendarAction;
    }

    // ─── 4. Natural Language Reminder / Scheduler Intent ────────────────
    final reminderAction = _tryExtractReminder(cleanInput);
    if (reminderAction != null) {
      return reminderAction;
    }

    // ─── 5. Natural Language Messaging Intent (WhatsApp, Instagram, etc.) 
    final messagingAction = _tryExtractMessaging(cleanInput);
    if (messagingAction != null) {
      return messagingAction;
    }

    // ─── 6. Phone Call / Audio Call Intent ──────────────────────────────
    final callAction = _tryExtractCall(cleanInput);
    if (callAction != null) {
      return callAction;
    }

    // ─── 7. YouTube / Browser Search Intent ─────────────────────────────
    final searchAction = _tryExtractSearch(cleanInput);
    if (searchAction != null) {
      return searchAction;
    }

    // ─── 8. Quick App Open ───────────────────────────────────────────────
    final openAppAction = _tryExtractOpenApp(cleanInput);
    if (openAppAction != null) {
      return openAppAction;
    }

    // ─── 9. Pure Conversational Queries (Greetings, general chit-chat) ────
    if (_isPureConversation(cleanInput)) {
      return AgentAction(
        action: 'general_query',
        params: {'query': cleanInput},
        response: 'Hello! I am CompanAI, your on-device Android automation assistant. I can open any app, navigate, search, send messages, call contacts, compare products, manage calendar/reminders, and complete multi-step tasks. What would you like me to do?',
      );
    }

    // ─── 10. General-Purpose Device Automation Task (Everything else!) ────
    return AgentAction(
      action: 'execute_task',
      params: {'goal': cleanInput},
      response: 'Starting task: "$cleanInput"',
    );
  }

  bool _isPureConversation(String input) {
    final lower = input.toLowerCase().trim();
    if (lower == 'hi' ||
        lower == 'hello' ||
        lower == 'hey' ||
        lower == 'how are you' ||
        lower == 'who are you' ||
        lower == 'what can you do' ||
        lower == 'help' ||
        lower == 'thanks' ||
        lower == 'thank you' ||
        lower == 'good morning' ||
        lower == 'good evening' ||
        lower == 'good night') {
      return true;
    }

    if (lower.startsWith('what is ') ||
        lower.startsWith('who is ') ||
        lower.startsWith('tell me a joke') ||
        lower.startsWith('write a poem') ||
        lower.startsWith('explain ')) {
      final actionKeywords = [
        'app',
        'phone',
        'device',
        'screen',
        'setting',
        'open',
        'search',
        'find',
        'check',
        'message',
        'call',
        'send',
        'turn',
        'buy',
        'cart',
        'form',
        'email',
        'play',
        'read'
      ];
      if (!actionKeywords.any((k) => lower.contains(k))) {
        return true;
      }
    }

    return false;
  }

  /// Evaluates task prompt and screen content to decide the next action
  Future<Map<String, dynamic>> decideNextStepFromPrompt(String taskPrompt) async {
    // 1. Extract goal from prompt: TASK: <goal>
    String goal = '';
    final goalMatch = RegExp(r'TASK:\s*(.+?)(?:\n|$)', caseSensitive: false).firstMatch(taskPrompt);
    if (goalMatch != null) {
      goal = goalMatch.group(1)!.trim();
    }

    // 2. Extract screen dump
    String screenDump = '';
    final screenMatch = RegExp(r'CURRENT SCREEN TEXT DUMP:\s*([\s\S]+?)(?:\n\nStep|\nStep|$)', caseSensitive: false)
        .firstMatch(taskPrompt);
    if (screenMatch != null) {
      screenDump = screenMatch.group(1)!.trim();
    } else {
      screenDump = taskPrompt;
    }

    // 3. Compact screen elements for small model context (<300 tokens)
    final compactScreen = _compactScreenElements(screenDump);
    final userPrompt = 'TASK: $goal\nSCREEN:\n$compactScreen\nNext Action JSON:';

    // 4. Run local model if loaded
    try {
      if (_engine.isModelLoaded) {
        final res = await _engine.generate(
          systemPrompt: _systemPrompt,
          userPrompt: userPrompt,
          temperature: 0.1,
          maxTokens: 128,
        );

        final structured = ActionSchemaValidator.parseAndValidate(res.text, defaultGoal: goal);
        if (structured.type != ActionType.unknown && structured.type != ActionType.wait) {
          return structured.toJson();
        }
      }
    } catch (e) {
      developer.log('Local model inference note: $e', name: 'LocalTaskPlanner');
    }

    // 5. High-speed deterministic fallback reasoning
    return _decideDeterministicNextAction(goal, screenDump);
  }

  // ─── Screen Compaction ───────────────────────────────────────────────────

  String _compactScreenElements(String fullScreenDump) {
    final lines = fullScreenDump.split('\n');
    final buffer = StringBuffer();
    int count = 0;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Skip status bar noise
      final lower = trimmed.toLowerCase();
      if (lower.contains('battery') ||
          lower.contains('percent') ||
          lower.contains('stop macro') ||
          RegExp(r'^\d{1,2}:\d{2}$').hasMatch(lower)) {
        continue;
      }

      buffer.writeln(trimmed);
      count++;
      if (count > 25) break; // Keep under 25 elements to stay < 300 tokens
    }

    return buffer.toString();
  }

  // ─── Deterministic Action Decision ───────────────────────────────────────

  Map<String, dynamic> _decideDeterministicNextAction(String goal, String screenDump) {
    final lowerGoal = goal.toLowerCase();
    final lowerScreen = screenDump.toLowerCase();

    // A. Messaging Flow (WhatsApp, Telegram, etc.)
    if (lowerGoal.contains('whatsapp') || lowerGoal.contains('send ') || lowerGoal.contains('message')) {
      final msgAction = _tryExtractMessaging(goal);
      final recipient = msgAction?.params['recipient']?.toString() ?? '';
      final message = msgAction?.params['message']?.toString() ?? '';

      // Check if message input field is visible
      if (lowerScreen.contains('type a message') || lowerScreen.contains('message') || lowerScreen.contains('edittext')) {
        if (message.isNotEmpty && lowerScreen.contains(message.toLowerCase())) {
          return {
            'action': 'click_text',
            'params': {'text': 'Send'},
            'reasoning': 'Tap send to deliver message',
            'is_complete': false,
          };
        } else if (message.isNotEmpty) {
          return {
            'action': 'type_text',
            'params': {'text': message, 'field_hint': 'Message'},
            'reasoning': 'Type exact message into chat',
            'is_complete': false,
          };
        }
      }

      // Check if target contact/group is visible on screen
      if (recipient.isNotEmpty && lowerScreen.contains(recipient.toLowerCase())) {
        return {
          'action': 'click_text',
          'params': {'text': recipient},
          'reasoning': 'Open chat with $recipient',
          'is_complete': false,
        };
      }

      // If search bar/icon visible
      if (lowerScreen.contains('search')) {
        return {
          'action': 'type_text',
          'params': {'text': recipient, 'field_hint': 'Search'},
          'reasoning': 'Search for $recipient',
          'is_complete': false,
        };
      }
    }

    // B. Search Flow (YouTube, Browser)
    if (lowerGoal.contains('youtube') || lowerGoal.contains('search')) {
      final searchAction = _tryExtractSearch(goal);
      final query = searchAction?.params['query']?.toString() ?? '';

      if (query.isNotEmpty) {
        if (lowerScreen.contains('search') || lowerScreen.contains('edittext')) {
          return {
            'action': 'type_text',
            'params': {'text': query},
            'reasoning': 'Type "$query" into search',
            'is_complete': false,
          };
        }
      }
    }

    // Default safe wait
    return {
      'action': 'wait',
      'params': {},
      'reasoning': 'Observe screen update for: $goal',
      'is_complete': false,
    };
  }

  // ─── Intent Extractors ───────────────────────────────────────────────────

  AgentAction? _tryExtractProductSearch(String input) {
    final lower = input.toLowerCase();
    if (!lower.contains('amazon') &&
        !lower.contains('flipkart') &&
        !lower.contains('meesho') &&
        !lower.contains('compare') &&
        !lower.contains('cheapest option') &&
        !lower.contains('prices in india')) {
      return null;
    }

    // Extract product name
    var query = input;
    query = query.replaceAll(RegExp(r'^(?:search|find|compare|check)\s+', caseSensitive: false), '');
    query = query.replaceAll(RegExp(r'\s+prices?\s+in\s+india', caseSensitive: false), '');
    query = query.replaceAll(RegExp(r'\s+on\s+(?:amazon|flipkart|meesho|and|,|\s+)+', caseSensitive: false), '');
    query = query.replaceAll(RegExp(r'\s+and\s+tell\s+me\s+the\s+cheapest\s+.*$', caseSensitive: false), '');
    query = query.replaceAll(RegExp(r'\s+and\s+compare\s+.*$', caseSensitive: false), '');

    final cleanQuery = _stripPunctuation(query);
    if (cleanQuery.isEmpty) return null;

    final sites = <String>[];
    if (lower.contains('amazon')) sites.add('amazon');
    if (lower.contains('flipkart')) sites.add('flipkart');
    if (lower.contains('meesho')) sites.add('meesho');
    if (sites.isEmpty) sites.addAll(['amazon', 'flipkart', 'meesho']);

    return AgentAction(
      action: 'search_product',
      params: {
        'query': cleanQuery,
        'sites': sites,
      },
      response: 'Searching and comparing "$cleanQuery" prices across ${sites.join(", ")}',
    );
  }

  AgentAction? _tryExtractCall(String input) {
    final lower = input.toLowerCase().trim();
    if (!lower.startsWith('call ') &&
        !lower.startsWith('make a call') &&
        !lower.startsWith('make an audio call') &&
        !lower.startsWith('phone call') &&
        !lower.startsWith('dial ')) {
      return null;
    }

    final match = RegExp(
      r'(?:call|make\s+(?:an?\s+)?(?:audio\s+)?call\s+(?:to\s+)?|phone\s+call\s+(?:to\s+)?|dial\s+)(.+?)$',
      caseSensitive: false,
    ).firstMatch(input);

    if (match != null) {
      final target = _stripPunctuation(match.group(1)!);
      return AgentAction(
        action: 'make_call',
        params: {'contact_name': target, 'call_type': 'audio'},
        response: 'Calling $target...',
      );
    }

    return null;
  }

  AgentAction? _tryExtractSearch(String input) {
    final lower = input.toLowerCase().trim();

    // YouTube search
    if (lower.contains('youtube')) {
      final match = RegExp(r'(?:search|find)\s+(?:on\s+youtube\s+for\s+|youtube\s+for\s+)?(.+?)(?:\s+on\s+youtube|$)', caseSensitive: false).firstMatch(input);
      final rawQuery = match != null ? match.group(1)!.replaceAll(RegExp(r'^(?:open\s+youtube\s+and\s+search\s+|search\s+youtube\s+for\s+)', caseSensitive: false), '').trim() : '';
      final query = _stripPunctuation(rawQuery);

      return AgentAction(
        action: 'search',
        params: {'app': 'youtube', 'query': query.isNotEmpty ? query : 'some'},
        response: 'Searching YouTube for "${query.isNotEmpty ? query : "some"}"',
      );
    }

    // Browser / Google search
    if (lower.startsWith('search google') || lower.startsWith('search web') || lower.startsWith('open browser and search')) {
      final rawQuery = input
          .replaceAll(RegExp(r'^(?:search\s+google\s+for|search\s+web\s+for|open\s+browser\s+and\s+search\s+for|open\s+browser\s+and\s+search)\s+', caseSensitive: false), '')
          .trim();
      final query = _stripPunctuation(rawQuery);

      return AgentAction(
        action: 'search',
        params: {'app': 'browser', 'query': query},
        response: 'Searching Google for "$query"',
      );
    }

    return null;
  }

  AgentAction? _tryExtractMessaging(String input) {
    final lower = input.toLowerCase().trim();
    if (!lower.contains('send') &&
        !lower.contains('message') &&
        !lower.contains('text ') &&
        !lower.contains('whatsapp') &&
        !lower.contains('telegram') &&
        !lower.contains('instagram')) {
      return null;
    }

    // Determine target messaging app
    String app = 'WhatsApp';
    if (lower.contains('sms') || lower.contains('text message')) {
      app = 'SMS';
    } else if (lower.contains('telegram')) {
      app = 'Telegram';
    } else if (lower.contains('instagram')) {
      app = 'Instagram';
    }

    String message = '';
    String recipient = '';

    // 1. Quoted message extraction: send "hello world" to Capstone team
    final quoteMatch = RegExp(r'["“]([^"”]+)["”]').firstMatch(input);
    if (quoteMatch != null) {
      message = quoteMatch.group(1)!.trim();
      final withoutQuote = input.replaceFirst(quoteMatch.group(0)!, '');
      final recipientMatch = RegExp(
        r'(?:to|in)\s+(?:the\s+)?([a-zA-Z0-9\s]+?)(?:\s+(?:on|via|using)\s+[a-zA-Z]+|\s+group|\s+chat|$)',
        caseSensitive: false,
      ).firstMatch(withoutQuote);
      if (recipientMatch != null) {
        recipient = recipientMatch.group(1)!.replaceAll(RegExp(r'\s+message\s*$', caseSensitive: false), '').trim();
      }
    }

    // 2. Pattern: send <msg> to <recipient>
    if (message.isEmpty || recipient.isEmpty) {
      final match = RegExp(
        r'(?:send|message|text)\s+(?:a\s+message\s+)?(.+?)\s+(?:to|in)\s+([a-zA-Z0-9\s]+?)(?:\s+(?:on|via|group|chat)\s*.*)?$',
        caseSensitive: false,
      ).firstMatch(input);

      if (match != null) {
        message = match.group(1)!.trim();
        recipient = match.group(2)!.trim();
      }
    }

    // 3. Pattern: open <app> and message <recipient> saying <msg>
    if (message.isEmpty || recipient.isEmpty) {
      final altMatch = RegExp(
        r'''(?:open\s+[a-zA-Z]+\s+and\s+)?(?:message|send\s+message\s+to|send\s+to)\s+([a-zA-Z0-9\s]+?)\s+(?:saying|with|that)\s+["']?([^"']+)["']?''',
        caseSensitive: false,
      ).firstMatch(input);
      if (altMatch != null) {
        recipient = altMatch.group(1)!.trim();
        message = altMatch.group(2)!.trim();
      }
    }

    // Clean up unwanted prefix/suffix
    message = message.replaceAll(RegExp(r'^\s*message\s+to\s+', caseSensitive: false), '').trim();
    if (message.endsWith(' message')) {
      message = message.substring(0, message.length - 8).trim();
    }

    if (message.isEmpty || recipient.isEmpty) return null;

    return AgentAction(
      action: 'send_message',
      params: {
        'app': app,
        'recipient': recipient,
        'message': message,
      },
      response: 'Sending "$message" to $recipient via $app',
    );
  }

  AgentAction? _tryExtractCalendarEvent(String input) {
    final lower = input.toLowerCase();
    if (!lower.contains('calendar') &&
        !lower.contains('meeting') &&
        !lower.contains('appointment') &&
        !lower.contains('schedule a meet') &&
        !lower.contains('event')) {
      return null;
    }

    String title = 'Meeting';
    final titleMatch = RegExp(r'''(?:called|titled|named|for)\s+["']?([^"']+)["']?''', caseSensitive: false).firstMatch(input);
    if (titleMatch != null) {
      title = titleMatch.group(1)!.trim();
    } else if (lower.contains('dentist')) {
      title = 'Dentist appointment';
    } else if (lower.contains('appointment')) {
      title = 'Appointment';
    }

    final now = DateTime.now();
    DateTime startTime = now.add(const Duration(hours: 1));
    DateTime endTime = startTime.add(const Duration(hours: 1));

    if (lower.contains('tomorrow')) {
      startTime = DateTime(now.year, now.month, now.day + 1, 10, 0);
      endTime = startTime.add(const Duration(hours: 1));
    }

    final timeMatch = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)?', caseSensitive: false).firstMatch(input);
    if (timeMatch != null) {
      int hour = int.tryParse(timeMatch.group(1)!) ?? 10;
      final minute = int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
      final ampm = timeMatch.group(3)?.toLowerCase();

      if (ampm == 'pm' && hour < 12) hour += 12;
      if (ampm == 'am' && hour == 12) hour = 0;

      startTime = DateTime(startTime.year, startTime.month, startTime.day, hour, minute);
      endTime = startTime.add(const Duration(hours: 1));
    }

    return AgentAction(
      action: 'create_calendar_event',
      params: {
        'title': title,
        'start_time': startTime.toIso8601String(),
        'end_time': endTime.toIso8601String(),
        'description': 'Created by CompanAI Local AI',
        'location': '',
      },
      response: 'Scheduling calendar event: "$title" for ${DateFormat('EEE, MMM d @ h:mm a').format(startTime)}',
    );
  }

  AgentAction? _tryExtractReminder(String input) {
    final lower = input.toLowerCase();
    if (!lower.startsWith('remind') &&
        !lower.contains('remind me') &&
        !lower.contains('set a reminder') &&
        !lower.contains('every morning') &&
        !lower.contains('every evening') &&
        !lower.contains('every monday')) {
      return null;
    }

    String title = 'Reminder';
    final taskMatch = RegExp(r'(?:to|about)\s+(.+?)(?:\s+(?:at|in|on|every)|$)', caseSensitive: false).firstMatch(input);
    if (taskMatch != null) {
      title = taskMatch.group(1)!.trim();
    }

    final now = DateTime.now();
    DateTime scheduledTime = now.add(const Duration(minutes: 30));
    String repeatType = 'none';

    if (lower.contains('every monday')) {
      repeatType = 'weekly';
      int daysUntilMonday = (DateTime.monday - now.weekday + 7) % 7;
      if (daysUntilMonday == 0 && now.hour >= 9) daysUntilMonday = 7;
      scheduledTime = DateTime(now.year, now.month, now.day + daysUntilMonday, 9, 0);
    } else if (lower.contains('every morning') || lower.contains('every day at 8')) {
      repeatType = 'daily';
      scheduledTime = DateTime(now.year, now.month, now.day, 8, 0);
      if (scheduledTime.isBefore(now)) scheduledTime = scheduledTime.add(const Duration(days: 1));
    } else if (lower.contains('in 30 minutes') || lower.contains('in 30 mins')) {
      scheduledTime = now.add(const Duration(minutes: 30));
    } else {
      final timeMatch = RegExp(r'at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?', caseSensitive: false).firstMatch(lower);
      if (timeMatch != null) {
        int hour = int.tryParse(timeMatch.group(1)!) ?? 8;
        final minute = int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
        final ampm = timeMatch.group(3)?.toLowerCase();

        if (ampm == 'pm' && hour < 12) hour += 12;
        if (ampm == 'am' && hour == 12) hour = 0;

        final targetDate = lower.contains('tomorrow') ? now.add(const Duration(days: 1)) : now;
        scheduledTime = DateTime(targetDate.year, targetDate.month, targetDate.day, hour, minute);
        if (scheduledTime.isBefore(now) && !lower.contains('tomorrow')) {
          scheduledTime = scheduledTime.add(const Duration(days: 1));
        }
      }
    }

    return AgentAction(
      action: 'set_reminder',
      params: {
        'title': title,
        'scheduled_time': scheduledTime.toIso8601String(),
        'repeat': repeatType,
        'message': 'Reminder: $title',
      },
      response: 'Set reminder for "$title" at ${DateFormat('EEE, MMM d @ h:mm a').format(scheduledTime)}${repeatType != 'none' ? ' (Repeats $repeatType)' : ''}',
    );
  }

  AgentAction? _tryExtractOpenApp(String input) {
    final lower = input.toLowerCase().trim();
    if (lower.startsWith('open ') && !lower.contains(' and ') && !lower.contains(' then ')) {
      final app = input.substring(5).trim();
      return AgentAction(
        action: 'open_app',
        params: {'app_name': app},
        response: 'Opening $app',
      );
    }
    return null;
  }

  bool _isCompoundMultiStep(String input) {
    final lower = input.toLowerCase();
    return lower.contains(' and then ') ||
        lower.contains(' then open ') ||
        lower.contains(' then search ') ||
        lower.contains(' then compare ') ||
        lower.contains(' and compare the prices');
  }

  String _stripPunctuation(String s) {
    return s.replaceAll(RegExp(r'[\.\?\!\,\;]+$'), '').trim();
  }
}

