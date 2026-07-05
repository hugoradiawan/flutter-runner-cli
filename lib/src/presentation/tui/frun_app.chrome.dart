part of 'frun_app.dart';

String _clipCellText(String text, int maxWidth) {
  if (maxWidth <= 0) return '';
  if (text.length <= maxWidth) return text;
  if (maxWidth == 1) return text.substring(0, 1);
  return '${text.substring(0, maxWidth - 1)}.';
}

String _badgeText(String label) => ' $label ';

int _badgeWidth(String label) => _badgeText(label).length;

Style _badgeStyleForCategory(FrunTheme theme, DiagnosticCategory category) {
  return switch (category) {
    DiagnosticCategory.error => theme.badgeErrorStyle,
    DiagnosticCategory.warning => theme.badgeWarnStyle,
    DiagnosticCategory.info => theme.badgeInfoStyle,
    DiagnosticCategory.todo => theme.badgeSuccessStyle,
  };
}

int _paintBadge(
  CellCanvas canvas,
  FrunTheme theme,
  int x,
  int y,
  String label,
  Style style, {
  HitRegions? hits,
  Msg? msg,
  int zIndex = 0,
}) {
  final text = _badgeText(label);
  canvas.paint(x, y, text, style: style, zIndex: zIndex);
  if (hits != null && msg != null) {
    hits.add(x: x, y: y, w: text.length, h: 1, msg: msg);
  }
  return x + text.length + 1;
}

int _paintHeaderAction(
  CellCanvas canvas,
  FrunTheme theme,
  HitRegions hits,
  int x,
  int y,
  String label,
  Msg msg, {
  bool danger = false,
}) {
  return _paintBadge(
    canvas,
    theme,
    x,
    y,
    label,
    danger ? theme.buttonStopStyle : theme.buttonStyle,
    hits: hits,
    msg: msg,
  );
}

int _paintPanelTitle(
  CellCanvas canvas,
  FrunTheme theme,
  int x,
  int y,
  String title, {
  String? meta,
  int? maxWidth,
}) {
  final label = meta == null || meta.isEmpty ? title : '$title  $meta';
  final innerMax = maxWidth == null ? null : math.max(0, maxWidth - 2);
  final clipped = innerMax == null ? label : _clipCellText(label, innerMax);
  canvas.paint(x, y, _badgeText(clipped), style: theme.panelTitleStyle);
  return x + _badgeWidth(clipped) + 1;
}

void _paintPanelFrame(
  CellCanvas canvas,
  FrunTheme theme,
  int width,
  int y,
  int height, {
  bool strong = false,
}) {
  if (height < 2 || width < 2) return;
  final style = strong ? theme.borderStrongStyle : theme.borderStyle;
  final horizontal = '─' * (width - 2);
  final bottomY = y + height - 1;
  canvas.paint(0, y, '╭$horizontal╮', style: style);
  canvas.paint(0, bottomY, '╰$horizontal╯', style: style);
  for (var row = y + 1; row < bottomY; row++) {
    canvas.paint(0, row, '│', style: style);
    canvas.paint(width - 1, row, '│', style: style);
  }
}

void _paintDivider(
  CellCanvas canvas,
  FrunTheme theme,
  int width,
  int y, {
  String? title,
}) {
  if (width <= 0) return;
  final text = '─' * width;
  canvas.paint(0, y, text, style: theme.borderStrongStyle);
  if (title != null && title.isNotEmpty && width > title.length + 4) {
    canvas.paint(2, y, _badgeText(title), style: theme.panelTitleStyle);
  }
}

void _paintSelectedRow(
  CellCanvas canvas,
  FrunTheme theme,
  int x,
  int y,
  int width,
) {
  if (width <= 0) return;
  canvas.paint(x, y, ' ' * width, style: theme.selectedRowStyle, zIndex: 0);
}
