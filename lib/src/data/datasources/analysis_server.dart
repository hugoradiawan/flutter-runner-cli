import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/diagnostic.dart';

/// Splits a raw LSP byte stream into decoded JSON-RPC messages.
///
/// LSP frames each message with a header block terminated by a blank line:
///
///     Content-Length: 123\r\n\r\n{"jsonrpc":"2.0",…}
///
/// [addBytes] accumulates partial chunks and returns whatever complete messages
/// have arrived. Headers are ASCII; the body is UTF-8 (Content-Length counts
/// bytes, so framing must be done on bytes, not characters). Kept separate from
/// [DartAnalysisServer] so it can be unit-tested without spawning a process.
class LspMessageFramer {
  final List<int> _buffer = <int>[];

  List<Map<String, Object?>> addBytes(List<int> chunk) {
    _buffer.addAll(chunk);
    final out = <Map<String, Object?>>[];
    while (true) {
      final headerEnd = _indexOfHeaderEnd();
      if (headerEnd < 0) break;
      final header = latin1.decode(_buffer.sublist(0, headerEnd));
      final contentLength = _parseContentLength(header);
      if (contentLength == null) {
        // Malformed header — drop it and resync past the blank line.
        _buffer.removeRange(0, headerEnd + 4);
        continue;
      }
      final bodyStart = headerEnd + 4; // past the \r\n\r\n
      if (_buffer.length < bodyStart + contentLength) break; // need more bytes
      final bodyBytes = _buffer.sublist(bodyStart, bodyStart + contentLength);
      _buffer.removeRange(0, bodyStart + contentLength);
      try {
        final decoded = json.decode(utf8.decode(bodyBytes));
        if (decoded is Map) out.add(decoded.cast<String, Object?>());
      } catch (_) {
        // Skip undecodable frames.
      }
    }
    return out;
  }

  int _indexOfHeaderEnd() {
    for (var i = 0; i + 3 < _buffer.length; i++) {
      if (_buffer[i] == 0x0d &&
          _buffer[i + 1] == 0x0a &&
          _buffer[i + 2] == 0x0d &&
          _buffer[i + 3] == 0x0a) {
        return i;
      }
    }
    return -1;
  }

  static int? _parseContentLength(String header) {
    for (final line in header.split('\r\n')) {
      final idx = line.indexOf(':');
      if (idx < 0) continue;
      if (line.substring(0, idx).trim().toLowerCase() == 'content-length') {
        return int.tryParse(line.substring(idx + 1).trim());
      }
    }
    return null;
  }
}

/// Parse the `diagnostics` array of a `textDocument/publishDiagnostics`
/// notification into [DiagnosticModel]s. Returns `null` when the URI isn't a local
/// file (those can't be jumped to). Visible for testing.
List<DiagnosticModel>? parsePublishDiagnostics(Map<String, Object?> params) {
  final uri = params['uri'];
  if (uri is! String) return null;
  final filePath = _uriToPath(uri);
  if (filePath == null) return null;
  final raw = params['diagnostics'];
  final out = <DiagnosticModel>[];
  if (raw is List) {
    for (final item in raw) {
      if (item is! Map) continue;
      final m = item.cast<String, Object?>();
      final range = (m['range'] as Map?)?.cast<String, Object?>();
      final start = (range?['start'] as Map?)?.cast<String, Object?>();
      final line = (start?['line'] as num?)?.toInt() ?? 0;
      final char = (start?['character'] as num?)?.toInt() ?? 0;
      final code = m['code'];
      out.add(
        DiagnosticModel(
          filePath: filePath,
          line: line + 1,
          column: char + 1,
          severity: DiagnosticModel.severityFromLsp(
            (m['severity'] as num?)?.toInt(),
          ),
          message: (m['message'] as String? ?? '').replaceAll('\n', ' ').trim(),
          code: code is String ? code : code?.toString(),
        ),
      );
    }
  }
  return out;
}

/// Apply a `publishDiagnostics` notification to a per-URI diagnostics map:
/// replace the file's whole list, or remove the key when the list is empty
/// (the analyzer's way of clearing a file). Visible for testing.
void applyPublishDiagnostics(
  Map<String, List<DiagnosticModel>> byUri,
  Map<String, Object?> params,
) {
  final uri = params['uri'];
  if (uri is! String) return;
  final parsed = parsePublishDiagnostics(params);
  if (parsed == null) return;
  if (parsed.isEmpty) {
    byUri.remove(uri);
  } else {
    byUri[uri] = parsed;
  }
}

String? _uriToPath(String uri) {
  final parsed = Uri.tryParse(uri);
  if (parsed == null || parsed.scheme != 'file') return null;
  // Normalized at the source so every downstream consumer (dedupe keys,
  // grouping, jump targets) can compare paths without re-normalizing.
  return p.normalize(parsed.toFilePath());
}

