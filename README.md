# Mimo — Flutter

อัปเดตเอกสาร: 16 ตุลาคม 2026

แอป Flutter สำหรับเลือก PC ใน Tailscale ดูสถานะเครื่อง และส่งคีย์ลัดผ่าน Mimo Agent บน Windows โฟลเดอร์ `mimo_flutter` เป็น repository root สำหรับ GitHub และทำงานแยกจาก prototype HTML เดิม UI ใช้ Flutter widgets ไม่ใช้ WebView หรือ Node.js runtime

ผู้รับช่วงต่อให้อ่าน [handoff.md](handoff.md) แล้วดู [ผลตรวจสอบ](docs/VALIDATION.md) และ [หลักฐาน build](docs/build-evidence.json) เอกสารผลตรวจสอบส่วนท้ายคือสถานะล่าสุด ข้อความ read-only เก่าเป็นประวัติการพัฒนา

## สถานะปัจจุบัน

| ส่วน | การทำงานและข้อจำกัด |
|---|---|
| Android / Tailscale | เปิดแอป Tailscale ที่ติดตั้งไว้ให้ผู้ใช้เข้าสู่ระบบ กลับ Mimo แล้วใช้ตัวตนผ่าน HTTPS ของ Agent ไม่กรอกรหัสผ่าน Tailscale ใน Mimo |
| รายการเครื่อง | Agent อ่าน Tailscale CLI จริง กรองเครื่องที่เปิดแอปด้วย stable ID และกรองเครื่องที่เพิ่มแล้ว ไม่ถือว่าออนไลน์แปลว่ามี Agent |
| Devices | เพิ่ม/ตั้งชื่อ/เปลี่ยนชื่อ/เลือก/ลบสมาชิก Mimo โดยไม่เปลี่ยนชื่อหรือลบเครื่องใน Tailscale |
| Status | CPU/GPU/RAM จริง กราฟรายวันแตะหรือชี้เพื่ออ่านเวลา ประวัติสะสมเฉพาะช่วงที่ Agent สังเกตได้ |
| อุณหภูมิ | NVIDIA GPU อ่านจริงจาก nvidia-smi; CPU ต้องมี sensor provider ที่อ่านได้ ไม่มีก็แสดง — |
| Keys / ORDER | เพิ่ม/แก้ไข/ลบคีย์ Pin สูงสุด 4 ปุ่มต่อเครื่อง Home แสดง 2 ปุ่มแรก แตะ ORDER ดูทั้งหมด |
| รับชุดคีย์ | แตะเลือกทีละปุ่ม แตะซ้ำเพื่อยกเลิก แล้วกดยืนยัน รองรับสูงสุด 6 คีย์ |
| ส่งคีย์จริง | Windows SendInput เมื่อเปิด Agent ด้วย --enable-commands มี auth, target/freshness checks, dedup และ rate limit |
| Clipboard | ดึงข้อความ/ลิงก์/รูปภาพ/เอกสาร/ตารางจาก PC จริง รายการทั่วไป30 นาที ส่วน Favorite เก็บถาวร มีปุ่มบันทึกไฟล์ |
| Files | ส่งให้ PC ที่เลือกจริง สูงสุด 100 MB บันทึกใน Downloads/Mimo และยืนยันเมื่อรับครบ |
| Theme / ข้อมูล | dark/light/system, membership/aliases/config/pins เก็บ local preferences ไม่มี account sync |

ค่าเริ่มต้นเป็น live mode โหมดตัวอย่างต้องเปิดด้วย `--dart-define=MIMO_DEMO=true` เท่านั้น ไม่เติม fixture เป็นค่าจริงเมื่ออ่านข้อมูลไม่ได้

## เครื่องมือที่ใช้และข้อกำหนด

รอบที่ตรวจสอบใช้ Flutter **3.47.7 stable**, Dart **3.13.5**, Windows, Java **25**, Android platform/build-tools **36** และ NDK **28.2.13676358** เก็บ `pubspec.lock` เพื่อทำซ้ำ dependencies เครื่องใหม่ต้องติดตั้ง Flutter และ Android toolchain เอง iOS ต้องใช้ macOS/Xcode

