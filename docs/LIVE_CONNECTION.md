Latest 1.1.0+3: [SHARING_AND_NOTIFICATIONS.md](SHARING_AND_NOTIFICATIONS.md) supersedes earlier file/clipboard and simultaneous keyboard limitations below.

# เชื่อมข้อมูลจริงผ่าน Tailscale

รุ่นถัดจาก read-only เพิ่ม Android onboarding และ keyboard commands ผ่าน `--enable-commands` แล้ว อ่าน [ANDROID_AND_COMMANDS.md](ANDROID_AND_COMMANDS.md) ซึ่งอธิบาย capability/endpoint/การ build ปัจจุบัน ข้อความ read-only ด้านล่างหมายถึงเมื่อรันโดยไม่มี flag นี้

## ขอบเขต

Flutter เป็น UI หลัก Agent เขียน Dart และใช้ PowerShell เฉพาะอ่าน Windows CIM ไม่มี Python/Node backend ไม่มี API token ของ Tailscale ในแอป ใช้ Tailscale ที่ติดตั้งและเข้าสู่ระบบบน Windows อยู่แล้ว โทรศัพท์ต้องเปิด Tailscale และอยู่ใน tailnet ที่เข้าถึงเครื่องนี้ได้

## เริ่มระบบ

ทำจาก repository root ด้วย Flutter/Dart SDK ที่ติดตั้งไว้:

```powershell
flutter pub get
flutter build web --release
dart run tool/mimo_agent.dart
```

Agent bind เฉพาะ `127.0.0.1:8765` เปิดเว็บทดสอบบน PC ได้ที่ `http://127.0.0.1:8765` รหัสจับคู่ 6 หลักอยู่ที่ `.local/agent/pairing.local.json` อ่านไฟล์นี้บน PC ส่วนตัว ห้ามส่งขึ้น Git หรือส่งภาพที่มีรหัสให้ผู้อื่น รหัสเปลี่ยนเมื่อ restart Agent

สำหรับโทรศัพท์ ให้เจ้าของ tailnet เปิด Serve/HTTPS ตามลิงก์ที่ CLI แสดง แล้วรัน:

```powershell
tailscale serve --bg --https=8443 http://127.0.0.1:8765
```

ใช้พอร์ตมาตรฐานของ Mimo คือ 8443 เพื่อให้ค้นหา Agent ของแต่ละ PC ได้ตรงกัน URL จะมี `:8443` หากพอร์ตนี้ถูกใช้อยู่ ให้ตรวจบริการเดิมก่อนเปลี่ยน หยุดเฉพาะบริการ Mimo ได้ด้วย `tailscale serve --https=8443 off` ห้ามใช้ reset เพราะอาจลบบริการอื่น

ใช้ HTTPS URL ที่คำสั่งรายงาน เปิดจากโทรศัพท์ที่เชื่อม Tailscale ด้วยบัญชีเจ้าของ PC → เข้าแอป → ค้นหา → เลือก PC → ตั้งชื่อ → บันทึก Web เชื่อมอัตโนมัติโดยไม่ใช้รหัสจับคู่ ถ้ายังไม่เชื่อมให้กดค้นหาอีกครั้งในหน้าเลือกเครื่อง รหัสจับคู่เป็นทางสำรองสำหรับ localhost ไม่ใช้ Funnel ไม่มีการเปิด public Internet การตั้งค่า Serve คงอยู่หลังปิด terminal แต่ต้องรัน Agent ค้างเพื่อมีข้อมูล

เครื่องที่กำลังเปิดแอปถูกกรองด้วย stable ID ที่ backend ตรวจจาก source IP ผ่าน `tailscale whois --json` ไม่ใช้ชื่อหรือการเดาจาก OS ถ้าเปิดบนโทรศัพท์จะซ่อนโทรศัพท์และยังแสดง PC ถ้าเปิดบน PC เครื่องเดียวกับ Agent จะซ่อน PC นั้นตามหลักเดียวกัน รายการที่เคยบันทึกเป็นเครื่องต้นทางจะถูกซ่อนใน Header/Devices โดยไม่ลบ alias/config เดิม

