import 'package:dart_tui/dart_tui.dart';

/// One clickable rectangle and the [Msg] to dispatch when the user clicks
/// inside it. Coordinates are in screen cells (origin top-left).
class HitRegion {
  HitRegion({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.msg,
  });

  final int x;
  final int y;
  final int w;
  final int h;
  final Msg msg;

  bool contains(int px, int py) =>
      px >= x && px < x + w && py >= y && py < y + h;
}

/// Per-frame registry: cleared and refilled each `view()` build. Last-added
/// region wins when rectangles overlap (so per-glyph buttons take precedence
/// over a wider tab label drawn first).
class HitRegions {
  final List<HitRegion> _regions = [];

  void clear() => _regions.clear();

  void add({
    required int x,
    required int y,
    required int w,
    required int h,
    required Msg msg,
  }) {
    if (w <= 0 || h <= 0) return;
    _regions.add(HitRegion(x: x, y: y, w: w, h: h, msg: msg));
  }

  /// Returns the most-recently-added region containing the given coordinate,
  /// or null if no region matches.
  Msg? hit(int px, int py) {
    for (var i = _regions.length - 1; i >= 0; i--) {
      if (_regions[i].contains(px, py)) return _regions[i].msg;
    }
    return null;
  }
}
