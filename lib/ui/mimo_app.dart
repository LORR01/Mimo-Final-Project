import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../domain/models.dart';
import '../state/mimo_store.dart';
import 'design.dart';
import 'chord_keyboard.dart';
import '../data/tailscale_bridge.dart';
part 'screens.dart';
part 'sheets.dart';

class MimoApp extends StatelessWidget {
  const MimoApp({super.key, required this.store});
  final MimoStore store;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => MaterialApp(
      title: 'Mimo · Flutter Prototype',
      debugShowCheckedModeBanner: false,
      theme: mimoTheme(Brightness.light),
      darkTheme: mimoTheme(Brightness.dark),
      themeMode: store.theme == 'system'
          ? ThemeMode.system
          : store.theme == 'light'
          ? ThemeMode.light
          : ThemeMode.dark,
      home: MimoShell(store: store),
    ),
  );
}

class MimoShell extends StatefulWidget {
  const MimoShell({super.key, required this.store});
  final MimoStore store;
  @override
  State<MimoShell> createState() => _MimoShellState();
}

class _MimoShellState extends State<MimoShell> with WidgetsBindingObserver {
  bool _waitingForTailscale = false;
  bool _networkSheetOpen = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForTailscale) {
      _waitingForTailscale = false;
      if (_networkSheetOpen) {
        unawaited(_loadNetwork());
      } else {
        unawaited(_resumeTailscale());
      }
    }
  }

  Future<void> _resumeTailscale() async {
    await _discoverySheet();
  }

  Future<void> _loadNetwork() async {
    if (s.liveConnected && !s.connectingAgent) {
      await s.searchDevices('live');
    } else {
      await s.connectAgent();
    }
    if (!mounted || !s.liveConnected) return;
    s.username = 'MIMO';
    s.navigate(DemoScreen.devices);
  }

  Future<void> _beginTailscale() async {
    if (!s.liveMode) {
      await _loginSheet();
      return;
    }
    if (s.liveConnected) {
      s.navigate(DemoScreen.devices);
      await _discoverySheet();
      return;
    }
    if (TailscaleBridge.isAndroid) {
      try {
        if (!await TailscaleBridge.installed()) {
          if (!mounted) return;
          await _sheet<void>(
            'ติดตั้ง Tailscale',
            Column(
              children: [
                const Text(
                  'ติดตั้ง Tailscale และเข้าสู่บัญชีเดียวกับ PC ก่อน Mimo จะไม่เก็บรหัสผ่าน Tailscale',
                ),
                FilledButton(
                  onPressed: TailscaleBridge.installPage,
                  child: const Text('เปิดหน้าติดตั้ง Tailscale'),
                ),
              ],
            ),
          );
          return;
        }
        _waitingForTailscale = true;
        await TailscaleBridge.open();
        return;
      } catch (_) {
        _waitingForTailscale = false;
        toast('เปิด Tailscale ไม่ได้ กรุณาเปิดแอป Tailscale จากโทรศัพท์');
      }
    }
    await _resumeTailscale();
  }

  MimoStore get s => widget.store;
  void toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onboarding =
        s.screen == DemoScreen.splash || s.screen == DemoScreen.loading;
    return Scaffold(
      body: CustomPaint(
        painter: GridPainter(Theme.of(context).brightness == Brightness.dark),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  if (!onboarding) _header(),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: onboarding
                              ? _onboarding()
                              : SingleChildScrollView(
                                  key: ValueKey(s.screen),
                                  padding: EdgeInsets.fromLTRB(
                                    MediaQuery.sizeOf(context).width < 360
                                        ? 24
                                        : 28,
                                    18,
                                    MediaQuery.sizeOf(context).width < 360
                                        ? 24
                                        : 28,
                                    100,
                                  ),
                                  child: _page(),
                                ),
                        ),
                        if (!onboarding)
                          Positioned(
                            left: 28,
                            right: 28,
                            bottom: 16,
                            child: _navigation(),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => LayoutBuilder(
    builder: (context, constraints) {
      final height = (constraints.maxWidth * .509).clamp(168.0, 214.0),
          side = constraints.maxWidth < 360 ? 26.0 : 38.0;
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: art('room-header-original.png', fit: BoxFit.cover),
              ),
              Positioned(
                left: side,
                right: side,
                top: 32,
                child: Row(
                  children: [
                    art('profile-original.png', width: 38, height: 38),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'HELLO! ${s.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: coral,
                            ),
                          ),
                          const Text(
                            "Let's start your day",
                            style: TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Settings',
                      onPressed: () => s.navigate(DemoScreen.theme),
                      icon: art('settings-original.png', width: 24, height: 24),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 40,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Notifications',
                      onPressed: _notificationsSheet,
                      icon: Badge(
                        label: Text('${s.unreadNotifications}'),
                        child: art('bell-original.png', width: 25, height: 28),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 40,
                      ),
                    ),
                  ],
                ),
              ),
              if (s.screen == DemoScreen.home)
                Positioned(
                  right: side + 8,
                  bottom: -28,
                  width: 122,
                  height: 130,
                  child: IgnorePointer(
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        maxHeight: 180,
                        child: art(
                          'mimo-peeking-original.png',
                          width: 122,
                          height: 180,
                          fit: BoxFit.fitWidth,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: side,
                right: side,
                bottom: 18,
                height: 44,
                child: Builder(
                  builder: (buttonContext) => Material(
                    color: Colors.white.withValues(alpha: .24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                      side: BorderSide(
                        color: Colors.brown.withValues(alpha: .4),
                      ),
                    ),
                    child: InkWell(
                      key: const Key('device-switcher'),
                      onTap: () => _deviceMenu(buttonContext),
                      borderRadius: BorderRadius.circular(7),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            StatusDot(s.active?.canOperate ?? false),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                s.active?.displayName ?? 'ยังไม่มีอุปกรณ์',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.white,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  Future<void> _deviceMenu(BuildContext anchor) async {
    final box = anchor.findRenderObject()! as RenderBox,
        overlay = Overlay.of(anchor).context.findRenderObject()! as RenderBox;
    final point = box.localToGlobal(Offset.zero, ancestor: overlay);
    final id = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        point.dx,
        point.dy + box.size.height + 8,
        overlay.size.width - point.dx - box.size.width,
        0,
      ),
      constraints: BoxConstraints.tightFor(width: box.size.width),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: coral),
      ),
      items: [
        const PopupMenuItem<String>(
          enabled: false,
          height: 28,
          child: Text(
            'เลือกอุปกรณ์ (SELECT DEVICE)',
            style: TextStyle(fontSize: 9),
          ),
        ),
        if (s.visibleDevices.isEmpty)
          const PopupMenuItem<String>(
            value: '__add',
            child: Text('เพิ่มอุปกรณ์'),
          ),
        ...s.visibleDevices.map(
          (d) => PopupMenuItem<String>(
            value: d.id,
            child: Row(
              children: [
                StatusDot(d.canOperate),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.displayName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${d.machine.os} · ${d.machine.ip}\nTailscale ${d.machine.online ? 'ออนไลน์' : 'ออฟไลน์'} · Agent ${d.agentLabel}',
                        style: const TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ),
                if (d.id == s.activeDeviceId)
                  const Icon(Icons.check, color: coral, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
    if (id == '__add') {
      if (mounted) _discoverySheet();
    } else if (id != null) {
      s.selectDevice(id);
    }
  }

  Widget _navigation() {
    const tabs = [
      DemoScreen.home,
      DemoScreen.status,
      DemoScreen.keys,
      DemoScreen.devices,
      DemoScreen.clipboard,
      DemoScreen.theme,
    ];
    const icons = [
      Icons.home_outlined,
      Icons.bar_chart,
      Icons.grid_view_outlined,
      Icons.devices_outlined,
      Icons.content_paste_outlined,
      Icons.brush_outlined,
    ];
    const labels = ['Home', 'Status', 'Keys', 'Devices', 'Clip', 'Theme'];
    return Container(
      height: 48,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: coral,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final selected =
              s.screen == tabs[index] ||
              (s.screen == DemoScreen.files &&
                  tabs[index] == DemoScreen.devices);
          return Expanded(
            flex: selected ? 2 : 1,
            child: Tooltip(
              message: labels[index],
              child: InkWell(
                key: Key('nav-${tabs[index].name}'),
                onTap: () => s.navigate(tabs[index]),
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xff221e1e) : null,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icons[index],
                        size: 18,
                        color: selected ? coral : const Color(0xff221e1e),
                      ),
                      if (selected) ...[
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            labels[index],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: coral,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _onboarding() {
    final loading = s.screen == DemoScreen.loading;
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        child: SizedBox(
          height: c.maxHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: art(
                  loading ? 'mimo-sweating.png' : 'mimo-waving.png',
                  width: 220,
                  height: 240,
                ),
              ),
              const SizedBox(height: 24),
              if (loading)
                const Text(
                  'LOADING...',
                  style: TextStyle(
                    color: coral,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else ...[
                art('mimo-logo.png', width: 200, height: 90),
                const SizedBox(height: 44),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('get-started'),
                      onPressed: s.connectingAgent ? null : _beginTailscale,
                      child: Text(
                        s.connectingAgent
                            ? 'กำลังเชื่อม Tailscale…'
                            : s.liveMode
                            ? 'เข้าสู่ระบบด้วย Tailscale'
                            : 'Get Started',
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _page() {
    if (s.visibleDevices.isEmpty && s.screen != DemoScreen.theme) {
      return _emptyDevices();
    }
    final content = switch (s.screen) {
      DemoScreen.home => _home(),
      DemoScreen.status => s.selectedMetric == null ? _status() : _focus(),
      DemoScreen.keys => _keys(),
      DemoScreen.devices => _devices(),
      DemoScreen.clipboard => _clipboard(),
      DemoScreen.theme => _theme(),
      DemoScreen.files => _files(),
      _ => const SizedBox.shrink(),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (s.liveMode) _connectionCard(),
        if (s.storageWarning != null)
          Text(
            s.storageWarning!,
            style: const TextStyle(color: coral, fontSize: 10),
          ),
        if (s.blockedReason.isNotEmpty && s.screen != DemoScreen.theme)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '${s.blockedReason} · ส่งไฟล์หรือคำสั่งไม่ได้',
              style: const TextStyle(fontSize: 10, color: coral),
            ),
          ),
        content,
      ],
    );
  }

  Widget _emptyDevices() => Panel(
    child: Column(
      children: [
        if (s.liveMode) ...[
          Text(
            s.liveConnected
                ? 'เชื่อมต่อ Mimo Agent แล้ว'
                : 'ค้นหา PC ในเครือข่าย Tailscale',
            textAlign: TextAlign.center,
            style: const TextStyle(color: coral, fontSize: 12),
          ),
          TextButton(
            onPressed: _connectAgentSheet,
            child: Text(
              s.liveConnected
                  ? 'เปลี่ยนการเชื่อมต่อ'
                  : 'ค้นหาเครื่องใน Tailscale',
            ),
          ),
        ],
        art('mimo-shy-original.png', height: 100),
        const Text(
          'ยังไม่มีอุปกรณ์ใน Mimo',
          style: TextStyle(
            color: coral,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'ค้นหาเครื่องผ่าน Tailscale แล้วตั้งชื่อแสดง',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _discoverySheet,
          child: const Text('เพิ่มอุปกรณ์'),
        ),
      ],
    ),
  );
  Future<void> _pickFile() async {
    final target = s.active;
    if (target == null || !s.canSendFiles) {
      toast(s.fileBlockedReason);
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        withData: false,
        withReadStream: s.liveMode,
        allowMultiple: false,
      );
      if (result == null) return;
      final file = result.files.single;
      if (s.liveMode && file.size > 100 * 1024 * 1024) {
        toast('ไฟล์ต้องมีขนาดไม่เกิน 100 MB');
        return;
      }
      if (s.liveMode) {
        final stream =
            file.readStream ??
            (file.bytes == null ? null : Stream.value(file.bytes!));
        if (stream == null) {
          toast('อ่านไฟล์ไม่ได้ กรุณาเลือกไฟล์อีกครั้ง');
          return;
        }
        final sent = await s.sendRealFile(
          deviceId: target.id,
          name: file.name,
          size: file.size,
          bytes: stream,
        );
        toast(
          sent.done
              ? 'ส่ง ${file.name} ไปที่ ${target.displayName} แล้ว'
              : sent.error!,
        );
        return;
      }
      final transfer = s.sendFile(
        name: file.name,
        size: file.size,
        deviceId: target.id,
      );
      toast(
        transfer == null
            ? '${s.visibleDevices.where((d) => d.id == target.id).firstOrNull?.blockedReason ?? 'เครื่องถูกลบจาก Mimo'} · ส่งไฟล์ไม่ได้'
            : 'ตัวอย่าง: ส่ง ${file.name} ไปยัง ${target.displayName}',
      );
    } catch (_) {
      toast('เปิดตัวเลือกไฟล์ไม่ได้ กรุณาลองใหม่');
    }
  }

  Widget _filePicker() => Column(
    children: [
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          key: const Key('choose-file'),
          onPressed: s.canSendFiles ? _pickFile : null,
          icon: const Icon(Icons.upload_file, size: 20),
          label: const Text('เลือกไฟล์ที่จะส่ง'),
        ),
      ),
      Text(
        s.liveMode
            ? s.fileBlockedReason
            : s.blockedReason.isEmpty
            ? 'ส่งไปยัง ${s.active?.displayName}'
            : s.blockedReason,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 10, color: coral),
      ),
    ],
  );

  Widget _connectionCard() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.dataSourceLabel,
            style: const TextStyle(color: coral, fontSize: 10),
          ),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _connectAgentSheet,
                  child: Text(
                    s.liveConnected
                        ? 'เลือกเครื่องใน Tailscale'
                        : 'ค้นหาเครื่องใน Tailscale',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'อ่านข้อมูลใหม่',
                onPressed: s.liveConnected ? () => s.refreshLive() : null,
                icon: const Icon(Icons.refresh, size: 18),
              ),
              if (s.liveConnected)
                IconButton(
                  tooltip: 'ยกเลิกการเชื่อมต่อ',
                  onPressed: s.disconnectAgent,
                  icon: const Icon(Icons.link_off, size: 18),
                ),
            ],
          ),
        ],
      ),
    ),
  );
  Widget _transferHistory() => Column(
    children: s.activeTransfers
        .map(
          (t) => Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Panel(
              child: Row(
                children: [
                  const Icon(Icons.file_present_outlined, color: coral),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.name,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${t.size} B · ส่งไปยัง ${s.active?.displayName}\n${t.done ? 'ส่งเสร็จแล้ว' : t.error ?? 'กำลังส่ง…'}',
                          style: const TextStyle(fontSize: 10),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: t.error != null
                              ? 0
                              : t.done
                              ? 1
                              : s.liveMode
                              ? t.progress
                              : .45,
                          color: coral,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        )
        .toList(),
  );
}
