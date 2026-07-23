# เอกสารส่งมอบ: Deploy LAHIS ขึ้น Staging (PODD)

เอกสารนี้รวบรวมข้อมูลสำหรับทีม Technical ฝั่ง PODD ใช้ประกอบการทำและ deploy **Mobile**, **Dashboard**, และ **API** ขึ้น server Staging

---

## 1. Git Repository

ระบบ LAHIS ประกอบด้วย **หลาย repository** (ที่เก็บโค้ด) แยกตามหน้าที่ ไม่ได้รวมอยู่ในที่เดียว

เพื่อให้ง่ายต่อการดูแล เราแบ่งเป็น 2 กลุ่ม:

| กลุ่ม | ความหมายแบบง่าย | ใช้ทำอะไร |
|--------|------------------|-----------|
| **Upstream** | โค้ดหลักของระบบ (OHTK) | ฟีเจอร์ใหม่, แก้บั๊กของระบบกลาง |
| **Downstream** | โค้ดเฉพาะของ LAHIS ที่แยกออกมาจากโค้ดหลัก | หน้าตา/แบรนด์ LAHIS, ตั้งค่าเฉพาะ LAHIS, แอปมือถือของ LAHIS |

### 1.1 Upstream — โค้ดหลัก (OHTK)

เป็น repository ของทีมพัฒนาหลัก ใช้ชื่อองค์กร **onehealthtoolkit**

| ชื่อ | หน้าที่แบบสั้น | ลิงก์ |
|------|----------------|--------|
| **OHTK API** | ส่วนหลังบ้าน (server / ฐานข้อมูล / บริการข้อมูล) | https://github.com/onehealthtoolkit/ohtk-api |
| **OHTK MS** | แดชบอร์ดเว็บสำหรับเจ้าหน้าที่ (เวอร์ชันหลัก) | https://github.com/onehealthtoolkit/ohtk-ms |
| **OHTK Mobile** | แอปมือถือเวอร์ชันหลัก (ต้นทางของ LAHIS Mobile) | https://github.com/onehealthtoolkit/ohtk-mobile |

**หมายเหตุสำคัญเกี่ยวกับ API**

- **API ไม่ได้แยก fork เป็น LAHIS**
- ฝั่ง Staging ของ LAHIS ใช้โค้ดจาก **OHTK API** โดยตรง แล้วไปตั้งค่า (ชื่อโดเมน, tenant, env) ให้เป็นของ LAHIS ตอน deploy
- แดชบอร์ดและมือถือของ LAHIS เท่านั้นที่แยกเป็น repository เฉพาะแบรนด์

### 1.2 Downstream — โค้ดเฉพาะ LAHIS

เป็น repository ภายใต้องค์กร **ohtk-lahis**  
แยกออกมาจากโค้ดหลัก เพื่อให้ทีม LAHIS ดูแลส่วนที่เป็นแบรนด์และการปล่อยเวอร์ชันของตัวเองได้

| ชื่อ | มาจาก | หน้าที่แบบสั้น | ลิงก์ |
|------|--------|----------------|--------|
| **LAHIS MS** | fork จาก OHTK MS | แดชบอร์ดเว็บสำหรับ LAHIS | https://github.com/ohtk-lahis/lahis-ms |
| **LAHIS Mobile** | fork จาก OHTK Mobile | แอปมือถือสำหรับ LAHIS | https://github.com/ohtk-lahis/lahis-mobile |

### 1.3 LAHIS Deployment — ขั้นตอน Deploy Staging

| ชื่อ | หน้าที่แบบสั้น | ลิงก์ |
|------|----------------|--------|
| **LAHIS Deployment** | เก็บขั้นตอนและสคริปต์สำหรับ deploy ระบบ LAHIS ขึ้น Staging (API + Dashboard) | https://github.com/ohtk-lahis/lahis-deployment |

- อยู่ภายใต้องค์กร **ohtk-lahis** เหมือน LAHIS MS / LAHIS Mobile
- **ไม่ได้เก็บโค้ดแอป** — โค้ดแอปยังอยู่ที่ OHTK API, LAHIS MS, LAHIS Mobile
- ขั้นตอน deploy Staging อยู่ใน repository นี้ — ไม่ได้อยู่ใน repo ของแอป

---

## 2. ข้อมูลตัวอย่าง (Seed data) บน Staging

