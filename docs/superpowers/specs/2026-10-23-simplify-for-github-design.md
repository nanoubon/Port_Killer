# Port Killer: ทำให้เรียบง่ายและปลอดภัยก่อนปล่อยฟรีบน GitHub (Design)

> หลังอนุมัติ: คัดลอกเอกสารนี้ไปไว้ที่ `docs/superpowers/specs/2026-10-23-simplify-for-github-design.md` แล้ว commit จากนั้นใช้ superpowers:writing-plans เพื่อทำแผนลงมือ

## 1. เจตนาและเหตุผล

Port Killer จะปล่อยฟรีบน GitHub ให้นักพัฒนาคนอื่นใช้ งานของแอปมีอย่างเดียว: ตอบว่า **"อะไรจับ port นี้อยู่ แล้วปิดมันอย่างปลอดภัยได้ไหม"** ผู้ใช้คือ dev ที่เจอ `EADDRINUSE` แล้วไม่อยากพิมพ์ `lsof -i :3000` เอง

ตอนนี้แอปทำเกินงานนั้นไปมาก และหลายส่วนเป็นของปลอมหรืออันตราย จากการสำรวจโค้ด:
- **ฆ่าผิดตัวได้:** ก่อนสแกนเสร็จ ตารางแสดง `demoPorts` พร้อมปุ่ม KILL ที่ทำงานจริง ทำให้ `kill -9 451` ไปโดน process จริงที่บังเอิญมี PID นั้น (`ContentView.swift:518` → `PortViewModel.swift:266`) กฎ auto-kill ที่มีแค่ชื่อจะ match ทุก port และ `kill -9` ทุก 8 วินาที (`PortViewModel.swift:346`, `:791`) กฎยังทำงานเงียบ ๆ ทั้งที่หน้าจอจัดการกฎเข้าถึงไม่ได้แล้ว
- **ข้อมูลปลอมดูเหมือนจริง:** ตัวเลขแดชบอร์ด, heatmap "REAL-TIME TELEMETRY", ประวัติปลอม, uptime/command ที่แต่งขึ้น และเลขเวอร์ชัน "v2.4.0" ที่ hard-code ไว้
- **อ่านข้อมูลผิด:** IPv6 `[::1]:3000` ถูกอ่านเป็น port 1, ชื่อ process ถูกตัดเหลือ 9 ตัวอักษร (`com.docke`), `lsof` คืนค่า exit 1 เมื่อไม่มี listener แล้วแอปแสดงเป็น error
- **ฟีเจอร์พัง:** Start at login อ้าง helper bundle ที่ไม่มีอยู่ แต่สวิตช์ค้าง ON, `ShellHelper` อ่าน pipe หลัง `waitUntilExit()` จึงอาจค้าง
- **ปล่อยไม่ได้:** ตั้ง deployment target ไว้ที่ macOS 26.2, README มี 2 บรรทัด, ไม่มีเทส, ไม่ได้ notarize

ความสำเร็จคือ dev ที่ไม่รู้จักแอปโหลด .dmg มา เปิดได้ทันที คลิก menu bar เห็น port ของตัวเองถูกต้องครบ และ kill ได้โดยไม่มีวันฆ่าผิดตัวหรือเห็นข้อมูลปลอม

## 2. เป้าหมาย / สิ่งที่ไม่ทำ / สิ่งที่ถือว่าล้มเหลว

**เป้าหมาย**
- รายการ TCP listening ports ที่ถูกต้อง 100%: port (IPv4 และ IPv6), ชื่อ process เต็ม, PID, user, bind address
- kill อย่างปลอดภัย: ยืนยันทุกครั้ง, SIGTERM ก่อนแล้วค่อย SIGKILL, เตือนเมื่อเป็น process พิเศษ, แจ้งผลลัพธ์ชัดเจน
- ใช้ได้สองทาง: menu bar popover สำหรับงานเร็ว และหน้าต่างหลักที่เป็นตารางอย่างเดียว
- Pin port ที่ใช้บ่อย และ Start at login ที่ทำงานจริง
- รองรับ macOS 14+, หน้าตาแบบ native ตาม light/dark ของระบบ
- แจกผ่าน GitHub Releases พร้อม README ที่ใช้ติดตั้งได้จริง (รุ่นแรกเป็น .zip ที่ยังไม่ notarize และเปลี่ยนเป็น .dmg ที่ notarize แล้วเมื่อมี Developer ID ดู §3)

