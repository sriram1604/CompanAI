import 'dart:developer' as developer;
import 'package:android_intent_plus/android_intent.dart';
import 'package:intl/intl.dart';

class CalendarService {
  /// Create a calendar event using Android's native Calendar Contract intent
  Future<String> createEvent({
    required String title,
    required DateTime startTime,
    DateTime? endTime,
    String? location,
    String? description,
    bool allDay = false,
  }) async {
    try {
      final end = endTime ?? startTime.add(const Duration(hours: 1));

      final arguments = <String, dynamic>{
        'title': title,
        'beginTime': startTime.millisecondsSinceEpoch,
        'endTime': end.millisecondsSinceEpoch,
        'allDay': allDay,
        if (location != null && location.isNotEmpty) 'eventLocation': location,
        if (description != null && description.isNotEmpty)
          'description': description,
      };

      final intent = AndroidIntent(
        action: 'android.intent.action.INSERT',
        data: 'content://com.android.calendar/events',
        arguments: arguments,
      );

      await intent.launch();

      final formattedDate =
          DateFormat('EEE, MMM d, yyyy @ h:mm a').format(startTime);
      developer.log(
        'Calendar event intent launched: "$title" at $formattedDate',
        name: 'CalendarService',
      );

      return 'Calendar event created for "$title" on $formattedDate';
    } catch (e) {
      developer.log('Error creating calendar event: $e', name: 'CalendarService');
      return 'Could not open Calendar: $e';
    }
  }
}
