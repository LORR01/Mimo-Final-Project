# การเชื่อมต่อ Mimo หลังเปิดเครื่องใหม่

การเชื่อมต่อประกอบด้วยสามส่วนที่ต้องทำงานพร้อมกัน: Tailscale เชื่อมเครือข่าย, Serve ส่ง HTTPS ไปยัง PC และ Mimo Agent อ่านข้อมูล/รับคำสั่ง การเปิด Tailscale อย่างเดียวจึงยังไม่เพียงพอ

## ตั้งค่าครั้งแรก

1. ติดตั้ง Tailscale บน PC และโทรศัพท์ เข้าสู่บัญชีเจ้าของ PC และตรวจว่านโยบายเครือข่ายอนุญาตให้เชื่อมต่อกัน
2. แตกชุด PC Agent ทั้งหมดลงโฟลเดอร์ถาวรที่บัญชี Windows นี้เขียนได้ ไม่รันจากใน ZIP หรือย้ายโฟลเดอร์หลังติดตั้ง
3. เปิด `Enable Mimo Auto Start.cmd` ด้วยบัญชี Windows ที่จะใช้งาน ระบบเริ่ม Agent ทันทีและทุกครั้งที่บัญชีนี้เข้าสู่ Windows หากเครื่องปฏิเสธการลงทะเบียนงาน ให้เปิด PowerShell ด้วยสิทธิ์ผู้ดูแลภายใต้บัญชีเดิม แล้วรันคำสั่งติดตั้งจาก source ด้านล่าง ไม่ลงทะเบียนด้วยบัญชีผู้ดูแลคนอื่น
4. เปิด Tailscale → Preferences → Run Unattended หากต้องการคงเครือข่ายหลังรีสตาร์ต/ออกจากบัญชี ตัวเลือกนี้ทำให้การเชื่อมต่อเครือข่ายคงอยู่ จึงควรพิจารณาการใช้งานร่วมกันของ PC ตาม [คำแนะนำ Tailscale](https://tailscale.com/docs/how-to/run-unattended)
5. ตรวจบริการ Serve เดิมก่อนตั้ง Mimo จาก PowerShell ที่มีสิทธิ์เหมาะสม:

```powershell
tailscale serve status
tailscale serve --bg --https=8443 http://127.0.0.1:8765
```

หากพอร์ต 8443 เป็นของบริการอื่น ให้หยุดและจัดการการตั้งค่าให้ชัดเจนก่อน ไม่แทนที่บริการเดิม ไม่ใช้ `tailscale serve reset` และไม่ใช้ Funnel เพื่อแก้ปัญหานี้ หาก Tailscale ขออนุมัติ Serve/HTTPS ให้เจ้าของบัญชีเปิดตามลิงก์ที่แสดง

`--bg` ทำให้ Serve กลับมาหลัง Tailscale เริ่มใหม่ ตาม [เอกสาร Serve](https://tailscale.com/docs/reference/tailscale-cli/serve) ส่วน Agent เริ่มด้วย Scheduled Task ของ Mimo แยกกัน

6. ใช้ APK ที่ build ด้วย gateway URL ของ PC นี้ APK ของผู้พัฒนาไม่ใช่ gateway สำหรับทุก tailnet ผู้ใช้โปรเจกต์ใหม่ต้อง [build APK ด้วย URL ของตนเอง](../README.md#build-android-apk)
7. เปิด `Check Mimo Connection.cmd` แล้วเชื่อมจากโทรศัพท์เพื่อยืนยันทั้งสองฝั่ง

Mimo Agent เริ่มหลังเข้าสู่ Windows เพราะคลิปบอร์ดและการส่งคีย์ต้องใช้ desktop session ไม่ทำงานก่อน sign-in แม้ Tailscale จะออนไลน์แล้ว เครื่องที่ปิด/หลับไม่สามารถรับคำสั่งหรือไฟล์ได้ และคีย์ลัดไม่ข้ามการป้องกันหน้าจอล็อก/UAC

## คำสั่งสำหรับ source repository

หลัง build Windows Agent แล้ว รันจาก root ของ repository:

```powershell
./tool/manage-agent-startup.ps1 -Mode Install
./tool/manage-agent-startup.ps1 -Mode Status
./tool/check-agent.ps1
```

สำหรับโฟลเดอร์ Agent ที่แตกไฟล์ ใช้ `./tool/manage-agent-startup.ps1` และ `./tool/check-agent.ps1` จาก root ของชุดนั้นได้เช่นกัน หากต้องการชี้ตำแหน่งอื่น ให้ส่ง `-AgentDirectory 'C:\MimoAgent'`

ตัวตรวจสอบไม่แก้ firewall, ACL, บริการ หรือการตั้งค่า Windows และไม่พิมพ์ token คลิปบอร์ดหรือรายชื่อเครื่อง ค่า exit code 1 หมายถึงมี FAIL, 0 หมายถึงไม่มี FAIL; WARN ยังอาจต้องจัดการ เช่น ยังไม่ติดตั้ง Auto Start การตรวจ HTTPS บน PC ไม่ยืนยันสิทธิ์หรือ VPN ของโทรศัพท์

## แยกสาเหตุทีละส่วน

| ผลตรวจ/อาการ | ความหมายและวิธีแก้ |
|---|---|
| Missing package file | แตกชุด Agent ให้ครบ หรือ build ใหม่ อย่าคัดเฉพาะ EXE; ต้องมีสคริปต์อ่าน metrics ด้วย |
| Auto Start is not installed | เปิด Enable Mimo Auto Start หนึ่งครั้งด้วยบัญชี Windows ที่ใช้งาน |
| Auto Start ไม่ Running | ติดตั้งใหม่และตรวจ Task Scheduler → งานที่ขึ้นต้นด้วย Mimo Agent อย่าเปลี่ยนเป็น SYSTEM หรือเลือกให้รันโดยไม่ต้องมีผู้ใช้เข้าสู่ระบบ |
| Auto Start points to another folder | ถอนจากชุดเดิมแล้วติดตั้งจากชุดใหม่ เพื่อให้ path และข้อมูลส่วนตัวตรงกัน |
| Local Agent unavailable | ดู `.local/agent/logs/agent.stderr.log` และ `agent.stdout.log`; ถ้าเพิ่งเริ่มงาน รอสักครู่แล้วตรวจใหม่ |
| พอร์ต 8765 ถูกใช้งาน | ตรวจ `Get-NetTCPConnection -LocalPort 8765 -State Listen` แล้วดู process ที่เป็นเจ้าของ หยุดเฉพาะ Agent เก่าที่ตรวจแล้ว ไม่ kill โปรแกรมที่ไม่รู้จัก |
| Tailscale disconnected | เปิด Tailscale เชื่อมต่อ/ลงชื่อเข้าใช้ใหม่ ตรวจอินเทอร์เน็ตและสถานะการอนุมัติหรือหมดอายุของอุปกรณ์ |
| Missing Mimo HTTPS proxy | ตรวจ `tailscale serve status` แล้วตั้งเฉพาะ mapping ของ Mimo ตามขั้นตอนติดตั้ง |
| HTTPS unreachable | ตรวจ DNS, HTTPS approval, การเชื่อมต่อ และ tailnet policy; ไม่ปิด certificate validation เพื่อให้ผ่าน |
| PC ผ่าน แต่ Android ไม่ผ่าน | ตรวจ Tailscale VPN บนโทรศัพท์ บัญชีเจ้าของ PC นโยบายถึง PC และ gateway ของ APK ถ้าเปลี่ยน PC gateway ต้อง build APK ใหม่ |
| ดูสถานะได้ แต่ส่งคีย์/ไฟล์ไม่ได้ | ตรวจว่า Agent เปิดด้วย `--enable-commands --enable-sharing`, เครื่องที่เลือกออนไลน์ และใช้ Agent รุ่นตรงกับ APK |
| ไม่มีอุณหภูมิ CPU | เป็นปัญหา sensor provider แยกจาก Tailscale ดูคู่มือ PC Agent; ไม่มี sensor จะไม่สร้างค่าจำลอง |

หากต้องส่ง log ให้ผู้พัฒนาตรวจ ให้ปิดบังชื่อเครื่อง IP บัญชี และข้อมูลส่วนตัวก่อน ห้ามส่ง `.local/agent/pairing.local.json`, Favorite archive หรือ token

## อัปเดต ย้าย หรือถอน Auto Start

1. เปิด `Disable Mimo Auto Start.cmd` จากชุดเดิมเพื่อหยุดงานและ Agent ที่ supervisor ดูแล คำสั่งนี้ไม่ลบ Favorite และไม่เปลี่ยน Tailscale
2. สำรอง `.local/agent/` แบบส่วนตัวก่อนอัปเดตหรือย้าย โดยเฉพาะโฟลเดอร์ Favorite อย่านำไปอัปโหลดใน repository หรือชุดแจกจ่าย
3. แทนไฟล์ชุดโปรแกรมที่ตำแหน่งเดิม หรือย้ายทั้งข้อมูลไปตำแหน่งใหม่ ไม่เปิด Agent สองตัวพร้อมกัน
4. เปิด `Enable Mimo Auto Start.cmd` จากชุดใหม่ แล้วรันตัวตรวจสอบและเชื่อมต่อจากโทรศัพท์

หากต้องการถอนจาก source ใช้ `./tool/manage-agent-startup.ps1 -Mode Uninstall` การเปิด Agent ด้วยตนเองเป็น process แยกจาก Auto Start อาจต้องปิดหน้าต่างนั้นเอง

## ตรวจหลังรีสตาร์ตจริง

เมื่อสะดวกและบันทึกงานอื่นแล้ว ให้รีสตาร์ต PC เข้าสู่ Windows ด้วยบัญชีเดิม โดยไม่เปิด Agent ด้วยตนเอง รอให้เครือข่ายพร้อม แล้วตรวจ:

- `Check Mimo Connection.cmd` พบ Local Agent, Tailscale และ HTTPS เป็น PASS
- เปิด Mimo บนโทรศัพท์ที่เชื่อม Tailscale แล้วเลือก PC ได้
- ข้อมูลสถานะอัปเดต และลองส่งไฟล์ทดสอบที่ไม่มีข้อมูลสำคัญ
- หากจะทดสอบคีย์ลัด ให้ใช้หน้าต่างทดสอบที่ตั้งใจรับคำสั่ง

การลงทะเบียน trigger หรือทดสอบ restart เฉพาะ process ไม่ใช่หลักฐานว่าทดสอบรีสตาร์ต Windows จริงแล้ว ดูขอบเขตผลทดสอบใน [VALIDATION.md](VALIDATION.md)