ถ้า CLI แจ้ง `Serve is not enabled on your tailnet` ต้องเปิดผ่านบัญชี Tailscale ก่อน การอนุญาตในแชตอย่างเดียวไม่สามารถเปลี่ยน setting ของบัญชีได้ ตรวจ `tailscale serve status` ก่อนแก้บริการที่มีอยู่ อ่านเอกสาร [Tailscale Serve](https://tailscale.com/docs/reference/tailscale-cli/serve)

Android native app เปิดแอป Tailscale ที่ติดตั้งไว้เพื่อเข้าสู่ระบบ แล้วเชื่อม gateway HTTPS ที่กำหนดตอน build โดยไม่มีช่อง URL ใน flow ปกติ โดยต้องมี Tailscale VPN ของระบบเปิดอยู่ ไม่ฝัง VPN SDK ไม่ขอ Tailscale token และไม่ให้ HTTP ไปยัง IP เครื่องอื่น Android APK ทดสอบ build แล้ว ส่วน iOS ต้องใช้ macOS/Xcode และยังไม่ได้ build

## โครงสร้างและเส้นทางข้อมูล

```text
Windows Tailscale CLI ─→ TailnetReader ─┐
Windows CIM/WMI ─→ WindowsCollector ────┼→ MimoAgent localhost:8765
ช่วงเวลาที่ Agent สังเกต ─→ UsageLedger ┘        ↓ Tailscale Serve HTTPS
                                        AgentClient (Flutter)
                                                ↓
                                    MimoStore → Header/Devices/Status/Focus
```

- `tool/mimo_agent.dart`: entry point, pairing file และ lifecycle
- `tool/agent/collector.dart`: bounded child processes, Tailscale reader, Windows collector และ usage ledger
- `tool/agent/windows_metrics.ps1`: trusted read-only CIM script ไม่มี input จาก UI
- `tool/agent/server.dart`: routes, pairing/session, CORS, freshness และ static `build/web` เท่านั้น
- `lib/data/agent_client.dart`: HTTP adapter และ snapshot parser แยกจาก widgets
- `lib/main.dart`: live default; demo ต้อง `--dart-define=MIMO_DEMO=true`
- `lib/state/mimo_store.dart`: membership/alias แยกจากเครื่องจริง, refresh/freshness, empty states และ guards
- `.local/agent/usage.json`: ประวัติที่สังเกตบน PC; `.local/verification/`: ภาพ render ข้อมูลจริง ทั้งโฟลเดอร์ถูก ignore

`TailMachine.id` ใช้ immutable Tailscale ID ชื่อ/IP ไม่ใช่ primary key `MimoDevice` เก็บ alias แยก การลบออกจาก Mimo ไม่ลบเครื่องจาก tailnet เครื่อง offline เป็น unreachable เครื่องอื่น online เป็น unknown จนกว่าจะเชื่อม Agent ของเครื่องนั้น ไม่มีการสแกน port หรืออ้างว่าเครื่องอื่นพร้อมส่งคำสั่ง

preferences เก็บ membership/aliases/config/theme/บันทึก clipboard ในแอป แต่ไม่เก็บ pairing code/session token ข้อมูล demo ไม่เติมกลับใน live mode และไม่ใช้ readings ที่บันทึกเก่าแทนข้อมูลสด การสลับออก/ลบเครื่องหรือ disconnect ล้างข้อมูลที่ไม่ตรงเครื่อง

## ความหมายของค่าที่อ่าน

| UI | แหล่งข้อมูล/ข้อจำกัด |
|---|---|
| CPU % | Processor `_Total` PercentProcessorTime |
| GPU % | GPU engine counters รวมแต่ละ process ภายใน engine เดียวกัน แล้วใช้ engine ที่ทำงานสูงสุด ไม่รวมทุก engine เป็นเปอร์เซ็นต์เทียม |
| RAM | TotalVisibleMemorySize และ FreePhysicalMemory คำนวณ GiB; UI ใช้ป้าย GB ตามแบบเดิม |
| CPU/GPU °C | Sensor WMI ของ LibreHardwareMonitor/OpenHardwareMonitor เท่านั้น ถ้าไม่มีให้ `—` พร้อมเหตุผลใน Tooltip/หน้า Focus |
| Weekly | เวลาที่ Agent รันและอ่าน sample สำเร็จ ไม่ใช่เวลาใช้คีย์บอร์ดหรือย้อนหลังจาก Windows; ไม่เติมช่วงพัก/ปิด Agent วันที่ไม่เคยสังเกตเป็น null |
| ชื่อเดิม/IP/OS/online | `tailscale status --json` ของ tailnet ที่เครื่องนี้มองเห็น |

CPU/GPU model และ OS caption รวมใน snapshot `hardware` เพื่อสานงาน ไม่ใช่ค่าจำลองของ seed ข้อมูลหมดอายุจะไม่แสดงต่อเป็น live Commands/files/clipboard capabilities เป็น false เสมอในรุ่นนี้ การคัดลอกข้อความใช้ clipboard ของอุปกรณ์ที่เปิดแอป ยังไม่อ่านคลิปบอร์ด PC

## API และการป้องกัน

| Route | สิทธิ์/ผลลัพธ์ |
|---|---|
| GET /v1/health | public เฉพาะ service/protocol/readOnly ไม่เผยข้อมูลเครื่อง |
| POST /v1/pair | JSON code → random session token อายุ 8 ชั่วโมง; 5 ครั้งที่ผิดภายใน 5 นาทีถูกจำกัด |
| POST /v1/tailscale-session | ตรวจ Serve identity + whois → session โดยไม่ใช้ code เฉพาะบัญชีเจ้าของ Agent PC; ระบุ clientDeviceId สำหรับซ่อนเครื่องต้นทาง |
| GET /v1/devices | Bearer token; real self + peers |
| GET /v1/devices/{id}/snapshot | Bearer token; อ่านได้เฉพาะ ID ของ Agent นี้ เครื่องอื่นตอบ 404 |
| POST /v1/devices/{id}/keys | Bearer token + --enable-commands; allowlisted key chord/requestId, ตรวจเครื่อง/freshness/dedup/rate limit |

ไม่มี command/upload endpoint requests แบบ write อื่นตอบ 405 API ที่ขาด token/หมดอายุเป็น 401, snapshot เก่าหรืออ่านระบบไม่สำเร็จเป็น 503 CORS จำกัด localhost origin ของ Agent และ HTTPS DNS ของตนเอง ไม่มี wildcard ไม่ส่ง token ตาม redirect เซิร์ฟเวอร์ bind loopback; private HTTPS อาศัย Serve และ ACL ของ tailnet รหัส/session ยังเป็นการจับคู่ prototype ไม่ใช่ระบบบัญชี production

การเข้าโดยไม่ใช้ code ตรวจ loopback proxy, HTTPS forwarded host ที่อนุญาต, IP เดี่ยวที่ parse ได้, Tailscale login เทียบ whois, stable ID/owner/IP/current network map และ key expiry; ปฏิเสธ MachineAuthorized=false แต่ไม่บังคับว่าฟิลด์ต้องมีใน CLI ปฏิเสธ Funnel/ผู้ใช้คนอื่น/tagged nodes ที่ไม่มี identity headers ไม่เชื่อ header จาก remote โดยตรง ดู [identity headers](https://tailscale.com/docs/features/tailscale-serve#identity-headers) Backend loopback และไฟล์จับคู่ถือว่ากระบวนการในบัญชี Windows เดียวกันเป็น trusted local boundary

## ตรวจสอบและสานงาน

```powershell
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
flutter test test/live_machine_test.dart --dart-define=MIMO_LIVE_TEST=true
flutter build web --release
```

คำสั่ง live test ต้องมี Agent บน PC เครื่องทดสอบ จะอ่านรหัสจากไฟล์ในเครื่อง จับคู่จริง และ render Status ที่ 320/390 px เขียนภาพที่ `.local/verification/` ไม่พิมพ์ token/rหัส Tests ปกติใช้ fake collector/HTTP fixtures และไม่ต้องมี Tailscale Windows ใน CI

ทดสอบ Flutter client แบบไม่ใช้ code ผ่าน HTTPS จริงด้วย `flutter test test/live_identity_test.dart --dart-define=MIMO_IDENTITY_TEST=true --dart-define=MIMO_AGENT_URL=https://<ชื่อเครื่อง>.<tailnet>.ts.net:8443` ไม่ข้าม certificate verification ส่วน live_machine_test ใช้ localhost สำหรับภาพ UI ของ PC เพราะการเรียกผ่าน HTTPS บน PC จะซ่อน PC ผู้เปิดแอปจากรายการอย่างถูกต้อง

งานต่อไป: per-device Agent connection/session routing, capability negotiation, authenticated command/file transports, temperature provider setup และ native device builds ห้ามแปลง online/unknown เป็น ready หรือเติมตัวเลข seed เมื่ออ่านจริงไม่ได้ อัปเดตเอกสารและทดสอบป้องกัน wrong-device/stale response ทุกครั้ง
