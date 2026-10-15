typedef Json = Map<String, dynamic>;

class TailMachine {
  const TailMachine({
    required this.id,
    required this.hostname,
    required this.ip,
    required this.os,
    required this.online,
    this.agentUrl = '',
  });
  final String id, hostname, ip, os;
  final String agentUrl;
  final bool online;
  factory TailMachine.fromJson(Json j) => TailMachine(
    id: j['id'] as String,
    hostname: j['hostname'] as String,
    ip: j['ip'] as String,
    os: j['os'] as String,
    online: j['online'] == true,
    agentUrl: j['agentUrl'] as String? ?? '',
  );
  Json toJson() => {
    'id': id,
    'hostname': hostname,
    'ip': ip,
    'os': os,
    'online': online,
    'agentUrl': agentUrl,
  };
}

enum AgentStatus { ready, missing, unreachable, unknown }

class DiscoveredDevice {
  const DiscoveredDevice(this.machine, this.agent);
  final TailMachine machine;
  final AgentStatus agent;
}

class MimoDevice {
  MimoDevice({
    required this.machine,
    required this.displayName,
    required this.agent,
    required this.readings,
    required this.addedAt,
    this.live = false,
  });
  TailMachine machine;
  String displayName;
  AgentStatus agent;
  Map<String, double> readings;
  final int addedAt;
  final bool live;
  String get id => machine.id;
  bool get canOperate => machine.online && agent == AgentStatus.ready;
  String get blockedReason => !machine.online
      ? 'เครื่องออฟไลน์ใน Tailscale'
      : agent != AgentStatus.ready
      ? 'Mimo Agent ยังไม่พร้อมใช้งาน'
      : '';
  String get agentLabel => !machine.online
      ? 'ติดต่อไม่ได้'
      : agent == AgentStatus.ready
      ? 'พร้อมใช้งาน'
      : agent == AgentStatus.unknown
      ? 'ยังไม่ได้เชื่อม Agent'
      : 'ยังไม่พร้อม';
  Json toJson() => {
    'machine': machine.toJson(),
    'displayName': displayName,
    'agent': agent.name,
    'readings': readings,
    'addedAt': addedAt,
    'live': live,
  };
  factory MimoDevice.fromJson(Json j) => MimoDevice(
    machine: TailMachine.fromJson(
      Map<String, dynamic>.from(j['machine'] as Map),
    ),
    displayName: j['displayName'] as String,
    agent: AgentStatus.values.byName(j['agent'] as String),
    readings: (j['readings'] as Map).map(
      (k, v) => MapEntry(k as String, (v as num).toDouble()),
    ),
    addedAt: (j['addedAt'] as num).toInt(),
    live: j['live'] == true,
  );
}

class Metric {
  const Metric(this.id, this.label, this.value, this.percent, this.caption);
  final String id, label, value, caption;
  final double percent;
}

class DemoTransfer {
  DemoTransfer({
    required this.id,
    required this.deviceId,
    required this.name,
    required this.size,
  });
  final String id, deviceId, name;
  final int size;
  bool done = false;
  double progress = 0;
  String? error, storedName;
}

enum DiscoveryState { idle, searching, found, empty, error }

enum DemoScreen {
  splash,
  loading,
  home,
  status,
  keys,
  devices,
  clipboard,
  theme,
  files,
}
