import 'package:dart_tui/dart_tui.dart';

import '../../domain/entities/app_config.dart';
import '../../domain/value_objects/config_values.dart';
import '../app/transcript.dart';

class FrunTheme {
  const FrunTheme({
    required this.textStyle,
    required this.valueStyle,
    required this.titleStyle,
    required this.panelTitleStyle,
    required this.panelSubtitleStyle,
    required this.borderStyle,
    required this.borderStrongStyle,
    required this.inputBorderStyle,
    required this.dimStyle,
    required this.accentStyle,
    required this.errorStyle,
    required this.warnStyle,
    required this.successStyle,
    required this.systemStyle,
    required this.surfaceStyle,
    required this.surfaceMutedStyle,
    required this.selectedRowStyle,
    required this.emptyStyle,
    required this.badgeNeutralStyle,
    required this.badgeInfoStyle,
    required this.badgeErrorStyle,
    required this.badgeWarnStyle,
    required this.badgeSuccessStyle,
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
    required this.pickerChipSelectedStyle,
    required this.pickerEmulatorChipSelectedStyle,
    required this.pickerDeviceChipSelectedStyle,
    required this.linkHighlightStyle,
    required this.selectionStyle,
    required this.visualLineStyle,
    required this.visualBlockStyle,
    required this.searchMatchStyle,
    required this.searchActiveStyle,
    required this.cursorStyle,
    required this.replaceCursorStyle,
  });