/// Thin LSP client for the Dart Analysis Server (`dart language-server`).
///
/// Unlike the Flutter daemon (newline-delimited `[{…}]` JSON), LSP frames
/// messages with `Content-Length` headers — see [LspMessageFramer]. We send an
/// `initialize` handshake rooted at the project; the server then analyzes the
/// whole project and pushes `textDocument/publishDiagnostics` notifications for
/// every file with issues (the same mechanism that fills the VS Code "Problems"
/// panel). We aggregate those into a flat, debounced [diagnostics] stream.
class DartAnalysisServer {
  DartAnalysisServer._(
    this._process,
    this._projectRoot,
    this._workspaceFolders,
  );

  final Process _process;
  final String _projectRoot;

  /// Every package root the server should analyze. For a single-package project
  /// this is just `[projectRoot]`; for a monorepo (melos / pub workspace) it is
  /// one entry per package — without them, `dart language-server` only analyzes
  /// the root's own package and silently ignores the siblings.
  final List<String> _workspaceFolders;

  final LspMessageFramer _framer = LspMessageFramer();
  final Map<String, List<DiagnosticModel>> _byUri =
      <String, List<DiagnosticModel>>{};

  /// Documents we've pushed to the server via `didOpen`, mapped to their
  /// current sync version. Opening a file makes it a *priority* document the
  /// analyzer reports on within seconds — without this, a freshly-edited file
  /// in a large monorepo can wait minutes for the background pass to reach it.
  ///
  /// Insertion order is LRU order: [_openOrChange] re-inserts on every change,
  /// so [keys.first] is the least-recently-touched document.
  final Map<String, int> _openVersions = <String, int>{};

  /// Soft cap on [_openVersions]. Each distinct edited file gets opened once and
  /// never closed, so over a long session the map would grow without bound.
  /// Evicting the least-recently-used entry is safe: the next edit to that path
  /// re-sends a `didOpen` at version 1.
  static const int _maxOpenVersions = 300;

  /// Soft cap on [_byUri]. Large monorepos can accumulate diagnostic maps for
  /// thousands of files; once the cap is reached the oldest URI is evicted.
  static const int _maxByUri = 500;

  /// Files requested via [openFile] before the `initialize` handshake finished.
  /// Flushed once the server is ready.
  final List<String> _pendingOpens = <String>[];

  int _nextId = 1;
  int _initializeId = -1;
  bool _initialized = false;
  bool _disposed = false;

  final StreamController<List<DiagnosticModel>> _diagnostics =
      StreamController<List<DiagnosticModel>>.broadcast();
  final StreamController<String> _stderr = StreamController<String>.broadcast();
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  Timer? _coalesce;

  /// Debounced stream of the full project diagnostic set (all files flattened).
  /// Emits at most once per ~250 ms burst of per-file pushes.
  Stream<List<DiagnosticModel>> get diagnostics => _diagnostics.stream;

  /// stderr lines from the language-server process (surfaces startup failures).
  Stream<String> get stderrLines => _stderr.stream;

  List<DiagnosticModel>? _snapshotCache;

  /// The latest known full diagnostic set across all files. Flattened lazily
  /// and cached until the next `publishDiagnostics` mutates [_byUri], so
  /// repeated reads (watcher events, repository queries) don't re-copy
  /// thousands of entries.
  List<DiagnosticModel> get snapshot => _snapshotCache ??= _byUri.values
      .expand((e) => e)
      .toList(growable: false);

  static String _defaultDartExecutable() =>
      Platform.isWindows ? 'dart.bat' : 'dart';

  /// Spawn `dart language-server` rooted at [projectRoot] and begin analysis.
  ///
  /// Throws [ProcessException] when `dart` is not on the PATH.
  static Future<DartAnalysisServer> start({
    required String projectRoot,
    List<String>? workspaceFolders,
    String? dartExecutable,
    Map<String, String>? environment,
  }) async {
    final exe = dartExecutable ?? _defaultDartExecutable();
    final folders = (workspaceFolders == null || workspaceFolders.isEmpty)
        ? <String>[projectRoot]
        : workspaceFolders;
    final process = await Process.start(
      exe,
      const <String>[
        'language-server',
        '--client-id',
        'frun',
        '--client-version',
        '0.1.0',
      ],
      workingDirectory: projectRoot,
      environment: environment,
      runInShell: Platform.isWindows,
    );
    final server = DartAnalysisServer._(process, projectRoot, folders);
    server._listen();
    server._initialize();
    return server;
  }

