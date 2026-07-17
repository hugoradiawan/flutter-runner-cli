import 'dart:async';

import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

import '../../domain/entities/isolate_info.dart';
import '../../domain/ports/isolate_control.dart';

/// Connects to a running app's VM service and exposes its isolates plus
/// pause/resume/step/kill controls. Implements the domain [IsolateControl]
/// port; the raw [extensionEvents] stream stays on this concrete class for
/// the inspector bridge.
class IsolateManager implements IsolateControl {
  IsolateManager({
    vm.VmService? service,
    Iterable<IsolateInfoEntity> isolates = const <IsolateInfoEntity>[],
  }) : _service = service {
    for (final isolate in isolates) {
      _isolates[isolate.id] = isolate;
    }
  }

  vm.VmService? _service;
  final Map<String, IsolateInfoEntity> _isolates =
      <String, IsolateInfoEntity>{};
  final StreamController<List<IsolateInfoEntity>> _changes =
      StreamController<List<IsolateInfoEntity>>.broadcast();
  StreamSubscription<vm.Event>? _isolateEvents;
  StreamSubscription<vm.Event>? _debugEvents;
  StreamSubscription<vm.Event>? _extensionEvents;
  final StreamController<vm.Event> _extensionStream =
      StreamController<vm.Event>.broadcast();

  vm.VmService? get service => _service;

  @override
  bool get isConnected => _service != null;

  /// Notified whenever the isolate list or one of its statuses changes.
  @override
  Stream<List<IsolateInfoEntity>> get changes => _changes.stream;

  /// Broadcast of `ext.*` extension events — used by the widget inspector
  /// integration to react to selection changes.
  Stream<vm.Event> get extensionEvents => _extensionStream.stream;

  @override
  Stream<Map<String, Object?>> get flutterErrors => _extensionStream.stream
      .where((e) => e.extensionKind == 'Flutter.Error')
      .map((e) => e.extensionData?.data ?? const <String, dynamic>{});

  List<IsolateInfoEntity>? _sortedCache;
  int _revision = 0;

  /// Monotonic version, bumped on every isolate list/status change. Lets the
  /// TUI's frame signature use one int instead of hashing every isolate per
  /// frame.
  @override
  int get revision => _revision;

  @override
  List<IsolateInfoEntity> get isolates {
    final cached = _sortedCache;
    if (cached != null) return cached;
    final list = _isolates.values.toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return _sortedCache = list;
  }

  IsolateInfoEntity? byId(String id) => _isolates[id];

  @override
  Future<void> connect(String wsUri) async {
    await disconnect();
    _service = await vmServiceConnectUri(wsUri);
    try {
      _isolateEvents = _service!.onIsolateEvent.listen(_onIsolateEvent);
      _debugEvents = _service!.onDebugEvent.listen(_onDebugEvent);
      _extensionEvents = _service!.onExtensionEvent.listen(
        _extensionStream.add,
      );
      await Future.wait<void>([
        _service!.streamListen(vm.EventStreams.kIsolate),
        _service!.streamListen(vm.EventStreams.kDebug),
        _service!.streamListen(vm.EventStreams.kExtension),
      ]);
      await _refreshAll();
    } catch (_) {
      // Partial wiring must not linger: `isConnected` would report true while
      // event subscriptions/streams are broken. Reset, then let the caller
      // handle the original failure.
      await disconnect();
      rethrow;
    }
  }

  Future<void> _refreshAll() async {
    final service = _service;
    if (service == null) return;
    final vmObj = await service.getVM();
    _isolates.clear();
    for (final ref in vmObj.isolates ?? const <vm.IsolateRef>[]) {
      final id = ref.id;
      if (id == null) continue;
      try {
        final iso = await service.getIsolate(id);
        _isolates[id] = _toInfo(ref, iso);
      } catch (_) {
        /* may be racing teardown */
      }
    }
    _emit();
  }

  @override
  Future<void> refresh() => _refreshAll();

