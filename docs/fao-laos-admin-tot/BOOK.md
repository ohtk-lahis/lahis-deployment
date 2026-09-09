# LAHIS Admin Train-the-Trainer Guide — Book Manifest

This file is the canonical reader order, chapter number, and reader-facing title for the guide. The build process must read this file; it must not infer order from filenames or reuse a table copied into a chapter.

| Chapter | Source | Reader-facing title | Primary audience |
|---|---|---|---|
| 0 | `chapters/00-how-to-use.md` | วิธีใช้คู่มือนี้ | ผู้ดูแลระบบ, ผู้ฝึกสอน |
| 1.1 | `chapters/01-what-we-have.md` | LAHIS มีอะไร และการอบรมนี้จะใช้ส่วนใด | ผู้ดูแลระบบ, ผู้ฝึกสอน |
| 1.2 | `chapters/02-system-map.md` | แผนผังระบบ | ผู้ดูแลระบบ, ผู้ฝึกสอน |
| 2.1 | `chapters/03-login.md` | เข้าสู่ระบบ Staging | ผู้ดูแลระบบ, ผู้ฝึกสอน |
| 2.2 | `chapters/04-first-checks.md` | ตรวจข้อมูลพื้นที่และผู้ใช้เบื้องต้น | ผู้ดูแลระบบ, ผู้ฝึกสอน |
| 3 | `chapters/05-user-onboarding.md` | เตรียมผู้ใช้ใหม่ด้วย Invitation Code | System Admin |
| 4.1 | `chapters/06a-form-builder-labels.md` | ปรับแบบฟอร์มรายงาน: ข้อความและกติกาข้อมูล | System Admin |
| 4.2 | `chapters/06b-disease-groups-conditions.md` | กลุ่มโรคและการแสดงคำถามตามชนิดสัตว์ | System Admin |
| 4.3 | `chapters/06c-add-species-disease-symptom.md` | เพิ่มชนิดสัตว์ รายการโรค และอาการ | System Admin |
| 5 | `chapters/07-followup-metrics.md` | แบบฟอร์มติดตามผลและการรวมตัวเลข | System Admin, Officer |
| 6 | `chapters/08-census-round.md` | เตรียมและติดตามรอบสำมะโนสัตว์ | System Admin, Officer |
| 7.1 | `chapters/08b-case-workflow.md` | Case Workflow: ภาพรวมเส้นทางของ Case | System Admin, Officer |
| 7.2 | `chapters/08a-case-definition.md` | Case Definition: ออกแบบและกำกับกติกาเปิด Case อัตโนมัติ | System Admin |
| 7.3 | `chapters/08c-case-close-form.md` | แบบฟอร์มปิด Case: ข้อมูลผลการตรวจสอบ | System Admin, Officer |
| 7.4 | `chapters/08d-reporter-alerts.md` | Reporter Alerts: ข้อความอัตโนมัติถึงผู้รายงาน | System Admin |
| 8 | `chapters/09-daily-work.md` | งานประจำวัน: สาธิตเส้นทางรายงานหนึ่งรายการ | Officer, ผู้รายงาน, ผู้ฝึกสอน |

## Rules for this manifest

- `Chapter`, `Source`, and `Reader-facing title` are the only authority for the book's table of contents and assembly order.
- Every chapter's front matter and H1 must match its row exactly.
- A new chapter requires a new row here before it is included in a reader build.
- The order `08b` before `08a` is deliberate: explain the Case workflow before teaching the separate System Admin Case Definition.
