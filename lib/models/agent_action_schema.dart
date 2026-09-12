import 'dart:convert';
import 'dart:developer' as developer;

/// Supported action types in the CompanAI Local Agent schema
enum ActionType {
  openApp,
  findContact,
  findGroup,
  sendMessage,
  makeCall,
  search,
  searchProduct,
  tap,
  type,
  swipe,
  scroll,
  back,
  home,
  wait,
  verify,
  finish,
  askUser,
  createCalendarEvent,
  createReminder,
  scheduleTask,
  unknown,
}

extension ActionTypeExtension on ActionType {
  String get schemaName {
    switch (this) {
      case ActionType.openApp:
        return 'open_app';
      case ActionType.findContact:
        return 'find_contact';
      case ActionType.findGroup:
        return 'find_group';
      case ActionType.sendMessage:
        return 'send_message';
      case ActionType.makeCall:
        return 'make_call';
      case ActionType.search:
        return 'search';
      case ActionType.searchProduct:
        return 'search_product';
      case ActionType.tap:
        return 'tap';
      case ActionType.type:
        return 'type';
      case ActionType.swipe:
        return 'swipe';
      case ActionType.scroll:
        return 'scroll';
      case ActionType.back:
        return 'back';
      case ActionType.home:
        return 'home';
      case ActionType.wait:
        return 'wait';
      case ActionType.verify:
        return 'verify';
      case ActionType.finish:
        return 'finish';
      case ActionType.askUser:
        return 'ask_user';
      case ActionType.createCalendarEvent:
        return 'create_calendar_event';
      case ActionType.createReminder:
        return 'create_reminder';
      case ActionType.scheduleTask:
        return 'schedule_task';
      case ActionType.unknown:
        return 'unknown';
    }
  }

  static ActionType fromString(String? name) {
    if (name == null) return ActionType.unknown;
    final clean = name.trim().toLowerCase();
    switch (clean) {
      case 'open_app':
      case 'open':
      case 'launch_app':
        return ActionType.openApp;
      case 'find_contact':
      case 'search_contact':
        return ActionType.findContact;
      case 'find_group':
      case 'search_group':
        return ActionType.findGroup;
      case 'send_message':
      case 'send_sms':
      case 'message':
        return ActionType.sendMessage;
      case 'make_call':
      case 'call':
      case 'phone_call':
      case 'audio_call':
        return ActionType.makeCall;
      case 'search':
      case 'search_web':
      case 'search_youtube':
        return ActionType.search;
      case 'search_product':
      case 'compare_products':
        return ActionType.searchProduct;
      case 'tap':
      case 'click':
      case 'click_text':
      case 'click_at':
        return ActionType.tap;
      case 'type':
      case 'type_text':
      case 'input':
        return ActionType.type;
      case 'swipe':
        return ActionType.swipe;
      case 'scroll':
      case 'scroll_screen':
        return ActionType.scroll;
      case 'back':
      case 'press_back':
        return ActionType.back;
      case 'home':
      case 'press_home':
        return ActionType.home;
      case 'wait':
        return ActionType.wait;
      case 'verify':
        return ActionType.verify;
      case 'finish':
      case 'done':
      case 'complete':
        return ActionType.finish;
      case 'ask_user':
      case 'prompt_user':
      case 'confirm':
        return ActionType.askUser;
      case 'create_calendar_event':
      case 'calendar':
      case 'schedule_event':
        return ActionType.createCalendarEvent;
      case 'create_reminder':
      case 'set_reminder':
        return ActionType.createReminder;
      case 'schedule_task':
      case 'schedule_job':
        return ActionType.scheduleTask;
      default:
        return ActionType.unknown;
    }
  }
}

/// Validated structured action produced by local model or rule-based parser
class StructuredAction {
  final ActionType type;
  final String actionName;
  final Map<String, dynamic> params;
  final String reasoning;
  final bool isComplete;
  final String? error;

