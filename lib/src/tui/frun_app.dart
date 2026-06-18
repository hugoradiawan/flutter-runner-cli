import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dart_tui/dart_tui.dart';
import 'package:path/path.dart' as p;

import '../analysis/diagnostic.dart';
import '../app/app_state.dart';
import '../app/commands/command.dart';
import '../app/commands/command_registry.dart';
import '../app/link_extractor.dart';
import '../app/run_tab.dart';
import '../app/transcript.dart';
import '../config/config.dart';
import '../config/config_store.dart';
import '../config/history_store.dart';
import '../ide/source_location.dart';
import '../version.dart';
import 'clipboard.dart';
import 'hit_regions.dart';
import 'input_controller.dart';
import 'theme.dart';
import 'transcript_cursor.dart';
import 'vim/ex_parser.dart';
import 'vim/vim_buffer.dart';
import 'vim/vim_engine.dart';
import 'vim/vim_mode.dart';
import 'vim/vim_state.dart';

part 'frun_app.messages.dart';
part 'frun_app.types.dart';
part 'frun_app.reducer.dart';
part 'frun_app.keys.dart';
part 'frun_app.engine.dart';
part 'frun_app.mouse.dart';
part 'frun_app.view.dart';
part 'frun_app.paint.dart';
part 'frun_app.overlays.dart';

/// Top-level TUI:
///   0..bodyH-1:  transcript (full width, borderless)
///   then:        optional status block (toggled by /status)
///   then:        info bar — tabs strip on the left, project/device/ide on the right
///   penultimate: input prompt (multi-line in vim mode)
///   last:        footer / hints
///
/// All instance state lives on [_FrunModelBase] so each behaviour mixin can
/// read/write it via its `on _FrunModelBase` constraint. The concrete
/// [FrunModel] composes those mixins; the TeaModel overrides
/// (init/update/view) are supplied by them.
abstract class _FrunModelBase extends TeaModel {
  _FrunModelBase({
    required this.state,
    required this.registry,
    required this.onQuit,
    required ConfigStore configStore,
  })  : _configStore = configStore,
        _input = InputController(editorMode: state.config.editorMode);

  final AppState state;
  final CommandRegistry registry;
  final void Function() onQuit;

  final ConfigStore _configStore;
  final InputController _input;

  bool _configEditorActive = false;
  int _configEditorRow = 0;
  FrunConfig? _configDraft;
  final HistoryStore _historyStore = HistoryStore();
  late final TranscriptCursor _tc;
  final HitRegions _hits = HitRegions();
  final VimState _vimState = VimState();
  late final VimEngine _vim;

  int _transcriptScroll = 0;
  int _focusedLinkIndex = -1;

  int _pickerSelectedIndex = 0;
  int _pickerScrollOffset = 0;
  bool _pickerWasActive = false;

  // Diagnostics overlay selection (indexes into the flattened file-header +
  // issue row list) and its scroll offset.
  int _diagSelectedIndex = 0;
  int _diagScrollOffset = 0;
  // Vim-mode panel state: `gg` pending-g latch, and whether `/` search-typing
  // is active (so bare letters feed the filter instead of acting as motions).
  bool _diagPendingG = false;
  bool _diagSearching = false;

  // Mouse-drag selection state. `_mouseAnchor` is captured on left-click
  // inside the transcript body when no hit-region intercepts; the selection
  // itself is materialised on the first MouseMotionMsg so a plain click
  // doesn't strand a zero-width range.
  bool _mouseSelecting = false;
  Pos? _mouseAnchor;
  bool _mouseDragged = false;
  // Captured at click-time so release can restore the prior input/cursor
  // mode regardless of whether the user was in vim normal, insert, or the
  // non-vim editor mode when the drag began.
  VimMode? _mousePriorVimMode;
  bool _mousePriorTcActive = false;
  int _autoScrollDirection = 0; // -1 = toward newer (down), +1 = toward older (up), 0 = none

  // Cached layout state, refreshed each view() call.
  List<_VisibleLink> _visibleLinks = const <_VisibleLink>[];
  List<_DisplayRow> _lastDisplayRows = const <_DisplayRow>[];
  List<String> _displayRowsText = const <String>[];
  int _lastVisibleStart = 0;
  int _lastVisibleEnd = 0;
  int _lastBodyHeight = 10;
  int _lastBodyY = 0;
  int _width = 80;
  int _height = 24;

  // ── Shared state-only helpers ────────────────────────────────────────────
  // These live on the base (not a mixin) because they touch nothing but the
  // fields above and are called from several behaviour mixins. Hosting them
  // here keeps the mixin `on` graph acyclic.

  VimBuffer get _activeBuffer => _tc.active ? _tc : _input;

  void _resetViewForNewTab() {
    _transcriptScroll = 0;
    _focusedLinkIndex = -1;
    _tc.exit();
  }

  String _promptForMode() {
    if (_vimState.mode == VimMode.exCmd) return ':';
    if (_vimState.mode == VimMode.search) {
      return (_vimState.lastSearch?.forward ?? true) ? '/' : '?';
    }
    if (state.config.editorMode == FrunEditorMode.vim &&
        _vimState.mode != VimMode.insert) {
      return '· ';
    }
    return '> ';
  }
}

final class FrunModel extends _FrunModelBase
    with
        // Applied in dependency order: each mixin's `on` constraints must
        // already be in the chain when it is mixed in.
        _EngineMixin,
        _MouseMixin,
        _OverlayMixin,
        _PaintMixin,
        _ViewMixin,
        _KeyMixin,
        _ReducerMixin {
  FrunModel({
    required super.state,
    required super.registry,
    required super.onQuit,
    required super.configStore,
  }) {
    // Kept in the concrete class: this wiring references mixin methods
    // (_viewportFor, _runExCmd, _runSearch, _submit, _switchTabFromVim) that
    // are only statically visible on the fully-composed type.
    _tc = TranscriptCursor(rowsProvider: () => _displayRowsText);
    _vim = VimEngine(
      state: _vimState,
      viewport: _viewportFor,
      runExCmd: _runExCmd,
      runSearch: _runSearch,
      onSubmit: _submit,
      onTabSwitch: _switchTabFromVim,
    );
  }
}