แต่ละ PC ที่จะอ่านค่าหรือส่งคีย์ต้องติดตั้ง Tailscale, เข้าสู่ระบบ และรัน Mimo Agent ของตนเอง โทรศัพท์ต้องเปิด Tailscale VPN และมีสิทธิ์เข้าถึงตาม tailnet policy สำหรับระบบปัจจุบันการเข้าสู่ระบบอัตโนมัติยอมรับบัญชีเจ้าของ PC เท่านั้น

APK ทดสอบที่ build แล้วอยู่ `build/deliverables/Mimo-testing.apk` ส่วน PC package อยู่ `build/deliverables/Mimo-PC-Agent.zip` โฟลเดอร์ build ถูก ignore จึงไม่ตามไปกับ Git clone

## เริ่มระบบจริง

รันคำสั่งจาก repository root:

```powershell
flutter pub get
flutter build web --release
dart run tool/mimo_agent.dart --enable-commands --enable-sharing
```

Agent bind เฉพาะ `127.0.0.1:8765` เปิด terminal อีกหน้าสำหรับ HTTPS ภายใน tailnet:

```powershell
tailscale serve status
tailscale serve --bg --https=8443 http://127.0.0.1:8765
```

ตรวจว่าพอร์ต 8443 ไม่ชนบริการอื่นก่อนเปลี่ยน หาก Tailscale ขอเปิด Serve/HTTPS ให้เจ้าของบัญชีทำตามหน้าอนุมัติ ใช้ URL ที่ CLI รายงาน เช่น `https://your-pc.your-tailnet.ts.net:8443` ไม่ใช้ Funnel และไม่ reset บริการ Serve ทั้งเครื่อง การตั้งค่า Serve คงอยู่ แต่ Agent ต้องเปิดค้างไว้

เปิด URL นี้เพื่อใช้ Flutter Web กับ Agent แบบ origin เดียวกัน สำหรับอ่านค่าอย่างเดียวให้รัน Agent โดยไม่ใส่ `--enable-commands` รหัสจับคู่ localhost สำรองสร้างใน `.local/agent/pairing.local.json` เมื่อเริ่ม Agent ห้ามเผยแพร่ไฟล์นี้

หากใช้ PC zip ให้แตกทั้งชุดแล้วเปิด `Start Mimo Agent.cmd` แทน Dart command ข้างบน ดู [PC_AGENT_SETUP.md](docs/PC_AGENT_SETUP.md) ห้ามเปิด Agent สองตัวชนพอร์ต 8765

### Android และการเข้าสู่ระบบ

1. ติดตั้ง Mimo APK และแอป Tailscale ทางการบนโทรศัพท์ เชื่อม tailnet ด้วยบัญชีเจ้าของ PC
2. เปิด Mimo เลือกเข้าสู่ระบบด้วย Tailscale หากแอปเปิด Tailscale ให้ทำการเข้าสู่ระบบ/เชื่อมต่อแล้วกลับ Mimo
3. APK ตั้งค่า gateway ของ PC ไว้ตั้งแต่ build แล้ว เมื่อกลับจาก Tailscale จะแสดงรายการเครื่องอัตโนมัติ ไม่ต้องกรอก URL หรือรหัสจับคู่
4. ค้นหาเครื่อง เลือก PC ตั้งชื่อแสดงแล้วบันทึก จากนั้นเลือกเครื่องที่ Header

```powershell
flutter devices
flutter run -d <device-id> --dart-define=MIMO_AGENT_URL=https://your-pc.your-tailnet.ts.net:8443
```

APK ที่เตรียมบนเครื่องพัฒนาตั้ง gateway ของเครื่องพัฒนาแล้ว หากย้าย gateway ไป PC แรกเครื่องอื่น ให้ผู้พัฒนา build ด้วย -AgentUrl ของเครื่องนั้น โดยไม่ใส่ token ลง source รายการเครือข่ายมาจาก PC Agent ที่เรียก CLI ไม่ได้อ่านฐานข้อมูลส่วนตัวของแอป Tailscale Android หาก gateway แรกเข้าไม่ถึง ยังไม่มี automatic gateway failover