**ไม่ทำ (ตัดออก)**
- แดชบอร์ด metric, heatmap, quick actions, ช่อง ⌘K ปลอม, "Kill All High Usage"
- Pro / IAP / App Store ทั้งหมด: `ProPurchaseManager`, `ProProfileDocument`, profile import/export, `import StoreKit`, views ที่เกี่ยวข้อง (~600 บรรทัด)
- กฎ auto-kill ทั้งระบบ รวมถึงการลบ key `PortKiller.autoKillRules` ที่ค้างอยู่ใน UserDefaults ของผู้ใช้เดิมตอนเปิดแอป
- ประวัติการ kill (หน้า History และ `killHistory`) ให้ลบ key ที่ค้างอยู่ด้วย
- Onboarding
- ธีมมืด Monolith แบบสีคงที่ (`Color.pk*`, `.preferredColorScheme(.dark)`)
- UDP, การยกสิทธิ์เป็น root เพื่อ kill process ของ user อื่น, auto-update (Sparkle)

**ถือว่าล้มเหลวแม้จะใช้งานได้**
- มีโอกาสใดก็ตามที่ kill ส่งไปยัง PID ที่ผู้ใช้ไม่ได้เห็นและยืนยันบนหน้าจอ
- มีตัวเลขหรือข้อความใดที่ไม่ได้มาจากระบบจริง
- ปุ่มใดที่กดแล้วไม่ทำตามชื่อ
- แอปกิน CPU หรือแบตเตอรี่ตอนไม่ได้เปิดดูอยู่

## 3. ข้อกำหนดที่ผู้ใช้ตัดสินใจแล้ว

- รูปร่างแอป: menu bar popover + หน้าต่างหลักเรียบ ๆ
- หน้าต่างหลัก: **แบบ A** เป็นตารางอย่างเดียว (Port, Process, PID, User, Address) เรียงลำดับได้ เลือกได้หลายแถว ใช้เมนูคลิกขวาสั่งงาน ไม่มีแผงรายละเอียด
- เก็บ: Pin port, Start at login
- ตัด: ประวัติการ kill, Onboarding, แดชบอร์ด, Pro, auto-kill
- macOS ขั้นต่ำ 14 Sonoma
- หน้าตา native macOS (สีระบบ, light/dark, Dynamic Type)
- แจก .dmg ที่ notarize แล้วบน GitHub Releases **แต่ตอนนี้ผู้ใช้ยังไม่มี Apple Developer Program / Developer ID** ดังนั้น:
  - ทำสคริปต์ release ที่รันบนเครื่อง (`scripts/release.sh`) รองรับทั้งสองโหมด: ถ้ามี Developer ID → sign, notarize, staple, สร้าง .dmg ถ้าไม่มี → build Release แบบ ad-hoc sign แล้วสร้าง .zip
  - รุ่นแรกปล่อยเป็น .zip ที่ไม่ได้ notarize README ต้องอธิบายวิธีเปิดครั้งแรก (คลิกขวา › Open หรือ System Settings › Privacy & Security › Open Anyway) และวิธี build จาก source
  - ไม่ทำ CI สำหรับ signing ในรอบนี้
- **Port ของ root / user อื่น: แสดงด้วยแต่ kill ไม่ได้** ใช้ `netstat -anv -p tcp` เป็นแหล่งข้อมูลที่สองที่ไม่ต้องใช้ root (ตรวจแล้วว่าบนเครื่องผู้ใช้ให้ `process:pid` ของทุก socket, ชื่อถูกตัดที่ 16 ตัวอักษรและอาจมีช่องว่าง เช่น `Claude Helper:27549` จึงต้อง parse จากด้านขวาของคอลัมน์ แล้วดึงชื่อเต็มจาก PID) แถวเหล่านี้แสดงแบบอ่านอย่างเดียว พร้อมป้าย "root"/ชื่อ user และเมนู "คัดลอกคำสั่ง `sudo kill <pid>`" แทนปุ่ม kill

