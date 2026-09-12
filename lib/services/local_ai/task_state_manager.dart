import 'dart:convert';
import 'dart:developer' as developer;
import 'package:shared_preferences/shared_preferences.dart';

enum TaskExecutionState {
  created,
  planning,
  running,
  waiting,
  verifying,
  paused,
  completed,
  failed,
  cancelled,
}

class SubTask {
  final int id;
  final String description;
  final String actionType;
  final Map<String, dynamic> params;
  bool isCompleted;
  String? result;

  SubTask({
    required this.id,
    required this.description,
    required this.actionType,
    required this.params,
    this.isCompleted = false,
    this.result,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'actionType': actionType,
        'params': params,
        'isCompleted': isCompleted,
        if (result != null) 'result': result,
      };

  factory SubTask.fromJson(Map<String, dynamic> json) => SubTask(
        id: json['id'] as int? ?? 1,
        description: json['description'] as String? ?? '',
        actionType: json['actionType'] as String? ?? 'generic',
        params: json['params'] is Map ? Map<String, dynamic>.from(json['params'] as Map) : {},
        isCompleted: json['isCompleted'] == true,
        result: json['result'] as String?,
      );
}

class PersistentTaskSession {
  final String taskId;
  final String originalGoal;
  TaskExecutionState state;
  final List<SubTask> subTasks;
  int currentSubTaskIndex;
  final Map<String, dynamic> contextData;
  final DateTime createdAt;
  DateTime updatedAt;

