import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Client-side FCM registration only. **Without Cloud Functions (free
/// Spark plan — see PHASES.md Phase 5), nothing in this app automatically
/// *sends* a push.** A device's token gets registered and foreground
/// messages get displayed if something sends one, but the "something" is
/// either:
/// - a human composing a message by hand in the Firebase Console
///   (Cloud Messaging > Compose notification), or
/// - a future server you control calling the FCM HTTP v1 API directly
///   (outside this app, needs a service account — not a Function, but
///   still infrastructure this app alone doesn't have), or
/// - upgrading to the Blaze plan and adding a Cloud Function trigger
///   later (e.g. "notify the Manager when a Sale needs approval" —
///   PHASES.md Phase 6's Approval Workflow is the natural trigger point
///   if/when that happens).
///
/// This class exists so the client half is ready the moment any of those
/// becomes true, rather than needing app updates later.
class FcmService {
  FcmService(this.messaging, this.firestore);

  final FirebaseMessaging messaging;
  final FirebaseFirestore firestore;

  /// Requests notification permission and, if granted, saves the
  /// device's FCM token to `/users/{uid}` so a future sender (manual or
  /// automated) knows where to deliver to. Safe to call on every app
  /// start — `set` with merge just keeps the token current.
  Future<void> registerToken(String uid) async {
    final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await messaging.getToken();
    if (token == null) return;

    await firestore.collection('users').doc(uid).set({'fcmToken': token}, SetOptions(merge: true));

    // Token can rotate (app reinstall, OS-level changes) — keep it current.
    messaging.onTokenRefresh.listen((newToken) {
      firestore.collection('users').doc(uid).set({'fcmToken': newToken}, SetOptions(merge: true));
    });
  }
}

/// Must be a top-level function (not a class method) — this is the
/// contract FirebaseMessaging.onBackgroundMessage requires, since it
/// runs in a separate isolate when the app is backgrounded/terminated.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Intentionally empty: FCM already displays the system notification
  // for a message with a `notification` payload without any app code
  // running. This handler only matters for *data-only* messages needing
  // custom background processing, which nothing in this app sends yet.
}
