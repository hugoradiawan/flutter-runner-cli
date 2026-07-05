import '../value_objects/notification_event.dart';

/// Fire-and-forget desktop notifications for app-lifecycle events.
abstract class Notifier {
  const Notifier();

  /// Show a notification for [event]. [label] scopes the title
  /// ('frun · <label>'); [detail] overrides the event's default body.
  void notify(FrunNotifEvent event, {String? label, String? detail});
}