  void _listen() {
    _stdoutSub = _process.stdout.listen(_onBytes, onError: (Object _) {});
    _stderrSub = _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (!_disposed && !_stderr.isClosed && line.isNotEmpty) {
            _stderr.add(line);
          }
        }, onError: (Object _) {});
  }

  void _onBytes(List<int> chunk) {
    if (_disposed) return;
    for (final msg in _framer.addBytes(chunk)) {
      _handleMessage(msg);
    }
  }

  void _handleMessage(Map<String, Object?> msg) {
    final method = msg['method'];
    if (method == null) {
      // A response to one of our requests — only `initialize` matters.
      if (!_initialized && msg['id'] == _initializeId) {
        _initialized = true;
        _notify('initialized', const <String, Object?>{});
        for (final path in _pendingOpens) {
          _openOrChange(path);
        }
        _pendingOpens.clear();
      }
      return;
    }
    if (method == 'textDocument/publishDiagnostics') {
      final params = (msg['params'] as Map?)?.cast<String, Object?>();
      if (params != null) {
        applyPublishDiagnostics(_byUri, params);
        if (_byUri.length > _maxByUri) {
          _byUri.remove(_byUri.keys.first);
        }
        _snapshotCache = null;
        _scheduleEmit();
      }
      return;
    }
    // Server→client request — must answer or the server may stall.
    if (msg.containsKey('id')) {
      if (method == 'workspace/configuration') {
        final items =
            ((msg['params'] as Map?)?['items'] as List?) ?? const <Object?>[];
        // Enable review-marker (todo/fixme) diagnostics, which are off by
        // default in the server, so the todo counter is populated.
        _respond(
          msg['id'],
          List<Object?>.filled(items.length, const <String, Object?>{
            'showTodos': true,
          }),
        );
      } else {
        _respond(msg['id'], null);
      }
    }
  }

  void _scheduleEmit() {
    _coalesce?.cancel();
    _coalesce = Timer(const Duration(milliseconds: 250), () {
      if (_disposed || _diagnostics.isClosed) return;
      _diagnostics.add(snapshot);
    });
  }

  void _initialize() {
    final rootUri = Uri.file(
      _projectRoot,
      windows: Platform.isWindows,
    ).toString();
    _initializeId = _request('initialize', <String, Object?>{
      'processId': pid,
      'clientInfo': <String, Object?>{'name': 'frun', 'version': '0.1.0'},
      'rootUri': rootUri,
      'capabilities': <String, Object?>{
        'textDocument': <String, Object?>{
          'publishDiagnostics': <String, Object?>{'relatedInformation': false},
        },
        'workspace': <String, Object?>{'configuration': true},
      },
      'workspaceFolders': <Object?>[
        for (final folder in _workspaceFolders)
          <String, Object?>{
            'uri': Uri.file(folder, windows: Platform.isWindows).toString(),
            'name': p.basename(folder),
          },
      ],
    });
  }

  void _send(Map<String, Object?> message) {
    if (_disposed) return;
    final body = utf8.encode(json.encode(message));
    try {
      _process.stdin.add(
        latin1.encode('Content-Length: ${body.length}\r\n\r\n'),
      );
      _process.stdin.add(body);
    } catch (_) {
      // stdin closed (server gone) — ignore.
    }
  }

  void _notify(String method, [Map<String, Object?>? params]) {
    _send(<String, Object?>{
      'jsonrpc': '2.0',
      'method': method,
      'params': ?params,
    });
  }

  int _request(String method, [Map<String, Object?>? params]) {
    final id = _nextId++;
    _send(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': ?params,
    });
    return id;
  }

  void _respond(Object? id, Object? result) {
    _send(<String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': result});
  }

  /// Open [path] as a priority document, or — if already open — push its latest
  /// on-disk content as a change. Call this for the files the user is actively
  /// editing so their diagnostics surface promptly and stay in sync with disk
  /// edits made by an external editor. No-op for non-`.dart` paths. Safe to
  /// call before the server has initialized (the request is queued).
  void openFile(String path) {
    if (_disposed) return;
    if (!path.endsWith('.dart')) return;
    final norm = p.normalize(path);
    if (!_initialized) {
      if (!_pendingOpens.contains(norm)) _pendingOpens.add(norm);
      return;
    }
    _openOrChange(norm);
  }

  void _openOrChange(String path) {
    final String text;
    try {
      text = File(path).readAsStringSync();
    } catch (_) {
      return; // unreadable/just-deleted — leave the server's last view in place
    }
    final uri = Uri.file(path, windows: Platform.isWindows).toString();
    final existing = _openVersions[path];
    if (existing == null) {
      if (_openVersions.length >= _maxOpenVersions) {
        _openVersions.remove(_openVersions.keys.first); // evict LRU
      }
      _openVersions[path] = 1;
      _notify('textDocument/didOpen', <String, Object?>{
        'textDocument': <String, Object?>{
          'uri': uri,
          'languageId': 'dart',
          'version': 1,
          'text': text,
        },
      });
    } else {
      final version = existing + 1;
      // Remove-then-add moves the entry to the end of insertion order, marking
      // it most-recently-used for the LRU eviction above.
      _openVersions
        ..remove(path)
        ..[path] = version;
      // Full-document sync (the analyzer's default) — replace the whole text.
      _notify('textDocument/didChange', <String, Object?>{
        'textDocument': <String, Object?>{'uri': uri, 'version': version},
        'contentChanges': <Object?>[
          <String, Object?>{'text': text},
        ],
      });
    }
  }

  Future<void> shutdown() async {
    if (_disposed) return;
    _disposed = true;
    _coalesce?.cancel();
    try {
      _request('shutdown');
      _notify('exit');
    } catch (_) {
      /* server may already be gone */
    }
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    try {
      _process.kill();
    } catch (_) {
      /* already dead */
    }
    if (!_diagnostics.isClosed) await _diagnostics.close();
    if (!_stderr.isClosed) await _stderr.close();
  }
}