## Build APK และ PC Agent

ดับเบิลคลิก `Build APK.cmd` เพื่อรัน pub get → format → analyze → tests → build APK หาก checks ล้มเหลวจะหยุด หรือกำหนด URL เอง:

```powershell
./tool/build-apk.ps1 -AgentUrl https://your-pc.your-tailnet.ts.net:8443
```

ส่ง `-FlutterPath` และ `-AndroidSdk` ได้เมื่อสคริปต์หา SDK ไม่พบ ผลลัพธ์เป็น **debug-signed testing APK** ยังไม่ใช่ production signing หรือ Play Store release Android package ปัจจุบันคือ `com.mimo.mimo_companion`, min SDK 24, target 36

สร้าง executable ของ PC หลัง build web:

```powershell
./tool/build-agent.ps1 -DartPath dart
```

ได้ไฟล์ใน `build/agent/` รวม executable, metric script, launcher, คู่มือ และ web build ถ้ามี สคริปต์นี้ไม่ได้สร้าง zip ให้เอง เมื่อต้องแพ็กให้เลือกเฉพาะไฟล์แจกจ่าย ห้ามรวม `.local/agent/` หรือ installer downloads ที่สร้างตอนใช้งาน

### Path ภาษาไทยบน Windows

พบ Flutter analyzer/shader compiler crash บน path non-ASCII ในเครื่องพัฒนา แนะนำ clone SDK และโปรเจกต์ไว้ path ภาษาอังกฤษ หรือใช้ temporary `subst` alias สำหรับทั้ง SDK และ project สคริปต์ APK รู้จัก alias ที่มีอยู่ แต่ไม่ควร commit drive letters หรือ SDK paths ของเครื่องหนึ่งลง repository

`android/gradle.properties` ปิด Kotlin incremental caching เพื่อแก้ Pub cache บน C: กับ project alias คนละ drive อย่าเปิดคืนโดยไม่ทดสอบกรณีนี้

## ทดลอง UI โดยไม่ต่อเครื่อง

```powershell
flutter run -d chrome --dart-define=MIMO_DEMO=true
```

ทดสอบผ่าน browser บนโทรศัพท์ใน Wi-Fi เดียวกันได้ด้วย:

```powershell
flutter run -d web-server --web-hostname <IPv4-Wi-Fi-PC> --web-port 3016 --dart-define=MIMO_DEMO=true
```

วิธีนี้เป็น Flutter Web โหมดจำลอง ไม่พิสูจน์ native Android หรือการเชื่อม Agent จริง ไม่ใช้ HTTP LAN ของ demo เป็นทางลัดสำหรับคำสั่ง PC จริง

## โครงสร้างและเส้นทางข้อมูล

```text
lib/main.dart                   เริ่ม repository/store และเลือก live/demo
lib/domain/models.dart          machine ID, aliases, Agent readiness, metrics
lib/domain/shortcuts.dart       key allowlist, normalization, chord capture
lib/data/services.dart          discovery/repository interfaces และ mocks
lib/data/agent_client.dart      HTTPS sessions, discovery, target routing
lib/data/tailscale_bridge.dart  MethodChannel เปิดแอป Tailscale บน Android
lib/state/mimo_store.dart       state, guards, pins, actions, persistence
lib/ui/mimo_app.dart            shell, header, onboarding, lifecycle
lib/ui/screens.dart             หน้าจอหลัก (part ของ mimo_app.dart)
lib/ui/sheets.dart              forms/modals (part ของ mimo_app.dart)
lib/ui/chord_keyboard.dart      multi-touch PC keyboard
lib/ui/design.dart              สี ฟอนต์ theme และองค์ประกอบร่วม
android/                       Android platform และ Tailscale launch bridge
assets/                        artwork, fonts, fixture และที่มา assets
 tool/mimo_agent.dart           entry point ของ Windows Agent
 tool/agent/server.dart         HTTP/auth/routes/guards/static web
 tool/agent/collector.dart      Tailscale, telemetry และ observed usage
 tool/agent/keys.dart           Windows SendInput FFI
 tool/agent/windows_metrics.ps1 trusted Windows metric collector
 tool/build-apk.ps1             ตรวจแล้ว build APK
 tool/build-agent.ps1           compile และจัดไฟล์ PC Agent
 test/                         store/widget/API/routing/optional live tests
 docs/                         คู่มือรายละเอียด หลักฐาน และภาพหน้าจอ
 handoff.md                    จุดเริ่มต้นสำหรับผู้รับช่วงต่อ
```

