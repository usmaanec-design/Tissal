# Maan Connect (Tisaal / اتصال)
### Phone-Number-Free Global Communication Platform (Android, iOS & Web)

A privacy-first, decentralized-identity messaging and peer-to-peer audio/video calling application. No mobile phone number, no email address, and no SIM card are ever required.

---

## 🌟 کلیدی خصوصیات (Key Highlights)

- 🔒 **Zero Personal Identifiable Information (Zero PII):**
  - کوئی موبائل نمبر درکار نہیں (No Phone Number).
  - کوئی ای میل درکار نہیں (No Email Address).
  - کوئی SIM کارڈ یا SMS ویریفکیشن نہیں (No SIM Card or SMS OTP).
- 🔑 **Cryptographic Identity & Recovery:**
  - 12 الفاظ کی کرپٹوگرافک ریکوری کی (BIP-39 Mnemonic Phrase).
  - خودکار یا اپنی پسند کا ہینڈل (`@MC-7K4P92` یا `@usman786`).
  - مستقل، محفوظ کرپٹوگرافک `Account ID` (Ed25519 Keypair).
  - چیلنج ریسپانس تصدیق (Challenge-Response Zero-Knowledge Login).
- 💬 **Real-time Instant Messaging:**
  - تیز رفتار WebSocket میسجنگ۔
  - ڈلیوری رپورٹس اور لائیو آن لائن اسٹیٹس۔
  - یوزرز کی تلاش اور کنکشن ریکویسٹس۔
- 📞 **P2P Voice & Video Calls (WebRTC):**
  - 1-to-1 براہ راست P2P ویڈیو اور آڈیو کالز۔
  - فل اسکرین ویڈیو کالنگ انٹرفیس مع لوکل کیمرہ (Picture-in-Picture).
  - STUN/TURN ریڈی انفراسٹرکچر برائے کم سے کم سرور لاگت۔

---

## 📁 پروجیکٹ کی ساخت (Project Structure)

```
Tisaal/
├── docs/
│   └── MVP_SPECIFICATION.md   # مکمل تکنیکی آرکیٹیکچر اور روڈ میپ
├── backend/                   # Node.js + TypeScript + WebSocket + SQLite
│   ├── src/
│   │   ├── crypto/            # Ed25519 سائننگ اور چیلنج تصدیق
│   │   ├── db/                # ڈیٹا بیس اسکیما اور کنکشن
│   │   ├── routes/            # Auth اور Users/Contacts REST APIs
│   │   ├── ws/                # WebSocket سگنلنگ (Chat & WebRTC)
│   │   └── server.ts          # مین سرور انٹری پوائنٹ
│   └── package.json
└── mobile/                    # Flutter موبائل ایپ (Android/iOS)
    ├── lib/
    │   ├── core/
    │   │   ├── crypto/        # BIP-39 & Ed25519 ڈارٹ انجن
    │   │   ├── models/        # User, Contact, Message ماڈلز
    │   │   └── services/      # ApiService, WebSocket, WebRTC سروسز
    │   ├── providers/         # Auth, Chat, اور Call اسٹیٹ مینیجرز
    │   ├── ui/
    │   │   ├── screens/       # Onboarding, Identity, Chats, Calls, Settings
    │   │   └── theme/         # پریمیم ڈارک میٹریل 3 تھیم
    │   └── main.dart
    └── pubspec.yaml
```

---

## 🚀 چلانے کا طریقہ (How to Run)

### 1. بیک اینڈ سرور چلائیں (Run Backend):
```powershell
cd c:\Users\usmaa\Downloads\active\Tisaal\backend
npm.cmd run dev
```
بیک اینڈ سرور `http://localhost:4000` اور رئیل ٹائم سگنلنگ `ws://localhost:4000/ws` پر شروع ہو جائے گا۔

### 2. موبائل ایپ چلائیں (Run Mobile App):
```powershell
cd c:\Users\usmaa\Downloads\active\Tisaal\mobile
flutter run
```
اینڈرائیڈ ایمولیٹر یا حقیقی ڈیوائس پر ایپ شروع ہو جائے گی۔

## 🧪 آڈٹ اور ٹیسٹنگ (Audit & Testing)

- **ٹیسٹ رپورٹ (Test Report):** [TEST_REPORT.md](file:///c:/Users/usmaa/Downloads/active/Tisaal/docs/TEST_REPORT.md)
- **سکیورٹی آڈٹ (Security Audit):** [SECURITY_AUDIT.md](file:///c:/Users/usmaa/Downloads/active/Tisaal/docs/SECURITY_AUDIT.md)

### ٹیسٹ چلانے کے احکامات (Commands):
```powershell
# 1. بیک اینڈ آڈٹ سوٹ چلائیں (9 ٹیسٹ کیسز)
cd c:\Users\usmaa\Downloads\active\Tisaal\backend
npm.cmd test

# 2. موبائل کلائنٹ کے یونٹ اور ویجیٹ ٹیسٹ چلائیں
cd c:\Users\usmaa\Downloads\active\Tisaal\mobile
flutter test

# 3. اینڈرائڈ ڈیبگ اے پی کے بلڈ کریں
flutter build apk --debug
```

---

## 🔐 شناخت اور ریکوری کیسے کام کرتی ہے؟
1. **نیا اکاؤنٹ بنانا:** ایپ ڈیوائس پر 12 الفاظ کی ریکوری فقرہ جنریٹ کرتی ہے۔
2. **رجسٹریشن:** ڈیوائس پر Ed25519 کیز ڈیرائیو ہوتی ہیں اور پبلک کی سرور پر رجسٹر ہوتی ہے۔
3. **لاگ ان یا نئے فون پر بحالی:** صرف 12 الفاظ درج کرنے سے اکاؤنٹ بغیر کسی فون یا ای میل کے بحال ہو جاتا ہے۔
