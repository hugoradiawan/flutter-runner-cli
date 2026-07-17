import '../app_state.dart';
import 'command.dart';

/// `/vim` (and `:vim` / `:help vim`) — a cheatsheet of the vim bindings the
/// TUI supports, grouped the way vim users think about them.
class VimHelpCommand extends Command {
  @override
  String get name => 'vim';

  @override
  String get summary => 'Vim keybinding cheatsheet';

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    final t = state.visibleTranscript;
    t.system('-- Vim cheatsheet (editor_mode: vim) --');
    for (final (heading, lines) in _sections) {
      t.system(heading);
      for (final line in lines) {
        t.info('  $line');
      }
    }
    return CommandResult.ok;
  }

  static const List<(String, List<String>)> _sections = [
    (
      'Modes',
      [
        'Esc/Ctrl-G normal · i I a A o O insert · v V Ctrl-V visual · R replace',
        ': ex command · / ? search · Esc on empty prompt = transcript scroll mode',
      ],
    ),
    (
      'Motions',
      [
        'h j k l · w W b B e E ge gE · 0 ^ \$ g_ · f F t T {ch} + ; ,',
        'gg G {n}G {n}% · { } · % (bracket) · H M L · Ctrl-D/U/F/B',
        'Counts everywhere: 5j 3w 2fx …',
      ],
    ),
    (
      'Operators',
      [
        'd c y > < gu gU g~ + any motion or text object (dw, ct), dfx, dgg, dG, d/pat, dn)',
        'Doubled = line: dd yy cc guu · counts multiply: 2d3w = 6 words',
        'x X s S D C Y J r{ch} ~ · u undo · Ctrl-R redo · . repeat',
      ],
    ),
    (
      'Text objects',
      ['iw aw iW aW · i( i[ i{ i< ib iB · i" i\' i` · it at · ip ap · is as'],
    ),
    (
      'Visual',
      [
        'v V Ctrl-V · o swap ends · ~ u U case · p paste over · J join · r{ch}',
        'Ctrl-V then I/A: block insert/append',
      ],
    ),
    (
      'Registers & marks',
      [
        '"{a-z} named · "+ "* clipboard · "_ black hole · 0 yank · 1-9 deletes · :reg',
        'm{a-z} set mark · \'{a} `{a} jump · Ctrl-O/Ctrl-I jumplist',
      ],
    ),
    (
      'Search',
      [
        '/ ? regex, smartcase (uppercase = case-sensitive) · n N repeat',
        '* # word under cursor (g* g# partial) · :noh clear highlight',
      ],
    ),
    (
      'Macros',
      [
        'q{a-z} record · q stop · @{a-z} play · @@ repeat · {n}@a',
        'Keys handled before the vim engine (Ctrl-G, Ctrl-T) are not recorded',
      ],
    ),
    (
      'Ex & substitute',
      [
        ':s/pat/rep/g on the input line · ranges: :%s :2,3s :\'<,\'>s (default: cursor line)',
        ':q :h :r :R … alias to slash commands · ZZ quit',
      ],
    ),
    (
      'Frun-specific',
      [
        'Ctrl-G = Esc (reliable on Windows) · gt gT {n}gt switch run tabs',
        'Transcript scroll mode: hjkl v y / n N zz zt zb Ctrl-E/Y · i or q back to prompt',
        'Overlays (diagnostics/isolates/config): j k 5j gg G Ctrl-D/U q /',
      ],
    ),
  ];
}
