import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// Support WhatsApp — client can tap and chat directly.
const kSupportWhatsAppE164 = '923312544969';
const kSupportWhatsAppDisplay = '+92 331 2544969';

Future<void> openSupportWhatsApp() async {
  final uri = Uri.parse('https://wa.me/$kSupportWhatsAppE164');
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) {
    await launchUrl(uri, mode: LaunchMode.platformDefault);
  }
}

class WhatsAppSupportButton extends StatelessWidget {
  const WhatsAppSupportButton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        tooltip: 'WhatsApp Support',
        onPressed: openSupportWhatsApp,
        icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
      );
    }
    return Tooltip(
      message: 'WhatsApp $kSupportWhatsAppDisplay',
      child: Material(
        color: const Color(0xFF25D366),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: openSupportWhatsApp,
          borderRadius: BorderRadius.circular(20),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat, color: Colors.white, size: 16),
                SizedBox(width: 6),
                Text(
                  'WhatsApp',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WhatsAppSupportFab extends StatelessWidget {
  const WhatsAppSupportFab({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      heroTag: 'whatsapp_support',
      backgroundColor: const Color(0xFF25D366),
      foregroundColor: Colors.white,
      tooltip: 'WhatsApp Support $kSupportWhatsAppDisplay',
      onPressed: openSupportWhatsApp,
      child: const Icon(Icons.chat),
    );
  }
}

/// Thin green support strip — used under mobile AppBars so support is
/// always one tap away without fighting nested page AppBars.
class WhatsAppSupportBar extends StatelessWidget {
  const WhatsAppSupportBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF128C7E),
      child: InkWell(
        onTap: openSupportWhatsApp,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.chat, color: Colors.white, size: 18),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(
                  child: Text(
                    'Support WhatsApp — $kSupportWhatsAppDisplay',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                Text(
                  'Chat',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
