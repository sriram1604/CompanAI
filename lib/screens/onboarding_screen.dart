import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../config/feature_flags.dart';
import '../services/ai_service.dart';
import '../services/screen_automation_service.dart';
import 'home_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/ambient_background.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  final ScreenAutomationService _screenAutomationService =
      ScreenAutomationService();
  final AiService _aiService = AiService();

  int _currentStep = 0;
  bool _isAccessibilityGranted = false;
  bool _isMicrophoneGranted = false;
  bool _isNotificationsGranted = false;
  bool _isContactsGranted = false;
  bool _isPhoneGranted = false;
  bool _isSmsGranted = false;
  bool _isOverlayGranted = false;

  // AI config states
  String _selectedProvider = 'gemini';
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController(
    text: 'https://generativelanguage.googleapis.com/v1beta/openai',
  );
  final TextEditingController _modelController = TextEditingController(
    text: 'gemini-2.0-flash',
  );
  bool _obscureKey = true;
  bool _isValidating = false;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAiDefaults();
    _checkPermissions();
  }

  Future<void> _loadAiDefaults() async {
    await _aiService.init();
    if (!mounted) return;
    if (_aiService.isConfigured) {
      final base = _aiService.baseUrl.toLowerCase();
      final model = _aiService.model.toLowerCase();
      String detected = 'custom';
      if (base.contains('generativelanguage.googleapis.com') ||
          model.contains('gemini')) {
        detected = 'gemini';
      } else if (base.contains('deepseek.com') || model.contains('deepseek')) {
        detected = 'deepseek';
      } else if (base.contains('groq.com')) {
        detected = 'groq';
      } else if (base.contains('nvidia.com')) {
        detected = 'nvidia';
      } else if (base.contains('11434')) {
        detected = 'ollama';
      } else if (base.contains('1234') || base.contains('8080')) {
        detected = 'local';
      }
      setState(() {
        _selectedProvider = detected;
        _apiKeyController.text = _aiService.apiKey;
        _baseUrlController.text = _aiService.baseUrl;
        _modelController.text = _aiService.model;
      });
    } else {
      _selectProvider('gemini');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final accessibilityRunning = await _screenAutomationService
        .isServiceRunning();
    final microphoneStatus = await Permission.microphone.status;
    final notificationsStatus = await Permission.notification.status;
    final contactsStatus = await Permission.contacts.status;
    final phoneStatus = await Permission.phone.status;
    final smsStatus = await Permission.sms.status;
    final overlayGranted = FeatureFlags.floatingOverlayEnabled
        ? await FlutterOverlayWindow.isPermissionGranted()
        : false;

    if (mounted) {
      setState(() {
        _isAccessibilityGranted = accessibilityRunning;
        _isMicrophoneGranted = microphoneStatus.isGranted;
        _isNotificationsGranted = notificationsStatus.isGranted;
        _isContactsGranted = contactsStatus.isGranted;
        _isPhoneGranted = phoneStatus.isGranted;
        _isSmsGranted = smsStatus.isGranted;
        _isOverlayGranted = overlayGranted;
      });
    }
  }

  Future<void> _requestPermission(Permission permission) async {
    await permission.request();
    _checkPermissions();
  }

  Future<void> _requestAccessibility() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enable Screen Control'),
        content: const Text(
          'If Android shows "Restricted setting", open App Info first, tap the '
          'three-dot menu, and choose "Allow restricted settings". Then return '
          'and open Accessibility Settings to enable CompanAI Screen Control.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _screenAutomationService.openAccessibilitySettings();
            },
            child: const Text('Accessibility Settings'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              openAppSettings();
            },
            child: const Text('Open App Info First'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestOverlayPermission() async {
    if (!FeatureFlags.floatingOverlayEnabled) return;
    bool granted = await FlutterOverlayWindow.isPermissionGranted();
    if (!granted) {
      await FlutterOverlayWindow.requestPermission();
      granted = await FlutterOverlayWindow.isPermissionGranted();
    }
    setState(() {
      _isOverlayGranted = granted;
    });
  }

  void _selectProvider(String provider) {
    setState(() {
      _selectedProvider = provider;
      _validationError = null;
      if (provider == 'gemini') {
        _baseUrlController.text =
            'https://generativelanguage.googleapis.com/v1beta/openai';
        _modelController.text = 'gemini-2.0-flash';
      } else if (provider == 'deepseek') {
        _baseUrlController.text = 'https://api.deepseek.com';
        _modelController.text = 'deepseek-chat';
      } else if (provider == 'groq') {
        _baseUrlController.text = 'https://api.groq.com/openai/v1';
        _modelController.text = 'llama-3.3-70b-versatile';
      } else if (provider == 'nvidia') {
        _baseUrlController.text = AiService.nvidiaBaseUrl;
        _modelController.text = AiService.nvidiaDefaultModel;
      } else if (provider == 'ollama') {
        _baseUrlController.text = 'http://10.0.2.2:11434/v1';
        _modelController.text = 'gemma2';
      } else if (provider == 'local') {
        _baseUrlController.text = 'http://10.0.2.2:1234/v1';
        _modelController.text = 'qwen2.5-7b-instruct';
      } else {
        _baseUrlController.clear();
        _modelController.clear();
      }
    });
  }

  Future<void> _testAndSave() async {
    setState(() {
      _isValidating = true;
      _validationError = null;
    });

    final apiKey = _apiKeyController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    final model = _modelController.text.trim();

    if (baseUrl.isEmpty || model.isEmpty) {
      setState(() {
        _validationError = 'Please fill out API Base URL and Model.';
        _isValidating = false;
      });
      return;
    }

    if (_selectedProvider != 'ollama' &&
        _selectedProvider != 'local' &&
        apiKey.isEmpty) {
      setState(() {
        _validationError = 'API Key is required for this provider.';
        _isValidating = false;
      });
      return;
    }

    try {
      final models = await _aiService.fetchAvailableModels(baseUrl, apiKey);
      if (models.isNotEmpty ||
          _selectedProvider == 'ollama' ||
          _selectedProvider == 'local' ||
          _selectedProvider == 'gemini' ||
          apiKey.isNotEmpty) {
        await _aiService.saveSettings(
          apiKey: apiKey,
          baseUrl: baseUrl,
          model: model,
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('onboarding_completed', true);

        if (mounted) {
          setState(() {
            _isValidating = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Configuration saved! Launching CompanAI...',
              ),
            ),
          );

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      } else {
        setState(() {
          _validationError =
              'Failed to fetch models from the server. Verify base URL and API Key.';
          _isValidating = false;
        });
      }
    } catch (e) {
      // If network test failed but user provided key & endpoint, save and allow proceeding
      await _aiService.saveSettings(
        apiKey: apiKey,
        baseUrl: baseUrl,
        model: model,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_completed', true);

      if (mounted) {
        setState(() {
          _isValidating = false;
        });

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    }
  }

  Future<void> _fetchModels() async {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (baseUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an API Base URL first.'),
        ),
      );
      return;
    }

    setState(() {
      _isValidating = true;
    });

    try {
      final models = await _aiService.fetchAvailableModels(baseUrl, apiKey);

      setState(() {
        _isValidating = false;
      });

      if (models.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No models found. Check base URL or API Key.',
              ),
            ),
          );
        }
        return;
      }

      if (mounted) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        showModalBottomSheet(
          context: context,
          backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
          ),
          builder: (context) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AiService.isNvidiaBaseUrl(baseUrl)
                          ? 'Select NVIDIA Model'
                          : 'Select Model',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: models.length,
                        itemBuilder: (context, index) {
                          final modelName = models[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            title: Text(
                              modelName,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.lightTextPrimary,
                              ),
                            ),
                            trailing: Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: isDark
                                  ? AppColors.darkTextMuted
                                  : AppColors.lightTextMuted,
                            ),
                            onTap: () {
                              setState(() {
                                _modelController.text = modelName;
                              });
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }
    } catch (e) {
      setState(() {
        _isValidating = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
          ),
        );
      }
    }
  }

  bool get _canProceedToModel {
    return _isAccessibilityGranted &&
        _isMicrophoneGranted &&
        (!FeatureFlags.floatingOverlayEnabled || _isOverlayGranted);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              // Top Animated Stepper Progress Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
                child: _buildAnimatedStepper(isDark),
              ),

              // Page Content
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (page) {
                    setState(() {
                      _currentStep = page;
                    });
                  },
                  children: [
                    _buildWelcomePage(isDark),
                    _buildPermissionsPage(isDark),
                    _buildModelSetupPage(isDark),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedStepper(bool isDark) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(3, (index) {
            final isActive = _currentStep == index;
            final isCompleted = _currentStep > index;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              height: 5,
              width: isActive
                  ? MediaQuery.of(context).size.width * 0.36
                  : MediaQuery.of(context).size.width * 0.22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.full),
                color: isActive
                    ? (isDark ? AppColors.primary : AppColors.primaryLight)
                    : isCompleted
                        ? (isDark ? AppColors.primary : AppColors.primaryLight)
                            .withValues(alpha: 0.4)
                        : (isDark
                            ? AppColors.darkSurfaceElevated
                            : AppColors.lightBorder),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: (isDark
                                  ? AppColors.primary
                                  : AppColors.primaryLight)
                              .withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
            );
          }),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildStepperLabel(0, 'Welcome', isDark),
            _buildStepperLabel(1, 'Permissions', isDark),
            _buildStepperLabel(2, 'AI Setup', isDark),
          ],
        ),
      ],
    );
  }

  Widget _buildStepperLabel(int index, String text, bool isDark) {
    final isActive = _currentStep == index;
    final isCompleted = _currentStep > index;

    return Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
        color: isActive
            ? (isDark ? AppColors.primary : AppColors.primaryLight)
            : isCompleted
                ? (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)
                : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
      ),
    );
  }

  // --- STEP 1: WELCOME SCREEN ---
  Widget _buildWelcomePage(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 3),
          // Large Glowing Robot Hero Container
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (isDark ? AppColors.primary : AppColors.primaryLight)
                      .withValues(alpha: 0.12),
                ),
              ),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? AppColors.darkSurface : Colors.white,
                  border: Border.all(
                    color: (isDark ? AppColors.primary : AppColors.primaryLight)
                        .withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isDark ? AppColors.primary : AppColors.primaryLight)
                          .withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.smart_toy_rounded,
                  size: 58,
                  color: isDark ? AppColors.primary : AppColors.primaryLight,
                ),
              ),
            ],
          ),
          const Spacer(flex: 2),

          // Title
          Text(
            'CompanAI',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your local, secure personal AI agent. Execute tasks across apps, automate phone actions, and converse with full privacy.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              height: 1.5,
            ),
          ),
          const Spacer(flex: 2),

          // Value propositions
          _buildFeatureTile(
            Icons.lock_outline_rounded,
            'Local & Privacy First',
            'Full support for on-device and local models. Keys stored securely.',
            isDark,
          ),
          const SizedBox(height: 10),
          _buildFeatureTile(
            Icons.touch_app_outlined,
            'Screen Automation',
            'Reads accessibility trees to perform automated taps, scrolls, and inputs.',
            isDark,
          ),

          const Spacer(flex: 3),

          // Get Started CTA
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? AppColors.primary : AppColors.primaryLight,
                foregroundColor: isDark ? const Color(0xFF0A0D14) : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Get Started',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildFeatureTile(
    IconData icon,
    String title,
    String subtitle,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 1.2,
        ),
      ),
      child: Row(
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
              size: 20,
              color: isDark ? AppColors.primary : AppColors.primaryLight,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- STEP 2: PERMISSIONS SCREEN ---
  Widget _buildPermissionsPage(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            'Permissions',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Grant permissions to enable device automation and voice control.',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 16),

          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                _buildSectionHeader('REQUIRED FOR AUTOMATION', isDark),
                _buildPermissionCard(
                  'Screen Control (Accessibility)',
                  'Reads screen state and performs touch & keyboard actions to automate tasks.',
                  Icons.visibility_rounded,
                  _isAccessibilityGranted,
                  _requestAccessibility,
                  isDark,
                ),
                const SizedBox(height: 10),
                _buildPermissionCard(
                  'Microphone',
                  'Listens to your spoken voice commands for hands-free operation.',
                  Icons.mic_rounded,
                  _isMicrophoneGranted,
                  () => _requestPermission(Permission.microphone),
                  isDark,
                ),
                if (FeatureFlags.floatingOverlayEnabled) ...[
                  const SizedBox(height: 10),
                  _buildPermissionCard(
                    'Display Over Other Apps',
                    'Allows floating assistant bubble for background task monitoring.',
                    Icons.layers_rounded,
                    _isOverlayGranted,
                    _requestOverlayPermission,
                    isDark,
                  ),
                ],

                const SizedBox(height: 20),
                _buildSectionHeader('OPTIONAL INTEGRATIONS', isDark),
                _buildPermissionCard(
                  'Notifications',
                  'Shows task completion alerts and background status notifications.',
                  Icons.notifications_rounded,
                  _isNotificationsGranted,
                  () => _requestPermission(Permission.notification),
                  isDark,
                ),
                const SizedBox(height: 10),
                _buildPermissionCard(
                  'Contacts',
                  'Allows agent to look up names when placing phone calls or sending messages.',
                  Icons.contacts_rounded,
                  _isContactsGranted,
                  () => _requestPermission(Permission.contacts),
                  isDark,
                ),
                const SizedBox(height: 10),
                _buildPermissionCard(
                  'Phone',
                  'Allows the agent to place outgoing calls on your command.',
                  Icons.phone_rounded,
                  _isPhoneGranted,
                  () => _requestPermission(Permission.phone),
                  isDark,
                ),
                const SizedBox(height: 10),
                _buildPermissionCard(
                  'SMS',
                  'Allows sending text messages on your behalf.',
                  Icons.sms_rounded,
                  _isSmsGranted,
                  () => _requestPermission(Permission.sms),
                  isDark,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),

          // Bottom Navigation Controls
          Row(
            children: [
              TextButton(
                onPressed: () {
                  _pageController.previousPage(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                  );
                },
                child: const Text(
                  'Back',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _canProceedToModel
                    ? () {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? AppColors.primary : AppColors.primaryLight,
                  foregroundColor: isDark ? const Color(0xFF0A0D14) : Colors.white,
                  disabledBackgroundColor: isDark
                      ? AppColors.darkSurfaceElevated
                      : AppColors.lightBorder,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      _canProceedToModel ? 'Next' : 'Grant Required',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_rounded, size: 16),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4, left: 2),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildPermissionCard(
    String title,
    String description,
    IconData icon,
    bool isGranted,
    VoidCallback onGrant,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(
          color: isGranted
              ? AppColors.successBorder
              : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
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
                  color: isGranted
                      ? AppColors.successContainer
                      : (isDark ? AppColors.primary : AppColors.primaryLight)
                          .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: isGranted
                      ? AppColors.success
                      : (isDark ? AppColors.primary : AppColors.primaryLight),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.lightTextPrimary,
                  ),
                ),
              ),
              if (isGranted)
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.success,
                  size: 22,
                )
              else
                ElevatedButton(
                  onPressed: onGrant,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark
                        ? AppColors.primary
                        : AppColors.primaryLight,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    minimumSize: const Size(0, 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                  ),
                  child: const Text(
                    'Grant',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // --- STEP 3: MODEL SETUP SCREEN ---
  Widget _buildModelSetupPage(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            'Configure AI Model',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Select your AI provider or enter custom OpenAI-compatible endpoint.',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 16),

          // Provider selector horizontal chips
          SizedBox(
            height: 86,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              children: [
                _buildProviderChip('gemini', 'Gemini', Icons.auto_awesome_rounded, isDark),
                const SizedBox(width: 8),
                _buildProviderChip('deepseek', 'DeepSeek', Icons.analytics_outlined, isDark),
                const SizedBox(width: 8),
                _buildProviderChip('groq', 'Groq', Icons.speed_rounded, isDark),
                const SizedBox(width: 8),
                _buildProviderChip('nvidia', 'NVIDIA NIM', Icons.memory_rounded, isDark),
                const SizedBox(width: 8),
                _buildProviderChip('ollama', 'Ollama', Icons.computer_rounded, isDark),
                const SizedBox(width: 8),
                _buildProviderChip('local', 'Local Server', Icons.dns_rounded, isDark),
                const SizedBox(width: 8),
                _buildProviderChip('custom', 'Custom', Icons.tune_rounded, isDark),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                _buildProviderHelperCard(isDark),
                if (_selectedProvider != 'ollama' &&
                    _selectedProvider != 'local') ...[
                  TextField(
                    controller: _apiKeyController,
                    obscureText: _obscureKey,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: _selectedProvider == 'gemini'
                          ? 'AIzaSy... (Gemini API Key)'
                          : 'sk-...',
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
                  const SizedBox(height: 14),
                ],

                TextField(
                  controller: _baseUrlController,
                  decoration: const InputDecoration(
                    labelText: 'API Base URL',
                    hintText: 'https://generativelanguage.googleapis.com/v1beta/openai',
                    prefixIcon: Icon(Icons.dns_rounded, size: 18),
                  ),
                ),
                const SizedBox(height: 14),

                TextField(
                  controller: _modelController,
                  decoration: InputDecoration(
                    labelText: 'Model Name',
                    hintText: 'gemini-2.0-flash',
                    prefixIcon: const Icon(Icons.smart_toy_outlined, size: 18),
                    suffixIcon: IconButton(
                      icon: _isValidating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded, size: 18),
                      tooltip: 'Fetch models list',
                      onPressed: _isValidating ? null : _fetchModels,
                    ),
                  ),
                ),
                _buildQuickModelChips(isDark),

                if (_validationError != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.errorContainer,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      border: Border.all(color: AppColors.errorBorder),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: AppColors.error,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _validationError!,
                            style: const TextStyle(
                              color: AppColors.error,
                              fontSize: 12.5,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),

          // Action Buttons
          Row(
            children: [
              TextButton(
                onPressed: _isValidating
                    ? null
                    : () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                        );
                      },
                child: const Text(
                  'Back',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _isValidating ? null : _testAndSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? AppColors.primary : AppColors.primaryLight,
                  foregroundColor: isDark ? const Color(0xFF0A0D14) : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                ),
                child: _isValidating
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isDark ? const Color(0xFF0A0D14) : Colors.white,
                          ),
                        ),
                      )
                    : const Row(
                        children: [
                          Text(
                            'Finish Setup',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.check_circle_outline_rounded, size: 18),
                        ],
                      ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildProviderChip(
    String id,
    String label,
    IconData icon,
    bool isDark,
  ) {
    final isSelected = _selectedProvider == id;

    return GestureDetector(
      onTap: () => _selectProvider(id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 96,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? AppColors.primary : AppColors.primaryLight)
                  .withValues(alpha: 0.15)
              : (isDark
                  ? AppColors.darkSurfaceElevated
                  : AppColors.lightSurface),
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(
            color: isSelected
                ? (isDark ? AppColors.primary : AppColors.primaryLight)
                : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
            width: isSelected ? 1.8 : 1.2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected
                  ? (isDark ? AppColors.primary : AppColors.primaryLight)
                  : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? (isDark ? AppColors.primary : AppColors.primaryLight)
                    : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderHelperCard(bool isDark) {
    if (_selectedProvider == 'gemini') {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: (isDark ? AppColors.primary : AppColors.primaryLight)
              .withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(
            color: (isDark ? AppColors.primary : AppColors.primaryLight)
                .withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 18,
              color: isDark ? AppColors.primary : AppColors.primaryLight,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Google Gemini (Free tier available at aistudio.google.com)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildQuickModelChips(bool isDark) {
    List<String> models = [];
    if (_selectedProvider == 'gemini') {
      models = [
        'gemini-2.0-flash',
        'gemini-2.0-flash-lite-preview-02-05',
        'gemini-1.5-flash',
        'gemini-1.5-pro',
      ];
    } else if (_selectedProvider == 'deepseek') {
      models = ['deepseek-chat', 'deepseek-reasoner'];
    } else if (_selectedProvider == 'groq') {
      models = ['llama-3.3-70b-versatile', 'mixtral-8x7b-32768'];
    } else if (_selectedProvider == 'nvidia') {
      models = ['z-ai/glm-5.2', 'meta/llama-3.3-70b-instruct'];
    }

    if (models.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: models.map((m) {
          final isCurrent = _modelController.text == m;
          return ChoiceChip(
            label: Text(
              m,
              style: TextStyle(
                fontSize: 11,
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
                ? AppColors.darkSurfaceElevated
                : AppColors.lightSurface,
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
              }
            },
          );
        }).toList(),
      ),
    );
  }
}
