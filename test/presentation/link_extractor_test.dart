import 'package:frun/src/presentation/app/link_extractor.dart';
import 'package:test/test.dart';

void main() {
  test('extracts file:line:col triples', () {
    final links = LinkExtractor.extract(
      'Exception thrown at lib/widgets/foo.dart:42:7 while building',
    );
    expect(links, hasLength(1));
    expect(links.single.uri, 'lib/widgets/foo.dart');
    expect(links.single.line, 42);
    expect(links.single.column, 7);
  });

  test('extracts file:line without column', () {
    final links = LinkExtractor.extract('See lib/main.dart:10 for context');
    expect(links, hasLength(1));
    expect(links.single.column, isNull);
  });

  test('extracts package: URIs', () {
    final links = LinkExtractor.extract(
      'package:flutter/src/widgets/framework.dart:1234:56 ←',
    );
    expect(links, hasLength(1));
    expect(links.single.uri, 'package:flutter/src/widgets/framework.dart');
    expect(links.single.line, 1234);
  });

  test('finds multiple links on one line', () {
    final links = LinkExtractor.extract(
      'a/b.dart:1 then c/d.dart:2:3 and package:e/f.dart:4',
    );
    expect(links, hasLength(3));
  });

  test('keeps the Windows drive letter on absolute paths', () {
    final links = LinkExtractor.extract(
      'widget: C:/Users/me/app/lib/src/chat.page.dart:148:12 built',
    );
    expect(links, hasLength(1));
    expect(links.single.uri, 'C:/Users/me/app/lib/src/chat.page.dart');
    expect(links.single.line, 148);
    expect(links.single.column, 12);
  });

  test('ignores non-dart references', () {
    final links = LinkExtractor.extract('see README.md:10 for details');
    expect(links, isEmpty);
  });

  test('extracts Windows relative paths with backslashes', () {
    final links = LinkExtractor.extract(
      r'test\presentation\foo_test.dart:12:3: some failure',
    );
    expect(links, hasLength(1));
    expect(links.single.uri, r'test\presentation\foo_test.dart');
    expect(links.single.line, 12);
    expect(links.single.column, 3);
  });

  group('pathToFileUri', () {
    test('keeps Windows drive letters out of the URI authority', () {
      expect(
        pathToFileUri(r'C:\Users\me\app\lib\main.dart', r'C:\Users\me\app'),
        'file:///C:/Users/me/app/lib/main.dart',
      );
    });

    test('resolves relative paths against a Windows project root', () {
      final uri = pathToFileUri('lib/main.dart', r'C:\Users\me\app');
      expect(uri, 'file:///C:/Users/me/app/lib/main.dart');
      // Round-trips back to a drive-letter path, not a UNC `\\c\…` host.
      expect(
        Uri.parse(uri).toFilePath(windows: true),
        r'C:\Users\me\app\lib\main.dart',
      );
    });

    test('resolves backslash relative paths against a Windows root', () {
      expect(
        pathToFileUri(r'test\foo_test.dart', r'C:\Users\me\app'),
        'file:///C:/Users/me/app/test/foo_test.dart',
      );
    });

    test('keeps posix behaviour for absolute and relative paths', () {
      expect(
        pathToFileUri('/abs/lib/main.dart', '/home/me/app'),
        'file:///abs/lib/main.dart',
      );
      expect(
        pathToFileUri('lib/main.dart', '/home/me/app'),
        'file:///home/me/app/lib/main.dart',
      );
    });
  });
}
