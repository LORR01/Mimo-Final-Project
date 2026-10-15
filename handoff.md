> Current implementation: 1.1.1+4 (16 October 2026). Read docs/SHARING_AND_NOTIFICATIONS.md first for live files, all five clipboard categories with 30-minute TTL except permanent Favorites, in-app notifications and sequential key selection. These supersede the older no-file/no-clipboard and simultaneous-release notes retained below.
# Mimo Flutter — Handoff

อัปเดต: 16 ตุลาคม 2026 เอกสารหลักสำหรับ AI/ผู้พัฒนาที่รับช่วงต่อ อ่าน [README.md](README.md) ก่อน แล้วอ่าน [ANDROID_AND_COMMANDS.md](docs/ANDROID_AND_COMMANDS.md), [VALIDATION.md](docs/VALIDATION.md) และ [build-evidence.json](docs/build-evidence.json)

เอกสารนี้อธิบายสถานะที่ตรวจสอบแล้ว ไม่ใช่การรับรองว่า process, Tailscale หรือ sensor ยังทำงานอยู่เมื่อกลับมาในรอบใหม่ ต้องตรวจ runtime อีกครั้งก่อนกล่าวว่าออนไลน์

## ขอบเขตที่ผู้ใช้กำหนด

- ทำงานใน `mimo_flutter` ซึ่งเป็น Flutter repository แยก ไม่แก้ prototype HTML ข้างเคียง
- รักษาการทำงานและดีไซน์ Mimo: artwork/mascot, rounded header, metric palette, ฟอนต์ไทย และหน้าจอโทรศัพท์
- งานล่าสุดเปลี่ยนจาก mock เป็น live Tailscale discovery/telemetry/Windows keyboard control พร้อม Android testing APK แต่ demo ยังแยกเปิดได้
- ผู้ใช้อนุญาต private Tailscale Serve แล้ว ไม่ใช่ public Funnel หรือการ reset Serve ของบริการอื่น
- ไม่ commit/push หรือตั้ง remote โดยอ้างว่างานเอกสารให้สิทธิ์ทำสิ่งเหล่านั้น

## สถานะการส่งมอบล่าสุด

| สิ่งที่ทำ | หลักฐาน/ข้อจำกัด |
|---|---|
| Flutter widgets ทั้งระบบ | Android/iOS/web scaffolds; ไม่ใช้ HTML runtime/WebView |
| Tailscale Android login | MethodChannel เปิด package com.tailscale.ipn แล้ว resume bootstrap; APK compile ผ่าน แต่ยังไม่ทดสอบ return flow บนโทรศัพท์จริง |
| Tailnet inventory | Windows Agent อ่าน CLI ผ่าน gateway; caller exclusion ใช้ verified stable ID; ไม่อ่าน private storage ของ Tailscale Android |
| Real metrics | CPU/GPU/RAM และ observed usage; NVIDIA load/temp จาก GPU เดียวกัน |
| Real commands | allowlisted chords ผ่าน SendInput; compiled exe ทดสอบ HTTPS auth + F24 จริงผ่าน |
| Keys / pins | pin ต่อ PC สูงสุด 4, Home 2, ORDER ทั้งหมด; edit/delete/persistence มี tests |
| PC keyboard | เลือกทีละปุ่ม แตะซ้ำเพื่อยกเลิก แล้วกดยืนยัน; modifier strip และปุ่มเลื่อนแป้น |
| Android artifact | debug-signed build ผ่าน ตรวจ signature แล้ว; ไม่ใช่ production release |
| ไม่เสร็จ | CPU sensor verification, physical sharing dialogs on Android, bidirectional clipboard writes, iOS build |

รอบก่อนแก้เอกสาร: tests 29 กลุ่มผ่าน, optional live tests 4 กลุ่ม skip โดย default, analyzer ไม่มีปัญหา, release web build ผ่าน, public widget PNGs 55 ภาพ ผลเก่าใน VALIDATION ให้ดูหัวข้อ Latest delivery ท้ายไฟล์เป็นหลัก รุ่น login fix 1.0.1+2 รัน checks และ build ใหม่

## จุดเริ่มอ่านโค้ด

