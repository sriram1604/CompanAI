import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../services/ai_service.dart';
import '../services/shizuku_service.dart';
import '../services/screen_automation_service.dart';
import '../services/telegram_service.dart';
import 'task_history_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../config/feature_flags.dart';
import '../theme/app_theme.dart';
import '../widgets/ambient_background.dart';

class SettingsScreen extends StatefulWidget {
  final AiService aiService;
  final ShizukuService shizukuService;
  final ScreenAutomationService screenAutomationService;
  final TelegramService telegramService;

  const SettingsScreen({
    super.key,
    required this.aiService,
    required this.shizukuService,
    required this.screenAutomationService,
    required this.telegramService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  late TextEditingController _apiKeyController;
  late TextEditingController _baseUrlController;
  late TextEditingController _modelController;
  late TextEditingController _telegramTokenController;
  bool _obscureKey = true;
  bool _telegramEnabled = false;
  double _maxSteps = 15;
  bool _disableMaxSteps = false;
  late TextEditingController _maxTokensController;
  double _temperature = 1.0;
  bool _useScreenCompression = true;
  bool _useSystemPrompt = true;
  bool _floatingIconEnabled = false;
  bool _isOverlayPermissionGranted = false;

  final Map<String, PermissionStatus> _permissions = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apiKeyController = TextEditingController(text: widget.aiService.apiKey);
    _baseUrlController = TextEditingController(text: widget.aiService.baseUrl);
    _modelController = TextEditingController(text: widget.aiService.model);
    _telegramTokenController = TextEditingController(
      text: widget.telegramService.botToken,
    );
    _telegramEnabled = widget.telegramService.isEnabled;
    _maxSteps = widget.aiService.rawMaxSteps.toDouble();
    _disableMaxSteps = widget.aiService.disableMaxSteps;
    _temperature = widget.aiService.temperature;
    _maxTokensController = TextEditingController(
      text: widget.aiService.maxTokens.toString(),
    );
    _useScreenCompression = widget.aiService.useScreenCompression;
    _useSystemPrompt = widget.aiService.useSystemPrompt;

    // Auto-save listeners
    _apiKeyController.addListener(_autoSave);
    _baseUrlController.addListener(_autoSave);
    _modelController.addListener(_autoSave);
    _telegramTokenController.addListener(_autoSave);
    _maxTokensController.addListener(_autoSave);

    _checkPermissions();
    if (FeatureFlags.floatingOverlayEnabled) {
      _checkOverlayStatus();
    }
  }

  Future<void> _checkOverlayStatus() async {
    bool isActive = await FlutterOverlayWindow.isActive();
    bool isGranted = await FlutterOverlayWindow.isPermissionGranted();
    if (mounted) {
      setState(() {
        _floatingIconEnabled = isActive;
        _isOverlayPermissionGranted = isGranted;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _apiKeyController.removeListener(_autoSave);
    _baseUrlController.removeListener(_autoSave);
    _modelController.removeListener(_autoSave);
    _telegramTokenController.removeListener(_autoSave);
    _maxTokensController.removeListener(_autoSave);
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _telegramTokenController.dispose();
    _maxTokensController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
      if (FeatureFlags.floatingOverlayEnabled) {
        _checkOverlayStatus();
      }
    }
  }

  Future<void> _checkPermissions() async {
    final perms = {
      'Microphone': Permission.microphone,
      'Contacts': Permission.contacts,
      'Phone': Permission.phone,
      'SMS': Permission.sms,
      'Notifications': Permission.notification,
    };

    for (final entry in perms.entries) {
      _permissions[entry.key] = await entry.value.status;
    }
    final overlayGranted = FeatureFlags.floatingOverlayEnabled
        ? await FlutterOverlayWindow.isPermissionGranted()
        : false;
    if (mounted) {
      setState(() {
        _isOverlayPermissionGranted = overlayGranted;
      });
    }
  }

  Future<void> _requestPermission(String name, Permission permission) async {
    final status = await permission.request();
    setState(() => _permissions[name] = status);
  }

  void _autoSave() {
    widget.aiService.saveSettings(
      apiKey: _apiKeyController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      model: _modelController.text.trim(),
    );

    widget.telegramService.saveSettings(
      botToken: _telegramTokenController.text.trim(),
      isEnabled: _telegramEnabled,
    );

    widget.aiService.saveMaxSteps(_maxSteps.toInt());
    widget.aiService.saveDisableMaxSteps(_disableMaxSteps);
    widget.aiService.saveAdvancedSettings(
      temperature: _temperature,
      maxTokens: int.tryParse(_maxTokensController.text) ?? 1024,
      useScreenCompression: _useScreenCompression,
      useSystemPrompt: _useSystemPrompt,
    );
  }

  Future<void> _fetchModels() async {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (baseUrl.isEmpty || apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter Base URL and API Key first.'),
        ),
      );
      return;
    }

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    final models = await widget.aiService.fetchAvailableModels(baseUrl, apiKey);

    // Hide loading
    if (mounted) Navigator.pop(context);

    if (models.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No models found or error fetching models.'),
          ),
        );
      }
      return;
    }

    if (mounted) {
      final isNvidia = AiService.isNvidiaBaseUrl(baseUrl);
      final isDark = Theme.of(context).brightness == Brightness.dark;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          title: Text(
            isNvidia ? 'Select NVIDIA Model' : 'Select a Model',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 320,
            child: ListView.builder(
              itemCount: models.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(
                    models[index],
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary,
                    ),
                  ),
                  onTap: () {
                    setState(() {
                      _modelController.text = models[index];
                    });
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildSettingsCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
    required bool isDark,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isDark ? AppColors.primary : AppColors.primaryLight)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Icon(
                  icon,
                  color: isDark ? AppColors.primary : AppColors.primaryLight,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AmbientBackground(
      showGlows: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            'Settings',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            ),
          ),
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          physics: const BouncingScrollPhysics(),
          children: [
            // 1. Appearance Card
            _buildSettingsCard(
              icon: Icons.palette_outlined,
              title: 'Appearance',
              subtitle: 'Choose your preferred color theme',
              isDark: isDark,
              children: [
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeNotifier,
                  builder: (context, currentMode, _) {
                    return SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text('System'),
                            icon: Icon(Icons.brightness_auto_rounded, size: 16),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text('Light'),
                            icon: Icon(Icons.light_mode_rounded, size: 16),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text('Dark'),
                            icon: Icon(Icons.dark_mode_rounded, size: 16),
                          ),
                        ],
                        selected: {currentMode},
                        onSelectionChanged: (Set<ThemeMode> newSelection) async {
                          final mode = newSelection.first;
                          themeNotifier.value = mode;
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('themeMode', mode.name);
                        },
                      ),
                    );
                  },
                ),
              ],
            ),

            // 2. AI Engine Configuration Card
            _buildSettingsCard(
              icon: Icons.psychology_outlined,
              title: 'AI Engine Configuration',
              subtitle: 'Supports any OpenAI-compatible API endpoint',
              isDark: isDark,
              children: [
                TextField(
                  controller: _apiKeyController,
                  obscureText: _obscureKey,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: 'sk-...',
                    prefixIcon: const Icon(Icons.key_rounded, size: 18),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureKey
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 18,
                      ),
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _baseUrlController,
                  decoration: const InputDecoration(
                    labelText: 'API Base URL',
                    hintText: 'https://api.deepseek.com',
                    prefixIcon: Icon(Icons.dns_rounded, size: 18),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ActionChip(
                      label: const Text('Gemini', style: TextStyle(fontSize: 11)),
                      onPressed: () {
                        _baseUrlController.text =
                            'https://generativelanguage.googleapis.com/v1beta/openai';
                        _modelController.text = 'gemini-2.0-flash';
                      },
                    ),
                    ActionChip(
                      label: const Text('DeepSeek', style: TextStyle(fontSize: 11)),
                      onPressed: () {
                        _baseUrlController.text = 'https://api.deepseek.com';
                        _modelController.text = 'deepseek-chat';
                      },
                    ),
                    ActionChip(
                      label: const Text('Groq', style: TextStyle(fontSize: 11)),
                      onPressed: () {
                        _baseUrlController.text = 'https://api.groq.com/openai/v1';
                        _modelController.text = 'llama-3.3-70b-versatile';
                      },
                    ),
                    ActionChip(
                      label: const Text('NVIDIA NIM', style: TextStyle(fontSize: 11)),
                      onPressed: () {
                        _baseUrlController.text = AiService.nvidiaBaseUrl;
                        _modelController.text = AiService.nvidiaDefaultModel;
                      },
                    ),
                    ActionChip(
                      label: const Text('Ollama', style: TextStyle(fontSize: 11)),
                      onPressed: () {
                        _baseUrlController.text = 'http://10.0.2.2:11434/v1';
                        _modelController.text = 'gemma2';
                      },
                    ),
                    ActionChip(
                      label: const Text('Local Server', style: TextStyle(fontSize: 11)),
                      onPressed: () {
                        _baseUrlController.text = 'http://192.168.1.X:8080/v1';
                      },
                    ),
                    ActionChip(
                      label: const Text('Clear', style: TextStyle(fontSize: 11)),
                      onPressed: () {
                        _baseUrlController.clear();
                        _apiKeyController.clear();
                        _modelController.clear();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _modelController,
                        decoration: const InputDecoration(
                          labelText: 'Model Name',
                          hintText: 'deepseek-chat',
                          prefixIcon: Icon(Icons.smart_toy_outlined, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _fetchModels,
                      icon: const Icon(Icons.sync_rounded, size: 16),
                      label: const Text(
                        'Fetch',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark
                            ? AppColors.primary
                            : AppColors.primaryLight,
                        foregroundColor: isDark ? const Color(0xFF0A0D14) : Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.md),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    'gemini-2.0-flash',
                    'gemini-1.5-flash',
                    'gemini-1.5-pro',
                    'deepseek-chat',
                    'llama-3.3-70b-versatile',
                  ].map((m) {
                    final isCurrent = _modelController.text == m;
                    return ChoiceChip(
                      label: Text(
                        m,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w500,
                          color: isCurrent
                              ? (isDark ? const Color(0xFF0A0D14) : Colors.white)
                              : (isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.lightTextPrimary),
                        ),
                      ),
                      selected: isCurrent,
                      selectedColor: isDark ? AppColors.primary : AppColors.primaryLight,
                      backgroundColor: isDark
                          ? AppColors.darkSurface
                          : AppColors.lightSurfaceElevated,
                      side: BorderSide(
                        color: isCurrent
                            ? (isDark ? AppColors.primary : AppColors.primaryLight)
                            : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                      ),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _modelController.text = m;
                          });
                          _autoSave();
                        }
                      },
                    );
                  }).toList(),
                ),
              ],
            ),

            // 3. Parameters & Tuning Card
            _buildSettingsCard(
              icon: Icons.tune_rounded,
              title: 'Parameters & Tuning',
              subtitle: 'Agent step boundaries and LLM sampling parameters',
              isDark: isDark,
              children: [
                SwitchListTile(
                  title: const Text('Disable Maximum Steps'),
                  subtitle: const Text(
                    'Warning: Can cause infinite execution loops.',
                    style: TextStyle(color: AppColors.warning, fontSize: 12),
                  ),
                  value: _disableMaxSteps,
                  onChanged: (bool value) {
                    setState(() {
                      _disableMaxSteps = value;
                    });
                    _autoSave();
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                if (!_disableMaxSteps) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Max Steps Per Task',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: (isDark
                                  ? AppColors.primary
                                  : AppColors.primaryLight)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                        ),
                        child: Text(
                          _maxSteps.toInt().toString(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? AppColors.primary
                                : AppColors.primaryLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _maxSteps,
                    min: 5,
                    max: 50,
                    divisions: 45,
                    onChanged: (value) {
                      setState(() {
                        _maxSteps = value;
                      });
                    },
                    onChangeEnd: (value) {
                      _autoSave();
                    },
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: _maxTokensController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Context Limit (Max Tokens)',
                    hintText: '1024',
                    prefixIcon: Icon(Icons.token_rounded, size: 18),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Temperature',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: (isDark
                                ? AppColors.primary
                                : AppColors.primaryLight)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
                      child: Text(
                        _temperature.toStringAsFixed(2),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? AppColors.primary
                              : AppColors.primaryLight,
                        ),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _temperature,
                  min: 0.0,
                  max: 2.0,
                  divisions: 20,
                  onChanged: (value) {
                    setState(() {
                      _temperature = value;
                    });
                  },
                  onChangeEnd: (value) {
                    _autoSave();
                  },
                ),
              ],
            ),

            // 4. Behavior & Extensions Card
            _buildSettingsCard(
              icon: Icons.extension_outlined,
              title: 'Behavior & Extensions',
              subtitle: 'Feature flags, prompt tuning, and floating assistant',
              isDark: isDark,
              children: [
                SwitchListTile(
                  title: const Text('Screen Compression'),
                  subtitle: const Text(
                    'Removes duplicate accessibility nodes to save tokens',
                  ),
                  value: _useScreenCompression,
                  onChanged: (bool value) {
                    setState(() {
                      _useScreenCompression = value;
                    });
                    _autoSave();
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  title: const Text('Send System Prompt'),
                  subtitle: const Text(
                    'Includes agent role instructions in LLM payload',
                  ),
                  value: _useSystemPrompt,
                  onChanged: (bool value) {
                    setState(() {
                      _useSystemPrompt = value;
                    });
                    _autoSave();
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                if (FeatureFlags.floatingOverlayEnabled)
                  SwitchListTile(
                    title: const Text('Floating Assistant Bubble'),
                    subtitle: const Text(
                      'Monitor and assign tasks from over other apps',
                    ),
                    value: _floatingIconEnabled,
                    onChanged: (val) async {
                      if (val) {
                        bool? isGranted =
                            await FlutterOverlayWindow.isPermissionGranted();
                        if (isGranted != true) {
                          bool? result =
                              await FlutterOverlayWindow.requestPermission();
                          if (result != true) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Permission to draw over other apps is required.',
                                ),
                              ),
                            );
                            return;
                          }
                        }
                        if (await FlutterOverlayWindow.isActive() == false) {
                          await FlutterOverlayWindow.showOverlay(
                            enableDrag: true,
                            overlayTitle: "CompanAI",
                            overlayContent: "Floating Assistant",
                            flag: OverlayFlag.focusPointer,
                            alignment: OverlayAlignment.centerRight,
                            visibility: NotificationVisibility.visibilitySecret,
                            positionGravity: PositionGravity.auto,
                            startPosition: const OverlayPosition(0, 200),
                            width: 56,
                            height: 56,
                          );
                        }
                      } else {
                        if (await FlutterOverlayWindow.isActive() == true) {
                          await FlutterOverlayWindow.closeOverlay();
                        }
                      }
                      setState(() => _floatingIconEnabled = val);
                      _autoSave();
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),

            // 5. Telegram Remote Access Card
            _buildSettingsCard(
              icon: Icons.send_rounded,
              title: 'Telegram Remote Control',
              subtitle: 'Control your mobile agent remotely through Telegram',
              isDark: isDark,
              children: [
                TextField(
                  controller: _telegramTokenController,
                  decoration: const InputDecoration(
                    labelText: 'Telegram Bot Token',
                    hintText: '123456:ABC-DEF1234ghIkl...',
                    prefixIcon: Icon(Icons.key_outlined, size: 18),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Enable Telegram Bot'),
                  subtitle: const Text('Listens for commands via Telegram chat'),
                  value: _telegramEnabled,
                  onChanged: (val) {
                    setState(() => _telegramEnabled = val);
                    _autoSave();
                  },
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),

            // 6. Screen Control & Accessibility
            _buildSettingsCard(
              icon: Icons.visibility_outlined,
              title: 'Screen Control (Accessibility)',
              subtitle: 'Required to read screen layout and perform automated taps',
              isDark: isDark,
              children: [_buildAccessibilityCard(isDark)],
            ),

            // 7. System Permissions Card
            _buildSettingsCard(
              icon: Icons.security_rounded,
              title: 'App Permissions',
              subtitle: 'Configure device capabilities for full automation',
              isDark: isDark,
              children: _buildPermissionTiles(isDark),
            ),

            // 8. Execution Logs Card
            _buildSettingsCard(
              icon: Icons.history_rounded,
              title: 'Execution Logs & Traces',
              subtitle: 'View history of task steps and token usage metrics',
              isDark: isDark,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (isDark
                              ? AppColors.primary
                              : AppColors.primaryLight)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                    child: Icon(
                      Icons.analytics_outlined,
                      size: 20,
                      color: isDark ? AppColors.primary : AppColors.primaryLight,
                    ),
                  ),
                  title: const Text('View Task History'),
                  subtitle: const Text('Browse complete execution trace logs'),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 15),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const TaskHistoryScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),

            // 9. About / Developer Card
            _buildSettingsCard(
              icon: Icons.info_outline_rounded,
              title: 'About CompanAI',
              subtitle: 'Developer information and open-source links',
              isDark: isDark,
              children: [
                // Developer Info Box
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurfaceElevated
                        : AppColors.lightSurfaceHighlight,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(
                      color: (isDark ? AppColors.primary : AppColors.primaryLight)
                          .withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              isDark ? AppColors.primary : AppColors.primaryLight,
                              isDark ? AppColors.primaryLight : AppColors.primary,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Created by',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppColors.darkTextMuted
                                    : AppColors.lightTextMuted,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Sriram Venkatesan',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.lightTextPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // GitHub Link
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (isDark ? AppColors.primary : AppColors.primaryLight)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                    child: Icon(
                      Icons.code_rounded,
                      size: 20,
                      color: isDark ? AppColors.primary : AppColors.primaryLight,
                    ),
                  ),
                  title: const Text(
                    'GitHub Repository',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                  subtitle: const Text(
                    'Source code, issues & releases',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 16),
                  onTap: () {
                    launchUrl(
                      Uri.parse('https://github.com/sriram1604/CompanAI'),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                ),
                Divider(
                  height: 1,
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),

                // LinkedIn Link
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0077B5).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                    child: const Icon(
                      Icons.business_center_rounded,
                      size: 20,
                      color: Color(0xFF0077B5),
                    ),
                  ),
                  title: const Text(
                    'LinkedIn',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                  subtitle: const Text(
                    'Connect on LinkedIn',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 16),
                  onTap: () {
                    launchUrl(
                      Uri.parse('https://www.linkedin.com/in/sriram-venkatesan-85433a260/'),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                ),
                Divider(
                  height: 1,
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),

                // Instagram Link
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE4405F).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      size: 20,
                      color: Color(0xFFE4405F),
                    ),
                  ),
                  title: const Text(
                    'Instagram',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                  subtitle: const Text(
                    '@_srx_.rzm_',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 16),
                  onTap: () {
                    launchUrl(
                      Uri.parse('https://www.instagram.com/_srx_.rzm_/'),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                ),
                Divider(
                  height: 1,
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),

                // Open Source Licenses
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                    child: Icon(
                      Icons.article_outlined,
                      size: 20,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                  title: const Text(
                    'Open Source Licenses',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                  subtitle: const Text(
                    'Third-party software notices & licenses',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: () {
                    showLicensePage(
                      context: context,
                      applicationName: 'CompanAI',
                      applicationVersion: '1.0.2',
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPermissionTiles(bool isDark) {
    final permissionMap = {
      'Microphone': Permission.microphone,
      'Contacts': Permission.contacts,
      'Phone': Permission.phone,
      'SMS': Permission.sms,
      'Notifications': Permission.notification,
    };

    final icons = {
      'Microphone': Icons.mic_rounded,
      'Contacts': Icons.contacts_rounded,
      'Phone': Icons.phone_rounded,
      'SMS': Icons.sms_rounded,
      'Notifications': Icons.notifications_rounded,
    };

    final list = permissionMap.entries.map((entry) {
      final status = _permissions[entry.key];
      final isGranted = status?.isGranted ?? false;

      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          icons[entry.key],
          color: isGranted
              ? AppColors.success
              : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
        ),
        title: Text(entry.key),
        trailing: isGranted
            ? const Icon(
                Icons.check_circle_rounded,
                color: AppColors.success,
                size: 20,
              )
            : ElevatedButton(
                onPressed: () => _requestPermission(entry.key, entry.value),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  minimumSize: const Size(0, 30),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                ),
                child: const Text('Grant', style: TextStyle(fontSize: 12)),
              ),
        subtitle: Text(
          isGranted
              ? 'Permission granted'
              : (status?.isDenied ?? true ? 'Not granted' : 'Denied permanently'),
          style: TextStyle(
            color: isGranted ? AppColors.success : AppColors.warning,
            fontSize: 12,
          ),
        ),
      );
    }).toList();

    if (FeatureFlags.floatingOverlayEnabled) {
      list.add(
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.layers_rounded,
            color: _isOverlayPermissionGranted
                ? AppColors.success
                : (isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary),
          ),
          title: const Text('Display Over Other Apps'),
          trailing: _isOverlayPermissionGranted
              ? const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.success,
                  size: 20,
                )
              : ElevatedButton(
                  onPressed: () async {
                    await FlutterOverlayWindow.requestPermission();
                    final granted =
                        await FlutterOverlayWindow.isPermissionGranted();
                    setState(() {
                      _isOverlayPermissionGranted = granted;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 30),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                  ),
                  child: const Text('Grant', style: TextStyle(fontSize: 12)),
                ),
          subtitle: Text(
            _isOverlayPermissionGranted ? 'Permission granted' : 'Not granted',
            style: TextStyle(
              color: _isOverlayPermissionGranted
                  ? AppColors.success
                  : AppColors.warning,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return list;
  }

  Widget _buildAccessibilityCard(bool isDark) {
    return FutureBuilder<bool>(
      future: widget.screenAutomationService.isServiceRunning(),
      builder: (context, snapshot) {
        final isRunning = snapshot.data ?? false;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isRunning
                ? AppColors.successContainer
                : (isDark
                    ? AppColors.darkSurface
                    : AppColors.lightSurfaceHighlight),
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: isRunning
                  ? AppColors.successBorder
                  : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
              width: 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isRunning
                        ? Icons.check_circle_rounded
                        : Icons.visibility_off_rounded,
                    color: isRunning ? AppColors.success : AppColors.warning,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isRunning
                        ? 'Screen Control is Active'
                        : 'Screen Control is Disabled',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: isRunning
                          ? AppColors.success
                          : (isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.lightTextPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (!isRunning) ...[
                Text(
                  'Open Accessibility Settings and turn ON "CompanAI Screen Control" to allow the agent to automate clicks and scrolls.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    await widget.screenAutomationService
                        .openAccessibilitySettings();
                  },
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  label: const Text('Open Accessibility Settings'),
                ),
              ] else ...[
                Text(
                  'Agent can read on-screen UI hierarchy, tap elements, and type inputs across other apps.',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
