part of 'mimo_app.dart';

extension _Screens on _MimoShellState {
  Widget _home() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Panel(
        color: coral,
        outline: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.active!.canOperate ? 'CONNECT' : 'UNAVAILABLE',
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.active!.displayName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    s.active!.canOperate
                        ? (s.liveMode
                              ? 'พร้อมใช้งาน'
                              : 'พร้อมรับคำสั่งตลอดเวลา')
                        : s.blockedReason,
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                  ),
                ],
              ),
            ),
            art('computer-original.png', width: 115, height: 120),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _sectionTitle('SHOW DETAILS', () => s.navigate(DemoScreen.status)),
      Row(
        children: s.metrics
            .take(3)
            .map(
              (m) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    onTap: () => s.focusMetric(m.id),
                    child: Panel(
                      padding: const EdgeInsets.symmetric(
                        vertical: 20,
                        horizontal: 3,
                      ),
                      child: Column(
                        children: [
                          Text(
                            m.label,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          FittedBox(child: number(m.value, size: 27)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 20),
      _sectionTitle('ORDER', _orderSheet),
      if (s.pinnedButtons.isEmpty)
        const Panel(
          child: Text(
            'ปักหมุดปุ่มจากหน้า Keys เพื่อแสดงที่นี่ · สูงสุด 4 ปุ่ม',
            style: TextStyle(fontSize: 12),
          ),
        ),
      Row(
        children: [
          for (final b in s.pinnedButtons.take(2))
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _orderCard(b),
              ),
            ),
        ],
      ),
    ],
  );
  Widget _sectionTitle(String title, VoidCallback onMore) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      InkWell(
        onTap: onMore,
        child: Text(
          title,
          style: const TextStyle(
            color: coral,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
      TextButton(
        onPressed: onMore,
        child: const Text(
          'MORE ↗',
          style: TextStyle(color: coral, fontSize: 10),
        ),
      ),
    ],
  );
  Future<void> _orderSheet() => _sheet<void>(
    'ORDER · ปุ่มที่ปักหมุด',
    AnimatedBuilder(
      animation: s,
      builder: (_, _) => Column(
        children: [
          if (s.pinnedButtons.isEmpty) const Text('ยังไม่มีปุ่มที่ปักหมุด'),
          for (final b in s.pinnedButtons) _shortcutTile(b),
        ],
      ),
    ),
  );

  Widget _orderCard(Json b) => Material(
    color: _groupColor(
      s.groups.where((g) => g['id'] == b['groupId']).firstOrNull?['color']
              as String? ??
          'purple',
    ),
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: s.canRunCommands
          ? () async => toast(await s.executeShortcut(b['id'] as String))
          : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: SizedBox(
          height: 104,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.push_pin, color: Colors.white, size: 18),
              const Spacer(),
              Text(
                b['name'] as String,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              Text(
                b['binding']?.toString() ?? 'กำหนดคีย์ลัดก่อน',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 9),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _shortcutTile(Json b) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: s.canRunCommands
                ? () async => toast(await s.executeShortcut(b['id'] as String))
                : null,
            child: Column(
              children: [
                Text(
                  b['name'] as String,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  (b['binding'] ?? b['note'] ?? 'กำหนดคีย์ลัดก่อน').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          key: ValueKey('pin-${b['id']}'),
          tooltip: s.pinnedIds.contains(b['id']) ? 'ถอดหมุด' : 'ปักหมุด ORDER',
          onPressed: () {
            final error = s.togglePin(b['id'] as String);
            if (error != null) toast(error);
          },
          icon: Icon(
            s.pinnedIds.contains(b['id'])
                ? Icons.push_pin
                : Icons.push_pin_outlined,
            color: coral,
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'จัดการปุ่ม',
          onSelected: (action) {
            if (action == 'edit') {
              _addButtonSheet(b['groupId'] as String, editing: b);
            } else {
              s.removeButton(b['id'] as String);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('แก้ไข')),
            PopupMenuItem(value: 'remove', child: Text('ลบปุ่ม')),
          ],
        ),
      ],
    ),
  );
  Widget _status() => Column(
    children: [
      if (s.temperatureNotice != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Panel(
            child: Text(
              s.temperatureNotice!,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.weeklyLabel, style: const TextStyle(fontSize: 10)),
            const SizedBox(height: 4),
            Text(
              s.weeklyTotal,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: coral,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 115,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const SizedBox(
                    width: 16,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('15', style: TextStyle(fontSize: 8)),
                        Text('10', style: TextStyle(fontSize: 8)),
                        Text('5', style: TextStyle(fontSize: 8)),
                        Text('0', style: TextStyle(fontSize: 8)),
                        SizedBox(height: 17),
                      ],
                    ),
                  ),
                  ...s.weeklyDays.asMap().entries.map((entry) {
                    final d = entry.value,
                        minutes = (d['minutes'] as num?)?.toInt();
                    final message = minutes == null
                        ? '${d['labelTh']}: ยังไม่มีประวัติที่บันทึกได้'
                        : '${d['labelTh']}: ${minutes ~/ 60} ชม. ${minutes % 60} นาที';
                    return Expanded(
                      child: Tooltip(
                        message: message,
                        triggerMode: TooltipTriggerMode.tap,
                        preferBelow: false,
                        child: Semantics(
                          label: message,
                          button: true,
                          child: InkWell(
                            onTap: () => toast(message),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Container(
                                  width: 13,
                                  height: minutes == null
                                      ? 1
                                      : ((d['percent'] as double) * 84).clamp(
                                          4,
                                          84,
                                        ),
                                  decoration: BoxDecoration(
                                    color: minutes == null
                                        ? Colors.grey
                                        : entry.key == 6
                                        ? coral
                                        : cpuColor,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(6),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  d['key'] as String,
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: entry.key == 6 ? coral : null,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                _metricTile(s.metrics[0], 138),
                const SizedBox(height: 12),
                _metricTile(s.metrics[2], 165),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: [
                _metricTile(s.metrics[1], 138),
                const SizedBox(height: 12),
                _metricTile(s.metrics[3], 76),
                const SizedBox(height: 10),
                _metricTile(s.metrics[4], 79),
              ],
            ),
          ),
        ],
      ),
    ],
  );
  Widget _metricTile(Metric m, double height) => Material(
    color: metricColor(m.id),
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      key: Key('metric-${m.id}'),
      onTap: () => s.focusMetric(m.id),
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    metricIcon(m.id),
                    size: m.id.endsWith('temp') ? 15 : 18,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      m.label,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              Tooltip(
                message: m.caption,
                child: FittedBox(
                  child: number(
                    m.value,
                    size: m.id.endsWith('temp') ? 29 : 34,
                    color: Colors.white,
                  ),
                ),
              ),
              if (m.caption.isNotEmpty && !m.id.endsWith('temp'))
                Text(
                  m.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9, color: Color(0xff272323)),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _focus() {
    final m =
        s.metrics.where((m) => m.id == s.selectedMetric).firstOrNull ??
        s.metrics.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: () => s.navigate(DemoScreen.status),
          icon: const Icon(Icons.grid_view, size: 18),
          label: const Text('ดูทั้งหมด (View All)'),
        ),
        const SizedBox(height: 18),
        Panel(
          child: Column(
            children: [
              const SizedBox(height: 8),
              SizedBox(
                width: 160,
                height: 160,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: m.percent / 100,
                        strokeWidth: 20,
                        color: metricColor(m.id),
                        backgroundColor: Colors.grey.withValues(alpha: .25),
                        strokeCap: StrokeCap.butt,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(m.label, style: const TextStyle(fontSize: 10)),
                        number(m.value, size: 38),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Chip(
                label: Text(
                  s.active!.canOperate
                      ? (s.liveMode
                            ? (m.value == '—'
                                  ? 'ไม่มีข้อมูลเซนเซอร์'
                                  : 'พร้อมใช้งาน')
                            : (m.id.contains('temp')
                                  ? 'อุณหภูมิปกติ'
                                  : 'กำลังดี'))
                      : s.blockedReason,
                  style: const TextStyle(color: coral, fontSize: 10),
                ),
                side: const BorderSide(color: coral),
              ),
              Text(
                s.active!.canOperate
                    ? (s.liveMode
                          ? (m.value == '—'
                                ? 'ยังไม่มีข้อมูล'
                                : s.active!.displayName)
                          : 'ยังมีแรงทำงานอีกเยอะ · ${s.active!.displayName}')
                    : s.blockedReason,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'SECONDARY METRICS',
          style: TextStyle(
            color: coral,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        ...s.metrics
            .where((other) => other.id != m.id)
            .map(
              (other) => Padding(
                padding: const EdgeInsets.only(top: 10),
                child: InkWell(
                  onTap: () => s.focusMetric(other.id),
                  child: Panel(
                    outline: false,
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(metricIcon(other.id), size: 21),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                other.label,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              other.value,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: other.percent / 100,
                          color: metricColor(other.id),
                          backgroundColor: Colors.grey.withValues(alpha: .25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Widget _keys() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading(
        'YOUR KEYS',
        subtitle: 'แตะกลุ่มเพื่อเปิดชุดคำสั่งของเครื่องที่เลือก',
      ),
      Panel(
        child: Row(
          children: [
            StatusDot(s.active!.canOperate),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.active!.displayName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.keyboard_outlined, color: coral),
          ],
        ),
      ),
      const SizedBox(height: 16),
      ...s.groups.map(
        (g) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Panel(
            outline: false,
            child: Column(
              children: [
                InkWell(
                  onTap: () => s.selectGroup(g['id'] as String),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _groupColor(g['color'] as String),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.folder_outlined,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          g['name'] as String,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(
                        s.selectedGroupId == g['id']
                            ? Icons.expand_less
                            : Icons.expand_more,
                      ),
                    ],
                  ),
                ),
                if (s.selectedGroupId == g['id']) ...[
                  const SizedBox(height: 12),
                  ...s.buttons
                      .where((b) => b['groupId'] == g['id'])
                      .map((b) => _shortcutTile(b)),
                  TextButton.icon(
                    onPressed: () => _addButtonSheet(g['id'] as String),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text(
                      'เพิ่มปุ่ม',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      if (s.groups.isEmpty)
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text('ยังไม่มีกลุ่มคำสั่ง', style: TextStyle(fontSize: 12)),
        ),
      FilledButton.icon(
        onPressed: _addGroupSheet,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('เพิ่มกลุ่ม'),
      ),
      const SizedBox(height: 8),
      Text(
        s.liveMode
            ? 'คีย์ลัดส่งไปยังหน้าต่างที่โฟกัสบน PC · ปักหมุดได้ 4 ปุ่ม'
            : 'โหมดสาธิต · ไม่ส่งคีย์จริง',
        style: const TextStyle(fontSize: 10),
      ),
    ],
  );
  Color _groupColor(String color) => switch (color) {
    'purple' => const Color(0xff67367c),
    'yellow' => tempColor,
    'mint' => const Color(0xff7db183),
    'blue' => ramColor,
    _ => cpuColor,
  };

  Widget _devices() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading('YOUR DEVICES', subtitle: 'มือถือกับคอมพิวเตอร์กำลังคุยกันอยู่!'),
      SizedBox(
        height: 222,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 175,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xffffad54), coral],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 190,
                      height: 190,
                      decoration: BoxDecoration(
                        color: tempColor.withValues(alpha: .2),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Positioned(
                      top: 15,
                      child: art('wifi-original.png', width: 26, height: 21),
                    ),
                    Positioned(
                      bottom: 8,
                      child: SizedBox(
                        width: 160,
                        height: 130,
                        child: Stack(
                          children: [
                            art(
                              'devices-original.png',
                              width: 160,
                              height: 130,
                            ),
                            Positioned(
                              left: 84,
                              top: 36,
                              child: art('face-original.png', width: 25),
                            ),
                            Positioned(
                              left: 24,
                              top: 67,
                              child: art('face-original.png', width: 19),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 10,
              child: art('mimo-shy-original.png', height: 85, width: 85),
            ),
            Positioned(
              right: 0,
              top: 9,
              child: art('chat-original.png', width: 22),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      Panel(
        child: Column(
          children: [
            Row(
              children: [
                StatusDot(s.active!.canOperate),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.active!.displayName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  s.active!.canOperate ? 'CONNECT' : 'UNAVAILABLE',
                  style: const TextStyle(
                    color: coral,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const Divider(),
            _fact(
              'การเชื่อมต่อ',
              s.liveMode ? 'เชื่อมต่อแล้ว' : 'Tailscale (ตัวอย่าง)',
            ),
            const Divider(),
            _fact(
              'สถานะ',
              s.active!.canOperate ? 'Mimo Agent พร้อมใช้งาน' : s.blockedReason,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _filePicker(),
      _transferHistory(),
      const SizedBox(height: 22),
      const Text(
        'อุปกรณ์ใน MIMO',
        style: TextStyle(
          color: coral,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
      ...s.visibleDevices.map(
        (d) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => s.selectDevice(d.id),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.displayName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${d.machine.hostname} · ${d.machine.os}\n${d.machine.ip}',
                              style: const TextStyle(fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      if (d.id == s.activeDeviceId)
                        const Icon(Icons.check_circle_outline, color: coral),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _deviceBadges(d),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => _nameSheet(d: d),
                      child: const Text('แก้ไขชื่อ'),
                    ),
                    OutlinedButton(
                      onPressed: () => _removeSheet(d),
                      child: const Text('ลบจาก Mimo'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 18),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          key: const Key('add-device'),
          onPressed: _discoverySheet,
          icon: const Icon(Icons.add),
          label: const Text('เพิ่มอุปกรณ์ (ค้นหาผ่าน Tailscale)'),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        s.liveMode
            ? 'เลือกเครื่องที่ต้องการใช้งาน'
            : 'ข้อมูลจำลอง · ยังไม่เชื่อม Tailscale หรือ Mimo Agent จริง',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 10),
      ),
    ],
  );
  Widget _fact(String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 10)),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
  Widget _deviceBadges(MimoDevice d) => Wrap(
    spacing: 5,
    runSpacing: 5,
    children: [
      _badge(
        'Tailscale ${d.machine.online ? 'ออนไลน์' : 'ออฟไลน์'}',
        d.machine.online,
      ),
      _badge('Mimo Agent ${d.agentLabel}', d.canOperate),
    ],
  );
  Widget _badge(String label, bool ready) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.grey.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 9,
        color: ready
            ? (Theme.of(context).brightness == Brightness.dark
                  ? Colors.lightGreenAccent
                  : Colors.green.shade800)
            : null,
      ),
    ),
  );

  Widget _clipboard() {
    final filtered = s.clips
        .where(
          (c) =>
              s.clipFilter == 'all' ||
              (s.clipFilter == 'favorite'
                  ? s.favorites[c['id']] == true
                  : c['type'] == s.clipFilter),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(
          'YOUR CLIPBOARD',
          subtitle: s.liveMode
              ? 'รายการจาก PC · เก็บไว้ 30 นาที'
              : 'สิ่งที่คัดลอกไว้จะถูกแยกประเภท',
        ),
        Panel(
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 175,
              child: Stack(
                children: [
                  Positioned(
                    left: 16,
                    top: 16,
                    child: Row(
                      children: [
                        StatusDot(s.active!.canOperate),
                        const SizedBox(width: 8),
                        Text(
                          s.active!.displayName,
                          style: const TextStyle(fontSize: 10, color: coral),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 16,
                    top: 58,
                    right: 116,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'คลิปบอร์ดที่\nพร้อมใช้งาน',
                          style: TextStyle(
                            color: coral,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${s.clips.length} รายการ',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 8,
                    bottom: -42,
                    child: art('mimo-crying-original.png', width: 108),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            OutlinedButton(
              onPressed: _addClipSheet,
              child: const Text('เพิ่มข้อความ'),
            ),
            OutlinedButton(
              onPressed: () => s.setClipFilter('favorite'),
              child: const Text('Favorite'),
            ),
            OutlinedButton(
              onPressed: () => s.navigate(DemoScreen.files),
              child: const Text('รับส่งไฟล์'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: (s.seed['CLIPBOARD_CATEGORIES'] as List)
                .map(
                  (cat) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                        cat['label'] as String,
                        style: const TextStyle(fontSize: 10),
                      ),
                      selected: s.clipFilter == cat['id'],
                      onSelected: (_) => s.setClipFilter(cat['id'] as String),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'ยังไม่มีรายการในหมวดนี้',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ...filtered.map(
          (c) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c['title'] as String,
                          style: const TextStyle(
                            fontSize: 12,
                            color: coral,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Favorite',
                        onPressed: () async {
                          final error = await s.toggleFavorite(
                            c['id'] as String,
                          );
                          if (error != null) toast(error);
                        },
                        icon: Icon(
                          s.favorites[c['id']] == true
                              ? Icons.star
                              : Icons.star_outline,
                          color: tempColor,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    c['preview'] as String,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (c['type'] == 'image' && c['fileName'] != null)
                    TextButton.icon(
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('ดูรูป'),
                      onPressed: () => _previewClipboard(c),
                    ),
                  if (c['fileName'] != null)
                    TextButton.icon(
                      icon: const Icon(Icons.download),
                      label: const Text('บันทึกไฟล์'),
                      onPressed: () async {
                        try {
                          final data = await s.clipboardFile(
                            c['deviceId'] as String,
                            c['id'] as String,
                          );
                          final path = await FilePicker.platform.saveFile(
                            fileName: c['fileName'] as String,
                            bytes: data,
                          );
                          if (path != null) toast('บันทึกไฟล์แล้ว');
                        } catch (_) {
                          toast('บันทึกไม่ได้ รายการอาจหมดอายุแล้ว');
                        }
                      },
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.favorites[c['id']] == true
                              ? 'Favorite · เก็บถาวร'
                              : c['expiresAt'] == null
                              ? (c['time'] ?? '').toString()
                              : 'เหลือ ${DateTime.parse(c['expiresAt'] as String).difference(DateTime.now()).inMinutes.clamp(0, 30)} นาที',
                          style: const TextStyle(fontSize: 9),
                        ),
                      ),
                      if (['text', 'link'].contains(c['type']))
                        IconButton(
                          tooltip: 'คัดลอก',
                          onPressed: () async {
                            if (!['text', 'link'].contains(c['type'])) {
                              toast(
                                'ไฟล์นี้เป็นตัวอย่าง ไม่มีเนื้อหาไฟล์ให้คัดลอก',
                              );
                              return;
                            }
                            try {
                              await Clipboard.setData(
                                ClipboardData(text: c['preview'] as String),
                              );
                              toast('คัดลอกแล้ว');
                            } catch (_) {
                              toast('คัดลอกไม่ได้ ระบบไม่อนุญาต');
                            }
                          },
                          icon: const Icon(Icons.copy_outlined, size: 18),
                        ),
                      IconButton(
                        tooltip: 'ลบ',
                        onPressed: () async {
                          final error = await s.removeClip(c['id'] as String);
                          if (error != null) toast(error);
                        },
                        icon: const Icon(Icons.delete_outline, size: 18),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _files() => Column(
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => s.navigate(DemoScreen.devices),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('อุปกรณ์'),
        ),
      ),
      const SizedBox(height: 16),
      heading('SEND A FILE', subtitle: 'ส่งให้เครื่องที่เลือกอยู่'),
      Panel(
        child: Column(
          children: [
            const Icon(Icons.upload_file, color: coral, size: 48),
            const SizedBox(height: 16),
            const Text('ปลายทาง', style: TextStyle(fontSize: 11)),
            Text(
              s.active!.displayName,
              style: const TextStyle(
                color: coral,
                fontWeight: FontWeight.w700,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 16),
            _filePicker(),
            const SizedBox(height: 12),
            const Text(
              'ไฟล์ไม่เกิน 100 MB · บันทึกใน Downloads/Mimo ของ PC',
              style: TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
      _transferHistory(),
      if (s.activeTransfers.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('ยังไม่มีไฟล์ที่ส่ง', style: TextStyle(fontSize: 11)),
        ),
    ],
  );
  Widget _theme() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading('YOUR THEME', subtitle: 'เลือกบรรยากาศที่เข้ากับคุณ'),
      ...[
        (
          id: 'light',
          title: 'แสงเช้า',
          subtitle: 'อบอุ่น สดใส (Morning Light)',
          icon: Icons.wb_sunny_outlined,
        ),
        (
          id: 'dark',
          title: 'ดาวกลางคืน',
          subtitle: 'สบายตาในที่มืด (Night Stars)',
          icon: Icons.nightlight_outlined,
        ),
        (
          id: 'system',
          title: 'ตามระบบ',
          subtitle: 'เปลี่ยนอัตโนมัติ (Follow OS)',
          icon: Icons.phone_android,
        ),
      ].map(
        (option) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: InkWell(
            onTap: () => s.setTheme(option.id),
            child: Panel(
              outline: s.theme == option.id,
              child: Row(
                children: [
                  Icon(option.icon, color: coral, size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          option.subtitle,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  if (s.theme == option.id)
                    const Icon(Icons.check_circle, color: coral),
                ],
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      const Text(
        'Mimo · Flutter display prototype',
        style: TextStyle(fontSize: 11),
      ),
    ],
  );
}