บน Staging มีชุดข้อมูลตัวอย่างสำหรับ tenant ชื่อ **demo** ไว้ให้ทดสอบได้ทันที  
ข้อมูลชุดนี้อยู่ใน repository **LAHIS Deployment** (`seeds/demo`) และจะถูกใส่เข้า tenant หลัง deploy ตามขั้นตอนใน repository นั้น

จุดประสงค์ของ seed data คือให้ทีมรู้ว่า **ตอนนี้ทดสอบอะไรได้แล้ว** โดยไม่ต้องสร้างข้อมูลพื้นฐานเองทั้งหมด

### 2.1 โครงสร้างพื้นที่ / หน่วยงาน

มีโครงหน่วยงานในลาวแบบตัวอย่าง:

| ระดับ | สิ่งที่มีใน seed |
|--------|------------------|
| ประเทศ | Laos |
| แขวง | ครบชุดแขวงหลัก (เช่น Vientiane Capital, Luang Prabang, Savannakhet, Champasak ฯลฯ) |
| เมือง/อำเภอ | มีบางส่วนภายใต้แขวงสำคัญ เช่น ใต้ Vientiane Capital มี Sangthong และเมืองอื่นๆ |
| บ้าน (Village) | มี **5 บ้าน** ใต้ Sangthong (`ST-01` … `ST-05`) |

**ทดสอบอะไรได้**

- เลือกหน่วยงาน / ดูลำดับชั้นบน Dashboard
- งานที่เกี่ยวกับหมู่บ้าน (เช่น ผูกผู้รายงานกับบ้าน)
- ทดสอบขอบเขตสิทธิ์ตามหน่วยงาน (ประเทศ / แขวง / เมือง)

### 2.2 บัญชีผู้ใช้ Dashboard

รหัสผ่านชุดทดสอบ (ใช้เฉพาะ lab/staging — ควรเปลี่ยนถ้าเครื่องเปิดให้คนนอกใช้):

| ชื่อผู้ใช้ | รหัสผ่าน | บทบาทแบบง่าย | หน่วยงาน |
|------------|----------|---------------|----------|
| `L01` | `1234` | Admin + superuser | Laos (ทั้งประเทศ) |
| `V01` | `1234` | Officer | Vientiane Capital |
| `S01` | `1234` | Officer | Sangthong |
| `lahisadmin` | `1234` | Superuser (ไม่ผูกหน่วยงาน) | — |

**ทดสอบอะไรได้**

- เข้า Dashboard ด้วยบัญชีต่างระดับ
- ดูว่า Admin กับ Officer เห็นเมนู / ข้อมูลต่างกันอย่างไร
- ตั้งค่าหน่วยงาน (ใช้ `L01`)

### 2.3 รหัสเชิญ (Invitation) สำหรับสมัคร Mobile

มีรหัสเชิญแบบตัวเลข สำหรับ **ผู้รายงาน (Reporter)** ผูกกับบ้านใน Sangthong บ้านละ 1 รหัส:

| รหัสเชิญ | บ้าน |
|----------|------|
| `4611164` | ST-01 Ban Sangthong |
| `4706052` | ST-02 Ban Nong Buathong |
| `6716604` | ST-03 Ban Nasom |
| `6935028` | ST-04 Ban Phon Ngam |
| `7064111` | ST-05 Ban Dong Khamxang |

**ทดสอบอะไรได้**

- สมัคร / ลงทะเบียนบน Mobile ด้วยรหัสเชิญ
- ตรวจว่าผู้ใช้ถูกผูกกับบ้านที่ถูกต้อง
- ทดลอง consent ตอนสมัคร (มีข้อความ consent ใส่ไว้ใน seed แล้ว)

### 2.4 แบบรายงาน (Report)

| รายการ | รายละเอียด |
|--------|------------|
| กลุ่มรายงาน | **Animal** |
| ประเภทหลัก | **Animal Sick/Death** (สัตว์ป่วย/ตาย) |
| Follow-up | มีแบบติดตามผลต่อจากรายงานหลัก |
| สถานะ | เปิดใช้แล้ว (published) |

**ทดสอบอะไรได้**

- ส่งรายงานสัตว์ป่วย/ตายจาก Mobile
- ดูรายงานบน Dashboard
- ทำ follow-up ต่อจากรายงาน
- ดูข้อความสรุปของรายงาน (summary text)

### 2.5 สำมะโน (Census)