### การตัดสินใจของผม (Claude) ที่ควรตรวจตอนอ่าน
- เปิดหน้าต่างหลักแล้วเปลี่ยนเป็น `NSApp.setActivationPolicy(.regular)` (มี Dock icon, ⌘-Tab และ menu bar พร้อมคำสั่ง ⌘R/⌘F) ปิดหน้าต่างแล้วกลับเป็น `.accessory` เปิดแอปหรือ login แล้วจะไม่เปิดหน้าต่างหลักเอง
- pin เดิมที่บันทึกด้วยชื่อที่ถูกตัด 9 ตัวอักษร: ในการสแกนครั้งแรก ถ้า port ตรงและชื่อเต็มขึ้นต้นด้วยชื่อเดิม ให้เขียนชื่อเต็มทับครั้งเดียว
- ไม่มีตัวเลือก "ไม่ต้องถามอีก" ใน dialog ยืนยัน
- รีเฟรชทุก 5 วินาทีเฉพาะตอนที่มีหน้าจอเปิดอยู่
- ลบ key `PortKiller.autoKillRules`, `PortKiller.killHistory`, `PortKiller.hasCompletedOnboarding` ตอนเปิดแอป

## 4. พฤติกรรมที่ต้องเป็น

### 4.1 การสแกน
- ใช้ `lsof -iTCP -sTCP:LISTEN -P -n +c 0` โดย `+c 0` ทำให้ได้ชื่อ process เต็ม ควรพิจารณาใช้ `-F` (output แบบ field) เพื่อ parse ได้แน่นอนกว่าการแยกด้วยช่องว่าง
- parse port จาก**เครื่องหมาย `:` ตัวสุดท้าย** ของ NAME เพื่อรองรับ `[::1]:3000` และ `[fe80::1%lo0]:3000`
- รวมแถว IPv4 กับ IPv6 ที่มี pid+port เดียวกันเป็นแถวเดียว แล้วแสดง address ทั้งสองแบบ
- exit 1 ที่ stdout ว่าง = ไม่มี listener ให้แสดง empty state ไม่ใช่ error
- ชื่อที่ lsof escape ไว้ (เช่น `\x20`) ต้อง decode ก่อนแสดง
- `ShellHelper`: อ่าน stdout/stderr ระหว่างที่ process ยังรัน (หรืออ่านจนจบก่อน wait) เพื่อไม่ให้ pipe เต็มแล้วค้าง ใส่ timeout ด้วย
- ระหว่างสแกนครั้งแรกแสดงสถานะกำลังโหลด และ**ห้ามมี demo data ในโค้ด production เลย** (ใช้ได้เฉพาะ `#Preview`)
- รีเฟรชอัตโนมัติเฉพาะตอนที่ popover หรือหน้าต่างหลักเปิดอยู่ (ค่าเริ่มต้นทุก 5 วินาที) และสแกนทันทีเมื่อเปิด popover

### 4.2 การ kill
- จุดที่สั่ง kill ได้: ปุ่ม ✕ ในแถวของ popover, เมนูคลิกขวาในตาราง, ปุ่ม/คีย์ Delete กับแถวที่เลือก
- **ยืนยันทุกครั้ง** ด้วย dialog ที่แสดงชื่อ process เต็ม, port, PID ถ้าเลือกหลายแถวให้แสดงรายการทั้งหมดใน dialog เดียว ไม่มีตัวเลือก "ไม่ต้องถามอีก"
- **ก่อนส่ง signal ให้ตรวจซ้ำ** ว่า PID นั้นยังเป็น process ชื่อเดิมและยังจับ port เดิมอยู่ เพื่อป้องกันกรณี PID ถูกนำกลับมาใช้ระหว่างเปิด dialog ถ้าไม่ตรงให้ยกเลิกแล้วแจ้งผู้ใช้
- คำเตือนสีเหลืองใน dialog เมื่อ:
  - เป็น Docker (`com.docker.*`, `vpnkit` ฯลฯ): "จะหยุด container ทุกตัว"
  - เป็น process ของระบบ (path อยู่ใน `/System/` หรือ `/usr/libexec/`, หรือรู้จักชื่อ เช่น ControlCenter, rapportd)
  - เป็น process ของ user อื่น: แจ้งว่าน่าจะไม่มีสิทธิ์
  - เป็นตัว Port Killer เอง: ห้าม kill