```text
Flutter → MimoStore → AgentClient → Tailscale Serve HTTPS → Windows Agent
                                                              ├─ Tailscale CLI: inventory / whois
                                                              ├─ CIM / NVIDIA / sensor provider: metrics
                                                              └─ SendInput: allowlisted keyboard chord
```

แต่ละ target PC ใช้ session แยก ตรวจ machine ID ก่อนอ่าน/ส่งคีย์ ไม่ส่ง gateway token ต่อไปอีกเครื่อง `machine.id` เป็น identity; hostname, alias และ IP เปลี่ยนได้ การตั้งชื่อใน Mimo ไม่เปลี่ยน Tailscale

## Persistence และขอบเขตสิทธิ์

`SharedPreferencesAsync` ใช้คีย์ `mimo:flutter_prototype:v1`, schemaVersion 1 เก็บ membership/aliases, active ID, per-device groups/buttons/bindings/pins, favorites, theme และ gateway URL มี queued snapshot writes และ `flush()` สำหรับทดสอบ ข้อมูลแยกตามแพลตฟอร์ม/browser origin ไม่ migrate HTML localStorage และไม่ sync ข้ามเครื่อง

Sessions อยู่ใน memory ไม่เก็บ API token/password ลง frontend หรือ preferences Agent ตรวจ Serve identity, CLI whois และบัญชีเจ้าของ PC ก่อนออก session การเปิด commands เท่ากับเชื่อถืออุปกรณ์ Tailscale ที่ผ่านบัญชีเจ้าของตามเงื่อนไขนี้ ยังไม่มีสิทธิ์แยกต่อแอป Android คีย์ส่งไปหน้าต่างที่มี focus บน Windows; UAC, locked desktop หรือแอปที่สิทธิ์สูงกว่าอาจปฏิเสธ ไม่ bypass สิทธิ์ และไม่มี arbitrary shell endpoint

## ทดสอบและหลักฐาน

```powershell
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
flutter test --dart-define=CAPTURE=true
flutter build web --release
```

ผลบันทึกล่าสุด: analyzer ผ่าน, tests 29 กลุ่มผ่าน, optional live tests 4 กลุ่มไม่รันใน default suite; build Web และ APK ผ่าน ตรวจลายเซ็น APK แล้ว ทดสอบ compiled PC Agent ผ่าน HTTPS จริงพร้อม F24 และอ่าน telemetry จริงได้

ภาพสาธารณะ 55 PNG อยู่ `docs/screenshots/` เป็น Flutter widget renders รวม 320/390 px ไม่ใช่ภาพจากโทรศัพท์จริงและไม่ใช่ pixel-perfect Canva comparison ยังไม่ได้ทดสอบติดตั้ง APK/Tailscale return flow/multi-touch บนเครื่อง Android จริง หรือ target PC ตัวที่สอง รายละเอียด/ค่า SHA-256 อยู่ [VALIDATION.md](docs/VALIDATION.md) และ [build-evidence.json](docs/build-evidence.json) รอบแก้ login รุ่น 1.0.1+2 รัน regression suite และ build ใหม่

CPU temperature ยังรอผู้ใช้เปิด LibreHardwareMonitor ด้วย Run as administrator แล้วแจ้งกลับ **ยังไม่ยืนยันว่าเปิดหรืออ่านค่าได้แล้ว** ส่วน GPU อ่านค่าจริงสำเร็จ เครื่องมือ sensor ไม่รวมใน APK/Agent zip ห้ามแทนด้วยค่าจำลองหรือปิด Windows protection เพื่อบังคับ driver