| รายการ | รายละเอียด |
|--------|------------|
| สำมะโนสัตว์ | `DEMO_ANIMAL` — ปี 2026, ทั้งประเทศ |
| สำมะโนคน | `DEMO_HUMAN` — ปี 2026, ทั้งประเทศ |
| นิยามฟอร์มสำมะโน | มี default สำหรับ animal + human |

**ทดสอบอะไรได้**

- เปิดรอบสำมะโนบน Dashboard
- ส่งข้อมูลสำมะโนจาก Mobile (ถ้า feature เปิดครบ)
- ตรวจหน้า census / definition ที่เกี่ยวข้อง

### 2.6 Feature ที่เปิดไว้ใน seed

| Feature | ความหมายแบบง่าย |
|---------|------------------|
| Village | เปิดใช้หมู่บ้าน / เมนูหมู่บ้าน / invitation ผูกบ้าน |
| Animal census | เปิดใช้สำมะโนสัตว์ (ต้องมี village เปิดอยู่ด้วย) |

**ทดสอบอะไรได้**

- เมนูและ flow ที่เกี่ยวกับหมู่บ้าน
- flow สำมะโนสัตว์

### 2.7 สิ่งที่ทดสอบได้หลังมี seed

| อยากทดสอบ | ใช้ seed ส่วนไหน |
|-----------|------------------|
| เข้า Dashboard | บัญชี `L01` / `V01` / `S01` |
| จัดการหน่วยงาน | `L01` + โครง authorities |
| สมัคร Mobile + ผูกบ้าน | รหัสเชิญ + 5 บ้านใน Sangthong |
| ส่งรายงานสัตว์ป่วย/ตาย | Report type **Animal Sick/Death** |
| ติดตามผลรายงาน | Follow-up form ของ Animal Sick/Death |
| สำมะโนสัตว์ / คน | Census rounds ปี 2026 |
| ข้อความยินยอมบน Mobile | Consent message ใน configuration |

---

## 3. การ Build แอป Mobile และการตั้ง URL ของ Tenant

แอป **LAHIS Mobile** (Flutter) **ไม่ได้จำที่อยู่ของ Tenant ทุกตัวไว้ในตัวแอปแบบตายตัว**

มี **2 จุด** ที่ URL ต้องตรงกับ Staging — ถ้าจุดใดจุดหนึ่งไม่ตรง แอปจะเชื่อม Staging ไม่ได้

| จุด | ทำที่ไหน | ทำไมสำคัญ |
|-----|----------|-----------|
| **1. URL รายการ Tenant** | ตอน **build แอป** | แอปจะรู้ว่าไปถามรายชื่อ Tenant ได้ที่ไหน |
| **2. URL ของแต่ละ Tenant** | ตอน **config Tenant บน API / Staging** | หลังผู้ใช้เลือก Tenant แล้ว แอปจะรู้ว่าต้องคุยกับที่อยู่ไหนต่อ |

ถ้าจุดใดจุดหนึ่งผิด แอปอาจ:

- ดึงรายการ Tenant ไม่ขึ้น หรือขึ้นรายการจากระบบอื่น
- เลือก Tenant ได้ แต่ login / สมัคร / ส่งรายงานไม่ได้
- ไปติดต่อ host ผิดชุด

### 3.1 ทำงานยังไงแบบสั้นๆ

```text
1) ตอน build แอป
   → กำหนด URL รายการ Tenant (TENANT_API_ENDPOINT)
   → เช่น https://api.lahis.ohtk.org/api/servers/

2) ตอนเปิดแอป
   → แอปเรียก URL นั้น เพื่อดึงรายการ Tenant
   → แต่ละรายการมาพร้อม "ที่อยู่ (domain)" ของ Tenant นั้น

3) ผู้ใช้เลือก Tenant
   → เช่น "LAHIS Demo"

4) หลังจากนั้น
   → แอปใช้ domain ของ Tenant นั้น ต่อ (login, รายงาน, census ฯลฯ)
   → เช่น https://demo.api.lahis.ohtk.org/...
```

สรุป:

- **Build URL** = ประตูไปหารายการ Tenant
- **Tenant domain** = ที่อยู่จริงของ Tenant หลังเลือกแล้ว

ทั้งสองค่าต้องเป็นของ **Staging ชุดเดียวกัน**

### 3.2 จุดที่ 1 — ค่าที่ต้องตั้งตอน build แอป

