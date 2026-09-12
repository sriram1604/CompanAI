import 'package:url_launcher/url_launcher.dart';
import '../models/agent_action.dart';
import '../models/chat_message.dart';
import 'app_launcher_service.dart';
import 'contacts_service.dart';
import 'contact_resolver_service.dart';
import 'communication_service.dart';
import 'alarm_service.dart';
import 'system_control_service.dart';
import 'shizuku_service.dart';
import 'screen_automation_service.dart';
import 'task_executor.dart';
import 'ai_service.dart';
import 'calendar_service.dart';
import 'reminder_scheduler_service.dart';
import 'messaging_service.dart';
import 'product_comparison_engine.dart';

class ActionHandler {
  final AppLauncherService _appLauncher = AppLauncherService();
  final ContactsService _contacts = ContactsService();
  final ContactResolverService _resolver = ContactResolverService();
  final CommunicationService _communication = CommunicationService();
  final AlarmService _alarm = AlarmService();
  final SystemControlService _systemControl = SystemControlService();
  final ShizukuService _shizuku = ShizukuService();
  final ScreenAutomationService _screenAutomation = ScreenAutomationService();
  final CalendarService _calendar = CalendarService();
  final ReminderSchedulerService _scheduler = ReminderSchedulerService();
  final MessagingService _messaging = MessagingService();
  final ProductComparisonEngine _productEngine = ProductComparisonEngine();

  ShizukuService get shizuku => _shizuku;
  ScreenAutomationService get screenAutomation => _screenAutomation;
  ReminderSchedulerService get scheduler => _scheduler;

  /// The currently running task executor, if any
  TaskExecutor? _currentExecutor;

