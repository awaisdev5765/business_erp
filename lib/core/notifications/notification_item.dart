import 'package:flutter/material.dart';

/// A purely client-computed, in-app notification — see
/// `notificationCenterProvider`. Not persisted: recomputed fresh from
/// existing data (low stock, pending approvals, sync failures,
/// conflicts) every time the bell is opened, so there's nothing to mark
/// read/unread or keep in sync across devices. This is the "in-app
/// notification" alternative to push (FCM tokens are registered but
/// nothing ever sends through them — that needs Cloud Functions, which
/// the free Spark plan excludes).
class NotificationItem {
  const NotificationItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.navIndexHint,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  /// Which AppShell nav section this notification is "about" — used to
  /// jump there on tap. A label, not an index, since the actual index
  /// depends on the signed-in role's filtered destination list.
  final String navIndexHint;
}
