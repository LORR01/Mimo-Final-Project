import 'package:flutter/material.dart';

const coral = Color(0xfff76d4d),
    cpuColor = Color(0xffde7f6d),
    gpuColor = Color(0xffe2883a),
    ramColor = Color(0xff5ea4b0),
    tempColor = Color(0xfff0c040);
Color metricColor(String id) => id == 'cpu'
    ? cpuColor
    : id == 'gpu'
    ? gpuColor
    : id == 'ram'
    ? ramColor
    : tempColor;
IconData metricIcon(String id) => id == 'cpu'
    ? Icons.memory_outlined
    : id == 'gpu'
    ? Icons.desktop_windows_outlined
    : id == 'ram'
    ? Icons.storage_outlined
    : Icons.thermostat_outlined;
ThemeData mimoTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    splashFactory: InkRipple.splashFactory,
    brightness: brightness,
    fontFamily: 'Poppins',
    fontFamilyFallback: const ['NotoSansThai'],
    scaffoldBackgroundColor: dark
        ? const Color(0xff191616)
        : const Color(0xffffedc7),
    colorScheme: ColorScheme.fromSeed(
      seedColor: coral,
      brightness: brightness,
      surface: dark ? const Color(0xff221e1e) : Colors.white,
      primary: coral,
    ),
    textTheme: ThemeData(brightness: brightness).textTheme.apply(
      fontFamily: 'Poppins',
      fontFamilyFallback: const ['NotoSansThai'],
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: coral,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontFamilyFallback: ['NotoSansThai'],
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: coral,
        side: const BorderSide(color: coral),
        textStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontFamilyFallback: ['NotoSansThai'],
          fontSize: 11,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xff221e1e) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.all(14),
    ),
  );
}

Widget art(
  String name, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.contain,
}) => Image.asset(
  'assets/art/$name',
  width: width,
  height: height,
  fit: fit,
  filterQuality: FilterQuality.high,
);
Widget heading(String title, {String? subtitle}) => Padding(
  padding: const EdgeInsets.only(bottom: 16),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: coral,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
      if (subtitle != null)
        Text(subtitle, style: const TextStyle(fontSize: 10)),
    ],
  ),
);
Widget number(String value, {double size = 34, Color? color}) => Text(
  value,
  style: TextStyle(
    fontFamily: 'MimoDisplay',
    fontWeight: FontWeight.w700,
    fontSize: size,
    color: color,
    height: 1.15,
  ),
);

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.color,
    this.outline = true,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final Color? color;
  final bool outline;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: outline ? Border.all(color: coral) : null,
    ),
    child: child,
  );
}

class StatusDot extends StatelessWidget {
  const StatusDot(this.online, {super.key});
  final bool online;
  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: online ? Colors.lightGreenAccent : Colors.grey,
      boxShadow: online
          ? [const BoxShadow(color: Colors.lightGreenAccent, blurRadius: 7)]
          : null,
    ),
  );
}

class GridPainter extends CustomPainter {
  GridPainter(this.dark);
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = (dark ? Colors.white : Colors.brown).withValues(alpha: .045)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(GridPainter old) => dark != old.dark;
}
