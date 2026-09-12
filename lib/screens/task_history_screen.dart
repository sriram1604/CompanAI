import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/task_history_logger.dart';
import '../theme/app_theme.dart';
import '../widgets/ambient_background.dart';
import '../widgets/app_status_badge.dart';

class TaskHistoryScreen extends StatefulWidget {
  const TaskHistoryScreen({super.key});

  @override
  State<TaskHistoryScreen> createState() => _TaskHistoryScreenState();
}

class _TaskHistoryScreenState extends State<TaskHistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  Map<String, dynamic>? _analytics;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final history = await TaskHistoryLogger.readHistory();
    final analytics = await TaskHistoryLogger.getAnalytics();
    setState(() {
      _history = history;
      _analytics = analytics;
      _isLoading = false;
    });
  }

  Future<void> _clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Task History'),
        content: const Text(
          'Are you sure you want to permanently delete all task history and logs?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await TaskHistoryLogger.clearHistory();
      _loadHistory();
    }
  }

  AppBadgeStatus _getBadgeStatus(String status) {
    switch (status.toLowerCase()) {
      case 'success':
        return AppBadgeStatus.success;
      case 'failed':
        return AppBadgeStatus.error;
      case 'cancelled':
        return AppBadgeStatus.warning;
      default:
        return AppBadgeStatus.info;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'success':
        return Icons.check_circle_rounded;
      case 'failed':
        return Icons.cancel_rounded;
      case 'cancelled':
        return Icons.stop_circle_rounded;
      default:
        return Icons.info_rounded;
    }
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
            'Task History (${_history.length})',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            ),
          ),
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Clear History',
              onPressed: _history.isEmpty ? null : _clearHistory,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _history.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.history_toggle_off_rounded,
                          size: 48,
                          color: isDark
                              ? AppColors.darkTextMuted
                              : AppColors.lightTextMuted,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No task history found.',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      // Analytics Metrics Bar
                      if (_analytics != null && _analytics!['totalTasks'] > 0)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: _buildStatTile(
                                  'Total',
                                  _analytics!['totalTasks'].toString(),
                                  null,
                                  isDark,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildStatTile(
                                  'Success',
                                  _analytics!['successCount'].toString(),
                                  AppColors.success,
                                  isDark,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildStatTile(
                                  'Failed',
                                  _analytics!['failedCount'].toString(),
                                  AppColors.error,
                                  isDark,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildStatTile(
                                  'Rate',
                                  '${(_analytics!['successRate'] * 100).toStringAsFixed(0)}%',
                                  (isDark ? AppColors.secondary : AppColors.primaryLight),
                                  isDark,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // History List
                      Expanded(
                        child: ListView.builder(
                          itemCount: _history.length,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          physics: const BouncingScrollPhysics(),
                          itemBuilder: (context, index) {
                            final task = _history[index];
                            final date =
                                DateTime.tryParse(task['timestamp'] ?? '');
                            final dateStr = date != null
                                ? DateFormat('MMM d, y • h:mm a').format(date)
                                : 'Unknown Date';
                            final status =
                                task['status'] as String? ?? 'Unknown';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.darkSurfaceElevated
                                    : AppColors.lightSurface,
                                borderRadius: BorderRadius.circular(AppRadii.lg),
                                border: Border.all(
                                  color: isDark
                                      ? AppColors.darkBorder
                                      : AppColors.lightBorder,
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: isDark ? 0.12 : 0.02,
                                    ),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Theme(
                                data: Theme.of(context).copyWith(
                                  dividerColor: Colors.transparent,
                                ),
                                child: ExpansionTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: _getBadgeStatus(status) ==
                                              AppBadgeStatus.success
                                          ? AppColors.successContainer
                                          : _getBadgeStatus(status) ==
                                                  AppBadgeStatus.error
                                              ? AppColors.errorContainer
                                              : AppColors.warningContainer,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _getStatusIcon(status),
                                      color: _getBadgeStatus(status) ==
                                              AppBadgeStatus.success
                                          ? AppColors.success
                                          : _getBadgeStatus(status) ==
                                                  AppBadgeStatus.error
                                              ? AppColors.error
                                              : AppColors.warning,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    task['goal'] ?? 'Unknown Goal',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: isDark
                                          ? AppColors.darkTextPrimary
                                          : AppColors.lightTextPrimary,
                                    ),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Row(
                                      children: [
                                        Text(
                                          dateStr,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: isDark
                                                ? AppColors.darkTextMuted
                                                : AppColors.lightTextMuted,
                                          ),
                                        ),
                                        const Spacer(),
                                        // Provider Badge (Local vs Cloud)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: (task['provider'] == 'Local Navigation')
                                                ? (isDark ? AppColors.success.withValues(alpha: 0.2) : AppColors.successContainer)
                                                : (isDark
                                                    ? AppColors.darkSurface
                                                    : AppColors.lightSurfaceHighlight),
                                            borderRadius:
                                                BorderRadius.circular(AppRadii.sm),
                                            border: Border.all(
                                              color: (task['provider'] == 'Local Navigation')
                                                  ? AppColors.success.withValues(alpha: 0.4)
                                                  : (isDark
                                                      ? AppColors.darkBorder
                                                      : AppColors.lightBorder),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                (task['provider'] == 'Local Navigation')
                                                    ? Icons.offline_bolt_rounded
                                                    : Icons.cloud_outlined,
                                                size: 11,
                                                color: (task['provider'] == 'Local Navigation')
                                                    ? AppColors.success
                                                    : (isDark
                                                        ? AppColors.darkTextSecondary
                                                        : AppColors.lightTextSecondary),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                (task['provider'] == 'Local Navigation')
                                                    ? 'Local AI (0 tokens)'
                                                    : '${task['total_tokens'] ?? 0} tokens',
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: (task['provider'] == 'Local Navigation')
                                                      ? AppColors.success
                                                      : (isDark
                                                          ? AppColors.darkTextSecondary
                                                          : AppColors.lightTextSecondary),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        0,
                                        16,
                                        16,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          const Divider(height: 16),
                                          Row(
                                            children: [
                                              AppStatusBadge(
                                                label: status,
                                                status: _getBadgeStatus(status),
                                                icon: _getStatusIcon(status),
                                              ),
                                              const SizedBox(width: 12),
                                              Text(
                                                'Steps: ${task['steps_taken'] ?? 0}',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12.5,
                                                  color: isDark
                                                      ? AppColors.darkTextSecondary
                                                      : AppColors.lightTextSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 14),
                                          Text(
                                            'EXECUTION TRACE',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 10.5,
                                              letterSpacing: 1.2,
                                              color: isDark
                                                  ? AppColors.darkTextMuted
                                                  : AppColors.lightTextMuted,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          ...((task['trace'] as List<dynamic>?) ??
                                                  [])
                                              .map(
                                            (t) => Container(
                                              margin:
                                                  const EdgeInsets.only(bottom: 6),
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? AppColors.darkBackground
                                                    : AppColors.lightSurfaceHighlight,
                                                borderRadius:
                                                    BorderRadius.circular(AppRadii.sm),
                                                border: Border.all(
                                                  color: isDark
                                                      ? AppColors.darkBorder
                                                      : AppColors.lightBorder,
                                                  width: 1,
                                                ),
                                              ),
                                              child: Text(
                                                '• $t',
                                                style: TextStyle(
                                                  fontFamily: 'monospace',
                                                  fontSize: 12,
                                                  color: isDark
                                                      ? AppColors.darkTextSecondary
                                                      : AppColors.lightTextSecondary,
                                                  height: 1.4,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildStatTile(
    String label,
    String value,
    Color? color,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
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
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color ??
                  (isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
