import 'dart:typed_data';

import 'package:dart_tui/dart_tui.dart';

/// App-side compositor replacing dart_tui's [Canvas] inside `view()`.
///
/// dart_tui's pipeline ANSI-encodes every painted string through
/// `Style.render`, then immediately decodes it char-by-char (regex prefix
/// match + substring per character), and serialises with an SGR open + reset
/// around every styled cell. This class removes that round trip:
///
///  * [paint] takes plain text plus an optional [Style] — no ANSI parsing.
///  * [paintAnsi] handles the one input that genuinely carries escape codes
///    (transcript rows rendered from daemon output) with a single
///    code-unit scan.
///  * [render] emits SGR codes per *run* of same-styled cells, not per cell,
///    so the frame string stays close to its visible size and the line-diff
///    renderer and ConPTY parse far fewer bytes.
///
/// The cell buffers persist across frames: [reset] only reallocates when the
/// terminal size changes. Styles are interned once per distinct [Style]
/// instance / escape-sequence run, so steady-state painting allocates almost
/// nothing beyond the final frame string.
///
/// Later paints win at equal `zIndex` (painter's order), higher `zIndex`
/// always wins — matching how the paint code already layers overlays.
final class CellCanvas {
  /// Marks the trailing cell of a double-width character; render() emits
  /// nothing for it. U+FFFF is a Unicode noncharacter, so it can never clash
  /// with painted content.
  static const int _wideTail = 0xFFFF;

  int _width = 0;
  int _height = 0;

  Uint32List _runes = Uint32List(0);
  Int16List _styleIds = Int16List(0);
  Int8List _z = Int8List(0);

  /// Interned SGR open sequences; index 0 is the unstyled cell.
  final List<String> _openSeqs = <String>[''];
  final Map<String, int> _idByOpenSeq = <String, int>{'': 0};

  /// Open-sequence id per [Style] instance. Theme styles are long-lived
  /// singletons, so identity is a stable key.
  final Map<Style, int> _idByStyle = Map<Style, int>.identity();

  /// Times the cell buffers were (re)allocated. Should stay at 1 across
  /// same-size frames (test hook).
  int debugGridReallocs = 0;

  int get width => _width;
  int get height => _height;

  /// Prepare for a new frame: clear all cells, reallocating only when the
  /// size actually changed.
  void reset(int width, int height) {
    assert(width > 0 && height > 0, 'CellCanvas size must be positive');
    final cells = width * height;
    if (width != _width || height != _height) {
      _width = width;
      _height = height;
      _runes = Uint32List(cells);
      _styleIds = Int16List(cells);
      _z = Int8List(cells);
      debugGridReallocs++;
      return;
    }
    _runes.fillRange(0, cells, 0);
    _styleIds.fillRange(0, cells, 0);
    _z.fillRange(0, cells, 0);
  }

  /// Paint plain [text] (no ANSI escapes) at ([x], [y]). Newlines advance to
  /// the next row starting again at [x]. When [style] is given, every painted
  /// cell carries its SGR open sequence.
  void paint(int x, int y, String text, {Style? style, int zIndex = 0}) {
    final styleId = style == null ? 0 : _styleIdOf(style);
    var col = x;
    var row = y;
    for (var i = 0; i < text.length; i++) {
      final cu = text.codeUnitAt(i);
      if (cu == 0x0A) {
        row++;
        col = x;
        continue;
      }
      var rune = cu;
      if (cu >= 0xD800 && cu <= 0xDBFF && i + 1 < text.length) {
        final lo = text.codeUnitAt(i + 1);
        if (lo >= 0xDC00 && lo <= 0xDFFF) {
          rune = 0x10000 + ((cu - 0xD800) << 10) + (lo - 0xDC00);
          i++;
        }
      }
      col = _setCell(col, row, rune, styleId, zIndex);
    }
  }

