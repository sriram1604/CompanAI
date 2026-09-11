import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/chat_message.dart';
import '../theme/app_theme.dart';
import 'app_status_badge.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        margin: EdgeInsets.only(
          left: isUser ? 48 : 8,
          right: isUser ? 8 : 48,
          top: 6,
          bottom: 6,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser
              ? (isDark ? AppColors.primary : AppColors.primaryLight)
              : (isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurface),
          gradient: isUser
              ? LinearGradient(
                  colors: isDark
                      ? [
                          AppColors.primary,
                          const Color(0xFFF59E0B), // Electric Yellow to Amber Gold
                        ]
                      : [
                          AppColors.primaryLight,
                          const Color(0xFFB45309), // Rich Amber for light theme
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppRadii.lg),
            topRight: const Radius.circular(AppRadii.lg),
            bottomLeft: Radius.circular(isUser ? AppRadii.lg : AppRadii.xs),
            bottomRight: Radius.circular(isUser ? AppRadii.xs : AppRadii.lg),
          ),
          border: isUser
              ? null
              : Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  width: 1.2,
                ),
          boxShadow: [
            BoxShadow(
              color: isUser
                  ? (isDark ? AppColors.primary : AppColors.primaryLight)
                      .withValues(alpha: isDark ? 0.25 : 0.15)
                  : Colors.black.withValues(alpha: isDark ? 0.18 : 0.03),
              blurRadius: isUser ? 12 : 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Action Result Badge if available
            if (message.actionResult != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppStatusBadge(
                  label: message.actionResult!.actionType.replaceAll('_', ' '),
                  status: message.actionResult!.success
                      ? AppBadgeStatus.success
                      : AppBadgeStatus.error,
                  icon: message.actionResult!.success
                      ? Icons.check_circle_rounded
                      : Icons.error_rounded,
                ),
              ),
            ],

            // Message Content
            if (isUser)
              SelectableText(
                message.content,
                style: TextStyle(
                  color: isDark ? const Color(0xFF0A0D14) : Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                  letterSpacing: 0.1,
                ),
              )
            else
              MarkdownBody(
                data: message.content,
                selectable: true,
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  p: TextStyle(
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.lightTextPrimary,
                    fontSize: 14.5,
                    height: 1.5,
                  ),
                  strong: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.w800,
                  ),
                  code: TextStyle(
                    color: isDark ? AppColors.primary : AppColors.primaryLight,
                    backgroundColor: isDark
                        ? AppColors.darkBackground.withValues(alpha: 0.6)
                        : AppColors.lightSurfaceHighlight,
                    fontSize: 13,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkBackground
                        : AppColors.lightSurfaceHighlight,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    border: Border.all(
                      color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                      width: 1,
                    ),
                  ),
                  codeblockPadding: const EdgeInsets.all(12),
                  blockquoteDecoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: isDark ? AppColors.primary : AppColors.primaryLight,
                        width: 3,
                      ),
                    ),
                  ),
                  listBullet: TextStyle(
                    color: isDark
                        ? AppColors.primary
                        : AppColors.primaryLight,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

            // Timestamp
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                _formatTime(message.timestamp),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: isUser
                      ? (isDark
                          ? const Color(0xFF0A0D14).withValues(alpha: 0.7)
                          : Colors.white.withValues(alpha: 0.8))
                      : (isDark
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
