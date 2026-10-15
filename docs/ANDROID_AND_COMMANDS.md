Latest 1.1.0+3: [SHARING_AND_NOTIFICATIONS.md](SHARING_AND_NOTIFICATIONS.md) supersedes earlier file/clipboard and simultaneous keyboard limitations below.

# Android, ORDER และ PC keyboard backend

เอกสารนี้อธิบายงานต่อจากระบบอ่าน telemetry เดิม อ่านคู่กับ LIVE_CONNECTION.md ส่วนข้อมูลเก่าใน VALIDATION เป็นประวัติการตรวจแต่ละรอบ

## ติดตั้งและเชื่อมโทรศัพท์

1. PC ต้องติดตั้ง Tailscale และเข้าสู่บัญชี รัน Mimo Agent ด้วย `--enable-commands` หากต้องการส่งคีย์
2. เปิด HTTPS ภายใน tailnet ที่พอร์ต 8443 ไปยัง localhost 8765 ตามคู่มือ LIVE_CONNECTION
3. ติดตั้ง APK บน Android และติดตั้งแอป Tailscale ทางการ ลงชื่อเข้าใช้บัญชีเดียวกับเจ้าของ PC และเปิด VPN
4. ใน Mimo แตะ **เข้าสู่ระบบด้วย Tailscale** ถ้ายังไม่เชื่อม Mimo จะเปิดแอป Tailscale ที่ติดตั้งไว้ ให้ลงชื่อเข้าใช้/อนุญาต VPN ในแอปนั้น แล้วกลับ Mimo
5. แอปเรียก session ผ่าน HTTPS โดยใช้ตัวตน Tailscale ที่ PC ตรวจด้วย whois จึงไม่ต้องคัดลอกรหัสจับคู่ เลือก PC จากรายการ ตั้งชื่อแสดง แล้วบันทึก