## เตรียม GitHub และเอกสารที่เกี่ยวข้อง

Push เฉพาะ repository `mimo_flutter` เก็บ `pubspec.lock`; ไม่รวม `.tooling`, build, `.local`, pairing/session files, signing keys หรือ local SDK config ยังไม่ได้ commit, ตั้ง remote หรือ push แทนผู้ใช้ Workflow ใน `.github/workflows/flutter.yml` มี format/analyze/test/build web แต่ยังไม่ได้ยืนยันรันบน GitHub และไม่ได้ build Android ใน CI

- [handoff.md](handoff.md): invariants, งานค้าง และวิธีสานงาน
- [Android / ORDER / commands](docs/ANDROID_AND_COMMANDS.md)
- [การเชื่อมข้อมูลจริง](docs/LIVE_CONNECTION.md)
- [คู่มือ PC package](docs/PC_AGENT_SETUP.md)
- [ความเทียบเคียง prototype](docs/PARITY.md)
- [ที่มา assets](assets/PROVENANCE.md)

ฟอนต์ใช้ Poppins, Noto Sans Thai และ Lilita One พร้อม license แทน Binate ที่มีข้อจำกัดแจกจ่าย ภาพ Canva เป็น third-party artwork ตาม provenance การ build ผ่านไม่ได้ยืนยันสิทธิ์เผยแพร่ภาพเหล่านั้น

## แก้ไข login รุ่น 1.0.1+2

Agent รุ่นเก่าบังคับ whois.Node.MachineAuthorized=true แต่ CLI ของ Android peer จริงไม่ส่งฟิลด์นี้ จึงปฏิเสธโทรศัพท์ รุ่นนี้ตรวจ whois stable ID/owner ร่วมกับ IP และ current network map พร้อมปฏิเสธ explicit unauthorized, expired keys และสมาชิกที่ไม่ตรงเงื่อนไข

หน้าปกติไม่มี Agent URL หรือช่อง pairing แล้ว กลับจาก Tailscale → ค้นหา → เลือก PC ได้เลย มีสถานะกำลังค้นหา ข้อผิดพลาด และลองใหม่ การเชื่อมซ้อนใช้ Future เดียวกัน ไม่คืน failure เงียบ ๆ หากค่าปลายทางเก่าติดต่อไม่ได้จะลอง gateway ที่ build ไว้

ต้องอัปเดตทั้ง APK และ PC Agent เพราะสาเหตุหลักอยู่ที่ backend ด้วย การทดสอบใช้ lifecycle/MethodChannel fixtures และข้อมูล whois ของโทรศัพท์จริงผ่าน localhost ที่ใส่ Serve-format headers ยังไม่ได้ยืนยัน HTTP request ที่ส่งจากโทรศัพท์จริงในรอบนี้

## รุ่น 1.1.0+3 — Files, Clipboard และการแจ้งเตือน

อ่าน [SHARING_AND_NOTIFICATIONS.md](docs/SHARING_AND_NOTIFICATIONS.md) สำหรับขอบเขตล่าสุด ซึ่งแทนข้อความเก่าที่ระบุว่า file transport/PC clipboard ยังไม่ทำ