  IsolateInfoEntity _toInfo(vm.IsolateRef ref, vm.Isolate iso) {
    final id = ref.id ?? iso.id ?? 'unknown';
    final name = ref.name ?? iso.name ?? id;
    IsolateStatus status;
    String? reason;
    final pause = iso.pauseEvent;
    if (pause == null) {
      status = IsolateStatus.running;
    } else if (pause.kind == vm.EventKind.kResume) {
      status = IsolateStatus.running;
    } else if (pause.kind == vm.EventKind.kIsolateExit) {
      status = IsolateStatus.exited;
    } else {
      status = IsolateStatus.paused;
      reason = pause.kind;
    }
    return IsolateInfoEntity(
      id: id,
      name: name,
      status: status,
      pauseReason: reason,
    );
  }

  void _onIsolateEvent(vm.Event event) {
    final id = event.isolate?.id;
    if (id == null) return;
    switch (event.kind) {
      case vm.EventKind.kIsolateStart:
      case vm.EventKind.kIsolateRunnable:
        _isolates[id] = IsolateInfoEntity(
          id: id,
          name: event.isolate?.name ?? id,
          status: IsolateStatus.running,
        );
        _emit();
      case vm.EventKind.kIsolateExit:
        // Drop the dead isolate so the map can't accumulate exited entries
        // across repeated hot restarts; the live list is what the UI shows.
        if (_isolates.remove(id) != null) {
          _emit();
        }
      case vm.EventKind.kIsolateUpdate:
        final info = _isolates[id];
        if (info != null && event.isolate?.name != null) {
          info.name = event.isolate!.name!;
          _emit();
        }
    }
  }

  void _onDebugEvent(vm.Event event) {
    final id = event.isolate?.id;
    if (id == null) return;
    final info = _isolates[id];
    if (info == null) return;
    switch (event.kind) {
      case vm.EventKind.kResume:
        info.status = IsolateStatus.running;
        info.pauseReason = null;
        _emit();
      case vm.EventKind.kPauseStart:
      case vm.EventKind.kPauseExit:
      case vm.EventKind.kPauseBreakpoint:
      case vm.EventKind.kPauseException:
      case vm.EventKind.kPauseInterrupted:
      case vm.EventKind.kPausePostRequest:
        info.status = IsolateStatus.paused;
        info.pauseReason = event.kind;
        _emit();
    }
  }

  void _emit() {
    _sortedCache = null;
    _revision++;
    if (!_changes.isClosed) _changes.add(isolates);
  }

  @override
  Future<void> pause(String id) async {
    await _service?.pause(id);
  }

  @override
  Future<void> resume(String id, {IsolateStepMode? step}) async {
    await _service?.resume(
      id,
      step: switch (step) {
        null => null,
        IsolateStepMode.over => vm.StepOption.kOver,
        IsolateStepMode.into => vm.StepOption.kInto,
        IsolateStepMode.out => vm.StepOption.kOut,
      },
    );
  }

  @override
  Future<void> kill(String id) async {
    await _service?.kill(id);
  }

  @override
  Future<List<StackFrameEntity>?> stack(String id) async {
    final service = _service;
    if (service == null) return null;
    final stack = await service.getStack(id);
    final frames = stack.frames ?? const <vm.Frame>[];
    return [
      for (final (i, f) in frames.indexed)
        StackFrameEntity(
          index: i,
          functionName: f.function?.name ?? '<anon>',
          scriptUri: f.location?.script?.uri,
        ),
    ];
  }

  @override
  Future<void> disconnect() async {
    await _isolateEvents?.cancel();
    await _debugEvents?.cancel();
    await _extensionEvents?.cancel();
    _isolateEvents = null;
    _debugEvents = null;
    _extensionEvents = null;
    try {
      await _service?.dispose();
    } catch (_) {
      /* ignore */
    }
    _service = null;
    _isolates.clear();
    _emit();
  }

  /// Full teardown: disconnect from the VM and close the broadcast
  /// controllers. After this the manager must not be reused.
  Future<void> dispose() async {
    await disconnect();
    await _changes.close();
    await _extensionStream.close();
  }
}
