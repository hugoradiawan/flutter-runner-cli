import 'dart:ffi';
import 'dart:io';

const int _gmemMoveable = 0x0002;
const int _cfUnicodeText = 13;

typedef _GlobalAllocC = Pointer Function(Uint32, IntPtr);
typedef _GlobalAllocDart = Pointer Function(int, int);
typedef _GlobalLockC = Pointer Function(Pointer);
typedef _GlobalLockDart = Pointer Function(Pointer);
typedef _GlobalUnlockC = Int32 Function(Pointer);
typedef _GlobalUnlockDart = int Function(Pointer);
typedef _GlobalFreeC = Pointer Function(Pointer);
typedef _GlobalFreeDart = Pointer Function(Pointer);

typedef _OpenClipboardC = Int32 Function(IntPtr);
typedef _OpenClipboardDart = int Function(int);
typedef _EmptyClipboardC = Int32 Function();
typedef _EmptyClipboardDart = int Function();
typedef _SetClipboardDataC = IntPtr Function(Uint32, Pointer);
typedef _SetClipboardDataDart = int Function(int, Pointer);
typedef _CloseClipboardC = Int32 Function();
typedef _CloseClipboardDart = int Function();

/// Write [text] to the Windows clipboard as `CF_UNICODETEXT` so UTF-16 code
/// points (including box-drawing characters and emoji) survive a paste in any
/// app, regardless of the current console code page. Returns false on any
/// Win32 failure so the caller can fall back to the legacy `clip.exe` path.
bool windowsSetClipboardUtf16(String text) {
  if (!Platform.isWindows) return false;
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final user32 = DynamicLibrary.open('user32.dll');
    final globalAlloc = kernel32
        .lookupFunction<_GlobalAllocC, _GlobalAllocDart>('GlobalAlloc');
    final globalLock = kernel32
        .lookupFunction<_GlobalLockC, _GlobalLockDart>('GlobalLock');
    final globalUnlock = kernel32
        .lookupFunction<_GlobalUnlockC, _GlobalUnlockDart>('GlobalUnlock');
    final globalFree = kernel32
        .lookupFunction<_GlobalFreeC, _GlobalFreeDart>('GlobalFree');
    final openClipboard = user32
        .lookupFunction<_OpenClipboardC, _OpenClipboardDart>('OpenClipboard');
    final emptyClipboard = user32
        .lookupFunction<_EmptyClipboardC, _EmptyClipboardDart>('EmptyClipboard');
    final setClipboardData = user32.lookupFunction<_SetClipboardDataC,
        _SetClipboardDataDart>('SetClipboardData');
    final closeClipboard = user32
        .lookupFunction<_CloseClipboardC, _CloseClipboardDart>('CloseClipboard');

    final units = text.codeUnits; // UTF-16 code units.
    final byteCount = (units.length + 1) * 2;
    final hMem = globalAlloc(_gmemMoveable, byteCount);
    if (hMem == nullptr) return false;

    final locked = globalLock(hMem);
    if (locked == nullptr) {
      globalFree(hMem);
      return false;
    }
    final dst = locked.cast<Uint16>();
    for (var i = 0; i < units.length; i++) {
      dst[i] = units[i];
    }
    dst[units.length] = 0; // NUL terminator.
    globalUnlock(hMem);

    if (openClipboard(0) == 0) {
      globalFree(hMem);
      return false;
    }
    emptyClipboard();
    final ok = setClipboardData(_cfUnicodeText, hMem) != 0;
    closeClipboard();
    if (!ok) {
      globalFree(hMem);
      return false;
    }
    // Ownership transferred to clipboard — do NOT GlobalFree on success.
    return true;
  } catch (_) {
    return false;
  }
}