| รายการ | ความหมายแบบง่าย | ตัวอย่างบน Staging ปัจจุบัน |
|--------|------------------|------------------------------|
| `TENANT_API_ENDPOINT` | URL ที่แอปใช้ดึงรายการ Tenant | `https://api.lahis.ohtk.org/api/servers/` |
| เอกสารบางฉบับเรียกว่า | `SERVER_LIST_ENDPOINT` (ค่าเดียวกัน แค่ชื่อคนละแบบ) | ค่าเดียวกับด้านบน |

- ใช้โค้ดจาก repository **LAHIS Mobile**
- ค่านี้ถูก **compile ติดไปกับตัวแอป** — เปลี่ยนทีหลังโดยไม่ build ใหม่ไม่ได้

ตัวอย่างคำสั่ง (แนวทาง):

```bash
flutter build appbundle \
  --dart-define=TENANT_API_ENDPOINT=https://api.lahis.ohtk.org/api/servers/
```

*(คำสั่ง build จริงอาจใช้สคริปต์ใน repo — สำคัญคือต้องส่ง `TENANT_API_ENDPOINT` ชี้ Staging ที่ถูกต้อง)*

### 3.3 จุดที่ 2 — Tenant configuration ต้องตั้ง URL ให้ถูก

บน API / Staging แต่ละ Tenant ต้องมี **domain (ที่อยู่)** ถูกต้อง  
ค่านี้คือสิ่งที่ `/api/servers/` ส่งกลับไปให้แอป และแอปจะใช้ต่อหลังผู้ใช้เลือก Tenant

| รายการ | ตัวอย่างบน Staging ปัจจุบัน |
|--------|------------------------------|
| ชื่อที่แสดง (Tenant name) | `LAHIS Demo` |
| schema / รหัสภายใน | `demo` |
| domain ของ Tenant | `demo.api.lahis.ohtk.org` |

**ต้องถูกพร้อมกัน**

1. บันทึก domain ของ Tenant ในระบบ API ให้ตรง host จริงของ Staging
2. host นั้นต้องเปิดใช้งานได้จริง (DNS / HTTPS ชี้มาที่ server Staging)
3. แอปที่ build แล้ว ไปดึงรายการจาก parent API ของ Staging ชุดเดียวกัน

ถ้า domain ใน Tenant config ผิด แม้ build แอปถูก ผู้ใช้อาจยัง **เห็นชื่อ Tenant** แต่ใช้งานต่อไม่ได้ เพราะแอปถูกพาไปที่อยู่ผิด

รายละเอียดการสร้าง Tenant / ใส่ domain อยู่ในขั้นตอนของ **LAHIS Deployment**  
section นี้เน้นว่า domain ของ Tenant ต้องตรงกับ Staging

### 3.4 ตรวจว่าชี้ถูกหรือยัง

| ตรวจอะไร | ผลที่ควรได้ |
|----------|-------------|
| เปิดแอป แล้วดูรายการ Tenant | เห็น Tenant ของ Staging ชุดนี้ (เช่น `LAHIS Demo`) |
| เลือก Tenant แล้ว login / สมัคร | ใช้บัญชีหรือรหัสเชิญจาก seed (Section 2) ได้ |
| เรียกดูรายการจาก parent API | `/api/servers/` แสดง Tenant พร้อม domain ที่ถูกต้อง |
| เรียกที่อยู่ของ Tenant โดยตรง | host เช่น `demo.api.lahis.ohtk.org` ตอบได้ |

**แยกอาการคร่าวๆ**

| อาการ | มักผิดที่ |
|-------|-----------|
| แอปไม่มีรายการ Tenant / รายการไม่ใช่ของ Staging | **build URL** (`TENANT_API_ENDPOINT`) |
| เห็น Tenant แล้ว แต่เข้าใช้งานต่อไม่ได้ | **Tenant domain / config บน server** |
| ทั้งรายการผิด และเข้าต่อไม่ได้ | อาจผิดทั้งสองจุด หรือชี้คนละสภาพแวดล้อม |

### 3.5 สิ่งที่ต้องพร้อมก่อน build และก่อนทดสอบ Mobile

| ต้องมี | ทำไม |
|--------|------|
| API Staging ทำงานอยู่ | แอปต้องเรียก `/api/servers/` ได้ |
| Tenant ถูกสร้างแล้ว และ domain ตั้งถูก | รายการ Tenant ต้องพาไปที่อยู่จริงได้ |
| DNS / HTTPS ของ domain Tenant ใช้ได้ | แอปต้องคุยกับ host นั้นต่อได้ |
| `TENANT_API_ENDPOINT` ตอน build ตรง Staging จริง | หลีกเลี่ยงการปน URL dev/local หรือระบบอื่น |