- ลำดับการปิด: ส่ง SIGTERM รอสูงสุดประมาณ 3 วินาที ถ้ายังไม่ปิดให้ถามว่า "บังคับปิด (SIGKILL)?"
- แจ้งผลแบบไม่ขวางการใช้งาน เช่น banner ใน popover หรือหน้าต่าง ตัวอย่าง: "ปิด node (3000) แล้ว", "ไม่มีสิทธิ์ปิด process ของ root", "process ปิดไปก่อนแล้ว"
- หลัง kill ให้สแกนใหม่ทันที

### 4.3 Pin
- pin ด้วย port และชื่อ process โดยเทียบแบบตรงตัว (เลิกใช้ substring และเลิกใช้ "port ตรงอย่างเดียวก็นับว่า pin")
- port ที่ pin ไว้อยู่บนสุดของรายการทั้งใน popover และตาราง
- ถ้า port ที่ pin ไว้ไม่ได้รันอยู่ ให้แสดงเป็นแถวจาง ๆ "ไม่ได้รัน" ที่ kill ไม่ได้ แต่ยกเลิก pin ได้
- เก็บใน UserDefaults (key `PortKiller.pinnedBookmarks` เดิม ย้ายข้อมูลเดิมมาได้ถ้ารูปแบบเข้ากัน)

### 4.4 Start at login
- ใช้ `SMAppService.mainApp` สถานะของสวิตช์ต้องอ่านจาก `status` จริงเสมอ ห้ามเก็บค่าที่ไม่ตรงกับระบบ
- ถ้าระบบต้องการการอนุมัติ (`.requiresApproval`) ให้แสดงข้อความพร้อมปุ่มเปิด System Settings › Login Items

### 4.5 หน้าจอ
- **Menu bar popover** ตาม mockup ที่ผู้ใช้เห็น: ช่องค้นหาด้านบน, ปุ่มรีเฟรช, แต่ละแถวแสดง port (monospace), ชื่อ process, `PID · user` และปุ่ม ✕ ด้านล่างมี เปิดหน้าต่าง, ตั้งค่า, ออก ป้าย "Docker" แสดงเฉพาะเมื่อเป็น Docker จริง
- **หน้าต่างหลัก:** SwiftUI `Table` คอลัมน์ Port, Process, PID, User, Address เรียงลำดับได้ เลือกหลายแถวได้ toolbar มีช่องค้นหา, รีเฟรช, Kill ที่เลือก เมนูคลิกขวามี Kill, คัดลอก PID, คัดลอก port, Pin/ยกเลิก pin, แสดงใน Activity Monitor ข้อความใน cell เลือกและคัดลอกได้
- **Settings** (macOS `Settings` scene): Start at login, ช่วงเวลารีเฟรช, ลิงก์ GitHub และเวอร์ชันที่อ่านจาก `CFBundleShortVersionString`
- คีย์ลัด: ⌘R รีเฟรช, ⌘F ค้นหา, Delete/⌘⌫ kill แถวที่เลือก (ผ่าน dialog), ⌘C คัดลอก, ⌘, ตั้งค่า
- ปุ่มที่มีแต่ไอคอนต้องมี `accessibilityLabel` และ `.help`
- ใช้สีระบบและ semantic font ทั้งหมด ไม่บังคับ dark mode
- ไอคอนแอปและไอคอน menu bar ใช้ของเดิม

## 5. ข้อจำกัด

- Swift + SwiftUI, ไม่ใช้ dependency ภายนอก (ตาม CLAUDE.md)
- Sandbox ต้องปิดต่อไป เพราะต้องรัน `lsof`/`kill` ใช้ Hardened Runtime ได้ (จำเป็นสำหรับ notarize)
- โปรเจกต์ใช้ `PBXFileSystemSynchronizedRootGroup`: ไฟล์ใหม่ใต้ `Port Killer/` ถูก compile อัตโนมัติ
- คง `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` งานที่รันนอก main thread ต้องอยู่ใน `actor` หรือเป็น `nonisolated`
- ต้องลด `MACOSX_DEPLOYMENT_TARGET` เป็น 14.0 แล้วแก้ API ที่ใหม่กว่านั้น
- Team ID ในโปรเจกต์คือ `F74446W6S9`: การ notarize ต้องมีใบรับรอง Developer ID Application ของทีมนี้

