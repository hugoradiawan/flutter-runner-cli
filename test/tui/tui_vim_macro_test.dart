import 'package:dart_tui/dart_tui.dart';
import 'package:frun/src/data/datasources/isolate_manager.dart';
import 'package:frun/src/domain/entities/app_config.dart';
import 'package:frun/src/domain/entities/flutter_project.dart';
import 'package:frun/src/domain/value_objects/config_values.dart';
import 'package:frun/src/presentation/app/app_state.dart';
import 'package:frun/src/presentation/app/commands/command_registry.dart';
import 'package:frun/src/presentation/di/dependencies.dart';
import 'package:frun/src/presentation/tui/frun_app.dart';
import 'package:test/test.dart';

void main() {
  group('Macros through the full key router', () {
    test('record dw on the input line, then replay with @a', () {
      final h = _harness();
      h.type('foo bar baz');
      h.key(KeyCode.escape); // normal mode (input non-empty)
      h.keyRune('0');
      for (final ch in 'qadwq'.split('')) {
        h.keyRune(ch);
      }
      expect(h.inputText, 'bar baz');
      h.keyRune('@');
      h.keyRune('a');
      expect(h.inputText, 'baz');
    });

    test('macro containing an insert session replays typed text', () {
      final h = _harness();
      h.type('x');
      h.key(KeyCode.escape);
      for (final ch in 'qaiAB'.split('')) {
        h.keyRune(ch);
      }
      h.key(KeyCode.escape);
      h.keyRune('q');
      expect(h.inputText, 'ABx');
      // Cursor rests on 'B' after Esc; replay inserts before it (vim-exact).
      h.keyRune('@');
      h.keyRune('a');
      expect(h.inputText, 'AABBx');
    });

    test('self-referencing macro terminates via the reentrancy caps', () {
      final h = _harness();
      h.type('seed');
      h.key(KeyCode.escape);
      // a = ix<Esc>@a — replays itself forever without the caps.
      for (final ch in 'qaix'.split('')) {
        h.keyRune(ch);
      }
      h.key(KeyCode.escape);
      for (final ch in '@aq'.split('')) {
        h.keyRune(ch);
      }
      h.keyRune('@');
      h.keyRune('a'); // must return, not hang
      expect(h.inputText.length, lessThan(10050));
      expect(h.inputText, contains('x'));
    });
  });
}

_Harness _harness({int width = 80, int height = 20}) {
  final state = AppState(
    project: const FlutterProjectEntity(
      root: '.',
      name: 'test',
      workspaceRoot: '.',
      watchRoot: '.',
      hasVsCodeFolder: false,
      hasZedFolder: false,
    ),
    config: AppConfigEntity.defaults().copyWith(editorMode: FrunEditorMode.vim),
    deps: Dependencies(isolateManager: IsolateManager()),
  );
  final model = FrunModel(
    state: state,
    registry: CommandRegistry(),
    onQuit: () {},
  );
  model.update(WindowSizeMsg(width, height));
  return _Harness(state, model);
}

final class _Harness {
  _Harness(this.state, this.model);

  final AppState state;
  final FrunModel model;

  String get inputText => model.debugInputText;

  void keyRune(String text) {
    model.update(KeyPressMsg(TeaKey(code: KeyCode.rune, text: text)));
  }

  void key(KeyCode code) {
    model.update(KeyPressMsg(TeaKey(code: code)));
  }

  void type(String text) {
    for (final ch in text.split('')) {
      keyRune(ch);
    }
  }
}