---

## 4. Integration (เชื่อมระบบภายนอก)

บน Staging ฝั่ง LAHIS มีช่องทางให้ระบบภายนอก **รับเหตุการณ์จาก LAHIS** และ **ส่งผลลัพธ์กลับเข้า LAHIS** ได้

งานระบบภายนอกที่เกี่ยวข้องกับ Staging ชุดนี้ ได้แก่:

| ระบบฝั่ง PODD | ทำอะไรแบบสั้นๆ | ส่งผลกลับเข้า LAHIS แบบไหน |
|---------------|-----------------|------------------------------|
| **Cluster Engine** | หา/จัดกลุ่มเหตุการณ์ที่เกี่ยวข้องกัน | บันทึกผล cluster กลับเข้า LAHIS |
| **Risk Suggestion** | ประเมินความเสี่ยงของรายงาน | บันทึก risk assessment กลับเข้า LAHIS |
| **AI feedback** | วิเคราะห์/ให้คำแนะนำจากรายงาน | บันทึก comment / feedback ให้เจ้าหน้าที่เห็น |

LAHIS เป็นตัวเก็บรายงาน ข้อมูลสำมะโน และแสดงผลบน Dashboard / Mobile  
ระบบ engine ด้านบนทำงาน **คู่ขนาน** ผ่านชั้น Integration — ไม่ได้ฝัง engine เหล่านี้ใน OHTK API โดยตรง

รายละเอียดสัญญาเชื่อมต่อ (OAuth, scope, รูปแบบ request/response, webhook) อยู่ใน:

**`lahis-deployment` → [INTEGRATION_GUIDELINE.md](./INTEGRATION_GUIDELINE.md)**

Section นี้สรุปภาพรวมและความรับผิดชอบ ไม่ซ้ำขั้นตอนละเอียดใน guideline

### 4.1 ภาพการทำงานแบบสั้นๆ

```text
[ผู้ใช้ Mobile / Dashboard]
        │
        ▼
[LAHIS API + Tenant บน Staging]
        │
        │  1) เมื่อมีรายงานใหม่ (เช่น report.submitted)
        │     LAHIS แจ้งออกไปทาง Webhook
        ▼
[ระบบฝั่ง PODD]
  - Cluster Engine
  - Risk Suggestion
  - AI feedback
        │
        │  2) ระบบฝั่งนอกรับ event / อ่านข้อมูลที่อนุญาต
        │  3) ประมวลผล
        │  4) เขียนผลกลับเข้า LAHIS ผ่าน Integration API
        ▼
[LAHIS เก็บผล + แสดงให้เจ้าหน้าที่]
```

มี 2 ทิศทาง:

| ทิศทาง | ความหมาย |
|--------|----------|
| **ออกจาก LAHIS** | แจ้ง event (เช่น มีรายงานใหม่) ไปที่ callback URL ของฝั่ง PODD |
| **เข้าสู่ LAHIS** | ฝั่ง PODD เรียก API เพื่ออ่านข้อมูลที่จำเป็น และเขียนผล (comment / risk / cluster) กลับ |

### 4.2 ใครรับผิดชอบอะไร

| ฝ่าย | รับผิดชอบ |
|------|-----------|
| **ทีม LAHIS / เอกสาร deploy** | เตรียม Staging, Tenant, seed, ชั้น Integration บน API/Dashboard |
| **Admin บน Dashboard** | สร้าง Integration Client, กำหนดสิทธิ์ (scope), ตั้ง Webhook endpoint |
| **ทีม PODD** | พัฒนา Cluster Engine, Risk Suggestion, AI feedback; รับ webhook; เรียก API; ดูแล secret/credential ของระบบ engine |
| **ทั้งสองฝ่าย** | ตกลง Tenant ที่ใช้ทดสอบ, ชนิด event, สิทธิ์ที่ต้องเปิด, วิธีตรวจว่าเชื่อมสำเร็จ |

### 4.3 ระบบฝั่ง PODD เชื่อมกับ LAHIS ตรงไหน

