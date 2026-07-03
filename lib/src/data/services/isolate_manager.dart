import 'dart:async';

import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

/// Frun's view of a single Dart isolate.
class IsolateInfo {
  IsolateInfo({
    required this.id,
    required this.name,
    required this.status,
    this.pauseReason,
  });

  final String id;
  String name;
  IsolateStatus status;
  String? pauseReason;
}

enum IsolateStatus { running, paused, exited, unknown }

/// Connects to a running app's VM service and exposes its isolates plus
/// pause/resume/step/kill controls.
class IsolateManager {
  IsolateManager({
    vm.VmService? service,
    Iterable<IsolateInfo> isolates = const <IsolateInfo>[],
  }) : _service = service {
    for (final isolate in isolates) {
      _isolates[isolate.id] = isolate;
    }
  }

  vm.VmService? _service;
  final Map<String, IsolateInfo> _isolates = <String, IsolateInfo>{};
  final StreamController<List<IsolateInfo>> _changes =
      StreamController<List<IsolateInfo>>.broadcast();
  StreamSubscription<vm.Event>? _isolateEvents;
  StreamSubscription<vm.Event>? _debugEvents;
  StreamSubscription<vm.Event>? _extensionEvents;
  final StreamController<vm.Event> _extensionStream =
      StreamController<vm.Event>.broadcast();

  vm.VmService? get service => _service;

  /// Notified whenever the isolate list or one of its statuses changes.
  Stream<List<IsolateInfo>> get changes => _changes.stream;

  /// Broadcast of `ext.*` extension events — used by the widget inspector
  /// integration to react to selection changes.
  Stream<vm.Event> get extensionEvents => _extensionStream.stream;

  List<IsolateInfo>? _sortedCache;
  int _revision = 0;

  /// Monotonic version, bumped on every isolate list/status change. Lets the
  /// TUI's frame signature use one int instead of hashing every isolate per
  /// frame.
  int get revision => _revision;

  List<IsolateInfo> get isolates {
    final cached = _sortedCache;
    if (cached != null) return cached;
    final list = _isolates.values.toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return _sortedCache = list;
  }

  IsolateInfo? byId(String id) => _isolates[id];

  Future<void> connect(String wsUri) async {
    await disconnect();
    _service = await vmServiceConnectUri(wsUri);
    _isolateEvents = _service!.onIsolateEvent.listen(_onIsolateEvent);
    _debugEvents = _service!.onDebugEvent.listen(_onDebugEvent);
    _extensionEvents = _service!.onExtensionEvent.listen(_extensionStream.add);
    await Future.wait<void>([
      _service!.streamListen(vm.EventStreams.kIsolate),
      _service!.streamListen(vm.EventStreams.kDebug),
      _service!.streamListen(vm.EventStreams.kExtension),
    ]);
    await _refreshAll();
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

  Future<void> refresh() => _refreshAll();

  IsolateInfo _toInfo(vm.IsolateRef ref, vm.Isolate iso) {
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
    return IsolateInfo(id: id, name: name, status: status, pauseReason: reason);
  }

  void _onIsolateEvent(vm.Event event) {
    final id = event.isolate?.id;
    if (id == null) return;
    switch (event.kind) {
      case vm.EventKind.kIsolateStart:
      case vm.EventKind.kIsolateRunnable:
        _isolates[id] = IsolateInfo(
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

  Future<void> pause(String id) async {
    await _service?.pause(id);
  }

  Future<void> resume(String id, {String? step}) async {
    await _service?.resume(id, step: step);
  }

  Future<void> kill(String id) async {
    await _service?.kill(id);
  }

  Future<vm.Stack?> getStack(String id) async {
    if (_service == null) return null;
    return _service!.getStack(id);
  }

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
}