## 6. ปล่อยให้ผู้สร้างตัดสินใจ

- โครงสร้างไฟล์ใหม่ (แนะนำให้แยก `ContentView.swift` ออกเป็นไฟล์ตามหน้าจอ)
- จะ parse lsof แบบ `-F` หรือแบบคอลัมน์ ตราบใดที่ผ่านเทสกรณี IPv6, ชื่อมีช่องว่าง, ไม่มี listener
- วิธีตรวจ "process ของระบบ" และรายชื่อ process ของ Docker
- วิธีดึงข้อมูลสำหรับการตรวจ PID ซ้ำ (`proc_pidpath`/`ps`/`lsof -p`)
- รูปแบบ banner แจ้งผล
- **เทส:** เพิ่ม unit test target สำหรับ lsof parser, การตรวจ PID ซ้ำ/คำเตือน และ pin matching โดยใช้ fixture ที่เป็น output จริงของ lsof (รวมตัวอย่างจากเครื่องผู้ใช้ในเอกสารนี้: `com.docke`, `ControlCe`, `127.0.0.1:…`, `*:…`) ส่วน UI ไม่บังคับต้องมีเทส
- **การปล่อย:** รายละเอียดภายใน `scripts/release.sh` (ขอบเขตกำหนดไว้ใน §3) README ต้องมีภาพหน้าจอ, ลิงก์ดาวน์โหลด, วิธี build จาก source และคำอธิบายว่าทำไมต้องปิด sandbox
- เวอร์ชันแรกที่ปล่อย (แนะนำ 1.0.0) และ CHANGELOG

## 7. การตรวจสอบ (end-to-end)

1. `xcodebuild -project "Port Killer.xcodeproj" -scheme "Port Killer" build` และ `test` ผ่าน (ต้องเลือก Xcode เต็มด้วย `xcode-select` ก่อน)
2. รัน `python3 -m http.server 3000` และ `nc -l ::1 4000` (IPv6) แล้วตรวจว่าทั้งสองแสดงด้วย port ที่ถูกต้องและชื่อเต็ม
3. kill ตัว http.server: ต้องขึ้น dialog, ปิดด้วย SIGTERM และขึ้น banner ว่าสำเร็จ
4. รันโปรแกรมที่ดัก SIGTERM (`trap '' TERM`): ต้องถามเรื่อง SIGKILL
5. kill port ของ Docker หรือ ControlCenter: ต้องเห็นคำเตือนสีเหลือง (กดยกเลิก)
6. เปิด dialog ค้างไว้ ปิด process เองใน terminal แล้วกดยืนยัน: แอปต้องไม่ส่ง signal และต้องแจ้งว่า process ปิดไปแล้ว
7. ปิด listener ทั้งหมดที่ทำได้: ต้องเห็น empty state ไม่ใช่ error
8. เปิดแอปครั้งแรกบนเครื่องที่มี key `PortKiller.autoKillRules` ค้างอยู่: key ต้องถูกลบ และไม่มีอะไรถูก kill
9. เปิด Start at login แล้ว logout/login: แอปต้องเปิดขึ้นมาเอง และสวิตช์ต้องตรงกับ System Settings
10. ค้นหาในโค้ดต้องไม่เจอ `demoPorts`, `StoreKit`, `AutoKillRule`, `v2.4.0` นอก `#Preview`
11. สลับ light/dark mode ทั้ง popover และหน้าต่างหลักต้องอ่านง่าย ใช้ VoiceOver อ่านปุ่ม ✕ ได้ว่า "Kill node on port 3000"
12. รัน `sudo python3 -m http.server 8088`: port 8088 ต้องแสดงเป็นแถวอ่านอย่างเดียวพร้อมป้าย root และไม่มีปุ่ม kill แต่มี "คัดลอก sudo kill"
13. `scripts/release.sh` บนเครื่องที่ไม่มี Developer ID: ต้องได้ .zip ที่แตกแล้วเปิดได้ตามขั้นตอนใน README