  final Style textStyle;
  final Style valueStyle;
  final Style titleStyle;
  final Style panelTitleStyle;
  final Style panelSubtitleStyle;
  final Style borderStyle;
  final Style borderStrongStyle;
  final Style inputBorderStyle;
  final Style dimStyle;
  final Style accentStyle;
  final Style errorStyle;
  final Style warnStyle;
  final Style successStyle;
  final Style systemStyle;
  final Style surfaceStyle;
  final Style surfaceMutedStyle;
  final Style selectedRowStyle;
  final Style emptyStyle;
  final Style badgeNeutralStyle;
  final Style badgeInfoStyle;
  final Style badgeErrorStyle;
  final Style badgeWarnStyle;
  final Style badgeSuccessStyle;
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
  final Style pickerChipSelectedStyle;
  final Style pickerEmulatorChipSelectedStyle;
  final Style pickerDeviceChipSelectedStyle;
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
        return textStyle;
    }
  }

  static FrunTheme dark() => FrunTheme(
    textStyle: const Style().foregroundColor256(252),
    valueStyle: const Style().foregroundColor256(250),
    titleStyle: const Style(isBold: true).foregroundColor256(81),
    panelTitleStyle: const Style(
      isBold: true,
    ).backgroundColor256(238).foregroundColor256(87),
    panelSubtitleStyle: const Style().foregroundColor256(245),
    borderStyle: const Style().foregroundColor256(240),
    borderStrongStyle: const Style().foregroundColor256(244),
    inputBorderStyle: const Style().foregroundColor256(66),
    dimStyle: const Style().foregroundColor256(244),
    accentStyle: const Style(isBold: true).foregroundColor256(81),
    errorStyle: const Style().foregroundColor256(203),
    warnStyle: const Style().foregroundColor256(215),
    successStyle: const Style().foregroundColor256(78),
    systemStyle: const Style(isItalic: true).foregroundColor256(245),
    surfaceStyle: const Style().backgroundColor256(235).foregroundColor256(252),
    surfaceMutedStyle: const Style()
        .backgroundColor256(237)
        .foregroundColor256(250),
    selectedRowStyle: const Style()
        .backgroundColor256(24)
        .foregroundColor256(231),
    emptyStyle: const Style(isItalic: true).foregroundColor256(245),
    badgeNeutralStyle: const Style(
      isBold: true,
    ).backgroundColor256(238).foregroundColor256(252),
    badgeInfoStyle: const Style(
      isBold: true,
    ).backgroundColor256(31).foregroundColor256(231),
    badgeErrorStyle: const Style(
      isBold: true,
    ).backgroundColor256(124).foregroundColor256(231),
    badgeWarnStyle: const Style(
      isBold: true,
    ).backgroundColor256(136).foregroundColor256(16),
    badgeSuccessStyle: const Style(
      isBold: true,
    ).backgroundColor256(29).foregroundColor256(231),
    statusBarStyle: const Style()
        .backgroundColor256(236)
        .foregroundColor256(252),
    promptStyle: const Style(isBold: true).foregroundColor256(87),
    activeTabStyle: const Style(
      isBold: true,
    ).backgroundColor256(30).foregroundColor256(231),
    inactiveTabStyle: const Style()
        .backgroundColor256(236)
        .foregroundColor256(250),
    exitedTabStyle: const Style()
        .backgroundColor256(235)
        .foregroundColor256(244),
    buttonStyle: const Style(
      isBold: true,
    ).backgroundColor256(29).foregroundColor256(231),
    buttonStopStyle: const Style(
      isBold: true,
    ).backgroundColor256(124).foregroundColor256(255),
    pickerChipStyle: const Style(
      isBold: true,
    ).backgroundColor256(238).foregroundColor256(252),
    pickerEmulatorChipStyle: const Style(
      isBold: true,
    ).backgroundColor256(31).foregroundColor256(231),
    pickerDeviceChipStyle: const Style(
      isBold: true,
    ).backgroundColor256(59).foregroundColor256(231),
    pickerChipSelectedStyle: const Style(
      isBold: true,
    ).backgroundColor256(37).foregroundColor256(231),
    pickerEmulatorChipSelectedStyle: const Style(
      isBold: true,
    ).backgroundColor256(39).foregroundColor256(16),
    pickerDeviceChipSelectedStyle: const Style(
      isBold: true,
    ).backgroundColor256(98).foregroundColor256(231),
    linkHighlightStyle: const Style(
      isBold: true,
    ).backgroundColor256(237).foregroundColor256(87),
    selectionStyle: const Style()
        .backgroundColor256(30)
        .foregroundColor256(231),
    visualLineStyle: const Style()
        .backgroundColor256(24)
        .foregroundColor256(231),
    visualBlockStyle: const Style(
      isBold: true,
    ).backgroundColor256(31).foregroundColor256(231),
    searchMatchStyle: const Style()
        .backgroundColor256(238)
        .foregroundColor256(222),
    searchActiveStyle: const Style(
      isBold: true,
    ).backgroundColor256(215).foregroundColor256(16),
    cursorStyle: const Style().backgroundColor256(87).foregroundColor256(16),
    replaceCursorStyle: const Style(
      isBold: true,
    ).backgroundColor256(196).foregroundColor256(231),
  );

  static FrunTheme light() => FrunTheme(
    textStyle: const Style().foregroundColor256(235),
    valueStyle: const Style().foregroundColor256(237),
    titleStyle: const Style(isBold: true).foregroundColor256(25),
    panelTitleStyle: const Style(
      isBold: true,
    ).backgroundColor256(254).foregroundColor256(25),
    panelSubtitleStyle: const Style().foregroundColor256(241),
    borderStyle: const Style().foregroundColor256(247),
    borderStrongStyle: const Style().foregroundColor256(240),
    inputBorderStyle: const Style().foregroundColor256(31),
    dimStyle: const Style().foregroundColor256(241),
    accentStyle: const Style(isBold: true).foregroundColor256(25),
    errorStyle: const Style().foregroundColor256(160),
    warnStyle: const Style().foregroundColor256(130),
    successStyle: const Style().foregroundColor256(28),
    systemStyle: const Style(isItalic: true).foregroundColor256(244),
    surfaceStyle: const Style().backgroundColor256(255).foregroundColor256(235),
    surfaceMutedStyle: const Style()
        .backgroundColor256(253)
        .foregroundColor256(236),
    selectedRowStyle: const Style()
        .backgroundColor256(153)
        .foregroundColor256(16),
    emptyStyle: const Style(isItalic: true).foregroundColor256(244),
    badgeNeutralStyle: const Style(
      isBold: true,
    ).backgroundColor256(252).foregroundColor256(235),
    badgeInfoStyle: const Style(
      isBold: true,
    ).backgroundColor256(31).foregroundColor256(231),
    badgeErrorStyle: const Style(
      isBold: true,
    ).backgroundColor256(160).foregroundColor256(231),
    badgeWarnStyle: const Style(
      isBold: true,
    ).backgroundColor256(178).foregroundColor256(16),
    badgeSuccessStyle: const Style(
      isBold: true,
    ).backgroundColor256(34).foregroundColor256(231),
    statusBarStyle: const Style()
        .backgroundColor256(254)
        .foregroundColor256(235),
    promptStyle: const Style(isBold: true).foregroundColor256(27),
    activeTabStyle: const Style(
      isBold: true,
    ).backgroundColor256(27).foregroundColor256(231),
    inactiveTabStyle: const Style()
        .backgroundColor256(253)
        .foregroundColor256(235),
    exitedTabStyle: const Style()
        .backgroundColor256(253)
        .foregroundColor256(244),
    buttonStyle: const Style(
      isBold: true,
    ).backgroundColor256(34).foregroundColor256(231),
    buttonStopStyle: const Style(
      isBold: true,
    ).backgroundColor256(160).foregroundColor256(231),
    pickerChipStyle: const Style(
      isBold: true,
    ).backgroundColor256(252).foregroundColor256(235),
    pickerEmulatorChipStyle: const Style(
      isBold: true,
    ).backgroundColor256(31).foregroundColor256(231),
    pickerDeviceChipStyle: const Style(
      isBold: true,
    ).backgroundColor256(61).foregroundColor256(231),
    pickerChipSelectedStyle: const Style(
      isBold: true,
    ).backgroundColor256(34).foregroundColor256(255),
    pickerEmulatorChipSelectedStyle: const Style(
      isBold: true,
    ).backgroundColor256(33).foregroundColor256(255),
    pickerDeviceChipSelectedStyle: const Style(
      isBold: true,
    ).backgroundColor256(93).foregroundColor256(255),
    linkHighlightStyle: const Style(
      isBold: true,
    ).backgroundColor256(229).foregroundColor256(94),
    selectionStyle: const Style()
        .backgroundColor256(153)
        .foregroundColor256(16),
    visualLineStyle: const Style()
        .backgroundColor256(189)
        .foregroundColor256(16),
    visualBlockStyle: const Style(
      isBold: true,
    ).backgroundColor256(117).foregroundColor256(16),
    searchMatchStyle: const Style()
        .backgroundColor256(220)
        .foregroundColor256(16),
    searchActiveStyle: const Style(
      isBold: true,
    ).backgroundColor256(208).foregroundColor256(16),
    cursorStyle: const Style().backgroundColor256(238).foregroundColor256(231),
    replaceCursorStyle: const Style(
      isBold: true,
    ).backgroundColor256(160).foregroundColor256(231),
  );

  static FrunTheme fromConfig(AppConfigEntity config) =>
      config.theme == FrunThemeMode.dark ? dark() : light();
}
