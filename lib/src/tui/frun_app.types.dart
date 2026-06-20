part of 'frun_app.dart';

// ─── Shared layout/render value types ──────────────────────────────────────

class _VisibleLink {
  _VisibleLink(this.transcriptLineIndex, this.link, this.visStart, this.visEnd);
  final int transcriptLineIndex;
  final TranscriptLink link;

  /// The link's [TranscriptLink.start]/[TranscriptLink.end] raw offsets mapped
  /// into visible-column space (ANSI stripped), matching `_DisplayRow.startCol`.
  final int visStart;
  final int visEnd;
}

/// One row's worth of text after soft-wrapping. A long transcript line wraps
/// into several `_DisplayRow`s.
///
/// [text] is the *visible* content with ANSI escape codes stripped, so column
/// indices into it map 1:1 onto on-screen cells. All column arithmetic — mouse
/// hit-testing, the vim cursor, selection, search, and yank — operates on
/// [text]. [startCol] is this row's visible-column offset into the source line
/// (so link spans can be mapped onto the right row).
///
/// [rendered] is the colourised string (the row's raw slice with its ANSI
/// intact, prefixed by the SGR state carried over from earlier wrapped chunks).
/// It is used *only* for the base full-line paint; overlays restyle [text].
class _DisplayRow {
  _DisplayRow(this.lineIndex, this.startCol, this.text, {this.rendered = ''});
  final int lineIndex;
  final int startCol;
  final String text;
  final String rendered;
}

// ─── Tuning constants (library-private; shared across the behaviour mixins) ─

const int _maxInputRows = 8;
const int _maxInfoBarRows = 6;
const int _maxPickerRows = 12;
const int _maxDiagnosticsRows = 16;
const int _pickerIndent = 2;
const String _runButtonLabel = ' ► ';
const String _pickerCloseLabel = ' x ';

// ─── Diagnostics overlay rows ──────────────────────────────────────────────

/// Single-cell glyph for each diagnostic category (used in the counters and the
/// overlay rows). Chosen from widely-supported, single-width symbols.
String _categoryIcon(DiagnosticCategory c) => switch (c) {
      DiagnosticCategory.error => '✘',
      DiagnosticCategory.warning => '▲',
      DiagnosticCategory.info => 'ⓘ',
      DiagnosticCategory.todo => '✎',
    };

Style _categoryStyle(FrunTheme theme, DiagnosticCategory c) => switch (c) {
      DiagnosticCategory.error => theme.errorStyle,
      DiagnosticCategory.warning => theme.warnStyle,
      DiagnosticCategory.info => theme.accentStyle,
      DiagnosticCategory.todo => theme.successStyle,
    };

enum _DiagRowKind { fileHeader, issue }

/// One row in the flattened diagnostics overlay: either a file header (with an
/// issue count) or a single issue. Selection only ever lands on [issue] rows.
class _DiagRow {
  const _DiagRow.fileHeader(this.file, this.count)
      : kind = _DiagRowKind.fileHeader,
        diagnostic = null;
  const _DiagRow.issue(Diagnostic this.diagnostic)
      : kind = _DiagRowKind.issue,
        file = '',
        count = 0;

  final _DiagRowKind kind;
  final String file;
  final int count;
  final Diagnostic? diagnostic;
}

// ─── Per-tab button table ──────────────────────────────────────────────────

class _TabSegment {
  const _TabSegment(this.index, this.tab, this.isActive, this.width);
  final int index;
  final RunTab tab;
  final bool isActive;
  final int width;
}

class _PickerChip {
  const _PickerChip(this.index, this.text);
  final int index;
  final String text;
}

enum _PickerKind { launch, emulator, bootMode, runTarget }

class _PickerSpec {
  const _PickerSpec({
    required this.kind,
    required this.itemCount,
    required this.header,
    required this.moreHintFormat,
  });
  final _PickerKind kind;
  final int itemCount;
  final String header;
  final String moreHintFormat;
}

class _Button {
  const _Button(this.letter, this.message, {this.isStop = false});
  final String letter;
  final Msg Function(int index) message;
  final bool isStop;
}

const activeButtons = <_Button>[
  _Button('r', ReloadTabMsg.new),
  _Button('R', RestartTabMsg.new),
  _Button('S', StopTabMsg.new, isStop: true),
];

class _ConfigEditorEntry {
  const _ConfigEditorEntry(this.key, this.values, {this.label});
  final String key;
  final List<String> values;
  final String? label;
  String get displayLabel => label ?? key;
}

const _configEditorEntries = <_ConfigEditorEntry>[
  _ConfigEditorEntry('ide', ['vscode', 'zed', 'neovim'], label: 'IDE'),
  _ConfigEditorEntry('editor_mode', ['normal', 'vim'], label: 'Editor mode'),
  _ConfigEditorEntry('theme', ['dark', 'light'], label: 'Theme'),
  _ConfigEditorEntry('hot_reload_on_save', ['true', 'false'], label: 'Hot reload on save'),
  _ConfigEditorEntry('open_devtools_on_launch', ['ask', 'always', 'never'], label: 'Open devtools on launch'),
  _ConfigEditorEntry('emulator_boot', ['quick', 'cold'], label: 'Emulator boot'),
  _ConfigEditorEntry('verbose_errors', ['false', 'true'], label: 'Verbose error logs'),
];

/// Number of *visible* columns in [raw] before raw string index [rawEnd]
/// (defaults to the whole string), skipping CSI escape sequences (which occupy
/// zero columns). Maps raw offsets — e.g. link spans extracted from a coloured
/// source line — into the visible-column space the renderer operates in.
///
/// Counts each non-escape UTF-16 code unit as one column, matching the wrapping
/// in `_layoutDisplayRows`.
int _visibleWidth(String raw, [int? rawEnd]) {
  final end = (rawEnd ?? raw.length).clamp(0, raw.length);
  var i = 0;
  var vis = 0;
  while (i < end) {
    if (raw[i] == '\x1b' && i + 1 < raw.length && raw[i + 1] == '[') {
      i += 2;
      while (i < raw.length) {
        final cu = raw.codeUnitAt(i);
        i++;
        if (cu >= 0x40 && cu <= 0x7E) break; // CSI final byte
      }
      continue;
    }
    i++;
    vis++;
  }
  return vis;
}

/// Updates [active] SGR parameter list from a raw SGR parameter string
/// (the text between `\x1b[` and `m`, e.g. `'1;33'` or `'0'`).
/// Handles reset codes, extended 256-colour, and truecolour sequences.
void _applyAnsiSgr(String params, List<String> active) {
  if (params.isEmpty || params == '0') {
    active.clear();
    return;
  }
  final parts = params.split(';');
  var j = 0;
  while (j < parts.length) {
    final p = parts[j];
    if (p == '0' || p.isEmpty) {
      active.clear();
      j++;
    } else if ((p == '38' || p == '48') && j + 1 < parts.length) {
      if (parts[j + 1] == '5' && j + 2 < parts.length) {
        active.add('$p;5;${parts[j + 2]}');
        j += 3;
      } else if (parts[j + 1] == '2' && j + 4 < parts.length) {
        active.add('$p;2;${parts[j + 2]};${parts[j + 3]};${parts[j + 4]}');
        j += 5;
      } else {
        active.add(p);
        j++;
      }
    } else {
      active.add(p);
      j++;
    }
  }
}
