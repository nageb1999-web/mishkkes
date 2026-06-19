# مشخّص — دليل الإعداد مع Supabase

تطبيق تقييم الذهب في السوق العراقي.

---

## الملفات

| الملف | الوصف |
|-------|-------|
| `index.html` | التطبيق الرئيسي للمستخدمين |
| `admin.html` | لوحة إدارة الأسعار (للمشرف فقط) |
| `supabase-schema.sql` | قاعدة البيانات الكاملة — نفّذه مرة واحدة |
| `README.md` | هذا الملف |

---

## الخطوة 1 — إنشاء مشروع Supabase

1. اذهب إلى [supabase.com](https://supabase.com) وأنشئ حساباً مجانياً.
2. اضغط **New Project** واختر اسماً واضحاً (مثلاً `mshakhkhas`).
3. احتفظ بكلمة مرور قاعدة البيانات في مكان آمن.
4. انتظر حتى ينتهي إنشاء المشروع (دقيقة أو دقيقتان).

---

## الخطوة 2 — تنفيذ ملف SQL

1. من القائمة الجانبية اختر **SQL Editor**.
2. اضغط **New Query**.
3. افتح ملف `supabase-schema.sql` وانسخ محتواه كاملاً.
4. الصقه في المحرر واضغط **Run**.
5. تأكد أن جميع الأوامر نفّذت بنجاح (لا توجد أخطاء حمراء).

---

## الخطوة 3 — الحصول على URL وANON KEY

1. من القائمة الجانبية اختر **Project Settings** ← **API**.
2. انسخ قيمتين:
   - **Project URL** (يبدأ بـ `https://`)
   - **anon / public** (مفتاح المشروع العام)

> ⚠️ **لا تستخدم** `service_role` key في أي ملف HTML أو JavaScript.
> إنه مفتاح سري لا يجب أن يظهر في المتصفح.

---

## الخطوة 4 — وضع المفاتيح في الملفات

### في `index.html`

افتح الملف وابحث عن السطرين في أعلاه:

```js
const SUPABASE_URL      = 'YOUR_SUPABASE_URL';
const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';
```

استبدل القيم بمفاتيحك:

```js
const SUPABASE_URL      = 'https://xxxxxxxxxxx.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGci...';
```

### في `admin.html`

نفس الشيء — افتح الملف وابحث عن نفس السطرين في أعلاه وأضف قيمك.

---

## الخطوة 5 — إنشاء أول مستخدم Admin

### أ) إنشاء المستخدم

1. من القائمة الجانبية اختر **Authentication** ← **Users**.
2. اضغط **Add user** ← **Create new user**.
3. أدخل بريد إلكتروني وكلمة مرور.
4. اضغط **Create user**.
5. انسخ **User ID** (UUID) الخاص بالمستخدم الجديد.

### ب) منح صلاحية Admin

1. اذهب إلى **SQL Editor** وأنشئ استعلاماً جديداً.
2. نفّذ الأمر التالي (استبدل UUID بمعرف المستخدم الفعلي):

```sql
UPDATE public.profiles
SET role = 'admin'
WHERE id = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx';
```

3. تحقق من النتيجة:

```sql
SELECT id, role FROM public.profiles;
```

---

## الخطوة 6 — اختبار التطبيق

1. افتح `index.html` في المتصفح (أو ارفعه على أي استضافة).
2. عند أول تشغيل سيحاول جلب السعر من Supabase تلقائياً.
3. إذا نجح الاتصال ستظهر رسالة "تم تحديث أسعار السوق".
4. إذا فشل (offline) سيعرض آخر سعر محفوظ أو السعر الافتراضي.

5. افتح `admin.html` وسجّل دخولك ببريد المشرف وكلمة المرور.
6. أضف سعر جديد واضغط "حفظ السعر".
7. عد إلى `index.html` — السعر يجب أن يتحدث فورياً عبر Realtime.

---

## بنية قاعدة البيانات

### `market_prices`

| الحقل | النوع | الوصف |
|-------|-------|-------|
| `id` | UUID | مفتاح أساسي |
| `city` | text | المدينة (البصرة، بغداد، أربيل) |
| `karat` | integer | العيار (21، 18، 22…) |
| `origin` | text | منشأ الذهب: iraqi / gulf / turkish / general |
| `market_type` | text | retail / wholesale / buyback |
| `price_basis` | text | **raw_gold** (للحاسبة) أو includes_workmanship (مرجعي) |
| `unit` | text | gram / mithqal |
| `price_iqd` | numeric | السعر كما أُدخل |
| `price_per_gram_iqd` | numeric | **السعر الموحّد للغرام — المستخدم في الحسابات** |
| `is_verified` | boolean | مرئي للعموم فقط إذا كان `true` |
| `confidence_level` | text | low / medium / high |
| `source_count` | integer | عدد المصادر |
| `updated_at` | timestamptz | وقت آخر تعديل (يُحدَّث تلقائياً) |

### `market_price_history`

سجل تاريخي غير قابل للحذف. يُسجَّل تلقائياً عند كل تعديل عبر Database Trigger.

### `profiles`

| الحقل | القيمة | الوصف |
|-------|--------|-------|
| `role` | `'user'` | مستخدم عادي — قراءة فقط |
| `role` | `'admin'` | مشرف — كامل الصلاحيات |

---

## آلية الأسعار

```
index.html يجلب السعر حسب:
  city   = اختيار المستخدم في الإعدادات
  karat  = 21 (للعيار الأساسي)
  origin = اختيار المستخدم
  price_basis = 'raw_gold'     ← شرط ثابت
  market_type = 'retail'       ← شرط ثابت
  is_verified = true           ← شرط ثابت

إذا لم يوجد سعر للمنشأ المحدد:
  → يُجرَّب origin = 'general' كـ fallback

إذا لم يوجد اتصال:
  → يُعرض آخر سعر محفوظ في localStorage

السعر المُسترجع (price_per_gram_iqd) يُستخدم لحساب:
  rawValue = netWeight × (price21 × karat/21)

لا تُستخدم أبداً أسعار price_basis = 'includes_workmanship' في الحاسبة.
```

---

## الأمان

- ✅ **ANON KEY فقط** في ملفات HTML — لا service_role.
- ✅ **RLS مُفعَّل** على جميع الجداول.
- ✅ المستخدم العادي يرى فقط `is_verified = true`.
- ✅ الإضافة والتعديل والحذف تتطلب `role = 'admin'`.
- ✅ سجل التاريخ لا يُمكن تعديله من الواجهة.

---

## أسئلة شائعة

**لماذا التطبيق يعمل بدون Supabase؟**
التطبيق يعمل offline باستخدام آخر سعر محفوظ في localStorage. إذا لم يُضبط URL وANON KEY، سيعرض سعراً تجريبياً (95,000 د.ع) ويعمل بشكل كامل.

**كيف أحدّث السعر يدوياً؟**
من `admin.html` بعد تسجيل الدخول → إضافة سعر جديد. ستظهر التحديثات للمستخدمين المتصلين فورياً عبر Realtime.

**هل يمكن إضافة مدن أخرى؟**
نعم — أضف السعر من لوحة الإدارة واختر "أخرى" كمدينة، أو حدّث قيود `city` في SQL إذا أردت مدناً محددة.

**ما الفرق بين raw_gold وincludes_workmanship؟**
`raw_gold` → سعر غرام الذهب النقي فقط. يُستخدم في الحاسبة.
`includes_workmanship` → سعر الصائغ الذي يشمل أجر الصنعة. يُعرض كمرجع فقط ولا يُستخدم في حساب القيمة الخام.

---

*مشخّص — نتائج تقديرية ولا تمثل سعراً ملزماً من محلات الذهب.*
