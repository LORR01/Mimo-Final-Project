import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:mimo_companion/domain/shortcuts.dart';

abstract class KeyExecutor {
  Future<int> send(List<String> keys);
}

final class KeyboardInput extends Struct {
  @Uint16()
  external int key;
  @Uint16()
  external int scan;
  @Uint32()
  external int flags;
  @Uint32()
  external int time;
  external Pointer<Void> extra;
}

final class MouseInput extends Struct {
  @Int32()
  external int x;
  @Int32()
  external int y;
  @Uint32()
  external int mouseData;
  @Uint32()
  external int flags;
  @Uint32()
  external int time;
  external Pointer<Void> extra;
}

final class HardwareInput extends Struct {
  @Uint32()
  external int message;
  @Uint16()
  external int low;
  @Uint16()
  external int high;
}

final class InputData extends Union {
  external KeyboardInput keyboard;
  external MouseInput mouse;
  external HardwareInput hardware;
}

final class NativeInput extends Struct {
  @Uint32()
  external int type;
  external InputData data;
}

class WindowsKeyExecutor implements KeyExecutor {
  WindowsKeyExecutor() {
    if (!Platform.isWindows) throw UnsupportedError('Windows only');
    final library = DynamicLibrary.open('user32.dll');
    _send = library
        .lookupFunction<
          Uint32 Function(Uint32, Pointer<NativeInput>, Int32),
          int Function(int, Pointer<NativeInput>, int)
        >('SendInput');
    _state = library.lookupFunction<Int16 Function(Int32), int Function(int)>(
      'GetAsyncKeyState',
    );
  }
  late final int Function(int, Pointer<NativeInput>, int) _send;
  late final int Function(int) _state;
  bool _busy = false;
  void _fill(NativeInput input, int code, bool release) {
    input.type = 1;
    input.data.keyboard.key = code;
    input.data.keyboard.flags =
        (release ? 2 : 0) |
        ({
              0x21,
              0x22,
              0x23,
              0x24,
              0x25,
              0x26,
              0x27,
              0x28,
              0x2d,
              0x2e,
              0x5b,
              0x2c,
            }.contains(code)
            ? 1
            : 0);
  }

  @override
  Future<int> send(List<String> keys) async {
    final normalized = normalizeChord(keys);
    final codes = normalized.map((k) => virtualKeys[k]!).toList();
    if (_busy) throw const HttpException('มีคำสั่งคีย์ลัดกำลังทำงาน');
    // Do not release or combine with keys the PC user is physically holding.
    if ({
      ...codes,
      0x10,
      0x11,
      0x12,
      0x5b,
      0x5c,
    }.any((code) => _state(code) & 0x8000 != 0)) {
      throw const HttpException('กรุณาปล่อยคีย์บน PC ก่อนส่งคีย์ลัด');
    }
    _busy = true;
    final input = calloc<NativeInput>(codes.length * 2);
    try {
      for (var i = 0; i < codes.length; i++) {
        _fill(input[i], codes[i], false);
        _fill(input[codes.length + i], codes[codes.length - i - 1], true);
      }
      final count = _send(codes.length * 2, input, sizeOf<NativeInput>());
      if (count != codes.length * 2) {
        // Best-effort release if Windows inserted only part of the batch.
        for (var i = 0; i < codes.length; i++) {
          _fill(input[i], codes[codes.length - i - 1], true);
        }
        _send(codes.length, input, sizeOf<NativeInput>());
        throw const HttpException(
          'Windows ไม่รับคีย์ครบ อาจถูก UAC/UIPI หรือหน้าจอล็อกป้องกันไว้',
        );
      }
      return count;
    } finally {
      calloc.free(input);
      _busy = false;
    }
  }
}
