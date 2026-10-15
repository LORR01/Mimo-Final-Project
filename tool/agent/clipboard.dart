import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

class ClipboardItem {
  const ClipboardItem({
    required this.type,
    required this.text,
    this.name,
    this.bytes,
  });
  final String type, text;
  final String? name;
  final Uint8List? bytes;
}

class ClipboardBatch {
  const ClipboardBatch(this.version, this.items);
  final String version;
  final List<ClipboardItem> items;
}

abstract class ClipboardSource {
  Future<ClipboardBatch?> read();
}

/// Read-only Windows clipboard adapter: Unicode, HTML tables, bitmap and copied
/// files. File contents are bounded and copied into expiring Agent memory.
class WindowsClipboardSource implements ClipboardSource {
  String? _lastVersion;
  @override
  Future<ClipboardBatch?> read() async {
    if (!Platform.isWindows) throw UnsupportedError('Windows only');
    final user = DynamicLibrary.open('user32.dll');
    final kernel = DynamicLibrary.open('kernel32.dll');
    final sequence = user.lookupFunction<Uint32 Function(), int Function()>(
      'GetClipboardSequenceNumber',
    );
    final version = sequence().toString();
    if (version == _lastVersion) return null;
    final open = user.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'OpenClipboard',
    );
    final close = user.lookupFunction<Int32 Function(), int Function()>(
      'CloseClipboard',
    );
    final get = user
        .lookupFunction<
          Pointer<Void> Function(Uint32),
          Pointer<Void> Function(int)
        >('GetClipboardData');
    final register = user
        .lookupFunction<
          Uint32 Function(Pointer<Utf16>),
          int Function(Pointer<Utf16>)
        >('RegisterClipboardFormatW');
    final lock = kernel
        .lookupFunction<
          Pointer<Uint8> Function(Pointer<Void>),
          Pointer<Uint8> Function(Pointer<Void>)
        >('GlobalLock');
    final unlock = kernel
        .lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('GlobalUnlock');
    final size = kernel
        .lookupFunction<
          UintPtr Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('GlobalSize');
    Uint8List? format(int code) {
      final handle = get(code);
      if (handle == nullptr) return null;
      final length = size(handle);
      if (length <= 0 || length > 20 * 1024 * 1024) return null;
      final pointer = lock(handle);
      if (pointer == nullptr) return null;
      try {
        return Uint8List.fromList(pointer.asTypedList(length));
      } finally {
        unlock(handle);
      }
    }

    Uint8List? named(String name) {
      final pointer = name.toNativeUtf16();
      try {
        return format(register(pointer));
      } finally {
        calloc.free(pointer);
      }
    }

    if (open(0) == 0) throw const FileSystemException('Clipboard busy');
    final items = <ClipboardItem>[];
    final files = <String>[];
    try {
      final textBytes = format(13);
      var text = '';
      if (textBytes != null && textBytes.length <= 1024 * 1024) {
        final units = textBytes.buffer.asUint16List(0, textBytes.length ~/ 2);
        final end = units.indexOf(0);
        if (end >= 0) text = String.fromCharCodes(units.take(end));
      }
      final htmlBytes = named('HTML Format');
      final html = htmlBytes == null
          ? ''
          : utf8.decode(htmlBytes, allowMalformed: true);
      if (html.toLowerCase().contains('<table')) {
        // Store an attachment, never render untrusted HTML as executable content.
        items.add(
          ClipboardItem(
            type: 'spreadsheet',
            text: text.isEmpty ? 'ตารางที่คัดลอก' : text,
            name: 'clipboard-table.html',
            bytes: htmlBytes,
          ),
        );
      } else if (text.contains('\t') && text.contains('\n')) {
        items.add(
          ClipboardItem(
            type: 'spreadsheet',
            text: text,
            name: 'clipboard-table.tsv',
            bytes: Uint8List.fromList(utf8.encode(text)),
          ),
        );
      } else if (text.isNotEmpty) {
        items.add(
          ClipboardItem(
            type: RegExp(r'^https?://', caseSensitive: false).hasMatch(text)
                ? 'link'
                : 'text',
            text: text,
          ),
        );
      }
      final png = named('PNG');
      if (png != null) {
        items.add(
          ClipboardItem(
            type: 'image',
            text: 'รูปภาพที่คัดลอก',
            name: 'clipboard.png',
            bytes: png,
          ),
        );
      } else {
        final dib = format(8) ?? format(17);
        if (dib != null && dib.length >= 40) {
          final header = ByteData.sublistView(dib);
          final headerSize = header.getUint32(0, Endian.little);
          final bits = header.getUint16(14, Endian.little);
          final compression = header.getUint32(16, Endian.little);
          final colors = header.getUint32(32, Endian.little);
          final palette = colors != 0 ? colors : (bits <= 8 ? 1 << bits : 0);
          final offset =
              14 +
              headerSize +
              palette * 4 +
              (headerSize == 40 && compression == 3 ? 12 : 0);
          if (offset <= dib.length + 14 && headerSize >= 40) {
            final bmp = Uint8List(dib.length + 14)
              ..setRange(14, dib.length + 14, dib);
            final out = ByteData.sublistView(bmp);
            out.setUint16(0, 0x4d42, Endian.little);
            out.setUint32(2, bmp.length, Endian.little);
            out.setUint32(10, offset, Endian.little);
            items.add(
              ClipboardItem(
                type: 'image',
                text: 'รูปภาพที่คัดลอก',
                name: 'clipboard.bmp',
                bytes: bmp,
              ),
            );
          }
        }
      }
      final drop = get(15); // CF_HDROP
      if (drop != nullptr) {
        final query = DynamicLibrary.open('shell32.dll')
            .lookupFunction<
              Uint32 Function(Pointer<Void>, Uint32, Pointer<Utf16>, Uint32),
              int Function(Pointer<Void>, int, Pointer<Utf16>, int)
            >('DragQueryFileW');
        final count = query(drop, 0xffffffff, nullptr, 0);
        for (var i = 0; i < count && i < 20; i++) {
          final length = query(drop, i, nullptr, 0);
          if (length <= 0 || length > 32767) continue;
          final buffer = calloc<Uint16>(length + 1).cast<Utf16>();
          try {
            query(drop, i, buffer, length + 1);
            files.add(buffer.toDartString());
          } finally {
            calloc.free(buffer);
          }
        }
      }
    } finally {
      close();
    }
    var total = 0;
    for (final path in files) {
      final file = File(path);
      if (!await file.exists()) continue;
      final length = await file.length();
      if (length > 20 * 1024 * 1024 || total + length > 50 * 1024 * 1024) {
        continue;
      }
      final bytes = await file.readAsBytes();
      total += bytes.length;
      if (bytes.length > 20 * 1024 * 1024 || total > 50 * 1024 * 1024) continue;
      final name = path.split(RegExp(r'[/\\]')).last;
      final ext = name.split('.').last.toLowerCase();
      items.add(
        ClipboardItem(
          type: ['png', 'jpg', 'jpeg', 'bmp', 'gif', 'webp'].contains(ext)
              ? 'image'
              : ['csv', 'xls', 'xlsx', 'ods', 'tsv'].contains(ext)
              ? 'spreadsheet'
              : 'document',
          text: name,
          name: name,
          bytes: bytes,
        ),
      );
    }
    if (sequence().toString() != version) return null;
    _lastVersion = version;
    return ClipboardBatch(version, items);
  }
}
