import 'package:frun/src/app/link_extractor.dart';
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

  test('ignores non-dart references', () {
    final links = LinkExtractor.extract('see README.md:10 for details');
    expect(links, isEmpty);
  });
}
