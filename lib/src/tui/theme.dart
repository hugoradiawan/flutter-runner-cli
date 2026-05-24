import 'package:dart_tui/dart_tui.dart';

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
    required this.activeTabStyle,
    required this.inactiveTabStyle,
    required this.exitedTabStyle,
    required this.buttonStyle,
    required this.buttonStopStyle,
    required this.pickerChipStyle,
    required this.pickerEmulatorChipStyle,
    required this.pickerDeviceChipStyle,
    required this.linkHighlightStyle,
    required this.selectionStyle,
    required this.visualLineStyle,
    required this.visualBlockStyle,
    required this.searchMatchStyle,
    required this.searchActiveStyle,
    required this.cursorStyle,
    required this.replaceCursorStyle,
  });

  final Style titleStyle;
  final Style borderStyle;
  final Style dimStyle;
  final Style accentStyle;
  final Style errorStyle;
  final Style warnStyle;
  final Style successStyle;
  final Style systemStyle;
  final Style statusBarStyle;
  final Style promptStyle;
  final Style activeTabStyle;
  final Style inactiveTabStyle;
  final Style exitedTabStyle;
  final Style buttonStyle;
  final Style buttonStopStyle;
  final Style pickerChipStyle;
  final Style pickerEmulatorChipStyle;
  final Style pickerDeviceChipStyle;
  final Style linkHighlightStyle;
  final Style selectionStyle;
  final Style visualLineStyle;
  final Style visualBlockStyle;
  final Style searchMatchStyle;
  final Style searchActiveStyle;
  final Style cursorStyle;
  final Style replaceCursorStyle;

  Style forLevel(TranscriptLevel level) {
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
        return const Style();
    }
  }

  static FrunTheme dark() => FrunTheme(
        titleStyle: const Style(isBold: true).foregroundColor256(39),
        borderStyle: const Style().foregroundColor256(244),
        dimStyle: const Style().foregroundColor256(244),
        accentStyle: const Style(isBold: true).foregroundColor256(39),
        errorStyle: const Style().foregroundColor256(196),
        warnStyle: const Style().foregroundColor256(214),
        successStyle: const Style().foregroundColor256(42),
        systemStyle: const Style(isItalic: true).foregroundColor256(245),
        statusBarStyle:
            const Style().backgroundColor256(238).foregroundColor256(252),
        promptStyle: const Style(isBold: true).foregroundColor256(39),
        activeTabStyle: const Style(isBold: true)
            .backgroundColor256(24)
            .foregroundColor256(230),
        inactiveTabStyle:
            const Style().backgroundColor256(235).foregroundColor256(250),
        exitedTabStyle:
            const Style().backgroundColor256(235).foregroundColor256(244),
        buttonStyle: const Style(isBold: true)
            .backgroundColor256(28)
            .foregroundColor256(255),
        buttonStopStyle: const Style(isBold: true)
            .backgroundColor256(124)
            .foregroundColor256(255),
        pickerChipStyle: const Style(isBold: true)
            .backgroundColor256(22)
            .foregroundColor256(231),
        pickerEmulatorChipStyle: const Style(isBold: true)
            .backgroundColor256(25)
            .foregroundColor256(231),
        pickerDeviceChipStyle: const Style(isBold: true)
            .backgroundColor256(53)
            .foregroundColor256(231),
        linkHighlightStyle: const Style(isBold: true)
            .backgroundColor256(240)
            .foregroundColor256(226),
        selectionStyle: const Style()
            .backgroundColor256(60)
            .foregroundColor256(231),
        visualLineStyle: const Style()
            .backgroundColor256(54)
            .foregroundColor256(231),
        visualBlockStyle: const Style(isBold: true)
            .backgroundColor256(63)
            .foregroundColor256(231),
        searchMatchStyle: const Style()
            .backgroundColor256(94)
            .foregroundColor256(231),
        searchActiveStyle: const Style(isBold: true)
            .backgroundColor256(208)
            .foregroundColor256(16),
        cursorStyle:
            const Style().backgroundColor256(244).foregroundColor256(16),
        replaceCursorStyle: const Style(isBold: true)
            .backgroundColor256(196)
            .foregroundColor256(231),
      );

  static FrunTheme light() => FrunTheme(
        titleStyle: const Style(isBold: true).foregroundColor256(27),
        borderStyle: const Style().foregroundColor256(240),
        dimStyle: const Style().foregroundColor256(240),
        accentStyle: const Style(isBold: true).foregroundColor256(27),
        errorStyle: const Style().foregroundColor256(160),
        warnStyle: const Style().foregroundColor256(130),
        successStyle: const Style().foregroundColor256(28),
        systemStyle: const Style(isItalic: true).foregroundColor256(244),
        statusBarStyle:
            const Style().backgroundColor256(254).foregroundColor256(235),
        promptStyle: const Style(isBold: true).foregroundColor256(27),
        activeTabStyle: const Style(isBold: true)
            .backgroundColor256(27)
            .foregroundColor256(231),
        inactiveTabStyle:
            const Style().backgroundColor256(252).foregroundColor256(235),
        exitedTabStyle:
            const Style().backgroundColor256(252).foregroundColor256(244),
        buttonStyle: const Style(isBold: true)
            .backgroundColor256(34)
            .foregroundColor256(231),
        buttonStopStyle: const Style(isBold: true)
            .backgroundColor256(160)
            .foregroundColor256(231),
        pickerChipStyle: const Style(isBold: true)
            .backgroundColor256(22)
            .foregroundColor256(231),
        pickerEmulatorChipStyle: const Style(isBold: true)
            .backgroundColor256(24)
            .foregroundColor256(231),
        pickerDeviceChipStyle: const Style(isBold: true)
            .backgroundColor256(91)
            .foregroundColor256(231),
        linkHighlightStyle: const Style(isBold: true)
            .backgroundColor256(229)
            .foregroundColor256(94),
        selectionStyle: const Style()
            .backgroundColor256(153)
            .foregroundColor256(16),
        visualLineStyle: const Style()
            .backgroundColor256(189)
            .foregroundColor256(16),
        visualBlockStyle: const Style(isBold: true)
            .backgroundColor256(117)
            .foregroundColor256(16),
        searchMatchStyle: const Style()
            .backgroundColor256(220)
            .foregroundColor256(16),
        searchActiveStyle: const Style(isBold: true)
            .backgroundColor256(208)
            .foregroundColor256(16),
        cursorStyle:
            const Style().backgroundColor256(238).foregroundColor256(231),
        replaceCursorStyle: const Style(isBold: true)
            .backgroundColor256(160)
            .foregroundColor256(231),
      );

  static FrunTheme fromConfig(FrunConfig config) =>
      config.theme == FrunThemeMode.dark ? dark() : light();
}
