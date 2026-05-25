import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// Win32 constants for SetConsoleMode.
const int _stdInputHandle = 0xFFFFFFF6; // -10 as unsigned
const int _enableProcessedInput = 0x0001;
const int _enableLineInput = 0x0002;
const int _enableEchoInput = 0x0004;
const int _enableWindowInput = 0x0008;
const int _enableMouseInput = 0x0010;
const int _enableQuickEditMode = 0x0040;
const int _enableExtendedFlags = 0x0080;
const int _enableVirtualTerminalInput = 0x0200;

typedef _GetStdHandleC = IntPtr Function(Uint32);
typedef _GetStdHandleDart = int Function(int);

typedef _GetConsoleModeC = Int32 Function(IntPtr, Pointer<Uint32>);
typedef _GetConsoleModeDart = int Function(int, Pointer<Uint32>);

typedef _SetConsoleModeC = Int32 Function(IntPtr, Uint32);
typedef _SetConsoleModeDart = int Function(int, int);

/// Disables QuickEdit Mode on the Windows console host so the TUI receives
/// mouse-click, mouse-motion, mouse-release and mouse-wheel SGR events. Also
/// enables ENABLE_MOUSE_INPUT and ENABLE_VIRTUAL_TERMINAL_INPUT.
///
/// Returns a callback that restores the original console mode (call it on
/// exit so the user's QuickEdit / line-input preferences are not stranded).
/// No-op on non-Windows platforms or if any Win32 call fails.
void Function() prepareWindowsConsoleForMouse() {
  if (!Platform.isWindows) return _noopRestore;
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final getStdHandle =
        kernel32.lookupFunction<_GetStdHandleC, _GetStdHandleDart>(
            'GetStdHandle');
    final getConsoleMode =
        kernel32.lookupFunction<_GetConsoleModeC, _GetConsoleModeDart>(
            'GetConsoleMode');
    final setConsoleMode =
        kernel32.lookupFunction<_SetConsoleModeC, _SetConsoleModeDart>(
            'SetConsoleMode');

    final hIn = getStdHandle(_stdInputHandle);
    if (hIn == 0) return _noopRestore;

    final pMode = calloc<Uint32>();
    try {
      if (getConsoleMode(hIn, pMode) == 0) return _noopRestore;
      final originalMode = pMode.value;
      var mode = originalMode;
      // ENABLE_EXTENDED_FLAGS must be set for the QUICK_EDIT_MODE clear to
      // stick on legacy console hosts.
      mode |= _enableExtendedFlags;
      mode &= ~_enableQuickEditMode;
      mode |= _enableMouseInput;
      mode |= _enableVirtualTerminalInput;
      // dart_tui drives raw input via stdin.lineMode/echoMode setters; make
      // sure cooked-mode flags stay cleared in case Dart restores them.
      mode &= ~_enableLineInput;
      mode &= ~_enableEchoInput;
      mode &= ~_enableProcessedInput;
      mode &= ~_enableWindowInput;
      setConsoleMode(hIn, mode);
      return () {
        try {
          setConsoleMode(hIn, originalMode);
        } catch (_) {}
      };
    } finally {
      calloc.free(pMode);
    }
  } catch (_) {
    // Best-effort — never crash boot if Win32 isn't reachable.
    return _noopRestore;
  }
}

void _noopRestore() {}
