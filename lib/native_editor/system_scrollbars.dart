import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _GetValueNative = Int32 Function(
  IntPtr,
  Pointer<Utf16>,
  Pointer<Utf16>,
  Uint32,
  Pointer<Uint32>,
  Pointer<Void>,
  Pointer<Uint32>,
);
typedef _GetValue = int Function(
  int,
  Pointer<Utf16>,
  Pointer<Utf16>,
  int,
  Pointer<Uint32>,
  Pointer<Void>,
  Pointer<Uint32>,
);

/// whether the system wants scrollbars to go away when they are not used. Zed
/// asks Windows the same, and with auto it only hides them when the answer is
/// yes: with "automatically hide scroll bars" turned off they stay.
///
/// Windows keeps the setting as the `DynamicScrollbars` value of
/// `HKEY_CURRENT_USER\Control Panel\Accessibility`, which is not there until it
/// is changed, and then it is on. When it cannot be read it is no, as Zed has it.
/// Other systems hide them, which is what they are drawn like there.
bool systemAutoHidesScrollbars() {
  if (!Platform.isWindows) {
    return true;
  }
  try {
    final advapi = DynamicLibrary.open('advapi32.dll');
    final getValue = advapi.lookupFunction<_GetValueNative, _GetValue>(
      'RegGetValueW',
    );
    final key = r'Control Panel\Accessibility'.toNativeUtf16();
    final name = 'DynamicScrollbars'.toNativeUtf16();
    final data = calloc<Uint32>();
    final size = calloc<Uint32>()..value = 4;
    try {
      // HKEY_CURRENT_USER, and only a value that is a DWORD
      const currentUser = 0x80000001;
      const dword = 0x10;
      final status = getValue(
        currentUser,
        key,
        name,
        dword,
        nullptr,
        data.cast(),
        size,
      );
      // ERROR_FILE_NOT_FOUND: never changed, so it is as it is made
      if (status == 2) {
        return true;
      }
      return status == 0 && data.value != 0;
    } finally {
      calloc.free(key);
      calloc.free(name);
      calloc.free(data);
      calloc.free(size);
    }
  } on Object {
    return false;
  }
}
