# Sharing, Clipboard และการแจ้งเตือน — 1.1.0+3

อัปเดต 16 ตุลาคม 2026 ใช้คู่กับ README.md และ handoff.md เอกสารนี้แทนขอบเขตเดิมที่ระบุว่า file transport/PC clipboard ยังไม่ทำ และแทนวิธีกดคีย์พร้อมกัน

## เริ่มใช้งาน

ติดตั้ง APK ใหม่และใช้ PC Agent รุ่นเดียวกัน เปิด launcher ใหม่ หรือรัน:

```powershell
dart run tool/mimo_agent.dart --enable-commands --enable-sharing
```

--enable-sharing คือการเปิดให้อุปกรณ์ที่ผ่านการยืนยันตัวตนอ่าน clipboard ของ PC และส่งไฟล์เข้ามา หากไม่ใส่ flag นี้ ทั้งสอง capability จะปิด การรันโดยไม่มี flags ยังเป็นโหมดอ่านสถานะเท่านั้น ใช้ Tailscale Serve :8443 เดิม ไม่ต้อง reset

## ส่งไฟล์

เลือก PC จาก Header → รับส่งไฟล์ → เลือกไฟล์ แอปจับ target ID ก่อนเปิด picker และตรวจความพร้อมซ้ำก่อนส่ง ไฟล์ส่งผ่าน HTTPS พร้อม session ของ target PC ไม่ใช้ gateway token ข้ามเครื่อง

- ไม่เกิน 100 MiB ต่อไฟล์ หน้าจอใช้คำว่า 100 MB
- ปลายทาง USERPROFILE/Downloads/Mimo บน PC ที่เลือก
- เก็บชื่อเดิมโดยเติมรหัสด้านหน้าเพื่อป้องกันเขียนทับ ไม่เปิดหรือ execute ไฟล์
- แถบความคืบหน้าคือจำนวนไบต์ที่ส่ง แต่ต้องมี HTTP201 receipt พร้อม deviceId/bytes ตรงกันจึงแสดงสำเร็จ
- รับลง .part แบบ exclusive ตรวจ Content-Length/size/timeout แล้ว rename หลังครบ ล้าง partial เมื่อรับไม่ครบ ปฏิเสธ path traversal, reserved Windows names และชื่ออักขระผิดกฎ
- ไม่รองรับส่งหลายไฟล์พร้อมกันใน picker รอบนี้ ไม่ทำ automatic retry ที่อาจส่งซ้ำเงียบ ๆ หากคำขอขาดหลัง PC รับครบ ผู้ใช้ต้องตรวจปลายทางก่อนลองใหม่

## Clipboard จาก PC

เปิดหน้า Clipboard ของ PC ที่เลือก แอปอ่านรายการประมาณทุก 5 วินาทีเมื่อทำงานอยู่ Agent เก็บประวัติในหน่วยความจำและไม่ส่งเนื้อหาลง logs

| ประเภท | แหล่ง Windows / การใช้งาน |
|---|---|
| ข้อความ | CF_UNICODETEXT; คัดลอกข้อความจาก PC มา clipboard ของเครื่องที่เปิด Mimo |
| ลิงก์ | Unicode text ที่ขึ้นต้น HTTP/HTTPS; คัดลอกลิงก์ได้ |
| รูปภาพ | registered PNG, CF_DIB หรือไฟล์รูปจาก Explorer; กดดูรูปหรือบันทึกไฟล์ |
| เอกสาร | CF_HDROP (ไฟล์จริงที่คัดลอกจาก Explorer); บันทึกไฟล์จริงได้ |
| ตาราง | HTML Format ที่มี table, TSV text หรือไฟล์ CSV/XLS/XLSX/ODS/TSV; เก็บไฟล์แนบและบันทึกได้ |

อ่าน clipboard อย่างเดียว ไม่ใช้ SetClipboardData/EmptyClipboard และไม่เปลี่ยนข้อมูลเดิมของ Windows โปรแกรมบางตัวใช้ virtual files / private formats เช่น Outlook attachment หรือ cloud placeholders ที่ยังไม่เป็นไฟล์จริง อาจอ่านไม่ได้ รอบนี้ไม่อ้างว่ารองรับทุก private format ของทุกโปรแกรม