Android bridge ใช้ MethodChannel `mimo/tailscale` เพื่อตรวจ/เปิด package `com.tailscale.ipn` และหน้าติดตั้งเท่านั้น ไม่อ่านรหัสผ่าน ไม่เข้าถึงข้อมูลส่วนตัวของแอป Tailscale และไม่สร้าง Tailscale node/VPN อีกตัว รายการเครื่องมาจาก CLI บน PC ผ่าน Mimo Agent ซึ่งเป็นจุดเชื่อมที่จำเป็นของสถาปัตยกรรมนี้ ดู [manifest ทางการของ Tailscale Android](https://github.com/tailscale/tailscale-android/blob/main/android/src/main/AndroidManifest.xml)

APK ที่ build ด้วยสคริปต์จะได้รับ HTTPS gateway URL ผ่าน `MIMO_AGENT_URL` ซึ่งเป็นตำแหน่งบริการ ไม่ใช่ token บันทึกปลายทางที่เชื่อมสำเร็จใน preferences ได้ รุ่น 1.0.1+2 ไม่แสดงช่อง URL ในแอป หากย้าย gateway แรกให้ build ใหม่ด้วย -AgentUrl ของ PC ใหม่ การเปิดจากเว็บใช้ origin ของเว็บ ส่วน native APK ใช้ค่าจาก build หรือ preferences การล็อกอิน Tailscale และการอนุญาต VPN เป็นขั้นตอนที่ผู้ใช้ทำในแอป Tailscale เอง

เครื่องที่เปิดแอปถูกซ่อนด้วย stable ID ของผู้ร้องขอ: โทรศัพท์ไม่แสดงตัวเองเป็น PC ปลายทาง หากเปิด Mimo บน PC เดียวกับ Agent ก็จะซ่อน PC เครื่องนั้นเช่นกัน

## หลาย PC

ทุก PC ที่จะควบคุมต้องมี Agent และ Serve ของตัวเอง รายการ online ใน Tailscale ไม่เท่ากับ Agent พร้อมใช้ โดยเริ่มจาก unknown และยืนยันจาก snapshot จริง

Gateway ส่ง machine ID, hostname, IP, OS, online และ URL จาก DNSName ของ Tailscale สำหรับ Agent ที่พอร์ตมาตรฐาน 8443 `AgentClient` แยก session ของ PC แต่ละเครื่อง ไม่ส่ง token ของ gateway ไปอีกเครื่อง ตรวจ HTTPS DNS tailnet เดียวกันและ `agentDeviceId` ให้ตรงเครื่องที่เลือกก่อนอ่าน/ส่งคีย์ เครื่อง offline หรือไม่มี Agent จะไม่เปิดปุ่มสั่งงาน

## ORDER และ Keys

- เพิ่มกลุ่ม → เพิ่มปุ่ม → ใส่ชื่อ/คำอธิบาย → แตะช่องคีย์ลัดเพื่อเปิดแป้น PC ไม่มีช่องคำสั่งตัวอย่างแล้ว
- แตะหมุดข้างปุ่มใน Keys ได้สูงสุด 4 ปุ่มต่อ PC ถ้าเต็มต้องถอดหมุดเดิมก่อน
- Home แสดง 2 ปุ่มแรกตามลำดับ pin แตะ ORDER หรือ MORE เพื่อเปิดทั้งหมดที่ pin ไว้
- แก้ไขปุ่มโดยไม่เสียลำดับ pin ลบปุ่มแล้วนำหมุดนั้นออกอัตโนมัติ ชื่อ/คีย์/pin เก็บใน preferences ตาม machine ID
- ปุ่มใน ORDER และ Keys ส่งคีย์ชุดเดียวกันไปยัง PC ที่เลือก มี guard เมื่อ offline, session หมดอายุ, snapshot เก่า, Agent ปิด commands หรือกำลังส่ง

## การเลือกคีย์ลัด

`lib/domain/shortcuts.dart` เป็นกติกากลางของ UI และ Agent ใช้ allowlist virtual keys 1–6 ปุ่ม แป้นรับหลาย pointer พร้อมกัน เก็บชุดที่กดค้างพร้อมกัน และยืนยันเมื่อปล่อยทั้งหมด การแตะ Ctrl แล้วปล่อยก่อนแตะ C จะไม่สร้าง Ctrl+C

หากเริ่มปล่อยชุดแรกแล้วแตะปุ่มใหม่ก่อนปล่อยครบ จะยกเลิกชุดนั้นเพื่อไม่เดาความตั้งใจ การเลื่อนหน้าจอ/ยกเลิก pointer/เสีย focus/แอปพักจะไม่ยืนยันคีย์เอง ปุ่มเลื่อนแป้นอยู่แยกจากพื้นที่รับหลายสัมผัส เพื่อไม่ให้ horizontal drag recognizer แย่งนิ้วที่สอง รองรับการเลือกผ่านคีย์บอร์ดจริงด้วย

Ctrl/Alt/Shift/Win อยู่ในแถบที่ไม่เลื่อนตามแป้น จึงยังกดค้างร่วมกับคีย์ด้านขวา เช่น Ctrl+F12 ได้ รวมเครื่องหมายบนแป้นหลักด้วย

## PC Agent ที่ส่งคีย์จริง

```powershell
dart run tool/mimo_agent.dart --enable-commands
```

Agent ปกติยังอ่านอย่างเดียวจนกว่าจะใช้ flag นี้ รันใน desktop session ของผู้ใช้ คีย์ส่งไปยังหน้าต่างที่กำลังโฟกัสบน PC โดย Windows SendInput ผ่าน Dart FFI ไม่เปิด process หรือ shell จากข้อความที่ผู้ใช้ส่ง

`POST /v1/devices/{id}/keys` ต้องมี Bearer session ที่ผ่านการตรวจ ใช้ JSON `keys` เป็นรายการชื่อคีย์ใน allowlist และ `requestId` เท่านั้น กฎสำคัญ:

- ตรวจ machine ID, session, snapshot ที่สด และ capability ก่อนทำงาน
- requestId เดิม/ชุดคีย์เดิมคืนผลเดิม ไม่ส่งซ้ำ แม้ร้องขอพร้อมกัน หาก ID เดิมแต่ชุดคีย์ต่างกันจะปฏิเสธ
- จำกัด 5 คำสั่ง/วินาทีต่อ session และ bounded dedup cache
- ส่ง key-down ทั้งชุดแล้ว key-up ย้อนลำดับใน batch เดียว หาก Windows รับไม่ครบจะพยายามปล่อยคีย์และคืน error ไม่รายงานสำเร็จ
- ปฏิเสธเมื่อผู้ใช้ PC กดคีย์ที่เกี่ยวข้อง/modifier ค้างอยู่ เพื่อไม่ปล่อยคีย์ที่ผู้ใช้กำลังกดเอง
- ไม่มี arbitrary text, PowerShell, shell, app path หรือ terminal execution endpoint ไม่รองรับ Ctrl+Alt+Delete
- UAC, หน้าจอล็อก และหน้าต่างสิทธิ์สูงกว่าอาจปฏิเสธ input ตามข้อจำกัดของ [SendInput/UIPI](https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-sendinput) แอปไม่ข้ามการป้องกันนี้

ผลสำเร็จหมายถึง Windows รับชุด input ครบ ไม่ใช่การยืนยันว่าทุกโปรแกรมตั้ง shortcut นั้นไว้แล้ว เช่น Discord ต้องตั้ง binding/โฟกัสให้ตรงกับการใช้งานจริง

## อุณหภูมิ

NVIDIA GPU ใช้ `nvidia-smi` ของไดรเวอร์ที่ติดตั้งอยู่เพื่ออ่าน load และ temperature จากการ์ดเดียวกัน (หากมีหลาย NVIDIA เลือกตัวที่มี load สูงสุด) ส่งชื่อใน snapshot.hardware.primaryGpu หากไม่มีใช้ Windows GPU engine counters/WMI ของ Libre/OpenHardwareMonitor ทดสอบบน PC นี้แล้วได้ค่าจริง

CPU ยังต้องมี sensor provider เช่น LibreHardwareMonitor ที่เปิดด้วย Run as administrator เพื่อส่ง WMI sensor Agent ไม่ใช้ ACPI thermal zone แทนอุณหภูมิ CPU แบบเดาสุ่ม ไม่ปิด Memory Integrity/driver blocklist และไม่ติดตั้ง kernel driver ให้อัตโนมัติ ถ้าไม่มี provider จะแสดง `—` พร้อมคำแนะนำใน Status/Focus

เตรียม LibreHardwareMonitor v0.9.6 จาก [GitHub ทางการ](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/tag/v0.9.6) ไว้ใน tooling ของเครื่องพัฒนา ตรวจ SHA-256 ของ zip กับ release digest แล้ว เครื่องมือดังกล่าวไม่รวมใน source/APK หรือ Agent zip การเปิด UAC และอนุญาตไดรเวอร์เป็นสิ่งที่เจ้าของ PC ต้องพิจารณา/ทำเอง

## Build แบบกดครั้งเดียว

ดับเบิลคลิก `Build APK.cmd` หรือรัน:

```powershell
./tool/build-apk.ps1 -AgentUrl https://your-pc.your-tailnet.ts.net:8443
```

สคริปต์ค้นหา Flutter/Android SDK และ URL ของ Serve ที่ชี้ localhost 8765 ได้ ถ้าใช้เครื่องอื่นให้ติดตั้ง SDK และส่ง `-FlutterPath`/`-AndroidSdk` ได้ ไม่ดาวน์โหลดหรือเปลี่ยน settings Tailscale ให้อัตโนมัติ ตรวจ pub get → format → analyze → tests ก่อน build หากไม่ผ่านจะหยุด ผลลัพธ์ `build/deliverables/Mimo-testing.apk` เป็น debug-signed APK สำหรับทดสอบติดตั้งจริง ไม่ใช่ production Play Store signing

สคริปต์ใช้ Windows Unicode API หา path alias เพื่อหลบ Flutter SDK crash บน path ภาษาไทย โดยไม่แก้ global PATH หรือปิด checks ของแอป

สร้าง PC Agent executable แยกด้วย:

```powershell
./tool/build-agent.ps1 -DartPath dart
```

ได้ `build/agent/mimo-agent.exe`, trusted metric script, web build ถ้ามี และ `Start Mimo Agent.cmd` เปิด launcher จากโฟลเดอร์นั้น ตั้ง Tailscale/Serve บน PC ก่อน หากมี Agent เดิมรันที่ 8765 ให้หยุดตัวเดิมก่อนเปิด executable เพื่อไม่ชนพอร์ต

## ขอบเขตที่ยังไม่ควรตีความเกินหลักฐาน

- Android install/login return flow ต้องทดสอบบนโทรศัพท์จริง APK compilation ไม่พิสูจน์ runtime ทุกยี่ห้อ
- CPU จะมีค่าเมื่อ provider อ่านเซนเซอร์ฮาร์ดแวร์ได้จริงเท่านั้น
- Backend ปัจจุบันรองรับ telemetry และ keyboard commands ส่วน PC clipboard sync และ file transport จริงยังไม่เปิดใช้งาน ปุ่มส่งไฟล์ live แสดงเหตุผลและถูกปิดไว้ ส่วน clipboard เป็นบันทึกใน Mimo/clipboard ของอุปกรณ์ที่เปิดแอป
- ไม่มีบัญชี Mimo production, Google Play signing หรือระบบอัปเดตอัตโนมัติ ไม่มี auth token ใน APK/preferences