| ไฟล์ | หน้าที่ |
|---|---|
| lib/main.dart | เลือก live/demo, initialize store/repository, startup connection |
| lib/domain/models.dart | machine/alias/readiness/metrics/config |
| lib/domain/shortcuts.dart | key allowlist, normalization และ ChordCapture |
| lib/data/services.dart | injectable discovery/repository, mocks, preferences |
| lib/data/agent_client.dart | session/auth, gateway discovery, separate target sessions |
| lib/data/tailscale_bridge.dart | native Tailscale open/install handoff |
| lib/state/mimo_store.dart | state, persistence queue, guards, pins, commands และ telemetry lifecycle |
| lib/ui/mimo_app.dart | UI library, header/selector, onboarding และ lifecycle |
| lib/ui/screens.dart / sheets.dart | Dart parts ของ mimo_app.dart ห้าม import เป็น library แยก |
| lib/ui/chord_keyboard.dart | multi-pointer keyboard และ desktop key events |
| lib/ui/design.dart | palette/theme/fonts/shared components |
| android/app/src/main/kotlin/com/mimo/mimo_companion/MainActivity.kt | Android MethodChannel bridge |
| tool/mimo_agent.dart | Agent entry point, flags และ runtime paths |
| tool/agent/server.dart | auth/session/API/routes/command limits/static assets |
| tool/agent/collector.dart | CLI/telemetry collection และ usage ledger |
| tool/agent/keys.dart | Windows FFI executor (injectable ใน tests) |
| tool/agent/windows_metrics.ps1 | trusted CIM/WMI/NVIDIA metric collector |
| tool/build-apk.ps1 / build-agent.ps1 | validation/build และ PC executable packaging |

## Invariants ที่ต้องรักษา

### Identity และ Tailscale

1. machine.id คือ stable identity ห้ามใช้ชื่อแสดง, hostname หรือ IP เป็น primary key Alias เป็นข้อมูล Mimo ไม่ใช่การ rename เครื่อง Tailscale
2. การพบเครื่อง/ออนไลน์ ไม่เท่ากับ Agent พร้อมใช้งาน ต้องมี fresh verified snapshot และ capability ก่อนส่งคำสั่ง
3. /v1/tailscale-session ต้องตรวจ loopback Serve identity, HTTPS/host, CLI whois, authorized node และ user ID ของเจ้าของ PC อย่าเปิด inventory แบบไม่ต้องยืนยันตัวตน ห้ามยอมรับ Funnel เพื่อใช้ flow นี้
4. clientDeviceId มาจาก caller ที่ตรวจจริง ซ่อนเฉพาะเครื่องที่เปิดแอปโดยไม่ลบ alias/config เดิม หากเปิดเว็บบน Agent PC มันจะซ่อน PC นั้นตามหลักเดียวกัน อย่าลบ Self ของ CLI ทิ้งเสมอ เพราะโทรศัพท์ยังต้องเลือก Agent PC ได้
5. แต่ละ target PC มี Agent/Serve :8443 ของตนเอง AgentClient ต้องใช้ session ของ target ตรวจ stable ID และ DNS tailnet อย่า forward gateway bearer token ไป peer
6. Native app ใช้ Tailscale VPN ที่ติดตั้งอยู่ แต่ inventory ต้องผ่าน configured gateway ที่เข้าถึงได้ ยังไม่มี gateway failover อัตโนมัติ และไม่มี embedded Tailscale SDK
7. Sessions อยู่ใน memory เท่านั้น gateway URL ไม่ใช่ secret แต่ห้ามฝัง API token ใน source/APK/preferences/log/docs

### Commands และ UI

