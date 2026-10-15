import 'package:flutter/material.dart';
import '../domain/shortcuts.dart';
import 'design.dart';

class ChordKeyboard extends StatefulWidget {
  const ChordKeyboard({super.key, required this.onConfirmed});
  final ValueChanged<List<String>> onConfirmed;
  @override
  State<ChordKeyboard> createState() => _ChordKeyboardState();
}

class _ChordKeyboardState extends State<ChordKeyboard> {
  final selected = <String>{};
  final horizontal = ScrollController();
  String? error;
  static const rows = [
    [
      'Esc',
      'F1',
      'F2',
      'F3',
      'F4',
      'F5',
      'F6',
      'F7',
      'F8',
      'F9',
      'F10',
      'F11',
      'F12',
    ],
    [
      '`',
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '0',
      '-',
      '=',
      'Backspace',
    ],
    ['Tab', 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '[', ']', '\\'],
    [
      'CapsLock',
      'A',
      'S',
      'D',
      'F',
      'G',
      'H',
      'J',
      'K',
      'L',
      ';',
      "'",
      'Enter',
    ],
    ['Z', 'X', 'C', 'V', 'B', 'N', 'M', ',', '.', '/', 'Up', 'Delete'],
    ['Space', 'Left', 'Down', 'Right', 'Home', 'End'],
    [
      'Insert',
      'PageUp',
      'PageDown',
      'PrintScreen',
      'MediaPlayPause',
      'VolumeMute',
      'VolumeDown',
      'VolumeUp',
    ],
  ];
  @override
  void dispose() {
    horizontal.dispose();
    super.dispose();
  }

  void toggle(String key) {
    setState(() {
      error = null;
      if (!selected.remove(key)) {
        if (selected.length >= 6) {
          error = 'เลือกได้สูงสุด 6 ปุ่ม';
          return;
        }
        selected.add(key);
      }
    });
  }

  Widget keyButton(String key, {double? width}) => Padding(
    padding: const EdgeInsets.all(2),
    child: SizedBox(
      width: width ?? (key.length > 3 ? 74 : 44),
      height: 44,
      child: Material(
        color: selected.contains(key) ? coral : const Color(0xff292525),
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          key: ValueKey('chord-$key'),
          onTap: () => toggle(key),
          borderRadius: BorderRadius.circular(7),
          child: Semantics(
            selected: selected.contains(key),
            button: true,
            label: key,
            child: Center(
              child: Text(
                key,
                style: const TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        selected.isEmpty ? 'แตะเลือกปุ่มที่ต้องการ' : selected.join(' + '),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      const Text(
        'เลือกทีละปุ่ม · แตะซ้ำเพื่อยกเลิก แล้วกดยืนยัน',
        style: TextStyle(fontSize: 11),
      ),
      const SizedBox(height: 12),
      SingleChildScrollView(
        controller: horizontal,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 860,
          child: Column(
            children: [
              for (final row in rows)
                Row(children: [for (final key in row) keyButton(key)]),
            ],
          ),
        ),
      ),
      Row(
        children: [
          for (final key in modifierKeys)
            Expanded(child: keyButton(key, width: double.infinity)),
        ],
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'คีย์ด้านซ้าย',
            onPressed: () => horizontal.jumpTo(
              (horizontal.offset - 200).clamp(
                0,
                horizontal.position.maxScrollExtent,
              ),
            ),
            icon: const Icon(Icons.chevron_left),
          ),
          const Text('เลื่อนแป้นคีย์', style: TextStyle(fontSize: 10)),
          IconButton(
            tooltip: 'คีย์ด้านขวา',
            onPressed: () => horizontal.jumpTo(
              (horizontal.offset + 200).clamp(
                0,
                horizontal.position.maxScrollExtent,
              ),
            ),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      if (error != null)
        Text(error!, style: const TextStyle(fontSize: 11, color: Colors.red)),
      Row(
        children: [
          TextButton(
            onPressed: () => setState(() {
              selected.clear();
              error = null;
            }),
            child: const Text('ล้างทั้งหมด'),
          ),
          const Spacer(),
          FilledButton(
            key: const Key('confirm-chord'),
            onPressed: selected.isEmpty
                ? null
                : () {
                    try {
                      widget.onConfirmed(normalizeChord(selected));
                    } on FormatException catch (e) {
                      setState(() => error = e.message);
                    }
                  },
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    ],
  );
}
