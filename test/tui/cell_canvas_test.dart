import 'package:dart_tui/dart_tui.dart';
import 'package:frun/src/presentation/tui/cell_canvas.dart';
import 'package:frun/src/presentation/tui/theme.dart';
import 'package:test/test.dart';

/// Strip ANSI escapes so tests can assert visible layout.
String _plain(String s) => s.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');

void main() {
  group('CellCanvas', () {
    test('plain paint fills cells and pads rows with spaces', () {
      final c = CellCanvas()..reset(8, 2);
      c.paint(1, 0, 'hi');
      final rows = c.render().split('\n');
      expect(rows, hasLength(2));
      expect(rows[0], ' hi     ');
      expect(rows[1], '        ');
    });

    test('styled cells emit one SGR run, not per-cell codes', () {
      final style = const Style(isBold: true).foregroundColor256(81);
      final c = CellCanvas()..reset(10, 1);
      c.paint(0, 0, 'abc', style: style);
      final out = c.render();
      expect(_plain(out), 'abc       ');
      // One reset + open (bold + colour = two seqs) at the run start, one
      // reset when the style ends — not per-cell codes (would be 9+).
      expect('\x1b['.allMatches(out).length, 4);
      expect(out.indexOf('abc'), greaterThan(0));
    });

    test('adjacent same-style paints share one run', () {
      final style = const Style().foregroundColor256(203);
      final c = CellCanvas()..reset(6, 1);
      c.paint(0, 0, 'ab', style: style);
      c.paint(2, 0, 'cd', style: style);
      final out = c.render();
      expect(_plain(out), 'abcd  ');
      expect('\x1b['.allMatches(out).length, 3); // reset+open, close, final
    });

    test('later paint wins at equal zIndex; higher z always wins', () {
      final c = CellCanvas()..reset(5, 1);
      c.paint(0, 0, 'aaaaa');
      c.paint(0, 0, 'bb'); // same z, later → wins
      expect(_plain(c.render()), 'bbaaa');

      c.reset(5, 1);
      c.paint(0, 0, 'high!', zIndex: 2);
      c.paint(0, 0, 'low..'); // lower z after → loses
      expect(_plain(c.render()), 'high!');
    });

    test('newline advances a row, restarting at the origin column', () {
      final c = CellCanvas()..reset(6, 2);
      c.paint(2, 0, 'ab\ncd');
      final rows = _plain(c.render()).split('\n');
      expect(rows[0], '  ab  ');
      expect(rows[1], '  cd  ');
    });

    test('wide char occupies two columns and renders once', () {
      final c = CellCanvas()..reset(6, 1);
      c.paint(0, 0, '你a');
      final out = _plain(c.render());
      expect(out, '你a   ');
      // 6 columns: wide char (2) + 'a' + 3 blanks → 5 emitted chars.
      expect(out.length, 5);
    });

    test('out-of-bounds paints are clipped silently', () {
      final c = CellCanvas()..reset(4, 2);
      c.paint(-2, 0, 'xy');
      c.paint(2, 1, 'abcdef');
      c.paint(0, 5, 'zz');
      final rows = _plain(c.render()).split('\n');
      expect(rows[0], '    ');
      expect(rows[1], '  ab');
    });

    test('paintAnsi accumulates SGR and a bare reset drops to plain', () {
      final c = CellCanvas()..reset(8, 1);
      c.paintAnsi(0, 0, 'a\x1b[31mb\x1b[1mc\x1b[0md');
      final out = c.render();
      expect(_plain(out), 'abcd    ');
      // 'b' is red; 'c' carries red+bold (accumulated, matching dart_tui).
      expect(out, contains('\x1b[31mb'));
      expect(out, contains('\x1b[31m\x1b[1mc'));
      // 'd' is plain again after the embedded reset.
      expect(out, contains('\x1b[0md'));
    });

    test(
      'paintAnsi baseStyle styles leading cells until an embedded reset',
      () {
        final base = const Style().foregroundColor256(78);
        final c = CellCanvas()..reset(6, 1);
        c.paintAnsi(0, 0, 'ab\x1b[0mcd', baseStyle: base);
        final out = c.render();
        expect(_plain(out), 'abcd  ');
        final baseOpen = base.render('x').split('x').first;
        expect(out, startsWith('\x1b[0m${baseOpen}ab'));
        expect(out, contains('\x1b[0mcd'));
      },
    );

    test('paintAnsi consumes non-SGR CSI sequences without painting them', () {
      final c = CellCanvas()..reset(6, 1);
      c.paintAnsi(0, 0, 'a\x1b[2Kb');
      expect(_plain(c.render()), 'ab    ');
    });

    test('reset reuses buffers for the same size and clears content', () {
      final c = CellCanvas()..reset(10, 4);
      expect(c.debugGridReallocs, 1);
      c.paint(0, 0, 'hello');
      c.reset(10, 4);
      expect(c.debugGridReallocs, 1);
      expect(_plain(c.render()).trim(), isEmpty);
      c.reset(11, 4);
      expect(c.debugGridReallocs, 2);
    });

    test('sliced paint matches painting the substring', () {
      const text = 'hello 你好 world';
      final style = const Style().foregroundColor256(203);

      final oracle = CellCanvas()..reset(20, 1);
      oracle.paint(0, 0, text);
      oracle.paint(6, 0, text.substring(6, 10), style: style, zIndex: 2);

      final sliced = CellCanvas()..reset(20, 1);
      sliced.paint(0, 0, text);
      sliced.paint(6, 0, text, style: style, zIndex: 2, start: 6, end: 10);

      expect(sliced.render(), oracle.render());
    });

    group('parseAnsiRuns + paintRuns replay paintAnsi byte-identically', () {
      // (name, ansi text, stripped visible text) — stripped is what the
      // layout's CSI-skipping scan would produce for the same input.
      const cases = <(String, String, String)>[
        ('plain text', 'abcd', 'abcd'),
        ('bold + accumulate + reset', 'a\x1b[31mb\x1b[1mc\x1b[0md', 'abcd'),
        ('256-colour', '\x1b[38;5;81mhi\x1b[0m there', 'hi there'),
        ('truecolour', '\x1b[38;2;10;20;30mxy', 'xy'),
        ('reset then restyle', '\x1b[31ma\x1b[0m\x1b[32mb', 'ab'),
        ('bare short reset', '\x1b[1ma\x1b[mb', 'ab'),
        ('non-SGR CSI ignored', 'a\x1b[2Kb', 'ab'),
        ('wide CJK styled', '\x1b[31m你a\x1b[0m好', '你a好'),
        ('emoji surrogate pairs', '😀\x1b[1m😀', '😀😀'),
        ('dangling escape at end', 'ab\x1b[3', 'ab'),
        ('escapes only, no text', '\x1b[31m\x1b[1m', ''),
      ];
      final baseStyles = <String, Style?>{
        'no base style': null,
        'coloured bold base': const Style(isBold: true).foregroundColor256(78),
      };

      for (final (name, ansi, stripped) in cases) {
        for (final entry in baseStyles.entries) {
          test('$name with ${entry.key}', () {
            final oracle = CellCanvas()..reset(16, 2);
            oracle.paintAnsi(1, 0, ansi, baseStyle: entry.value);

            final runs = CellCanvas.parseAnsiRuns(ansi);
            expect(runs.isEmpty ? 0 : runs.last.end, stripped.length);
            final replay = CellCanvas()..reset(16, 2);
            replay.paintRuns(1, 0, stripped, runs, baseStyle: entry.value);

            expect(replay.render(), oracle.render());
          });
        }
      }
    });

    test('every theme style yields a well-formed SGR open prefix', () {
      for (final theme in [FrunTheme.dark(), FrunTheme.light()]) {
        final styles = <Style>[
          theme.textStyle,
          theme.valueStyle,
          theme.titleStyle,
          theme.panelTitleStyle,
          theme.panelSubtitleStyle,
          theme.borderStyle,
          theme.borderStrongStyle,
          theme.inputBorderStyle,
          theme.dimStyle,
          theme.accentStyle,
          theme.errorStyle,
          theme.warnStyle,
          theme.successStyle,
          theme.systemStyle,
          theme.surfaceStyle,
          theme.surfaceMutedStyle,
          theme.selectedRowStyle,
          theme.emptyStyle,
          theme.badgeNeutralStyle,
          theme.badgeInfoStyle,
          theme.badgeErrorStyle,
          theme.badgeWarnStyle,
          theme.badgeSuccessStyle,
          theme.statusBarStyle,
          theme.promptStyle,
          theme.activeTabStyle,
          theme.inactiveTabStyle,
          theme.exitedTabStyle,
          theme.buttonStyle,
          theme.buttonStopStyle,
          theme.pickerChipStyle,
          theme.pickerEmulatorChipStyle,
          theme.pickerDeviceChipStyle,
          theme.pickerChipSelectedStyle,
          theme.pickerEmulatorChipSelectedStyle,
          theme.pickerDeviceChipSelectedStyle,
          theme.linkHighlightStyle,
          theme.selectionStyle,
          theme.visualLineStyle,
          theme.visualBlockStyle,
          theme.searchMatchStyle,
          theme.searchActiveStyle,
          theme.cursorStyle,
          theme.replaceCursorStyle,
        ];
        for (final style in styles) {
          final probe = style.render('x');
          final cut = probe.indexOf('x');
          expect(cut, greaterThan(0), reason: 'style renders inline SGR');
          final open = probe.substring(0, cut);
          // Open prefix must be purely SGR sequences (no stray text).
          expect(open.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), ''), isEmpty);
        }
      }
    });
  });
}