1. Agent ไม่เปิด commands โดย default ต้อง --enable-commands เท่านั้น UI และ store ต้องตรวจ readiness/freshness/capability/busy พร้อมกัน
2. Endpoint รับ typed chord/requestId แบบ strict, allowlist, bounded dedup และ rate limit อย่าเพิ่ม arbitrary shell/text injection route โดยอ้อม
3. SendInput ส่งลง focused Windows window และยอมรับข้อจำกัด UIPI/UAC/locked desktop ไม่ bypass หรือยกระดับ Agent เพื่อหลบข้อจำกัด
4. Pins คือ ordered IDs ต่อ device ใน config.pins สูงสุด 4; Home แสดง 2 แรก และ ORDER เปิดทั้งหมด การ edit ต้องคง ID/pin; delete ต้องล้าง pin เก่า
5. UI เลือกคีย์ทีละปุ่ม แตะซ้ำเพื่อนำออก และยืนยันเฉพาะปุ่มยืนยัน Modifier-only ยัง invalid ห้ามกลับไปใช้ release-to-confirm
6. Keyboard มี modifier strip คงที่และ scroll/arrow navigation ไม่ต้องใช้ multi-touch อีกแล้ว
7. Form controllers ต้องอยู่พ้น reverse animation ของ sheet และไม่สร้างใหม่ทุก telemetry rebuild
8. Dropdown ต้องอยู่เหนือ mascot และ header คงขอบโค้งทั้งเปิด/ปิด ใช้ metric colors CPU ชมพู/GPU ส้ม/RAM ฟ้า/temperature เหลือง รวม Focus และ bars

### State และข้อมูล

1. SharedPreferencesAsync key mimo:flutter_prototype:v1 / schemaVersion 1; write snapshot ต่อคิว ใช้ flush() ก่อนตรวจ persisted assertions
2. เก็บ membership/aliases/config/pins/favorites/theme/gateway/active ID; clipboard ใน live mode เป็น memory-only ไม่เก็บ session หรือรหัสผ่าน เมื่อเปลี่ยน schema ต้องวาง migration
3. Empty membership ที่บันทึกแล้วต้องคงว่าง ไม่เติม seed กลับ การลบ active เลือก ready → first → null
4. Live mode ห้าม fallback เป็น seed metrics หรือย้อนหลังเวลาปลอม ประวัติเป็นช่วงที่ Agent สังเกตได้เท่านั้น
5. File target ต้องจับตอนเปิด picker และตรวจซ้ำก่อนส่งจริง มี capability/freshness guards และรอ receipt ส่วน clipboard เป็น PC retrieval ตาม TTL ไม่เขียน clipboard กลับ PC
6. Dispose timers/listeners และกัน stale async response หลังเปลี่ยน device/connection อย่าทำ auto-retry รัวเมื่อ connection ล้มเหลว

## วิธีรันและ build ต่อ

```powershell
flutter pub get
flutter build web --release
dart run tool/mimo_agent.dart --enable-commands --enable-sharing
```

อีก terminal ตรวจ Serve เดิมก่อนเปิด Mimo:

```powershell
tailscale serve status
tailscale serve --bg --https=8443 http://127.0.0.1:8765
```

ห้าม reset หรือเขียนทับบริการเดิมที่พอร์ตอื่น Agent bind localhost:8765 เปิดผ่าน HTTPS ที่ CLI รายงานและโทรศัพท์ต้องเชื่อม Tailscale ด้วยบัญชีที่ผ่านเงื่อนไขเจ้าของ สำหรับโหมด UI-only ใช้ `flutter run -d chrome --dart-define=MIMO_DEMO=true`

```powershell
./tool/build-apk.ps1 -AgentUrl https://your-pc.your-tailnet.ts.net:8443
./tool/build-agent.ps1 -DartPath dart
```

APK script รัน format/analyze/tests ก่อน build ใช้ Build APK.cmd ได้เช่นกัน Android package com.mimo.mimo_companion, min24/target36 ใช้ debug signing ใน testing artifact ต้องจัด production signing/application identity ก่อนเผยแพร่จริง

PC executable ต้องมี tool/agent/windows_metrics.ps1 อยู่ตามโครงสร้างที่ build script คัดลอก และมี build/web หากต้อง serve เว็บ รันจาก working directory ของชุดไฟล์ที่แตก ไม่รัน Agent ซ้อนตัวเดิมบน 8765

### เครื่องพัฒนาและปัญหาที่ทราบ

- SDK version ที่ยืนยันแล้ว: Flutter3.47.7/Dart3.13.5, Java25, Android36/NDK28.2
- Windows path ภาษาไทยทำให้ analyzer/impellerc crash ใช้ English paths หรือ temporary subst สำหรับ SDK และ project ทั้งคู่ APK script ค้น alias ผ่าน Unicode API อย่า commit local aliases/local.properties
- kotlin.incremental=false ป้องกัน cache relativize ข้าม drive ระหว่าง Pub cache กับ project alias ไม่ใช่ตัวปิด tests
- file_picker รุ่นที่ lock build ได้จริง มี advisory เรื่อง migration ใน Flutter อนาคต ไม่ต้อง upgrade ทั้งชุดระหว่างแก้งานเล็กโดยไร้เหตุผล
- Widget capture ต้อง pump frame ก่อน toImage และโหลด MaterialIcons/Poppins/LilitaOne/NotoThai ให้ครบ มิฉะนั้นภาพ/การจับภาพอาจผิด

