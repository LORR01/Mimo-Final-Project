part of 'mimo_app.dart';

extension _Sheets on _MimoShellState {
  Future<void> _previewClipboard(Json clip) async {
    await _sheet<void>(
      'รูปภาพ',
      FutureBuilder<Uint8List>(
        future: s.clipboardFile(
          clip['deviceId'] as String,
          clip['id'] as String,
        ),
        builder: (ctx, value) => value.hasData
            ? Image.memory(
                value.data!,
                key: const Key('clipboard-preview'),
                cacheWidth: 768,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const Text('เปิดรูปไม่ได้ กรุณาบันทึกไฟล์เพื่อเปิดดู'),
              )
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  value.hasError
                      ? 'รูปหมดอายุหรือดาวน์โหลดไม่ได้'
                      : 'กำลังโหลดรูป…',
                ),
              ),
      ),
    );
  }

  Future<void> _notificationsSheet() async {
    await _sheet<void>(
      'การแจ้งเตือน',
      AnimatedBuilder(
        animation: s,
        builder: (ctx, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (s.notifications.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('ยังไม่มีการแจ้งเตือน'),
              ),
            for (final item in s.notifications)
              ListTile(
                leading: Icon(
                  item['type'] == 'clipboard'
                      ? Icons.content_paste
                      : Icons.computer,
                ),
                title: Text(
                  item['title'] as String,
                  style: const TextStyle(fontSize: 12),
                ),
                subtitle: Text((item['time'] as String).substring(11, 16)),
              ),
          ],
        ),
      ),
    );
    if (mounted) s.readNotifications();
  }

  Future<T?> _sheet<T>(String title, Widget child) => showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: coral,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 420),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .82,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'ปิด',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(
                      Icons.cancel_outlined,
                      color: Color(0xff221e1e),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      ),
    ),
  );
  ButtonStyle get _darkButton => FilledButton.styleFrom(
    backgroundColor: const Color(0xff221e1e),
    foregroundColor: Colors.white,
  );
  Future<void> _loginSheet() async {
    final name = TextEditingController(), password = TextEditingController();
    final form = GlobalKey<FormState>();
    bool obscure = true;
    final login = await _sheet<bool>(
      'WELCOME!',
      StatefulBuilder(
        builder: (ctx, setLocal) => Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('login-name'),
                controller: name,
                decoration: const InputDecoration(hintText: 'USERNAME'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'กรุณาใส่ชื่อผู้ใช้' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: password,
                obscureText: obscure,
                decoration: InputDecoration(
                  hintText: 'PASSWORD',
                  suffixIcon: IconButton(
                    tooltip: 'แสดง/ซ่อนรหัสผ่าน',
                    onPressed: () => setLocal(() => obscure = !obscure),
                    icon: Icon(
                      obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'กรุณาใส่รหัสผ่านตัวอย่าง' : null,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: coral,
                  ),
                  onPressed: () {
                    if (form.currentState!.validate()) Navigator.pop(ctx, true);
                  },
                  child: const Text('LOGIN'),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'บัญชีตัวอย่าง · ไม่บันทึกรหัสผ่าน',
                style: TextStyle(fontSize: 10, color: Color(0xff40261e)),
              ),
            ],
          ),
        ),
      ),
    );
    final username =
        name.text; // Controllers outlive the reverse sheet animation below.
    if (login == true && mounted) {
      await s.login(username);
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    name.dispose();
    password.dispose();
  }

  Future<void> _discoverySheet() async {
    if (_networkSheetOpen) return;
    _networkSheetOpen = true;
    if (s.liveMode) unawaited(_loadNetwork());
    String scenario = s.scenario;
    final candidate = await _sheet<DiscoveredDevice>(
      s.liveMode ? 'เลือกเครื่องใน Tailscale' : 'เพิ่มอุปกรณ์',
      StatefulBuilder(
        builder: (ctx, setLocal) => AnimatedBuilder(
          animation: s,
          builder: (ctx, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.liveMode
                    ? 'เลือก PC ที่ต้องการเพิ่ม · เครื่องที่เปิดแอปจะไม่แสดงเป็นปลายทาง'
                    : 'ข้อมูลจำลอง · ไม่ได้เชื่อม Tailscale จริง',
                style: const TextStyle(color: Color(0xff40261e), fontSize: 11),
              ),
              const SizedBox(height: 16),
              if (!s.liveMode)
                DropdownButtonFormField<String>(
                  initialValue: scenario,
                  decoration: const InputDecoration(
                    labelText: 'สถานการณ์สาธิต',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'found', child: Text('พบอุปกรณ์')),
                    DropdownMenuItem(
                      value: 'empty',
                      child: Text('ไม่พบอุปกรณ์'),
                    ),
                    DropdownMenuItem(
                      value: 'error',
                      child: Text('ค้นหาไม่สำเร็จ'),
                    ),
                  ],
                  onChanged: s.discoveryState == DiscoveryState.searching
                      ? null
                      : (v) => setLocal(() => scenario = v!),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('search-devices'),
                  style: _darkButton,
                  onPressed:
                      s.connectingAgent ||
                          s.discoveryState == DiscoveryState.searching
                      ? null
                      : () => s.liveMode
                            ? _loadNetwork()
                            : s.searchDevices(scenario),
                  child: Text(
                    s.connectingAgent ||
                            s.discoveryState == DiscoveryState.searching
                        ? 'กำลังค้นหา…'
                        : 'ค้นหาอุปกรณ์ผ่าน Tailscale',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (s.liveMode && s.liveError != null && !s.connectingAgent)
                Text(
                  s.liveError!,
                  key: const Key('network-error'),
                  style: const TextStyle(
                    color: Color(0xff40261e),
                    fontSize: 12,
                  ),
                ),
              if (s.liveMode && !s.liveConnected && !s.connectingAgent) ...[
                const Text(
                  'ตรวจว่าโทรศัพท์เชื่อม Tailscale ด้วยบัญชีเดียวกับ PC และ PC เปิด Mimo Agent อยู่ จากนั้นกดค้นหาอีกครั้ง',
                  style: TextStyle(color: Color(0xff40261e), fontSize: 12),
                ),
                if (TailscaleBridge.isAndroid)
                  OutlinedButton(
                    onPressed: _beginTailscale,
                    child: const Text('เปิดแอป Tailscale'),
                  ),
              ],
              if (s.connectingAgent ||
                  s.discoveryState == DiscoveryState.searching)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              if (s.discoveryState == DiscoveryState.empty)
                const Text(
                  'ไม่พบอุปกรณ์ใหม่ · เครื่องที่เพิ่มแล้วจะไม่แสดงซ้ำ',
                  style: TextStyle(color: Color(0xff40261e), fontSize: 12),
                ),
              if (s.discoveryState == DiscoveryState.error)
                Text(
                  s.discoveryError,
                  style: const TextStyle(
                    color: Color(0xff40261e),
                    fontSize: 12,
                  ),
                ),
              ...(s.liveMode && !s.liveConnected ? <DiscoveredDevice>[] : s.discovered).map(
                (candidate) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: Theme.of(ctx).colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      key: Key('discovered-${candidate.machine.id}'),
                      onTap: () => Navigator.pop(ctx, candidate),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              candidate.machine.hostname,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${candidate.machine.os} · ${candidate.machine.ip}',
                              style: const TextStyle(fontSize: 10),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 5,
                              runSpacing: 5,
                              children: [
                                _badge(
                                  'พบอุปกรณ์ · ${candidate.machine.online ? 'ออนไลน์' : 'ออฟไลน์'}',
                                  candidate.machine.online,
                                ),
                                _badge(
                                  'Mimo Agent ${candidate.agent == AgentStatus.ready
                                      ? 'พร้อมใช้งาน'
                                      : candidate.agent == AgentStatus.unreachable
                                      ? 'ติดต่อไม่ได้'
                                      : 'ยังไม่พร้อม'}',
                                  candidate.agent == AgentStatus.ready,
                                ),
                              ],
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
      ),
    );
    _networkSheetOpen = false;
    if (candidate != null && mounted) {
      await _nameSheet(candidate: candidate);
    }
  }

  Future<void> _connectAgentSheet() => _discoverySheet();

  Future<void> _nameSheet({MimoDevice? d, DiscoveredDevice? candidate}) async {
    final machine = d?.machine ?? candidate!.machine,
        controller = TextEditingController(
          text: d?.displayName ?? candidate!.machine.hostname,
        );
    final form = GlobalKey<FormState>();
    final saved = await _sheet<bool>(
      d == null ? 'ตั้งชื่อแสดงใน Mimo' : 'แก้ไขชื่อแสดง',
      Builder(
        builder: (ctx) => Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${machine.hostname} · ${machine.os}\n${machine.ip}',
                style: const TextStyle(color: Color(0xff40261e), fontSize: 11),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('device-name'),
                controller: controller,
                maxLength: 32,
                decoration: const InputDecoration(labelText: 'ชื่อแสดงใน Mimo'),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'กรุณาใส่ชื่อแสดงใน Mimo'
                    : null,
              ),
              const SizedBox(height: 10),
              const Text(
                'การตั้งชื่อนี้ไม่เปลี่ยนชื่อเครื่องใน Tailscale',
                style: TextStyle(color: Color(0xff40261e), fontSize: 11),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('save-device-name'),
                  style: _darkButton,
                  onPressed: () {
                    if (!form.currentState!.validate()) return;
                    final error = s.saveDevice(
                      machine.id,
                      controller.text,
                      candidate: candidate,
                    );
                    if (error != null) {
                      toast(error);
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('บันทึกชื่อ'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved == true) toast('บันทึกชื่อแสดงใน Mimo แล้ว');
    await Future<void>.delayed(const Duration(milliseconds: 350));
    controller.dispose();
  }

  Future<void> _removeSheet(MimoDevice device) async {
    final confirmed = await _sheet<bool>(
      'ลบจากรายการ Mimo',
      Builder(
        builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ลบ ${device.displayName} จาก Mimo เท่านั้น เครื่องยังอยู่ใน Tailscale\nข้อมูลกลุ่ม ปุ่ม และคลิปบอร์ดใน Mimo ของเครื่องนี้จะถูกลบด้วย',
              style: const TextStyle(color: Color(0xff40261e), fontSize: 12),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: _darkButton,
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('ลบจาก Mimo'),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      s.removeDevice(device.id);
      toast('ลบจาก Mimo แล้ว · เครื่องยังอยู่ใน Tailscale');
    }
  }

  Future<void> _addGroupSheet() async {
    final controller = TextEditingController();
    final form = GlobalKey<FormState>();
    String color = 'purple', error = '';
    await _sheet<void>(
      'เพิ่มกลุ่ม',
      StatefulBuilder(
        builder: (ctx, setLocal) => Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: controller,
                maxLength: 32,
                decoration: const InputDecoration(labelText: 'ชื่อกลุ่ม'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'กรุณาใส่ชื่อกลุ่ม' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: color,
                decoration: const InputDecoration(labelText: 'สีของกลุ่ม'),
                items: const [
                  DropdownMenuItem(value: 'purple', child: Text('ม่วง')),
                  DropdownMenuItem(value: 'yellow', child: Text('เหลือง')),
                  DropdownMenuItem(value: 'blue', child: Text('ฟ้า')),
                  DropdownMenuItem(value: 'mint', child: Text('มิ้นต์')),
                  DropdownMenuItem(value: 'coral', child: Text('พีช')),
                ],
                onChanged: (v) => color = v!,
              ),
              if (error.isNotEmpty)
                Text(error, style: const TextStyle(color: Color(0xff40261e))),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: _darkButton,
                  onPressed: () {
                    if (!form.currentState!.validate()) return;
                    final result = s.addGroup(controller.text, color);
                    if (result != null) {
                      setLocal(() => error = result);
                      return;
                    }
                    Navigator.pop(ctx);
                  },
                  child: const Text('บันทึกกลุ่ม'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    controller.dispose();
  }

  Future<void> _addButtonSheet(String groupId, {Json? editing}) async {
    final name = TextEditingController(text: editing?['name'] as String?),
        note = TextEditingController(text: editing?['note'] as String?),
        binding = TextEditingController(text: editing?['binding'] as String?);
    final form = GlobalKey<FormState>();
    String group = groupId;
    await _sheet<void>(
      editing == null ? 'เพิ่มปุ่ม' : 'แก้ไขปุ่ม',
      Builder(
        builder: (ctx) => Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                maxLength: 32,
                decoration: const InputDecoration(labelText: 'ชื่อปุ่ม'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'กรุณาใส่ชื่อปุ่ม' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: note,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'คำอธิบาย'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: group,
                decoration: const InputDecoration(labelText: 'กลุ่ม'),
                items: s.groups
                    .map(
                      (g) => DropdownMenuItem(
                        value: g['id'] as String,
                        child: Text(g['name'] as String),
                      ),
                    )
                    .toList(),
                onChanged: (v) => group = v!,
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const Key('shortcut-binding'),
                controller: binding,
                readOnly: true,
                onTap: () async {
                  final keys = await _sheet<List<String>>(
                    'เลือกคีย์ลัด',
                    Builder(
                      builder: (keyboardContext) => ChordKeyboard(
                        onConfirmed: (keys) =>
                            Navigator.pop(keyboardContext, keys),
                      ),
                    ),
                  );
                  if (keys != null && ctx.mounted) {
                    binding.text = keys.join(' + ');
                  }
                },
                validator: (value) =>
                    value == null || value.isEmpty ? 'กรุณาเลือกคีย์ลัด' : null,
                decoration: const InputDecoration(
                  labelText: 'คีย์ลัด',
                  hintText: 'แตะเพื่อเปิดคีย์บอร์ด PC',
                  suffixIcon: Icon(Icons.keyboard_outlined),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: _darkButton,
                  onPressed: () {
                    if (!form.currentState!.validate()) return;
                    final error = s.addButton(
                      name.text,
                      note.text,
                      'custom',
                      binding.text,
                      group,
                      editingId: editing?['id'] as String?,
                    );
                    if (error != null) {
                      toast(error);
                      return;
                    }
                    Navigator.pop(ctx);
                  },
                  child: const Text('บันทึกปุ่ม'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    name.dispose();
    note.dispose();
    binding.dispose();
  }

  Future<void> _addClipSheet() async {
    final controller = TextEditingController();
    final form = GlobalKey<FormState>();
    await _sheet<void>(
      'เพิ่มข้อความ',
      Builder(
        builder: (ctx) => Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: controller,
                maxLength: 1000,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'ข้อความ / ลิงก์'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'กรุณาใส่ข้อความ' : null,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: _darkButton,
                  onPressed: () {
                    if (!form.currentState!.validate()) return;
                    s.addClip(controller.text);
                    Navigator.pop(ctx);
                  },
                  child: const Text('บันทึก'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    controller.dispose();
  }
}
