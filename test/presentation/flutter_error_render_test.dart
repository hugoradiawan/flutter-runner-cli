import 'package:frun/src/presentation/app/flutter_error_renderer.dart';
import 'package:test/test.dart';

/// A trimmed `Flutter.Error` payload shaped like the real one: the summary and
/// the error-causing widget live under `properties`, and the stack frames live
/// under a `DiagnosticsStackTrace` node's `properties` (not `children`).
Map<String, dynamic> _payload() => {
  'description': 'Exception caught by widgets library',
  'library': 'widgets library',
  'properties': [
    {
      'description':
          'The following assertion was thrown building ObxValue<RxBool>:',
      'type': 'ErrorDescription',
    },
    {
      'description': 'A VideoPlayerController was used after being disposed.',
      'type': 'ErrorSummary',
      'level': 'summary',
    },
    {'description': '', 'type': 'ErrorSpacer'},
    {
      'name': 'The relevant error-causing widget was',
      'type': 'DiagnosticsBlock',
      'children': [
        {
          'description':
              'ObxValue<RxBool> ObxValue:file:///C:/proj/lib/shared/ui/video/video.dart:145:7',
          'type': 'ErrorDescription',
        },
      ],
    },
    {
      'name': 'When the exception was thrown, this was the stack',
      'type': 'DiagnosticsStackTrace',
      'properties': [
        {
          'description':
              '#0      ChangeNotifier.debugAssertNotDisposed (package:flutter/src/foundation/change_notifier.dart:182:9)',
          'type': 'DiagnosticsProperty<void>',
        },
        {
          'description':
              '#1      ChangeNotifier.addListener (package:flutter/src/foundation/change_notifier.dart:271:27)',
          'type': 'DiagnosticsProperty<void>',
        },
        {
          'description':
              '#2      _VideoPlayerState.didUpdateWidget (package:video_player/video_player.dart:891:23)',
          'type': 'DiagnosticsProperty<void>',
        },
        {
          'description':
              '#3      StatefulElement.update (package:flutter/src/widgets/framework.dart:5893:55)',
          'type': 'DiagnosticsProperty<void>',
        },
      ],
    },
  ],
};

void main() {
  group('renderFlutterError', () {
    test('compact render: summary, widget file:line, trimmed stack', () {
      final out = renderFlutterError(_payload(), projectRoot: r'C:\proj');

      // Headline summary present.
      expect(
        out,
        contains('A VideoPlayerController was used after being disposed.'),
      );
      // Context line preserved.
      expect(out, contains('building ObxValue<RxBool>'));
      // Widget location resolved + made relative + forward-slashed (clickable).
      expect(out, contains('widget: lib/shared/ui/video/video.dart:145:7'));
      // The one user/plugin frame is kept.
      expect(out, contains('package:video_player/video_player.dart:891:23'));
      // Framework frames collapsed, not printed verbatim.
      expect(out, contains('framework frames hidden'));
      expect(out, isNot(contains('change_notifier.dart:182:9')));
      // No raw dump in the compact path.
      expect(out, isNot(contains('raw Flutter.Error payload')));
    });

    test('verbose render appends the raw JSON payload', () {
      final out = renderFlutterError(
        _payload(),
        verbose: true,
        projectRoot: r'C:\proj',
      );
      expect(out, contains('raw Flutter.Error payload (verbose_errors)'));
      expect(out, contains('"library"'));
      // Compact section still rendered above the dump.
      expect(
        out,
        contains('A VideoPlayerController was used after being disposed.'),
      );
    });

    test('unknown-shape payload falls back to a raw dump', () {
      final out = renderFlutterError({'library': 'something', 'mystery': 42});
      expect(out, contains('raw Flutter.Error payload (nothing extracted)'));
      expect(out, contains('"mystery"'));
    });
  });
}