## ทดสอบที่เหมาะกับงาน

```powershell
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
flutter test test/keyboard_ui_test.dart --dart-define=CAPTURE=true
```

- store_test / live_store_test: persistence, identity, readiness, empty/error/stale states
- shortcuts_test / keyboard_ui_test: chord capture, add/edit, pin limit/order/isolation และ mobile layout
- agent_server_test / agent_commands_test: auth, strict API, target, expiry/rate/dedup, canceled download
- device_routing_test: session แยกต่อ target และ wrong-ID rejection โดย fixtures
- ui_test: mobile screens/theme/forms/selector; CAPTURE=true สำหรับภาพหลัก

Optional tests คุยกับเครื่องจริง ต้องรู้ Agent/state/URL ที่กำลังใช้งาน ห้ามนำไปเปิดเป็น CI default:

```powershell
flutter test test/live_identity_test.dart --dart-define=MIMO_IDENTITY_TEST=true --dart-define=MIMO_AGENT_URL=https://your-pc.your-tailnet.ts.net:8443
flutter test test/live_machine_test.dart --dart-define=MIMO_LIVE_TEST=true
flutter test test/live_command_test.dart --dart-define=MIMO_COMMAND_TEST=true --dart-define=MIMO_AGENT_URL=https://your-pc.your-tailnet.ts.net:8443
```

live_machine_test ใช้ localhost และ .local/agent โดย default หากรัน compiled package ให้เพิ่ม `--dart-define=MIMO_AGENT_STATE=build/agent/.local/agent` ตัว live_command_test **ส่ง F24 จริง** อย่ารันโดยไม่ตรวจ target และบริบท desktop ห้าม print pairing code/session token ภาพข้อมูลเครื่องจริงอยู่ .local/verification ซึ่งถูก ignore

## งานค้างและขั้นตอนถัดไป

1. **CPU temperature:** ผู้ใช้บอกว่าจะเปิด LibreHardwareMonitor เองแล้วแจ้งกลับ ยังไม่มีข้อความยืนยันว่าเปิดแล้ว เครื่องมือ official v0.9.6 เตรียมใน tooling และตรวจ hash รอบก่อนแล้ว แต่ไม่รวมใน deliverable รอคำยืนยัน จากนั้นตรวจ WMI/provider และ API ว่ามี CPU sensor จริง ห้ามอ้างว่าอ่านได้จากคำว่า “จะเปิด” และห้ามใช้ ACPI zone เป็น CPU temperature ทดแทน
2. **Android จริง:** ติดตั้ง APK บนโทรศัพท์ ทดสอบไม่มี/มี Tailscale, login/cancel/resume, gateway failure, discovery/self exclusion, add/rename/remove/reload และ multi-touch Ctrl+C/Ctrl+V/F12 รวม offline/no-Agent
3. **PC ตัวที่สอง:** ติดตั้ง Agent/Serve ที่ peer แล้วพิสูจน์ identity/session isolation และข้อมูล/คำสั่งส่งเข้า target จริง ตอนนี้ยืนยันด้วย fixtures เท่านั้น
4. **File transport / PC clipboard:** ทำ PC receiving และ read-only clipboard retrieval แล้ว ต้องทดสอบ native file/save dialogs และ copied formats ของโปรแกรมใช้งานจริงเพิ่มตามคู่มือ SHARING_AND_NOTIFICATIONS.md
5. **Production:** signing, distribution/updates, artwork redistribution rights, iOS build และ CI Android ยังไม่เสร็จ แยกจากความสำเร็จของ debug build

## ผลลัพธ์และไฟล์ที่ต้องรักษา