  /// Paint [text] that may contain CSI escape sequences (e.g. a transcript
  /// row rendered from daemon output). SGR sequences accumulate into the
  /// active style exactly as dart_tui's Canvas did: a bare reset
  /// (`\x1b[0m` / `\x1b[m`) drops back to *plain* (not [baseStyle]), any other
  /// SGR appends to the current open-sequence run. Non-SGR CSI sequences are
  /// consumed and ignored.
  void paintAnsi(int x, int y, String text, {Style? baseStyle, int zIndex = 0}) {
    var styleId = baseStyle == null ? 0 : _styleIdOf(baseStyle);
    var openSeq = _openSeqs[styleId];
    var col = x;
    var row = y;
    var i = 0;
    while (i < text.length) {
      final cu = text.codeUnitAt(i);
      if (cu == 0x1B && i + 1 < text.length && text.codeUnitAt(i + 1) == 0x5B) {
        final seqStart = i;
        i += 2;
        var finalByte = 0;
        while (i < text.length) {
          finalByte = text.codeUnitAt(i);
          i++;
          if (finalByte >= 0x40 && finalByte <= 0x7E) break;
        }
        if (finalByte == 0x6D /* m */) {
          final seq = text.substring(seqStart, i);
          if (seq == '\x1b[0m' || seq == '\x1b[m') {
            openSeq = '';
            styleId = 0;
          } else {
            openSeq = openSeq + seq;
            styleId = _idOfOpenSeq(openSeq);
          }
        }
        continue;
      }
      if (cu == 0x0A) {
        row++;
        col = x;
        i++;
        continue;
      }
      var rune = cu;
      if (cu >= 0xD800 && cu <= 0xDBFF && i + 1 < text.length) {
        final lo = text.codeUnitAt(i + 1);
        if (lo >= 0xDC00 && lo <= 0xDFFF) {
          rune = 0x10000 + ((cu - 0xD800) << 10) + (lo - 0xDC00);
          i++;
        }
      }
      i++;
      col = _setCell(col, row, rune, styleId, zIndex);
    }
  }

  /// Collapse the grid into the frame string, emitting SGR codes only where
  /// the style changes along a row.
  String render() {
    final sb = StringBuffer();
    for (var row = 0; row < _height; row++) {
      final base = row * _width;
      var current = 0;
      for (var col = 0; col < _width; col++) {
        final idx = base + col;
        final rune = _runes[idx];
        if (rune == _wideTail) continue;
        final styleId = _styleIds[idx];
        if (styleId != current) {
          sb.write('\x1b[0m');
          if (styleId != 0) sb.write(_openSeqs[styleId]);
          current = styleId;
        }
        sb.writeCharCode(rune == 0 ? 0x20 : rune);
      }
      if (current != 0) sb.write('\x1b[0m');
      if (row < _height - 1) sb.write('\n');
    }
    return sb.toString();
  }

  /// Write one rune at ([col], [row]) if in bounds and not occluded by a
  /// higher z paint. Returns the next column (advances by the rune's width
  /// even when the write itself was clipped or occluded).
  int _setCell(int col, int row, int rune, int styleId, int z) {
    final wide = _runeWidth(rune) == 2;
    if (row >= 0 && row < _height && col >= 0 && col < _width) {
      final idx = row * _width + col;
      if (z >= _z[idx]) {
        _runes[idx] = rune;
        _styleIds[idx] = styleId;
        _z[idx] = z;
        if (wide && col + 1 < _width) {
          final tail = idx + 1;
          if (z >= _z[tail]) {
            _runes[tail] = _wideTail;
            _styleIds[tail] = styleId;
            _z[tail] = z;
          }
        }
      }
    }
    return col + (wide ? 2 : 1);
  }

  int _styleIdOf(Style style) {
    final cached = _idByStyle[style];
    if (cached != null) return cached;
    // Derive the style's SGR open sequence once by rendering a sentinel and
    // slicing everything before it. Theme styles are inline SGR-only, so the
    // suffix is just the reset.
    final probe = style.render('x');
    final cut = probe.indexOf('x');
    final open = cut <= 0 ? '' : probe.substring(0, cut);
    final id = _idOfOpenSeq(open);
    _idByStyle[style] = id;
    return id;
  }

  int _idOfOpenSeq(String open) {
    final existing = _idByOpenSeq[open];
    if (existing != null) return existing;
    final id = _openSeqs.length;
    assert(id <= 0x7FFF, 'style table overflow');
    _openSeqs.add(open);
    _idByOpenSeq[open] = id;
    return id;
  }

  /// Column width of [code]: mirrors dart_tui Canvas's width estimate so the
  /// switch does not change layout for CJK / emoji content.
  static int _runeWidth(int code) {
    if (code < 0x1100) return 1;
    if (code <= 0x11ff ||
        (code >= 0x2e80 && code <= 0x9fff) ||
        (code >= 0xac00 && code <= 0xd7af) ||
        (code >= 0xf900 && code <= 0xfaff) ||
        (code >= 0xfe30 && code <= 0xfe4f) ||
        (code >= 0xff00 && code <= 0xff60) ||
        (code >= 0x1f300 && code <= 0x1f9ff)) {
      return 2;
    }
    return 1;
  }
}