รูปเปิดในแผงเมื่อกดดู เพื่อลดการดาวน์โหลดรูปใหญ่ทั้งหมดพร้อมกันบนโทรศัพท์ จำกัด cache ไฟล์แนบฝั่งแอป 4 รายการ และ decode ภาพ preview ที่ความกว้างจำกัด ไม่แสดง HTML เป็น WebView/เนื้อหาที่รัน script ได้

## อายุข้อมูล 30 นาที

นับจากเวลาที่ Agent จับข้อมูลเข้า Mimo เป็นเวลา 30 นาที ไม่ใช่เวลาที่ผู้ใช้เปิดหน้า Clipboard

- Agent ลบ metadata และ attachment bytes เมื่อครบกำหนด (ตรวจทุกประมาณ 5 วินาที และก่อนตอบ API)
- แอปตรวจ expiresAt และลบเฉพาะรายการ/cache ที่ไม่ติด Favorite และหมดอายุ Favorite เก็บถาวรจนถอนดาวหรือลบเอง
- Live clipboard เป็น memory-only ไม่บันทึกเนื้อหาหรือ bytes ใน preferences การปิดแอปทำให้รายการ local หาย เมื่อเปิดใหม่จะอ่านรายการที่ยังไม่หมดอายุจาก Agent
- sequence number ป้องกัน clipboard เดิมที่ยังค้างใน Windows ถูกนำเข้ามาซ้ำหลังหมดอายุ ยกเว้นมีการคัดลอกใหม่หรือเริ่ม Agent session ใหม่
- ไม่ลบต้นฉบับ ไม่เคลียร์ clipboard ของ Windows และไม่ลบไฟล์ที่ผู้ใช้กดบันทึกออกจาก Mimo เอง
- Limits: 50 รายการ, attachment แต่ละชิ้นไม่เกิน 20 MiB, หน่วยความจำ Agent ไม่เกิน 100 MiB; copied-file batch สูงสุด 20 ไฟล์/50 MiB เกินขนาดอาจถูกข้ามหรือรายการเก่าถูกนำออกก่อนครบ 30 นาที

## การแจ้งเตือน

ตามขอบเขตที่ผู้ใช้เลือก: แจ้งเตือนเฉพาะใน Mimo ขณะเปิดใช้งาน ไม่มี Android foreground/background service หรือคำสัญญาว่าจะแจ้งเตือนหลังปิดแอป

กระดิ่งแสดงจำนวนยังไม่อ่าน กดเพื่อดูรายการ ปิดแผงแล้วทำเครื่องหมายว่าอ่านแล้ว เก็บสูงสุด 100 รายการในหน่วยความจำ

- Clipboard: ครั้งแรกใช้เป็น baseline ไม่แจ้งข้อมูลเก่าทั้งหมด หลังจากนั้นรายการ ID ใหม่ของ PC ที่เลือกแจ้งครั้งเดียว
- สถานะ: แจ้งเมื่อเครื่องที่เพิ่มเปลี่ยน online/offline; target ที่อ่านไม่ได้อาจแสดงติดต่อไม่ได้/ออฟไลน์ ป้องกันแจ้งซ้ำเมื่อสถานะไม่เปลี่ยน
- ไม่ใส่เนื้อหาข้อความ รูป หรือเอกสารใน notification preview

## เลือกคีย์ลัด

แตะเลือกทีละปุ่ม แตะซ้ำเพื่อนำออก เลือกได้สูงสุด 6 คีย์ กดล้างทั้งหมดเพื่อเริ่มใหม่ และกดยืนยันเมื่อเลือกครบ Modifier อย่างเดียวใช้ไม่ได้ ตัวอย่าง: Ctrl → C → ยืนยัน ไม่ต้องกดค้างพร้อมกัน

## API และส่วนโค้ด

ทุก route ต้องมี auth, stable target และความพร้อมตาม capability ใช้ session ต่อ PC ที่ตรวจ ID แล้ว

```text
POST /v1/devices/{id}/files                  raw stream + X-Mimo-Filename
GET  /v1/devices/{id}/clipboard              metadata + expiresAt
GET  /v1/devices/{id}/clipboard/{clipId}/file attachment; 404 หลังหมดอายุ
```

X-Mimo-Filename ใช้ base64url ของ UTF-8 basename Content-Type=application/octet-stream ไม่รับ destination path จาก frontend ไฟล์แนบ clipboard ใช้ octet-stream, Content-Disposition: attachment, nosniff และ Cache-Control: no-store