| งานฝั่ง PODD | โดยทั่วไปต้องทำบน Integration | ผลที่ควรเห็นใน LAHIS |
|--------------|--------------------------------|------------------------|
| **AI feedback** | รับ event รายงานใหม่ → (ถ้าต้องการ) อ่านสรุปรายงาน → เขียน comment กลับ | เจ้าหน้าที่เห็น feedback/คำแนะนำบนรายงาน |
| **Risk Suggestion** | อ่านข้อมูลรายงานที่เกี่ยวข้อง → เขียน risk assessment กลับ | รายงานมีระดับ/ผลการประเมินความเสี่ยง |
| **Cluster Engine** | อ่านรายงาน / สำมะโนตามที่อนุญาต → เขียนผล cluster กลับ | มีผลกลุ่มเหตุการณ์ให้ดู/ใช้ต่อในระบบ |

หมายเหตุสำคัญ:

- Integration ใช้ **ที่อยู่ของ Tenant** (เช่น `https://demo.api.lahis.ohtk.org`) ไม่ใช่แค่ parent API
- ต้องมี **Integration Client** และสิทธิ์ที่ตรงงาน (อ่านรายงาน, เขียน comment, เขียน risk, เขียน cluster ฯลฯ)
- ข้อมูลที่เปิดให้ระบบภายนอกเป็น **ชุดสรุปที่ออกแบบไว้** ไม่ใช่เปิดฟอร์มดิบ / รูป / ตัวตนผู้รายงานทั้งหมดผ่านช่องนี้

### 4.4 Configuration ฝั่ง server (ต้องตั้งก่อนเชื่อม)

การมีโค้ด engine ฝั่ง PODD อย่างเดียว **ยังเชื่อม LAHIS ไม่ได้**  
ต้องมีการตั้งค่าฝั่ง server / Dashboard ภายใต้ Tenant ที่จะใช้ (เช่น `demo`) ก่อน

ทำบน Dashboard โดยทั่วไปที่:

**Admin → Integrations**

| สิ่งที่ต้องตั้ง | ความหมายแบบง่าย | ใช้ทำอะไร |
|----------------|------------------|-----------|
| **Integration Client** | บัญชีระบบสำหรับ engine ภายนอก | ขอ token เพื่อเรียก API อ่าน/เขียนผลกลับ |
| **สิทธิ์ (scope)** | ขอบเขตที่ client ทำได้ | เช่น อ่านรายงาน, เขียน comment, เขียน risk, เขียน cluster |
| **Webhook Endpoint** | จุดรับ event จาก LAHIS | LAHIS แจ้งเมื่อมีรายงานใหม่ (เช่น `report.submitted`) |
| **Callback URL** | ที่อยู่ HTTPS ของระบบฝั่ง PODD | ปลายทางที่ webhook ส่งไป |
| **Signing secret (อ้างอิง secret)** | กุญแจตรวจว่า webhook มาจาก LAHIS จริง | ฝั่งรับใช้ตรวจลายเซ็น |
| **สถานะเปิดใช้งาน** | client / endpoint ต้อง active | ปิดอยู่จะเรียกหรือรับ event ไม่ได้ |

**ลำดับแนวทาง**

1. ตกลง Tenant, scope, event, และ callback URL
2. สร้าง **Integration Client** บน Dashboard (ได้ client id / client secret)
3. ถ้าต้องการรับ event จาก LAHIS → สร้าง **Webhook Endpoint** ชี้ไป callback ของระบบ engine
4. เก็บ credential / secret ในช่องทางที่ปลอดภัย (ไม่ใส่ใน ticket, chat, หรือ repo)
5. ระบบฝั่ง PODD ใช้ client credentials ขอ token จาก **ที่อยู่ Tenant** แล้วค่อยเรียก Integration API
6. ตรวจว่า webhook มาถึง และเขียนผลกลับได้

**จุดที่มักทำให้เชื่อมไม่ติด**

| อาการ | มักเกี่ยวกับ config |
|-------|---------------------|
| ขอ token ไม่ได้ | Client ยังไม่สร้าง, ปิดอยู่, หรือใช้ host ผิด (ต้องเป็น Tenant host) |
| เรียก API แล้วถูกปฏิเสธ | scope ไม่ครบ หรือ client ไม่ได้อยู่ Tenant นั้น |
| มีรายงานใหม่แต่ engine ไม่ได้รับ | Webhook endpoint ยังไม่ตั้ง / ปิดอยู่ / callback URL ผิด |
| รับ webhook แล้วไม่เชื่อถือได้ | ยังไม่ได้ตั้งหรือตรวจ signing secret |

