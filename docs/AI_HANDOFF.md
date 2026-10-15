# AI handoff — จุดเริ่มต้น

เอกสารหลักย้ายมาอยู่ที่ [../handoff.md](../handoff.md) ใน repository root ของ Flutter แล้ว เพื่อให้ AI และผู้พัฒนารับช่วงอ่านข้อมูลชุดเดียวกัน

เริ่มจาก [README.md](../README.md) → [handoff.md](../handoff.md) → [ANDROID_AND_COMMANDS.md](ANDROID_AND_COMMANDS.md) และผลล่าสุดใน [VALIDATION.md](VALIDATION.md) / [build-evidence.json](build-evidence.json)

อัปเดต 15 ตุลาคม 2026: มี Android testing APK, Tailscale login handoff, per-device ORDER pins และ authenticated Windows keyboard commands แล้ว CPU sensor ยังรอผู้ใช้เปิด LibreHardwareMonitor และยังไม่ได้ทดสอบติดตั้งบนโทรศัพท์จริง รายละเอียดและข้อจำกัดทั้งหมดอยู่ใน handoff หลัก

รุ่น 1.0.1+2 แก้ Android peer login ที่ Agent ปฏิเสธฟิลด์ MachineAuthorized ที่ไม่มีใน CLI และเปลี่ยนหน้าเชื่อมต่อเป็นรายการเครื่องโดยไม่กรอก URL รายละเอียดอยู่ handoff.md หัวข้อ Login blocker fixed

รุ่นปัจจุบัน 1.1.0+3: ส่งไฟล์จริง, clipboard 5 หมวดหมดอายุ 30 นาที, แจ้งเตือนในแอป และเลือกคีย์ทีละปุ่มพร้อมยืนยัน อ่าน SHARING_AND_NOTIFICATIONS.md และ handoff.md ส่วนล่าสุดก่อนสานงาน

Current1.1.1+4: Favorite items/attachments are permanent, unpin starts a new30-minute timer, and user-approved no-phone/glasses/happy mascot launcher icon is installed. Read latest handoff.md and docs/design/README.md. Do not revert to expiring Favorites.