- ส่งไฟล์จริงผ่าน HTTPS ไปยัง PC ที่เลือก รับสูงสุด 100 MB ไม่เขียนทับและไม่เปิดไฟล์เอง UI รอ receipt จาก PC ก่อนแจ้งสำเร็จ
- Agent เปิดด้วย --enable-sharing จึงจะรับไฟล์และอ่าน clipboard; launcher ใหม่เปิดพร้อม --enable-commands แล้ว
- Clipboard อ่าน Unicode text, links, PNG/DIB image, copied files ใน Explorer และ HTML/TSV tables อาจไม่ได้รองรับ virtual files ของทุกโปรแกรม เช่น attachment ที่ไม่ได้เป็นไฟล์จริงบนดิสก์
- รายการและไฟล์แนบ clipboard อยู่ในหน่วยความจำ เก็บสูงสุด 30 นาทีจากเวลารับเข้า Mimo ทั้ง Agent และแอปตรวจ expiry ไม่มี raw clipboard history ใน live preferences ข้อความที่เพิ่มเองใน live mode ก็เป็นข้อมูลชั่วคราว
- รูป/เอกสาร/ตารางมีปุ่มบันทึก ใช้ system save dialog; การหมดอายุไม่ลบต้นฉบับ ไม่เคลียร์ Windows clipboard และไม่ลบไฟล์ที่ผู้ใช้บันทึกเอง
- แจ้งเตือนในแอปขณะเปิดใช้งานเท่านั้น มีจำนวนยังไม่อ่านและรายการในกระดิ่ง ไม่ใช้ Android background service การแจ้งเตือน clipboard ติดตาม PC ที่เลือกอยู่; สถานะ Tailscale ติดตามเครื่องที่เพิ่มไว้ ไม่แจ้งซ้ำทุก poll
- แป้นคีย์ลัดเลือกทีละปุ่ม กดยืนยันเอง; ยกเลิกวิธีกดหลายปุ่มค้างพร้อมกันแล้วปล่อยเพื่อยืนยัน

ทดสอบ real HTTPS upload แล้วตรวจ byte-for-byte บนดิสก์จริง และทดสอบตัวอ่าน clipboard Windows จริงโดยไม่แก้ clipboard ของผู้ใช้ การทดสอบชนิดข้อมูลครบ 5 หมวดและ expiry ใช้ fixture API กับนาฬิกาจำลอง ไม่ใช่การรอ 30 นาทีจริงหรือทดสอบคัดลอกจากทุกโปรแกรม การติดตั้ง APK และ system file dialogs บนโทรศัพท์จริงยังต้องตรวจ

## Permanent Favorites and approved launcher icon — 1.1.1+4

- User selected concept A with round orange glasses and a cheerful smile, then explicitly reverted the phone-waving revision: final icon has NO phone. Approved source: assets/branding/mimo-launcher.png (same as docs/design/icon-a-glasses-happy-v2.png).
- Generated with built-in imagegen using the existing mascot as identity reference. Prompt: cheerful cream long-eared Mimo wearing round coral glasses, happy eyes and smile, two paws on coral desktop monitor, orange/black palette, no lettering or phone. Preview sheets/rejected variants stay under docs/design and are not launcher assets.
- Reproduce platform resources with `dart run flutter_launcher_icons` using flutter_launcher_icons.yaml. Android adaptive background black, foreground inset16%; generated legacy densities, iOS icons and web icons. Production iOS build remains untested.
- Favorite items no longer expire, including images/documents/tables. PC-sourced favorites persist metadata and binary attachments in .local/agent/favorites on that PC, excluded from source/package. Favorites bypass temporary count/byte eviction limits; disk capacity remains the limit and write failures are reported rather than pretending success.
- Favorite metadata/local text are retained in app preferences so relaunch keeps the cards. PC attachments stay on the PC and require it online to retrieve if not cached; do not claim an offline phone attachment vault.
- Unfavorite starts a NEW 30-minute expiry timer. Delete removes the Mimo archive item and stored attachment on the PC, not the original source file or user-saved copies. Deleting a PC-sourced item is now an authenticated backend DELETE, not merely hiding the local card.
- New authenticated POST /v1/devices/{id}/clipboard/{clipId}/favorite with strict boolean {favorite: true/false}; DELETE /v1/devices/{id}/clipboard/{clipId}. Keep target/owner/session/sharing checks. Persistent writes are serialized, manifest replaced atomically, attachments flushed before success. Read-only Agent must not expose archived attachments without --enable-sharing.
- Tests in favorites_test.dart verify survival after31 minutes, cache pressure, Agent restart, exact attachment bytes, unpin TTL, archive deletion, local preferences reload and manual removal. Sharing regression remains covered. APK and Agent both need updating for Favorite API.

GitHub repository: https://github.com/LORR01/Mimo-Final-Project — private repository; source อยู่ที่ root ของ repo นี้ ไม่รวม SDK, APK/build หรือข้อมูลส่วนตัวของ Agent.
