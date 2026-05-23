import 'package:utopia_tui/utopia_tui.dart';

import '../app/transcript.dart';
import '../config/config.dart';

class FrunTheme {
  const FrunTheme({
    required this.titleStyle,
    required this.borderStyle,
    required this.dimStyle,
    required this.accentStyle,
    required this.errorStyle,
    required this.warnStyle,
    required this.successStyle,
    required this.systemStyle,
    required this.statusBarStyle,
    required this.promptStyle,
  });

  final TuiStyle titleStyle;
  final TuiStyle borderStyle;
  final TuiStyle dimStyle;
  final TuiStyle accentStyle;
  final TuiStyle errorStyle;
  final TuiStyle warnStyle;
  final TuiStyle successStyle;
  final TuiStyle systemStyle;
  final TuiStyle statusBarStyle;
  final TuiStyle promptStyle;

  TuiStyle forLevel(TranscriptLevel level) {
    switch (level) {
      case TranscriptLevel.error:
        return errorStyle;
      case TranscriptLevel.warn:
        return warnStyle;
      case TranscriptLevel.success:
        return successStyle;
      case TranscriptLevel.system:
        return systemStyle;
      case TranscriptLevel.debug:
        return dimStyle;
      case TranscriptLevel.info:
        return const TuiStyle();
    }
  }

  static FrunTheme dark() => const FrunTheme(
    titleStyle: TuiStyle(bold: true, fg: 39),
    borderStyle: TuiStyle(fg: 244),
    dimStyle: TuiStyle(fg: 244),
    accentStyle: TuiStyle(bold: true, fg: 39),
    errorStyle: TuiStyle(fg: 196),
    warnStyle: TuiStyle(fg: 214),
    successStyle: TuiStyle(fg: 42),
    systemStyle: TuiStyle(fg: 245, italic: true),
    statusBarStyle: TuiStyle(bg: 238, fg: 252),
    promptStyle: TuiStyle(bold: true, fg: 39),
  );

  static FrunTheme light() => const FrunTheme(
    titleStyle: TuiStyle(bold: true, fg: 27),
    borderStyle: TuiStyle(fg: 240),
    dimStyle: TuiStyle(fg: 240),
    accentStyle: TuiStyle(bold: true, fg: 27),
    errorStyle: TuiStyle(fg: 160),
    warnStyle: TuiStyle(fg: 130),
    successStyle: TuiStyle(fg: 28),
    systemStyle: TuiStyle(fg: 244, italic: true),
    statusBarStyle: TuiStyle(bg: 254, fg: 235),
    promptStyle: TuiStyle(bold: true, fg: 27),
  );

  static FrunTheme fromConfig(FrunConfig config) =>
      config.theme == FrunThemeMode.dark ? dark() : light();
}