- build/deliverables/Mimo-testing.apk และ Mimo-PC-Agent.zip เป็น ignored artifacts ดู hash/ขนาดที่ docs/build-evidence.json หาก build ใหม่ให้อัปเดต evidence อย่าคัดเลขเก่ามาอ้าง
- README.md เป็นคู่มือเริ่มต้น; handoff.md นี้เป็นเอกสารรับช่วงหลัก; docs/AI_HANDOFF.md ชี้มาที่นี่เพื่อไม่ให้มีสองชุดขัดกัน
- docs/ANDROID_AND_COMMANDS.md และ PC_AGENT_SETUP.md อธิบาย architecture/installation; LIVE_CONNECTION.md/PARITY.md เป็นรายละเอียดสนับสนุน
- docs/VALIDATION.md เก็บประวัติผลจริงพร้อม limitations ภาพ public 51 PNG เป็น widget renders ไม่ใช่ physical phone หรือ golden tests
- ห้ามรวม .local, tokens, pairing codes, usage history, keystores, SDK/cache หรือ APK ใน source commit โดยไม่ตั้งใจ ไม่เก็บ real tailnet inventory/hostname ในเอกสารที่เตรียม push

เมื่อทำงานต่อให้รายงานสิ่งที่เปลี่ยน สิ่งที่ทดสอบจริง สิ่งที่ยังจำลอง และ human-only blockers แยกชัดเจน ไม่ถือว่า compile ผ่านเท่ากับติดตั้งหรือทำงานบนโทรศัพท์แล้ว

## Login blocker fixed — 1.0.1+2

- Real CLI output for Android peers omits Node.MachineAuthorized. Previous fixtures always supplied it and hid the production bug. Do not restore the old `!= true` check.
- Agent now requires consistent Serve login/whois owner/stable ID, current CLI Running state, matching current peer ID/UserID/source IP and InNetworkMap=true (Self handled separately), no explicit authorization denial and no expired whois key. Missing authorization field alone is not proof of authorization; current network membership is also mandatory.
- test/agent_server_test.dart uses real-shaped omitted fields and rejects wrong membership/owner/IP, unknown ID, explicit denial and expiry.
- test/tailscale_login_test.dart mocks Android app handoff/lifecycle and verifies delayed startup, shared concurrent requests, error/retry and a visible device list without URL fields. It captures tailscale-error-390.png and tailscale-devices-390.png.
- _discoverySheet is the single normal connection/device-picker surface. _connectAgentSheet is a compatibility method delegating to it. No URL/pairing form in app UI; /v1/pair remains available for localhost tests.
- MimoStore.configuredGateway comes from MIMO_AGENT_URL at build (web uses origin). connectAgent coalesces in-flight requests and retries configured gateway if a saved endpoint fails. Do not accept a login merely because another app was opened.
- To change the FIRST gateway for another installation, rebuild with -AgentUrl. Earlier notes about changing it in a connection panel are obsolete. Automatic discovery across arbitrary tailnets without a known gateway remains unimplemented; do not imply opening the installed Android app exports its inventory.
- Compiled backend must be replaced along with APK; updating just the phone cannot fix the old server's rejection. Preserve the private Serve mapping; update executable/package and restart only Mimo Agent.
- Current phone CLI identity was accepted by the compiled fixed Agent using loopback requests with Serve-format headers; caller excluded and Agent PC included. This is not an end-to-end request originating on physical Android. APK physical install remains to be verified.

## Sharing handoff — 1.1.0+3