  const StructuredAction({
    required this.type,
    required this.actionName,
    required this.params,
    this.reasoning = '',
    this.isComplete = false,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'action': actionName,
        'params': params,
        'reasoning': reasoning,
        'is_complete': isComplete,
        if (error != null) 'error': error,
      };

  factory StructuredAction.fromJson(Map<String, dynamic> json) {
    final rawAction = (json['action'] ?? json['name'] ?? 'wait').toString();
    final type = ActionTypeExtension.fromString(rawAction);
    final params = json['params'] is Map<String, dynamic>
        ? json['params'] as Map<String, dynamic>
        : (json['params'] is Map ? Map<String, dynamic>.from(json['params'] as Map) : <String, dynamic>{});
    
    // Copy top-level properties to params if not present
    for (final entry in json.entries) {
      if (entry.key != 'action' &&
          entry.key != 'params' &&
          entry.key != 'reasoning' &&
          entry.key != 'is_complete') {
        params.putIfAbsent(entry.key, () => entry.value);
      }
    }

    final reasoning = (json['reasoning'] ?? json['response'] ?? json['description'] ?? '').toString();
    final isComplete = json['is_complete'] == true || type == ActionType.finish;

    return StructuredAction(
      type: type,
      actionName: type.schemaName,
      params: params,
      reasoning: reasoning,
      isComplete: isComplete,
    );
  }

  static StructuredAction wait([String reason = 'Observing screen update']) => StructuredAction(
        type: ActionType.wait,
        actionName: 'wait',
        params: {},
        reasoning: reason,
        isComplete: false,
      );

  static StructuredAction finish({required bool success, String reason = 'Goal accomplished'}) => StructuredAction(
        type: ActionType.finish,
        actionName: 'finish',
        params: {'result': success ? 'success' : 'failed', 'reason': reason},
        reasoning: reason,
        isComplete: true,
      );

  static StructuredAction askUser({required String question, List<String>? options}) => StructuredAction(
        type: ActionType.askUser,
        actionName: 'ask_user',
        params: {'question': question, if (options != null) 'options': options},
        reasoning: question,
        isComplete: false,
      );
}

/// Robust JSON repair and validation utility for small on-device models
class ActionSchemaValidator {
  /// Extract, repair and validate JSON into a StructuredAction
  static StructuredAction parseAndValidate(String rawOutput, {String defaultGoal = ''}) {
    final trimmed = rawOutput.trim();
    if (trimmed.isEmpty) {
      return StructuredAction.wait('Empty model output');
    }

    // 1. Try direct extraction
    String jsonCandidate = _extractJsonBlock(trimmed);

    // 2. Repair common JSON formatting errors from small models
    jsonCandidate = _repairJson(jsonCandidate);

    try {
      final decoded = jsonDecode(jsonCandidate);
      if (decoded is Map<String, dynamic>) {
        return _validateAction(StructuredAction.fromJson(decoded));
      } else if (decoded is Map) {
        return _validateAction(StructuredAction.fromJson(Map<String, dynamic>.from(decoded)));
      }
    } catch (e) {
      developer.log('Action schema JSON parse error: $e\nCandidate: $jsonCandidate', name: 'ActionSchemaValidator');
    }

    // 3. Fallback: heuristic extraction from text
    return _extractHeuristicAction(trimmed, defaultGoal);
  }

  static String _extractJsonBlock(String text) {
    // Markdown code block
    final codeBlockRegex = RegExp(r'```(?:json)?\s*(\{[\s\S]*?\})\s*```');
    final match = codeBlockRegex.firstMatch(text);
    if (match != null) {
      return match.group(1)!;
    }

    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      return text.substring(start, end + 1);
    }

    if (start != -1) {
      return text.substring(start);
    }

    return text;
  }

