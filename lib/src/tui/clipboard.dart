import 'dart:io';

/// Copy [text] to the OS clipboard via pbcopy / wl-copy / xclip.
///
/// Returns true if any binary accepted the text with exit code 0. SSH sessions
/// without a local clipboard helper return false — caller should warn the user.
Future<bool> copyToClipboard(String text) async {
  final candidates = <List<String>>[
    if (Platform.isMacOS) ['pbcopy'],
    if (Platform.isLinux) ...[
      ['wl-copy'],
      ['xclip', '-selection', 'clipboard'],
      ['xsel', '--clipboard', '--input'],
    ],
    if (Platform.isWindows) ['clip.exe'],
  ];

  for (final argv in candidates) {
    try {
      final p = await Process.start(argv.first, argv.skip(1).toList());
      p.stdin.write(text);
      await p.stdin.close();
      final code = await p.exitCode;
      if (code == 0) return true;
    } catch (_) {
      // try next candidate
    }
  }
  return false;
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
