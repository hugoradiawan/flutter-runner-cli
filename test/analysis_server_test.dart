import 'dart:convert';

import 'package:frun/src/data/datasources/analysis_server.dart';
import 'package:frun/src/data/models/diagnostic.dart';
import 'package:test/test.dart';

List<int> _frame(Map<String, Object?> msg) {
  final body = utf8.encode(json.encode(msg));
  return <int>[
    ...latin1.encode('Content-Length: ${body.length}\r\n\r\n'),
    ...body,
  ];
}

Map<String, Object?> _publish(String uri, List<Map<String, Object?>> diags) =>
    <String, Object?>{
      'jsonrpc': '2.0',
      'method': 'textDocument/publishDiagnostics',
      'params': <String, Object?>{'uri': uri, 'diagnostics': diags},
    };

Map<String, Object?> _diag(
  int severity,
  int line,
  int char,
  String message, {
  String? code,
}) =>
    <String, Object?>{
      'severity': severity,
      'range': <String, Object?>{
        'start': <String, Object?>{'line': line, 'character': char},
        'end': <String, Object?>{'line': line, 'character': char + 1},
      },
      'message': message,
      if (code != null) 'code': code,
    };

void main() {
  group('LspMessageFramer', () {
    test('decodes a single framed message', () {
      final framer = LspMessageFramer();
      final msgs = framer.addBytes(_frame(_publish('file:///C:/x.dart', [])));
      expect(msgs, hasLength(1));
      expect(msgs.first['method'], 'textDocument/publishDiagnostics');
    });

    test('reassembles a message split across chunks', () {
      final framer = LspMessageFramer();
      final bytes = _frame(_publish('file:///C:/x.dart', []));
      final cut = bytes.length ~/ 2;
      expect(framer.addBytes(bytes.sublist(0, cut)), isEmpty);
      expect(framer.addBytes(bytes.sublist(cut)), hasLength(1));
    });

    test('decodes two back-to-back messages in one chunk', () {
      final framer = LspMessageFramer();
      final bytes = <int>[
        ..._frame(_publish('file:///C:/a.dart', [])),
        ..._frame(_publish('file:///C:/b.dart', [])),
      ];
      expect(framer.addBytes(bytes), hasLength(2));
    });
  });

  group('parsePublishDiagnostics', () {
    test('maps severities and 0-based positions to 1-based', () {
      final parsed = parsePublishDiagnostics(<String, Object?>{
        'uri': 'file:///C:/proj/lib/main.dart',
        'diagnostics': <Map<String, Object?>>[
          _diag(1, 5, 2, 'err'),
          _diag(2, 0, 0, 'warn'),
          _diag(3, 9, 3, 'info', code: 'todo'),
          _diag(4, 1, 1, 'hint'),
        ],
      })!;
      expect(
        parsed.map((d) => d.severity).toList(),
        <DiagnosticSeverity>[
          DiagnosticSeverity.error,
          DiagnosticSeverity.warning,
          DiagnosticSeverity.info,
          DiagnosticSeverity.info, // hint folds into info
        ],
      );
      expect(parsed.first.line, 6); // 5 + 1
      expect(parsed.first.column, 3); // 2 + 1
      expect(parsed[2].code, 'todo');
    });

    test('returns null for non-file URIs', () {
      final parsed = parsePublishDiagnostics(<String, Object?>{
        'uri': 'untitled:Untitled-1',
        'diagnostics': <Object?>[],
      });
      expect(parsed, isNull);
    });
  });

  group('applyPublishDiagnostics', () {
    test('adds a file then clears it on an empty array', () {
      final byUri = <String, List<Diagnostic>>{};
      applyPublishDiagnostics(
        byUri,
        _publish('file:///C:/x.dart', <Map<String, Object?>>[
          _diag(1, 0, 0, 'boom'),
        ])['params']! as Map<String, Object?>,
      );
      expect(byUri, hasLength(1));

      applyPublishDiagnostics(
        byUri,
        _publish('file:///C:/x.dart', [])['params']! as Map<String, Object?>,
      );
      expect(byUri, isEmpty);
    });
  });
}
