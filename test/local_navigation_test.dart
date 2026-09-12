import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/models/agent_action_schema.dart';
import 'package:private_agent/services/local_ai/local_task_planner.dart';
import 'package:private_agent/services/local_ai/task_state_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ActionSchemaValidator & JSON Repair Tests', () {
    test('repairs unclosed JSON and trailing commas', () {
      final malformed = '{"action": "click_text", "params": {"text": "Search chats",},';
      final action = ActionSchemaValidator.parseAndValidate(malformed);
      expect(action.type, ActionType.tap);
      expect(action.params['target'], 'Search chats');
    });

    test('parses markdown wrapped json', () {
      final md = '```json\n{"action": "send_message", "params": {"app": "WhatsApp", "target": "Capstone Team", "message": "hello"}}\n```';
      final action = ActionSchemaValidator.parseAndValidate(md);
      expect(action.type, ActionType.sendMessage);
      expect(action.params['target'], 'Capstone Team');
      expect(action.params['message'], 'hello');
    });

    test('repairs single quotes', () {
      final singleQuotes = "{'action': 'make_call', 'params': {'contact': 'Amma', 'call_type': 'audio'}}";
      final action = ActionSchemaValidator.parseAndValidate(singleQuotes);
      expect(action.type, ActionType.makeCall);
      expect(action.params['contact'], 'Amma');
    });

    test('safely falls back for empty output', () {
      final action = ActionSchemaValidator.parseAndValidate('');
      expect(action.type, ActionType.wait);
    });
  });

  group('TaskStateManager Multi-Step Decomposition', () {
    final stateManager = TaskStateManager();

    test('decomposes TEST 14 compound prompt into ordered sub-tasks', () {
      final compound = 'Open WhatsApp, message the Capstone group, then open YouTube and search Java, then search AirPods on Amazon, Flipkart and Meesho and compare the prices.';
      final session = stateManager.createSession(compound);

      expect(session.subTasks.length, greaterThanOrEqualTo(3));
      expect(session.subTasks[0].actionType, 'send_message');
      expect(session.subTasks[1].actionType, 'search');
      expect(session.subTasks[2].actionType, 'search_product');
      expect(session.currentSubTaskIndex, 0);
      expect(session.isFinished, isFalse);
    });

    test('advances sub-tasks correctly', () {
      final session = stateManager.createSession('Open WhatsApp then search Java');
      expect(session.currentSubTaskIndex, 0);
      stateManager.advanceSubTask('Opened WhatsApp');
      expect(session.currentSubTaskIndex, 1);
      stateManager.advanceSubTask('Searched Java');
      expect(session.isFinished, isTrue);
    });
  });

  group('LocalTaskPlanner Intent Extraction Matrix', () {
    final planner = LocalTaskPlanner();

    test('TEST 1: WhatsApp message to Capstone Project Team group', () async {
      final action = await planner.planUserCommand(
        'Open WhatsApp and send "hello this is sriram\'s companai assistant" to Capstone Project Team.',
      );
      expect(action.action, 'send_message');
      expect(action.params['app'], 'WhatsApp');
      expect(action.params['recipient'].toString().toLowerCase(), contains('capstone'));
      expect(action.params['message'], "hello this is sriram's companai assistant");
    });

    test('TEST 2: WhatsApp message to Amma', () async {
      final action = await planner.planUserCommand('Open WhatsApp and send hello to Amma.');
      expect(action.action, 'send_message');
      expect(action.params['recipient'].toString().toLowerCase(), 'amma');
      expect(action.params['message'], 'hello');
    });

    test('TEST 3: Call Amma', () async {
      final action = await planner.planUserCommand('Call Amma.');
      expect(action.action, 'make_call');
      expect(action.params['contact_name'], 'Amma');
    });

    test('TEST 4: Make an audio call to Amma', () async {
      final action = await planner.planUserCommand('Make an audio call to Amma.');
      expect(action.action, 'make_call');
      expect(action.params['contact_name'], 'Amma');
    });

    test('TEST 5: Open Instagram and message John saying hello', () async {
      final action = await planner.planUserCommand('Open Instagram and message John saying hello.');
      expect(action.action, 'send_message');
      expect(action.params['app'], 'Instagram');
      expect(action.params['recipient'], 'John');
      expect(action.params['message'], 'hello');
    });

    test('TEST 6 & 7: YouTube search', () async {
      final action1 = await planner.planUserCommand('Open YouTube and search some.');
      expect(action1.action, 'search');
      expect(action1.params['app'], 'youtube');

      final action2 = await planner.planUserCommand('Open YouTube and search Java Spring Boot.');
      expect(action2.action, 'search');
      expect(action2.params['app'], 'youtube');
      expect(action2.params['query'], 'Java Spring Boot');
    });

    test('TEST 8: Open browser and search Apple AirPods', () async {
      final action = await planner.planUserCommand('Open browser and search Apple AirPods.');
      expect(action.action, 'search');
      expect(action.params['app'], 'browser');
      expect(action.params['query'], 'Apple AirPods');
    });

    test('TEST 9: Search Amazon for Apple AirPods', () async {
      final action = await planner.planUserCommand('Search Amazon for Apple AirPods.');
      expect(action.action, 'search_product');
      expect(action.params['sites'], contains('amazon'));
      expect(action.params['query'], 'Apple AirPods');
    });

    test('TEST 10: Compare Apple AirPods on Amazon, Flipkart, Meesho', () async {
      final action = await planner.planUserCommand(
        'Search Apple AirPods prices in India on Amazon, Flipkart and Meesho and tell me the cheapest option.',
      );
      expect(action.action, 'search_product');
      expect(action.params['sites'], contains('amazon'));
      expect(action.params['sites'], contains('flipkart'));
      expect(action.params['sites'], contains('meesho'));
      expect(action.params['query'], 'Apple AirPods');
    });

    test('TEST 11: Create a meeting tomorrow at 10 AM', () async {
      final action = await planner.planUserCommand('Create a meeting tomorrow at 10 AM.');
      expect(action.action, 'create_calendar_event');
      expect(action.params['title'], 'Meeting');
    });

    test('TEST 12: Remind me tomorrow at 8 AM to call Amma', () async {
      final action = await planner.planUserCommand('Remind me tomorrow at 8 AM to call Amma.');
      expect(action.action, 'set_reminder');
      expect(action.params['title'], 'call Amma');
    });

    test('TEST 13: Every Monday at 9 AM remind me about the meeting', () async {
      final action = await planner.planUserCommand('Every Monday at 9 AM remind me about the meeting.');
      expect(action.action, 'set_reminder');
      expect(action.params['repeat'], 'weekly');
      expect(action.params['title'], 'the meeting');
    });

    test('General Purpose Automation: Banking app check balance', () async {
      final action = await planner.planUserCommand('Open my banking app and check my account balance.');
      expect(action.action, 'execute_task');
      expect(action.params['goal'], contains('banking app'));
    });

    test('General Purpose Automation: Gmail check latest email from manager', () async {
      final action = await planner.planUserCommand('Open Gmail and find the latest email from my manager.');
      expect(action.action, 'execute_task');
      expect(action.params['goal'], contains('Gmail'));
    });

    test('Pure Conversation: Greetings and questions', () async {
      final greeting = await planner.planUserCommand('Hello, how are you?');
      expect(greeting.action, 'general_query');

      final capabilities = await planner.planUserCommand('What can you do?');
      expect(capabilities.action, 'general_query');
    });
  });
}
