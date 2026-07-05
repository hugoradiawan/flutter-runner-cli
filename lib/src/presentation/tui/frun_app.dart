import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:dart_tui/dart_tui.dart';
import 'package:path/path.dart' as p;
import 'package:vm_service/vm_service.dart' as vm;

import '../../data/services/history_store.dart';
import '../../data/services/isolate_manager.dart';
import '../../domain/entities/app_config.dart';
import '../../domain/entities/diagnostic.dart';
import '../../domain/value_objects/config_values.dart';
import '../../domain/value_objects/source_location.dart';
import '../../version.dart';
import '../app/app_state.dart';
import '../app/commands/command.dart';
import '../app/commands/command_registry.dart';
import '../app/ide_opener.dart';
import '../app/link_extractor.dart';
import '../app/run_tab.dart';
import '../app/transcript.dart';
import 'cell_canvas.dart';
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

part 'frun_app.chrome.dart';
part 'frun_app.engine.dart';
part 'frun_app.keys.dart';
part 'frun_app.messages.dart';
part 'frun_app.mouse.dart';
part 'frun_app.overlays.dart';
part 'frun_app.paint.dart';
part 'frun_app.reducer.dart';
part 'frun_app.types.dart';
part 'frun_app.view.dart';

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
  }) : _input = InputController(editorMode: state.config.editorMode);

  final AppState state;
  final CommandRegistry registry;
  final void Function() onQuit;

  final InputController _input;

  /// Persistent frame compositor; buffers survive across frames and only
  /// reallocate on terminal resize.
  final CellCanvas _cellCanvas = CellCanvas();

  bool _configEditorActive = false;
  int _configEditorRow = 0;
  AppConfigEntity? _configDraft;
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

  // Isolate lifecycle panel selection and scroll offset.
  int _isolateSelectedIndex = 0;
  int _isolateScrollOffset = 0;
  bool _isolatePendingG = false;

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
  int _autoScrollDirection =
      0; // -1 = toward newer (down), +1 = toward older (up), 0 = none

  // Cached layout state, refreshed each view() call.
  List<_VisibleLink> _visibleLinks = const <_VisibleLink>[];
  Transcript? _visibleLinksCacheTranscript;
  int _visibleLinksCacheRevision = -1;
  int _visibleLinksCacheWidth = -1;
  int _visibleLinksCacheStart = -1;
  int _visibleLinksCacheEnd = -1;
  List<_VisibleLink> _visibleLinksCache = const <_VisibleLink>[];
  // Per-source-line link cache, aligned with the transcript's retained lines
  // (same head-advance ring scheme as _rowsBuffer, but line-aligned: one slot
  // per transcript line, at _lineLinksHead + (lineIndex - baseIndex)). null
  // means not yet extracted; extraction runs lazily the first time a line
  // becomes visible and stays valid for the line's lifetime, because
  // transcript lines are immutable once appended. Maintained inside
  // _syncTranscriptLayout so eviction/reset follows the row buffers exactly.
  final List<List<_VisibleLink>?> _lineLinksBuffer = <List<_VisibleLink>?>[];
  int _lineLinksHead = 0;
  // Master storage for the wrapped display rows. Appends go in place at the
  // tail; scrollback eviction advances _rowsHead past dropped rows instead of
  // copying the survivors, and the dead prefix is compacted away only once it
  // outgrows the live region — so a content frame at a full ring buffer costs
  // O(changed rows), not O(total rows). _lastDisplayRows/_displayRowsText are
  // stable read-only views over the live region; row indices into them shift
  // when the head advances, exactly as they did when the lists were rebuilt.
  final List<_DisplayRow> _rowsBuffer = <_DisplayRow>[];
  final List<String> _rowTextsBuffer = <String>[];
  int _rowsHead = 0;
  // Bumped whenever existing buffer indices shift (full rebuild, compaction);
  // stable across pure appends and head advances. Dependent caches that store
  // buffer-index-aligned data (the search lowercase mirror) key off it.
  int _rowsBufferGeneration = 0;
  late final List<_DisplayRow> _lastDisplayRows = _ListSliceView(
    () => _rowsBuffer,
    () => _rowsHead,
  );
  late final List<String> _displayRowsText = _ListSliceView(
    () => _rowTextsBuffer,
    () => _rowsHead,
  );
  // Live view of the transcript lines the cached layout was built from.
  // Index 0 always corresponds to `transcript.baseIndex`.
  List<TranscriptLine> _lastLines = const <TranscriptLine>[];
  // Keys for reusing the display-row layout across paints. _layoutDisplayRows
  // walks the whole transcript (ANSI parse + soft-wrap), so re-running it on
  // every tick/mouse-move frame is pure waste. The wrapped output only changes
  // when the transcript content (revision) or the wrap width changes; the
  // Transcript instance is part of the key so switching tabs invalidates even
  // if the new tab's revision happens to match.
  Transcript? _layoutCacheTranscript;
  int _layoutCacheRevision = -1;
  int _layoutCacheWidth = -1;
  int _layoutCacheBaseIndex = 0;
  int _layoutCacheLineCount = 0;
  int _layoutAppendedRowCount = 0;
  // Display rows evicted off the top by the last layout sync (scrollback
  // trim). Row-index-anchored state (transcript cursor, selection, drag
  // anchor) shifts up by this much so it keeps pointing at the same content.
  int _layoutDroppedRowCount = 0;
  // Lowercased mirror of _rowTextsBuffer (aligned to raw buffer indices, dead
  // prefix included) so successive search keystrokes share one lowercase pass
  // instead of re-allocating a lowercased copy of every row per keystroke.
  // Populated only while a search query is active; emptied when search exits.
  final List<String> _lowerRowTexts = <String>[];
  int _lowerCacheGeneration = -1;
  Transcript? _searchCacheTranscript;
  int _searchCacheRevision = -1;
  int _searchCacheWidth = -1;
  String _searchCacheQuery = '';
  List<SearchMatch> _searchCacheMatches = const <SearchMatch>[];
  Map<int, List<int>> _searchCacheMatchIndexesByRow = const <int, List<int>>{};
  Map<int, List<int>> _searchMatchIndexesByRow = const <int, List<int>>{};
  int _debugLayoutBuilds = 0;
  int _debugSearchBuilds = 0;
  int _debugVisibleLinkBuilds = 0;
  int _debugLinkExtractions = 0;
  int _debugAnsiRunParses = 0;
  int _debugRowBufferCopies = 0;
  int _debugSearchLowerBuilds = 0;
  // Diagnostic counters memo: counts() walks every diagnostic (with a
  // per-entry toLowerCase in `category`); the tallies only change when the
  // diagnostics list is replaced, so recompute at most once per revision
  // instead of every painted frame.
  int _diagCountsCacheRevision = -1;
  (int, int, int, int) _diagCountsCache = (0, 0, 0, 0);
  int _debugDiagCountsBuilds = 0;
  // One-shot handoff of the tab-strip layout from _computeInfoBarHeight to
  // _paintInfoBar within a single view() pass, so the wrap layout runs once
  // per frame. Cleared on consume; never trusted across frames.
  (List<List<_TabSegment>>, int)? _tabRowsFrameCache;
  int _tabRowsFrameCacheWidth = -1;
  int _diagnosticRowsCacheRevision = -1;
  DiagnosticCategory? _diagnosticRowsCacheFilter;
  String _diagnosticRowsCacheSearch = '';
  List<_DiagRow> _diagnosticRowsCache = const <_DiagRow>[];
  // Previous transcript display-row count and wrap width, so a bottom append
  // can be detected and the scroll offset anchored when scrolled up.
  int _lastTotalRows = 0;
  int _lastLayoutWidth = 0;
  int _lastVisibleStart = 0;
  int _lastVisibleEnd = 0;
  int _lastBodyHeight = 10;
  int _lastBodyY = 0;
  int _width = 80;
  int _height = 24;
  // Tick counter for the Windows resize-poll fallback (checks every 4th tick).
  int _resizePollTick = 0;

  // Frame-skip gate. The UI has no animated elements, so when no
  // render-affecting state changed since the last frame we re-emit the previous
  // frame instead of repainting (the 250ms tick would otherwise repaint 4x/sec
  // while idle). A full repaint is forced at least every _maxSkippedFrames ticks
  // to self-heal any state the signature doesn't capture.
  static const int _maxSkippedFrames = 4; // ~1s at the 250ms tick interval
  // Preallocated signature slots, filled by index and compared element-wise
  // each frame — the skip path allocates nothing.
  static const int _sigLength = 42;
  final List<int> _sigCurrent = List<int>.filled(_sigLength, 0);
  final List<int> _sigPrevious = List<int>.filled(_sigLength, 0);
  bool _sigValid = false;
  String? _lastViewContent;
  Cursor? _lastViewCursor;
  int _framesSinceFullPaint = 0;

  // ── Shared state-only helpers ────────────────────────────────────────────
  // These live on the base (not a mixin) because they touch nothing but the
  // fields above and are called from several behaviour mixins. Hosting them
  // here keeps the mixin `on` graph acyclic.

  VimBuffer get _activeBuffer => _tc.active ? _tc : _input;

  /// Memoized (error, warning, info, todo) tallies for [AppState.diagnostics].
  /// counts() walks every diagnostic (with a per-entry toLowerCase); the
  /// tallies only change when the list is replaced, so recompute at most once
  /// per diagnostics revision. Shared by the input-bar counters and the
  /// diagnostics panel header.
  (int, int, int, int) _diagCounts() {
    if (state.diagnosticsRevision != _diagCountsCacheRevision) {
      _diagCountsCache = DiagnosticEntity.counts(state.diagnostics);
      _diagCountsCacheRevision = state.diagnosticsRevision;
      _debugDiagCountsBuilds++;
    }
    return _diagCountsCache;
  }

  int _cachedMaxScroll() {
    final visibleRowCount = _lastBodyHeight;
    if (visibleRowCount <= 0) return 0;
    return (_lastDisplayRows.length - visibleRowCount).clamp(0, 1 << 30);
  }

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

  int get debugLayoutBuilds => _debugLayoutBuilds;
  int get debugSearchBuilds => _debugSearchBuilds;
  int get debugVisibleLinkBuilds => _debugVisibleLinkBuilds;
  int get debugLinkExtractions => _debugLinkExtractions;
  int get debugAnsiRunParses => _debugAnsiRunParses;
  int get debugRowBufferCopies => _debugRowBufferCopies;
  int get debugDisplayRowsBufferIdentity => identityHashCode(_rowsBuffer);
  int get debugSearchLowerBuilds => _debugSearchLowerBuilds;
  int get debugDiagCountsBuilds => _debugDiagCountsBuilds;
  int get debugTranscriptScroll => _transcriptScroll;
  int get debugIsolateSelectedIndex => _isolateSelectedIndex;
}