- tool/agent/clipboard.dart: injectable source และ Windows FFI
- tool/agent/sharing.dart: bounded upload receiver
- tool/agent/server.dart: authenticated routes, retention และ memory limits
- lib/data/agent_client.dart: per-target uploads/downloads
- lib/state/mimo_store.dart: expiry, notifications, receipt/progress, session guards
- lib/ui/chord_keyboard.dart: toggle selection + explicit confirmation

## หลักฐานและข้อจำกัดการตรวจ

รัน format/analyze/full suite ก่อน build โดยสคริปต์ APK ไม่ข้าม failures Tests ครอบคลุม byte-for-byte receipts, duplicated names, auth/wrong target, traversal/reserved names/size limits, 5 หมวด clipboard, attachment auth, 30-minute expiry ด้วย injected clock, no resurrection, dismissal, notification dedup/read และ responsive UI 320/390

Real opt-in test ส่งไฟล์ผ่าน certificate-verified Tailscale HTTPS แล้วอ่านไฟล์ปลายทางบนดิสก์เพื่อเปรียบเทียบทุกไบต์ และเรียก Windows clipboard FFI จริงโดยไม่เปลี่ยน clipboard หรือพิมพ์เนื้อหาออกมา การรองรับทุกหมวดทดสอบด้วย fixtures ไม่ใช่การเปิดคัดลอกจากทุกโปรแกรมจริง

```powershell
flutter test test/live_sharing_test.dart --dart-define=MIMO_SHARING_TEST=true --dart-define=MIMO_AGENT_URL=https://your-pc.your-tailnet.ts.net:8443
```

คำสั่งนี้ส่งไฟล์จริงและอ่าน clipboard จริง ต้องรันบน Windows เครื่องของ Agent และใช้ --enable-sharing อย่านำไปเปิดใน CI default ผลล่าสุดและ hashes อยู่ docs/build-evidence.json การติดตั้ง APK, native file/save dialogs และปลายทาง PC เครื่องที่สองยังไม่ได้ทดสอบจริงในรอบนี้

## Permanent Favorites and approved launcher icon — 1.1.1+4

- User selected concept A with round orange glasses and a cheerful smile, then explicitly reverted the phone-waving revision: final icon has NO phone. Approved source: assets/branding/mimo-launcher.png (same as docs/design/icon-a-glasses-happy-v2.png).
- Generated with built-in imagegen using the existing mascot as identity reference. Prompt: cheerful cream long-eared Mimo wearing round coral glasses, happy eyes and smile, two paws on coral desktop monitor, orange/black palette, no lettering or phone. Preview sheets/rejected variants stay under docs/design and are not launcher assets.
- Reproduce platform resources with `dart run flutter_launcher_icons` using flutter_launcher_icons.yaml. Android adaptive background black, foreground inset16%; generated legacy densities, iOS icons and web icons. Production iOS build remains untested.
- Favorite items no longer expire, including images/documents/tables. PC-sourced favorites persist metadata and binary attachments in .local/agent/favorites on that PC, excluded from source/package. Favorites bypass temporary count/byte eviction limits; disk capacity remains the limit and write failures are reported rather than pretending success.
- Favorite metadata/local text are retained in app preferences so relaunch keeps the cards. PC attachments stay on the PC and require it online to retrieve if not cached; do not claim an offline phone attachment vault.
- Unfavorite starts a NEW 30-minute expiry timer. Delete removes the Mimo archive item and stored attachment on the PC, not the original source file or user-saved copies. Deleting a PC-sourced item is now an authenticated backend DELETE, not merely hiding the local card.
- New authenticated POST /v1/devices/{id}/clipboard/{clipId}/favorite with strict boolean {favorite: true/false}; DELETE /v1/devices/{id}/clipboard/{clipId}. Keep target/owner/session/sharing checks. Persistent writes are serialized, manifest replaced atomically, attachments flushed before success. Read-only Agent must not expose archived attachments without --enable-sharing.
- Tests in favorites_test.dart verify survival after31 minutes, cache pressure, Agent restart, exact attachment bytes, unpin TTL, archive deletion, local preferences reload and manual removal. Sharing regression remains covered. APK and Agent both need updating for Favorite API.