  PersistentTaskSession({
    required this.taskId,
    required this.originalGoal,
    this.state = TaskExecutionState.created,
    required this.subTasks,
    this.currentSubTaskIndex = 0,
    Map<String, dynamic>? contextData,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : contextData = contextData ?? {},
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  SubTask? get currentSubTask {
    if (currentSubTaskIndex >= 0 && currentSubTaskIndex < subTasks.length) {
      return subTasks[currentSubTaskIndex];
    }
    return null;
  }

  bool get isFinished =>
      state == TaskExecutionState.completed ||
      state == TaskExecutionState.failed ||
      state == TaskExecutionState.cancelled ||
      currentSubTaskIndex >= subTasks.length;

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'originalGoal': originalGoal,
        'state': state.name,
        'subTasks': subTasks.map((s) => s.toJson()).toList(),
        'currentSubTaskIndex': currentSubTaskIndex,
        'contextData': contextData,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory PersistentTaskSession.fromJson(Map<String, dynamic> json) => PersistentTaskSession(
        taskId: json['taskId'] as String? ?? 'task_${DateTime.now().millisecondsSinceEpoch}',
        originalGoal: json['originalGoal'] as String? ?? '',
        state: TaskExecutionState.values.firstWhere(
          (s) => s.name == json['state'],
          orElse: () => TaskExecutionState.created,
        ),
        subTasks: (json['subTasks'] as List?)
                ?.map((s) => SubTask.fromJson(Map<String, dynamic>.from(s as Map)))
                .toList() ??
            [],
        currentSubTaskIndex: json['currentSubTaskIndex'] as int? ?? 0,
        contextData: json['contextData'] is Map ? Map<String, dynamic>.from(json['contextData'] as Map) : {},
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
      );
}

/// Manages task persistence across app life-cycles, sub-goal progression, and compact context construction.
class TaskStateManager {
  static final TaskStateManager _instance = TaskStateManager._internal();
  factory TaskStateManager() => _instance;
  TaskStateManager._internal();

  static const String _prefKey = 'active_persistent_task_session';
  PersistentTaskSession? _activeSession;

  PersistentTaskSession? get activeSession => _activeSession;

  /// Decomposes complex multi-step prompt into a structured PersistentTaskSession
  PersistentTaskSession createSession(String userGoal) {
    final subTasks = _decomposeGoal(userGoal);
    final session = PersistentTaskSession(
      taskId: 'task_${DateTime.now().millisecondsSinceEpoch}',
      originalGoal: userGoal.trim(),
      state: TaskExecutionState.planning,
      subTasks: subTasks,
      currentSubTaskIndex: 0,
    );
    _activeSession = session;
    saveSession(session);
    return session;
  }

  /// Persist session state to SharedPreferences
  Future<void> saveSession(PersistentTaskSession session) async {
    try {
      session.updatedAt = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, jsonEncode(session.toJson()));
    } catch (e) {
      developer.log('Error saving task session: $e', name: 'TaskStateManager');
    }
  }

  /// Recover active task session if app was killed
  Future<PersistentTaskSession?> recoverActiveSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_prefKey);
      if (data != null && data.isNotEmpty) {
        final decoded = jsonDecode(data) as Map<String, dynamic>;
        final session = PersistentTaskSession.fromJson(decoded);
        if (!session.isFinished) {
          _activeSession = session;
          return session;
        }
      }
    } catch (e) {
      developer.log('Error recovering task session: $e', name: 'TaskStateManager');
    }
    return null;
  }

  /// Clear session
  Future<void> clearSession() async {
    _activeSession = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
    } catch (_) {}
  }

  /// Mark current subtask completed and advance to the next
  void advanceSubTask(String? resultMessage) {
    if (_activeSession != null) {
      final cur = _activeSession!.currentSubTask;
      if (cur != null) {
        cur.isCompleted = true;
        cur.result = resultMessage;
      }
      _activeSession!.currentSubTaskIndex++;
      if (_activeSession!.currentSubTaskIndex >= _activeSession!.subTasks.length) {
        _activeSession!.state = TaskExecutionState.completed;
      }
      saveSession(_activeSession!);
    }
  }

  /// Builds a compact prompt (<300 tokens) for small models like Qwen 2.5 1.5B
  String buildCompactPrompt({
    required PersistentTaskSession session,
    required String compactScreen,
    String? previousActionResult,
  }) {
    final cur = session.currentSubTask;
    final buffer = StringBuffer();

    buffer.writeln('TASK: ${session.originalGoal}');
    buffer.writeln('STEP ${session.currentSubTaskIndex + 1}/${session.subTasks.length}: ${cur?.description ?? "Complete"}');

    if (previousActionResult != null && previousActionResult.isNotEmpty) {
      buffer.writeln('PREV RESULT: $previousActionResult');
    }

    buffer.writeln('\nSCREEN:');
    buffer.writeln(compactScreen);
    buffer.writeln('\nSelect next structured action JSON:');

    return buffer.toString();
  }

  List<SubTask> _decomposeGoal(String userGoal) {
    final subTasks = <SubTask>[];
    int counter = 1;

    // Split on sequential clauses
    final clauses = userGoal
        .split(RegExp(r'\s+(?:and\s+then|then|after\s+that)\s+|,\s+then\s+|;\s*'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    for (final clause in clauses) {
      final lower = clause.toLowerCase();

      // 1. Messaging
      if (lower.contains('send') || lower.contains('message') || lower.contains('whatsapp') || lower.contains('telegram')) {
        subTasks.add(SubTask(
          id: counter++,
          description: clause,
          actionType: 'send_message',
          params: {'prompt': clause},
        ));
      }
      // 2. Product search & comparison
      else if (lower.contains('compare') || lower.contains('amazon') || lower.contains('flipkart') || lower.contains('meesho') || lower.contains('cheapest')) {
        subTasks.add(SubTask(
          id: counter++,
          description: clause,
          actionType: 'search_product',
          params: {'prompt': clause},
        ));
      }
      // 3. YouTube / Web search
      else if (lower.contains('youtube') || lower.contains('search ') || lower.contains('google')) {
        subTasks.add(SubTask(
          id: counter++,
          description: clause,
          actionType: 'search',
          params: {'prompt': clause},
        ));
      }
      // 4. Calls
      else if (lower.contains('call ') || lower.contains('dial ')) {
        subTasks.add(SubTask(
          id: counter++,
          description: clause,
          actionType: 'make_call',
          params: {'prompt': clause},
        ));
      }
      // 5. Open app
      else if (lower.startsWith('open ') || lower.startsWith('launch ')) {
        final words = clause.split(RegExp(r'\s+'));
        final appName = words.length >= 2 ? words[1] : 'app';
        subTasks.add(SubTask(
          id: counter++,
          description: 'Open $appName',
          actionType: 'open_app',
          params: {'app_name': appName},
        ));
      }
      // 6. Generic step
      else {
        subTasks.add(SubTask(
          id: counter++,
          description: clause,
          actionType: 'generic',
          params: {'prompt': clause},
        ));
      }
    }

    if (subTasks.isEmpty) {
      subTasks.add(SubTask(
        id: 1,
        description: userGoal,
        actionType: 'generic',
        params: {'prompt': userGoal},
      ));
    }

    return subTasks;
  }
}