- New code: tool/agent/clipboard.dart (Windows read-only FFI), sharing.dart (bounded exclusive receiving), sharing_test.dart / sharing_ui_test.dart / live_sharing_test.dart.
- --enable-sharing opts into OS clipboard reading and file receiving. Agent defaults remain disabled. Keep authentication, stable-target checks and existing Tailscale boundaries on all new routes.
- Files: raw streamed body, known Content-Length, X-Mimo-Filename = base64url UTF-8 basename. Limit 100 MiB. Temporary .part cleaned on failure; publish only complete receipt; UUID-like prefix avoids overwrites; reject traversal, Windows reserved names and invalid characters. Never execute uploads. PC destination is USERPROFILE/Downloads/Mimo.
- Clipboard: GetClipboardSequenceNumber prevents resurrecting unchanged expired data. CF_UNICODETEXT, registered HTML/PNG, CF_DIB and CF_HDROP supported. Tables use spreadsheet type to match existing tabs. No executable HTML rendering; attachments downloaded with octet-stream/nosniff/attachment headers. Virtual Outlook/cloud clipboard objects without CF_HDROP are not guaranteed.
- Retention: authoritative expiresAt is capture +30m; Agent purges bytes/history periodically and before API response, store purges cards/cache/favorites. Favorites persist until explicitly unpinned or deleted. Live clipboard contents are memory-only and excluded from preferences; reopening fetches still-valid Agent items. Max 50 entries / 100 MiB Agent attachment memory; per attachment 20 MiB; copied-file batch up to 20 files /50 MiB. Over-limit entries may be skipped/evicted before TTL.
- Notifications: in-app only, memory-only max100. Initial clipboard fetch establishes baseline; later IDs notify once, deleted/dismissed IDs do not reimport. Notify status transitions, suppress initial/repeated samples. No Android system notification permission/background polling promise.
- Keys UI now toggles selected keys sequentially and confirms via explicit button. Do NOT restore release-to-confirm. Modifier-only invalid selection still rejected; normalization/allowlist shared with backend. Old ChordCapture is legacy logic, no longer used by the widget.
- Receipt success and progress differ: byte progress reaching100% does not mean success until PC responds201 with matching stable ID and byte count. Capture target before picker and revalidate after return. Keep failed transfer visibly failed.
- Test results and artifact hashes must come from updated docs/build-evidence.json. Default suite skips 4 opt-in tests. live_sharing_test sends a real harmless verification file and reads real Windows clipboard; it must not print clipboard contents or credentials. It is not a mock-only test and is never CI default.
- Latest user confirms the previous Android Tailscale login fix works on their phone. New sharing native file/save dialogs and new APK still need physical-phone checking. CPU sensor manual setup remains independent and unresolved until verified.

## Permanent Favorites and approved launcher icon — 1.1.1+4

- User selected concept A with round orange glasses and a cheerful smile, then explicitly reverted the phone-waving revision: final icon has NO phone. Approved source: assets/branding/mimo-launcher.png (same as docs/design/icon-a-glasses-happy-v2.png).
- Generated with built-in imagegen using the existing mascot as identity reference. Prompt: cheerful cream long-eared Mimo wearing round coral glasses, happy eyes and smile, two paws on coral desktop monitor, orange/black palette, no lettering or phone. Preview sheets/rejected variants stay under docs/design and are not launcher assets.
- Reproduce platform resources with `dart run flutter_launcher_icons` using flutter_launcher_icons.yaml. Android adaptive background black, foreground inset16%; generated legacy densities, iOS icons and web icons. Production iOS build remains untested.
- Favorite items no longer expire, including images/documents/tables. PC-sourced favorites persist metadata and binary attachments in .local/agent/favorites on that PC, excluded from source/package. Favorites bypass temporary count/byte eviction limits; disk capacity remains the limit and write failures are reported rather than pretending success.
- Favorite metadata/local text are retained in app preferences so relaunch keeps the cards. PC attachments stay on the PC and require it online to retrieve if not cached; do not claim an offline phone attachment vault.
- Unfavorite starts a NEW 30-minute expiry timer. Delete removes the Mimo archive item and stored attachment on the PC, not the original source file or user-saved copies. Deleting a PC-sourced item is now an authenticated backend DELETE, not merely hiding the local card.
- New authenticated POST /v1/devices/{id}/clipboard/{clipId}/favorite with strict boolean {favorite: true/false}; DELETE /v1/devices/{id}/clipboard/{clipId}. Keep target/owner/session/sharing checks. Persistent writes are serialized, manifest replaced atomically, attachments flushed before success. Read-only Agent must not expose archived attachments without --enable-sharing.
- Tests in favorites_test.dart verify survival after31 minutes, cache pressure, Agent restart, exact attachment bytes, unpin TTL, archive deletion, local preferences reload and manual removal. Sharing regression remains covered. APK and Agent both need updating for Favorite API.

## GitHub handoff — 16 October 2026
User explicitly authorized uploading this Flutter repository to https://github.com/LORR01/Mimo-Final-Project (private), branch main. This supersedes historical no-commit/no-push status notes. Keep private runtime/clipboard archives, keys and build outputs excluded. GitHub Actions workflow is included; its execution status must be checked separately from local tests.

