import 'dart:io';

import 'package:path/path.dart' as p;

/// The user's "working set": absolute paths of `.dart` files with uncommitted
/// changes (staged, unstaged, or untracked) under the git repo at [root].
///
/// These are exactly the files an editor's "Changes"/"Source Control" panel
/// lists — the ones the user is actively editing. `frun` opens them as LSP
/// priority documents so the analyzer reports their diagnostics within seconds;
/// the whole-project background pass over a large monorepo is far too slow to
/// surface a freshly-edited file in time.
///
/// Returns an empty list when git is unavailable or [root] is not a repo —
/// callers degrade gracefully to background-only analysis.
List<String> gitDirtyDartFiles(String root) {
  ProcessResult res;
  try {
    res = Process.runSync(
      'git',
      <String>[
        '-C',
        root,
        // Disable path quoting so non-ASCII filenames come back verbatim.
        '-c',
        'core.quotepath=false',
        'status',
        '--porcelain',
        '--untracked-files=all',
      ],
      runInShell: Platform.isWindows,
    );
  } catch (_) {
    return const <String>[]; // git not on PATH
  }
  if (res.exitCode != 0) return const <String>[]; // not a repo, etc.
  return parseGitPorcelainDartFiles(res.stdout.toString(), root);
}

/// Parse the relative `.dart` paths out of `git status --porcelain` [output]
/// and resolve them to absolute, normalized paths under [root]. Only paths that
/// still exist on disk are returned (a deletion has nothing to analyze).
///
/// Split from [gitDirtyDartFiles] so the porcelain parsing — status prefixes,
/// rename `old -> new` arrows — can be unit-tested without spawning git.
List<String> parseGitPorcelainDartFiles(String output, String root) {
  final out = <String>[];
  for (final raw in output.split('\n')) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    // Porcelain v1 lines are `XY <path>` (two status columns, a space, path).
    if (line.length < 4) continue;
    var rel = line.substring(3).trim();
    if (rel.isEmpty) continue;
    // Renames/copies render as `old -> new`; the new path is what exists.
    final arrow = rel.indexOf(' -> ');
    if (arrow >= 0) rel = rel.substring(arrow + 4).trim();
    if (!rel.endsWith('.dart')) continue;
    final abs = p.normalize(p.join(root, rel));
    if (File(abs).existsSync()) out.add(abs);
  }
  return out;
}
