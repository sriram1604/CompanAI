class AgentAction {
  final String action;
  final Map<String, dynamic> params;
  final String response;

  AgentAction({
    required this.action,
    required this.params,
    required this.response,
  });

  factory AgentAction.fromJson(Map<String, dynamic> json) {
    return AgentAction(
      action: json['action'] as String? ?? 'general_query',
      params: json['params'] is Map ? Map<String, dynamic>.from(json['params'] as Map) : {},
      response: json['response'] as String? ?? '',
    );
  }

  static const List<String> availableActions = [
    'open_app',
    'make_call',
    'send_sms',
    'search_contact',
    'set_alarm',
    'set_volume',
    'set_brightness',
    'read_notifications',
    'read_screen',
    'run_adb_command',
    'create_calendar_event',
    'set_reminder',
    'schedule_job',
    'send_message',
    'search',
    'search_product',
    'compare_products',
    'execute_task',
    'ask_user',
    'general_query',
  ];
}