  /// Execute an action and return the result
  Future<AgentActionResult> execute(
    AgentAction action, {
    AiService? aiService,
    void Function(String)? onProgress,
  }) async {
    try {
      String result;

      switch (action.action) {
        case 'open_app':
          result = await _appLauncher.openApp(
            action.params['app_name'] as String? ?? action.params['package_name'] as String? ?? '',
          );
          break;

        case 'launch_package':
          final packageName = action.params['package_name'] as String? ?? '';
          result = await _appLauncher.openPackage(packageName);
          break;

        case 'make_call':
          final contactName = action.params['contact_name'] as String? ?? action.params['contact'] as String?;
          final phoneNumber = action.params['phone_number'] as String?;
          if (contactName != null && phoneNumber == null) {
            final resolution = await _resolver.resolveContact(contactName);
            if (resolution.isSingleMatch && resolution.primaryMatch?.primaryPhoneNumber != null) {
              result = await _communication.makeCall(
                contactName: resolution.primaryMatch!.displayName,
                phoneNumber: resolution.primaryMatch!.primaryPhoneNumber,
              );
            } else if (resolution.isAmbiguous) {
              final candidateList = resolution.candidateMatches
                  .map((c) => '• ${c.displayName}: ${c.primaryPhoneNumber ?? "No number"}')
                  .join('\n');
              result = 'Multiple contacts matched "$contactName":\n$candidateList\nPlease specify which one to call.';
            } else {
              result = resolution.message;
            }
          } else {
            result = await _communication.makeCall(
              contactName: contactName,
              phoneNumber: phoneNumber,
            );
          }
          break;

        case 'send_sms':
          result = await _communication.sendSms(
            contactName: action.params['contact_name'] as String?,
            phoneNumber: action.params['phone_number'] as String?,
            message: action.params['message'] as String? ?? '',
          );
          break;

        case 'search_contact':
          result = await _contacts.searchAndFormat(
            action.params['query'] as String? ?? '',
          );
          break;

        case 'set_alarm':
          result = await _alarm.setAlarm(
            hour: (action.params['hour'] as num?)?.toInt() ?? 0,
            minute: (action.params['minute'] as num?)?.toInt() ?? 0,
            label: action.params['label'] as String?,
          );
          break;

        case 'set_timer':
          result = await _alarm.setTimer(
            seconds: (action.params['seconds'] as num?)?.toInt() ?? 60,
            label: action.params['label'] as String?,
          );
          break;

        case 'set_volume':
          result = await _systemControl.setVolume(
            (action.params['level'] as num?)?.toInt() ?? 50,
          );
          break;

        case 'set_brightness':
          result = await _systemControl.setBrightness(
            (action.params['level'] as num?)?.toInt() ?? 50,
          );
          break;

        case 'run_adb_command':
          result = await _shizuku.runCommand(
            action.params['command'] as String? ?? '',
          );
          break;

        case 'send_email':
          result = await _communication.sendEmail(
            to: action.params['to'] as String? ?? '',
            subject: action.params['subject'] as String?,
            body: action.params['body'] as String?,
          );
          break;

        case 'open_url':
          result = await _appLauncher.openUrl(
            action.params['url'] as String? ?? '',
          );
          break;

        // ─── Search & Navigation ──────────────────────────────
        case 'search':
          final app = (action.params['app'] as String? ?? 'browser').toLowerCase();
          final query = action.params['query'] as String? ?? '';
          if (app.contains('youtube')) {
            final uri = Uri.parse('vnd.youtube://results?search_query=${Uri.encodeComponent(query)}');
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
              result = 'Searching YouTube for "$query"';
            } else {
              result = await _appLauncher.openUrl('https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}');
            }
          } else {
            result = await _appLauncher.openUrl('https://www.google.com/search?q=${Uri.encodeComponent(query)}');
          }
          break;

        // ─── Product Search & Cross-Site Comparison ───────────
        case 'search_product':
        case 'compare_products':
          final query = action.params['query'] as String? ?? '';
          final sites = (action.params['sites'] as List?)?.map((s) => s.toString()).toList();
          result = await _productEngine.searchAndCompareProducts(
            query: query,
            targetSites: sites,
            onProgress: onProgress,
          );
          break;

        // ─── Deterministic Calendar & Reminder Actions ────────
        case 'create_calendar_event':
          final title = action.params['title'] as String? ?? 'Event';
          final startTimeStr = action.params['start_time'] as String?;
          final endTimeStr = action.params['end_time'] as String?;
          final location = action.params['location'] as String?;
          final description = action.params['description'] as String?;
          final allDay = action.params['all_day'] as bool? ?? false;

          final startTime = startTimeStr != null
              ? DateTime.tryParse(startTimeStr) ?? DateTime.now().add(const Duration(hours: 1))
              : DateTime.now().add(const Duration(hours: 1));
          final endTime = endTimeStr != null ? DateTime.tryParse(endTimeStr) : null;

          result = await _calendar.createEvent(
            title: title,
            startTime: startTime,
            endTime: endTime,
            location: location,
            description: description,
            allDay: allDay,
          );
          break;

        case 'set_reminder':
        case 'schedule_job':
          final title = action.params['title'] as String? ?? 'Reminder';
          final scheduledTimeStr = action.params['scheduled_time'] as String?;
          final repeat = action.params['repeat'] as String? ?? 'none';
          final message = action.params['message'] as String?;
          final taskPrompt = action.params['task_prompt'] as String?;

          final scheduledTime = scheduledTimeStr != null
              ? DateTime.tryParse(scheduledTimeStr) ?? DateTime.now().add(const Duration(minutes: 30))
              : DateTime.now().add(const Duration(minutes: 30));

          result = await _scheduler.scheduleReminder(
            title: title,
            scheduledTime: scheduledTime,
            repeatType: repeat,
            message: message,
            taskPrompt: taskPrompt,
          );
          break;

        case 'send_message':
          final app = action.params['app'] as String? ?? 'WhatsApp';
          final recipient = action.params['recipient'] as String? ?? action.params['target'] as String? ?? '';
          final message = action.params['message'] as String? ?? '';

          result = await _messaging.sendMessage(
            app: app,
            recipient: recipient,
            message: message,
          );
          break;

        // ─── Screen Automation Actions ────────────────────────
        case 'read_screen':
          result = await _screenAutomation.getScreenDescription();
          break;

        case 'click_element':
          final text = action.params['text'] as String? ?? '';
          final success = await _screenAutomation.clickByText(text);
          result = success ? 'Clicked "$text"' : 'Could not find "$text" to click';
          break;

        case 'type_on_screen':
          final text = action.params['text'] as String? ?? '';
          final hint = action.params['field_hint'] as String?;
          final success = await _screenAutomation.typeText(text, fieldHint: hint);
          result = success ? 'Typed "$text"' : 'Could not type into field';
          break;

        case 'scroll_screen':
          final direction = action.params['direction'] as String? ?? 'down';
          final success = await _screenAutomation.scroll(direction);
          result = success ? 'Scrolled $direction' : 'Could not scroll';
          break;

        case 'press_back':
          final success = await _screenAutomation.pressBack();
          result = success ? 'Pressed back' : 'Could not press back';
          break;

        // ─── Multi-Step Task Execution ────────────────────────
        case 'execute_task':
          final goal = action.params['goal'] as String? ?? action.response;
          if (aiService == null) {
            result = 'AI service not available for task execution.';
            break;
          }
          _currentExecutor = TaskExecutor(
            aiService: aiService,
            screenService: _screenAutomation,
            appLauncher: _appLauncher,
            shizukuService: _shizuku,
            onProgress: onProgress,
          );
          result = await _currentExecutor!.executeTask(goal);
          _currentExecutor = null;
          break;

        default:
          result = action.response;
      }

      return AgentActionResult(
        actionType: action.action,
        success: true,
        details: result,
      );
    } catch (e) {
      return AgentActionResult(
        actionType: action.action,
        success: false,
        details: 'Error: $e',
      );
    }
  }

  /// Cancel the currently running task
  void cancelTask() {
    _currentExecutor?.cancel();
  }
}