รายละเอียดฟิลด์, ตัวอย่าง request, และ checklist เต็มอยู่ใน **INTEGRATION_GUIDELINE.md**

### 4.5 Stub Integration (ของที่มีทดลองไว้แล้ว)

ก่อนเชื่อมระบบจริงของ PODD ฝั่ง LAHIS มี **ตัวจำลอง (stub) + ชุดทดสอบ smoke** อยู่ใน repository **LAHIS Deployment** แล้ว

| ชื่อ | ความหมายแบบง่าย |
|------|------------------|
| **Integration Stub** | ระบบปลอมฝั่งนอก — รับ webhook จาก LAHIS แทน engine จริง |
| **Integration Smoke** | ชุดตรวจอัตโนมัติว่าเชื่อมอ่าน/เขียน (comment, risk, cluster) ผ่าน |

**ใช้ทำอะไร**

- ตรวจว่า Staging พร้อมสำหรับ Integration
- เป็นตัวอย่างว่า “ฝั่งนอก” ควรรับ event และส่งผลกลับอย่างไร
- ไม่ได้แทน Cluster Engine / Risk Suggestion / AI feedback ของ PODD

**ความสัมพันธ์กับงาน PODD**

```text
[ตอนนี้ / ตอนตรวจ LAHIS]
  LAHIS  ←→  Integration Stub + Smoke   (ของใน lahis-deployment)

[ตอนเชื่อมของจริง]
  LAHIS  ←→  ระบบ PODD
              (Cluster Engine, Risk Suggestion, AI feedback)
```

- Stub = ตัวทดลองฝั่ง LAHIS
- ของ PODD = ระบบจริงที่มาแทนฝั่งรับ/ประมวลผล/เขียนผลกลับ
- สัญญาเชื่อมต่อชุดเดียวกัน รายละเอียดใน **INTEGRATION_GUIDELINE.md**

โค้ดและเอกสารที่เกี่ยวข้อง:

- `lahis-deployment/integration-smoke/` (stub + smoke runner)
- `lahis-deployment/compose.integration-smoke.yml`
- `lahis-deployment/scripts/run-integration-smoke.sh`
- `lahis-deployment/integration-smoke/README.md`

รัน smoke (บน host Staging ตามเอกสาร deploy):

```bash
cd /opt/lahis
./scripts/run-integration-smoke.sh
```

### 4.6 สิ่งที่ต้องมีก่อนเริ่มเชื่อมบน Staging

| รายการ | ทำไม |
|--------|------|
| Staging API + Tenant (เช่น `demo`) พร้อมใช้ | Integration ทำงานภายใต้ Tenant |
| Configuration ฝั่ง server ตามข้อ 4.4 | Client, scope, webhook, callback พร้อมก่อนเชื่อม |
| บัญชี/สิทธิ์สร้าง Integration บน Dashboard | ตั้งค่า client และ endpoint ได้ |
| Callback URL ของระบบ engine (HTTPS) | รับ webhook จาก LAHIS |
| ตกลง scope / event ที่จะใช้ | เปิดสิทธิ์เท่าที่จำเป็น |
| เอกสาร **INTEGRATION_GUIDELINE.md** | สัญญาเชื่อมต่อและตัวอย่างการเรียก |

ขั้นตอนสร้าง client, ขอ token, ตรวจ webhook, และ smoke test อยู่ใน guideline / สคริปต์ใน `lahis-deployment`

### 4.7 บทสรุป

1. งาน **Cluster Engine / Risk Suggestion / AI feedback** อยู่ฝั่ง PODD
2. LAHIS เป็นแหล่งรายงาน + ที่เก็บผลลัพธ์ที่ส่งกลับ
3. เชื่อมผ่าน **Integration** (webhook ออก + API เข้า) บน Tenant Staging
4. ต้องมี **Configuration ฝั่ง server** (Integration Client, scope, Webhook endpoint) ก่อนจึงเชื่อมได้
5. รายละเอียดเทคนิคอยู่ใน **`INTEGRATION_GUIDELINE.md`** ใน repo **LAHIS Deployment**
6. มี **Stub + Smoke** ไว้ตรวจฝั่ง LAHIS ก่อนต่อระบบ engine จริง
7. ทดสอบได้บน Tenant **demo** ร่วมกับ seed data ใน Section 2 (เช่น ส่งรายงาน Animal Sick/Death แล้วให้ engine ประมวลผล)