  /// Fixes missing closing braces, single quotes, trailing commas, unquoted keys
  static String _repairJson(String jsonStr) {
    var repaired = jsonStr.trim();

    // Replace single quotes with double quotes for valid JSON
    repaired = repaired.replaceAll("'", '"');

    // Remove trailing commas before closing braces/brackets
    repaired = repaired.replaceAll(RegExp(r',\s*\}'), '}');
    repaired = repaired.replaceAll(RegExp(r',\s*\]'), ']');

    // Fix unclosed quotes
    int quoteCount = 0;
    for (int i = 0; i < repaired.length; i++) {
      if (repaired[i] == '"' && (i == 0 || repaired[i - 1] != '\\')) {
        quoteCount++;
      }
    }
    if (quoteCount % 2 != 0) {
      repaired += '"';
    }

    // Count open vs closed braces
    int openBraces = 0;
    int closeBraces = 0;
    for (int i = 0; i < repaired.length; i++) {
      if (repaired[i] == '{') openBraces++;
      if (repaired[i] == '}') closeBraces++;
    }

    while (closeBraces < openBraces) {
      repaired += '}';
      closeBraces++;
    }

    return repaired;
  }

  /// Validates required parameters per action type
  static StructuredAction _validateAction(StructuredAction action) {
    switch (action.type) {
      case ActionType.openApp:
        final pkg = action.params['package'] ?? action.params['package_name'];
        final app = action.params['app_name'] ?? action.params['name'] ?? action.params['app'];
        if (pkg == null && app == null) {
          return StructuredAction.wait('Missing app name for open_app');
        }
        return action;

      case ActionType.sendMessage:
        final msg = action.params['message'] ?? action.params['text'] ?? '';
        final target = action.params['target'] ?? action.params['recipient'] ?? action.params['contact'] ?? '';
        if (msg.toString().trim().isEmpty) {
          return StructuredAction.wait('Missing message text');
        }
        return StructuredAction(
          type: ActionType.sendMessage,
          actionName: 'send_message',
          params: {
            'app': action.params['app'] ?? 'WhatsApp',
            'target': target.toString().trim(),
            'message': msg.toString().trim(),
          },
          reasoning: action.reasoning,
          isComplete: action.isComplete,
        );

      case ActionType.makeCall:
        final contact = action.params['contact'] ?? action.params['contact_name'] ?? action.params['name'];
        final phone = action.params['phone_number'] ?? action.params['phone'];
        return StructuredAction(
          type: ActionType.makeCall,
          actionName: 'make_call',
          params: {
            if (contact != null) 'contact': contact.toString().trim(),
            if (phone != null) 'phone_number': phone.toString().trim(),
            'call_type': action.params['call_type'] ?? 'audio',
          },
          reasoning: action.reasoning,
          isComplete: action.isComplete,
        );

      case ActionType.tap:
        final target = action.params['target'] ?? action.params['text'];
        final x = action.params['x'];
        final y = action.params['y'];
        if (target == null && (x == null || y == null)) {
          return StructuredAction.wait('Missing target or coordinates for tap');
        }
        return action;

      case ActionType.type:
        final text = action.params['text'] ?? action.params['content'] ?? action.params['query'];
        if (text == null || text.toString().isEmpty) {
          return StructuredAction.wait('Missing text for type action');
        }
        return action;

      default:
        return action;
    }
  }

  /// Heuristic parser if model returned freeform text
  static StructuredAction _extractHeuristicAction(String text, String defaultGoal) {
    final lower = text.toLowerCase();

    if (lower.contains('done') || lower.contains('finish') || lower.contains('completed')) {
      return StructuredAction.finish(success: true, reason: text);
    }

    if (lower.contains('click') || lower.contains('tap')) {
      final match = RegExp(r'(?:click|tap)\s+["“]?([^"”\n\.]+)', caseSensitive: false).firstMatch(text);
      if (match != null) {
        return StructuredAction(
          type: ActionType.tap,
          actionName: 'tap',
          params: {'target': match.group(1)!.trim()},
          reasoning: text,
        );
      }
    }

    if (lower.contains('type') || lower.contains('enter')) {
      final match = RegExp(r'(?:type|enter)\s+["“]?([^"”\n]+)', caseSensitive: false).firstMatch(text);
      if (match != null) {
        return StructuredAction(
          type: ActionType.type,
          actionName: 'type',
          params: {'text': match.group(1)!.trim()},
          reasoning: text,
        );
      }
    }

    return StructuredAction.wait('Observing screen for: $defaultGoal');
  }
}
