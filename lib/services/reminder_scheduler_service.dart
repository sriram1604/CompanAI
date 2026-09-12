import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScheduledJob {
  final String id;
  final String title;
  final DateTime scheduledTime;
  final String repeatType; // 'none', 'daily', 'weekly'
  final String message;
  final String? taskPrompt;
  final DateTime createdAt;
  bool isActive;

  ScheduledJob({
    required this.id,
    required this.title,
    required this.scheduledTime,
    this.repeatType = 'none',
    required this.message,
    this.taskPrompt,
    DateTime? createdAt,
    this.isActive = true,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'scheduledTime': scheduledTime.toIso8601String(),
        'repeatType': repeatType,
        'message': message,
        'taskPrompt': taskPrompt,
        'createdAt': createdAt.toIso8601String(),
        'isActive': isActive,
      };

  factory ScheduledJob.fromJson(Map<String, dynamic> json) => ScheduledJob(
        id: json['id'] as String,
        title: json['title'] as String,
        scheduledTime: DateTime.parse(json['scheduledTime'] as String),
        repeatType: json['repeatType'] as String? ?? 'none',
        message: json['message'] as String? ?? '',
        taskPrompt: json['taskPrompt'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : DateTime.now(),
        isActive: json['isActive'] as bool? ?? true,
      );

  String get formattedTime {
    return DateFormat('EEE, MMM d @ h:mm a').format(scheduledTime);
  }
}

class ReminderSchedulerService {
  static final ReminderSchedulerService _instance =
      ReminderSchedulerService._internal();
  static ReminderSchedulerService get instance => _instance;
  factory ReminderSchedulerService() => _instance;
  ReminderSchedulerService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() => init();

  Future<void> init() async {
    if (_initialized) return;

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(initSettings);

    // Create persistent high-priority notification channel for reminders
    final androidPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'companai_reminders_channel',
        'CompanAI Reminders & Scheduled Tasks',
        description: 'Scheduled reminders and automated background tasks',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      await androidPlugin.createNotificationChannel(channel);
    }

    _initialized = true;
  }

  Future<File> get _storageFile async {
    final docsDir = await getApplicationDocumentsDirectory();
    return File('${docsDir.path}/scheduled_jobs.json');
  }

  /// Get all saved scheduled jobs
  Future<List<ScheduledJob>> getAllJobs() async {
    try {
      final file = await _storageFile;
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final list = jsonDecode(content) as List;
      return list
          .map((e) => ScheduledJob.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      developer.log('Error reading scheduled jobs: $e',
          name: 'ReminderSchedulerService');
      return [];
    }
  }

  /// Save all scheduled jobs to persistent store
  Future<void> _saveJobs(List<ScheduledJob> jobs) async {
    try {
      final file = await _storageFile;
      final jsonStr = jsonEncode(jobs.map((j) => j.toJson()).toList());
      await file.writeAsString(jsonStr);
    } catch (e) {
      developer.log('Error saving scheduled jobs: $e',
          name: 'ReminderSchedulerService');
    }
  }

  /// Schedule a new reminder or background task
  Future<String> scheduleReminder({
    required String title,
    required DateTime scheduledTime,
    String repeatType = 'none',
    String? message,
    String? taskPrompt,
  }) async {
    await init();

    final jobId = DateTime.now().millisecondsSinceEpoch.toString();
    final notifId = (DateTime.now().millisecondsSinceEpoch % 100000);
    final reminderMsg = message ?? 'Reminder: $title';

    final job = ScheduledJob(
      id: jobId,
      title: title,
      scheduledTime: scheduledTime,
      repeatType: repeatType,
      message: reminderMsg,
      taskPrompt: taskPrompt,
      isActive: true,
    );

    final jobs = await getAllJobs();
    jobs.add(job);
    await _saveJobs(jobs);

    // Schedule Android local notification
    final now = DateTime.now();
    final delay = scheduledTime.difference(now);

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'companai_reminders_channel',
      'CompanAI Reminders & Scheduled Tasks',
      channelDescription: 'Scheduled reminders and automated background tasks',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.reminder,
      styleInformation: BigTextStyleInformation(reminderMsg),
    );

    final NotificationDetails details =
        NotificationDetails(android: androidDetails);

    if (delay.isNegative || delay.inSeconds <= 0) {
      // Immediate notification if time is in the past
      await _notificationsPlugin.show(
        notifId,
        'Reminder: $title',
        reminderMsg,
        details,
      );
    } else {
      // Note: For deterministic exact scheduling on Android devices
      Future.delayed(delay, () async {
        await _notificationsPlugin.show(
          notifId,
          'Reminder: $title',
          reminderMsg,
          details,
        );
      });
    }

    final formatted = DateFormat('EEE, MMM d @ h:mm a').format(scheduledTime);
    developer.log(
      'Scheduled reminder: "$title" for $formatted (Repeat: $repeatType)',
      name: 'ReminderSchedulerService',
    );

    return 'Reminder scheduled for "$title" at $formatted${repeatType != 'none' ? ' (Repeats $repeatType)' : ''}';
  }

  /// Cancel a scheduled job by ID
  Future<bool> cancelJob(String id) async {
    final jobs = await getAllJobs();
    final index = jobs.indexWhere((j) => j.id == id);
    if (index != -1) {
      jobs[index].isActive = false;
      await _saveJobs(jobs);
      return true;
    }
    return false;
  }

  /// Reschedule all active jobs (e.g. after phone reboot)
  Future<void> rescheduleAll() async {
    final jobs = await getAllJobs();
    final now = DateTime.now();
    for (final job in jobs.where((j) => j.isActive)) {
      if (job.repeatType != 'none' || job.scheduledTime.isAfter(now)) {
        await scheduleReminder(
          title: job.title,
          scheduledTime: job.scheduledTime,
          repeatType: job.repeatType,
          message: job.message,
          taskPrompt: job.taskPrompt,
        );
      }
    }
  }
}
