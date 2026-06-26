import 'dart:convert';
import 'dart:io';

import '../../data/services/windows_clipboard.dart';

/// ANSI CSI escape stripper. Matches `ESC [ ... <final-byte>` where final is
/// `@`..`~`. Used so copied transcript text doesn't carry colour codes into
/// whatever app the user pastes into.
final RegExp _ansiCsi = RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]');

/// OSC sequences `ESC ] ... BEL` (used for hyperlinks etc.).
final RegExp _ansiOsc = RegExp(r'\x1B\][^\x07]*\x07');

String _stripAnsi(String text) =>
    text.replaceAll(_ansiCsi, '').replaceAll(_ansiOsc, '');

/// Copy [text] to the OS clipboard via pbcopy / wl-copy / xclip / Win32.
///
/// Returns true if the platform clipboard accepted the text. SSH sessions
/// without a local clipboard helper return false — caller should warn the user.
Future<bool> copyToClipboard(String text) async {
  final cleaned = _stripAnsi(text);

  if (Platform.isWindows) {
    if (windowsSetClipboardUtf16(cleaned)) return true;
    // Fallback to clip.exe (legacy code-page path — may mojibake non-ASCII).
    return _runCopy(['clip.exe'], cleaned);
  }

  final candidates = <List<String>>[
    if (Platform.isMacOS) ['pbcopy'],
    if (Platform.isLinux) ...[
      ['wl-copy'],
      ['xclip', '-selection', 'clipboard'],
      ['xsel', '--clipboard', '--input'],
    ],
  ];

  for (final argv in candidates) {
    if (await _runCopy(argv, cleaned)) return true;
  }
  return false;
}

Future<bool> _runCopy(List<String> argv, String text) async {
  try {
    final p = await Process.start(argv.first, argv.skip(1).toList());
    p.stdin.encoding = utf8;
    p.stdin.write(text);
    await p.stdin.close();
    final code = await p.exitCode;
    return code == 0;
  } catch (_) {
    return false;
  }
}

/// Read the OS clipboard via pbpaste / wl-paste / xclip / xsel / PowerShell.
/// Returns null when no helper is available or all helpers fail.
Future<String?> pasteFromClipboard() async {
  final candidates = <List<String>>[
    if (Platform.isMacOS) ['pbpaste'],
    if (Platform.isLinux) ...[
      ['wl-paste', '--no-newline'],
      ['xclip', '-selection', 'clipboard', '-o'],
      ['xsel', '--clipboard', '--output'],
    ],
    if (Platform.isWindows)
      ['powershell', '-NoProfile', '-Command', 'Get-Clipboard'],
  ];

  for (final argv in candidates) {
    try {
      final r = await Process.run(argv.first, argv.skip(1).toList());
      if (r.exitCode == 0) return (r.stdout as String?) ?? '';
    } catch (_) {
      // try next candidate
    }
  }
  return null;
}
