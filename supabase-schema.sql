-- ════════════════════════════════════════════════════════════════
--  مشخّص — Supabase Schema
--  نفّذ هذا الملف كاملاً في Supabase SQL Editor مرة واحدة فقط.
-- ════════════════════════════════════════════════════════════════


-- ────────────────────────────────────────────────────────────────
-- 1. جدول profiles
--    يُنشأ تلقائياً لكل مستخدم Auth جديد عبر Trigger.
--    role = 'user' افتراضياً؛ يمكن تغييره يدوياً إلى 'admin'.
-- ────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.profiles (
  id          UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role        TEXT        NOT NULL DEFAULT 'user'
                          CHECK (role IN ('user','admin')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.profiles       IS 'بيانات المستخدمين ودورهم في النظام';
COMMENT ON COLUMN public.profiles.role  IS 'user = قراءة فقط؛ admin = كامل الصلاحيات';


-- ── Trigger: إنشاء profile تلقائياً عند تسجيل مستخدم Auth ── --

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, role)
  VALUES (NEW.id, 'user')
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- ────────────────────────────────────────────────────────────────
-- 2. جدول market_prices
--    السجل الحي لأسعار السوق — يقرأه التطبيق مباشرة.
-- ────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.market_prices (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),

  city                TEXT        NOT NULL,
  karat               INTEGER     NOT NULL
                                  CHECK (karat IN (6,8,9,10,12,14,18,20,21,22,24)),

  -- منشأ الذهب
  origin              TEXT        NOT NULL DEFAULT 'general'
                                  CHECK (origin IN ('iraqi','gulf','turkish','general')),

  -- نوع السوق
  market_type         TEXT        NOT NULL DEFAULT 'retail'
                                  CHECK (market_type IN ('retail','wholesale','buyback')),

  -- هل السعر يشمل المصنعية أم لا؟
  -- raw_gold → يُستخدم مباشرة في حاسبة التقييم
  -- includes_workmanship → مرجعي فقط، لا يُستخدم كـ rawPricePerGram
  price_basis         TEXT        NOT NULL DEFAULT 'raw_gold'
                                  CHECK (price_basis IN ('raw_gold','includes_workmanship')),

  -- وحدة الإدخال المُستخدمة عند الإضافة (للعرض فقط)
  unit                TEXT        NOT NULL DEFAULT 'gram'
                                  CHECK (unit IN ('gram','mithqal')),

  -- السعر كما أُدخل
  price_iqd           NUMERIC(14,2) NOT NULL CHECK (price_iqd > 0),

  -- السعر الموحّد لغرام واحد من العيار المحدد
  -- إذا unit = mithqal  →  price_per_gram_iqd = price_iqd / 5
  -- إذا unit = gram     →  price_per_gram_iqd = price_iqd
  price_per_gram_iqd  NUMERIC(14,2) NOT NULL CHECK (price_per_gram_iqd > 0),

  -- مستوى الثقة وعدد المصادر
  confidence_level    TEXT        NOT NULL DEFAULT 'medium'
                                  CHECK (confidence_level IN ('low','medium','high')),
  source_count        INTEGER     NOT NULL DEFAULT 1 CHECK (source_count >= 1),

  -- هل تم التحقق من هذا السعر؟ الأسعار غير المعتمدة لا تظهر للمستخدم العام.
  is_verified         BOOLEAN     NOT NULL DEFAULT FALSE,

  -- توقيتات
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- من أضاف السعر (اختياري للتدقيق)
  created_by          UUID        REFERENCES auth.users(id) ON DELETE SET NULL
);

COMMENT ON TABLE  public.market_prices                  IS 'أسعار الذهب الحية حسب المدينة والعيار والمنشأ';
COMMENT ON COLUMN public.market_prices.price_basis      IS 'raw_gold = خام للحاسبة؛ includes_workmanship = مرجعي فقط';
COMMENT ON COLUMN public.market_prices.price_per_gram_iqd IS 'السعر الموحّد لكل غرام — القيمة المُستخدمة في الحسابات';
COMMENT ON COLUMN public.market_prices.is_verified      IS 'true = مرئي للعموم عبر RLS';


-- ── فهارس للاستعلامات الشائعة ── --

CREATE INDEX IF NOT EXISTS idx_mp_city_karat_origin
  ON public.market_prices (city, karat, origin);

CREATE INDEX IF NOT EXISTS idx_mp_verified
  ON public.market_prices (is_verified);

CREATE INDEX IF NOT EXISTS idx_mp_updated_at
  ON public.market_prices (updated_at DESC);


-- ────────────────────────────────────────────────────────────────
-- 3. جدول market_price_history
--    سجل غير قابل للحذف يُسجّل كل تعديل على market_prices.
-- ────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.market_price_history (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  market_price_id     UUID        REFERENCES public.market_prices(id) ON DELETE SET NULL,

  city                TEXT        NOT NULL,
  karat               INTEGER     NOT NULL,
  origin              TEXT        NOT NULL,
  market_type         TEXT        NOT NULL,
  price_basis         TEXT        NOT NULL,
  price_per_gram_iqd  NUMERIC(14,2) NOT NULL,

  -- من عدّل ومتى
  changed_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  changed_by          UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  note                TEXT
);

COMMENT ON TABLE public.market_price_history IS 'سجل تاريخي لكل تعديل على أسعار السوق — لا يُحذف';

CREATE INDEX IF NOT EXISTS idx_mph_price_id
  ON public.market_price_history (market_price_id);

CREATE INDEX IF NOT EXISTS idx_mph_changed_at
  ON public.market_price_history (changed_at DESC);


-- ── Trigger: تسجيل التغيير تلقائياً عند تعديل سعر ── --

CREATE OR REPLACE FUNCTION public.log_price_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- سجّل فقط إذا تغيّر السعر الفعلي
  IF OLD.price_per_gram_iqd IS DISTINCT FROM NEW.price_per_gram_iqd
     OR OLD.is_verified IS DISTINCT FROM NEW.is_verified
  THEN
    INSERT INTO public.market_price_history (
      market_price_id,
      city, karat, origin, market_type, price_basis,
      price_per_gram_iqd,
      changed_by
    ) VALUES (
      NEW.id,
      NEW.city, NEW.karat, NEW.origin, NEW.market_type, NEW.price_basis,
      NEW.price_per_gram_iqd,
      auth.uid()
    );
  END IF;

  -- تحديث updated_at تلقائياً
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_price_updated ON public.market_prices;

CREATE TRIGGER on_price_updated
  BEFORE UPDATE ON public.market_prices
  FOR EACH ROW
  EXECUTE FUNCTION public.log_price_change();


-- ── Trigger: تسجيل الإنشاء الأول في التاريخ أيضاً ── --

CREATE OR REPLACE FUNCTION public.log_price_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.market_price_history (
    market_price_id,
    city, karat, origin, market_type, price_basis,
    price_per_gram_iqd,
    changed_by,
    note
  ) VALUES (
    NEW.id,
    NEW.city, NEW.karat, NEW.origin, NEW.market_type, NEW.price_basis,
    NEW.price_per_gram_iqd,
    auth.uid(),
    'إضافة جديدة'
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_price_inserted ON public.market_prices;

CREATE TRIGGER on_price_inserted
  AFTER INSERT ON public.market_prices
  FOR EACH ROW
  EXECUTE FUNCTION public.log_price_insert();


-- ════════════════════════════════════════════════════════════════
-- 4. Row Level Security (RLS)
-- ════════════════════════════════════════════════════════════════

-- ── تفعيل RLS على الجداول ── --

ALTER TABLE public.profiles           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.market_prices      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.market_price_history ENABLE ROW LEVEL SECURITY;


-- ══════════════
-- profiles
-- ══════════════

-- المستخدم يرى صفحته الخاصة فقط
DROP POLICY IF EXISTS "profiles: read own" ON public.profiles;
CREATE POLICY "profiles: read own"
  ON public.profiles
  FOR SELECT
  USING (auth.uid() = id);

-- المشرف يرى جميع الملفات الشخصية
DROP POLICY IF EXISTS "profiles: admin read all" ON public.profiles;
CREATE POLICY "profiles: admin read all"
  ON public.profiles
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.role = 'admin'
    )
  );

-- المشرف يعدّل الأدوار
DROP POLICY IF EXISTS "profiles: admin update" ON public.profiles;
CREATE POLICY "profiles: admin update"
  ON public.profiles
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.role = 'admin'
    )
  );


-- ══════════════
-- market_prices
-- ══════════════

-- القراءة العامة: فقط الأسعار المعتمدة — لا تتطلب تسجيل دخول
DROP POLICY IF EXISTS "market_prices: public read verified" ON public.market_prices;
CREATE POLICY "market_prices: public read verified"
  ON public.market_prices
  FOR SELECT
  USING (is_verified = TRUE);

-- المشرف يقرأ كل شيء بما فيها غير المعتمدة
DROP POLICY IF EXISTS "market_prices: admin read all" ON public.market_prices;
CREATE POLICY "market_prices: admin read all"
  ON public.market_prices
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.role = 'admin'
    )
  );

-- المشرف فقط يُضيف أسعاراً جديدة
DROP POLICY IF EXISTS "market_prices: admin insert" ON public.market_prices;
CREATE POLICY "market_prices: admin insert"
  ON public.market_prices
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.role = 'admin'
    )
  );

-- المشرف فقط يعدّل الأسعار
DROP POLICY IF EXISTS "market_prices: admin update" ON public.market_prices;
CREATE POLICY "market_prices: admin update"
  ON public.market_prices
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.role = 'admin'
    )
  );

-- المشرف فقط يحذف الأسعار
DROP POLICY IF EXISTS "market_prices: admin delete" ON public.market_prices;
CREATE POLICY "market_prices: admin delete"
  ON public.market_prices
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.role = 'admin'
    )
  );


-- ══════════════════════
-- market_price_history
-- ══════════════════════

-- القراءة العامة: مسموح لمن سجّل دخوله (أو المشرف)
DROP POLICY IF EXISTS "history: authenticated read" ON public.market_price_history;
CREATE POLICY "history: authenticated read"
  ON public.market_price_history
  FOR SELECT
  USING (auth.role() = 'authenticated');

-- لا يُسمح بالحذف أو التعديل على السجل التاريخي — التعديل يتم فقط عبر Trigger
-- (لم نضع policy للـ INSERT/UPDATE/DELETE — الـ Trigger يعمل بـ SECURITY DEFINER)


-- ════════════════════════════════════════════════════════════════
-- 5. تفعيل Realtime للجدول الرئيسي
-- ════════════════════════════════════════════════════════════════

-- يتيح لـ index.html الاشتراك في تحديثات فورية عبر Supabase Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.market_prices;


-- ════════════════════════════════════════════════════════════════
-- 6. بيانات اختبار أولية (افتراضية — احذفها لاحقاً أو حافظ عليها)
-- ════════════════════════════════════════════════════════════════

-- ملاحظة: هذه البيانات تحتاج مستخدم admin مُعيَّن لـ created_by.
-- يمكن تشغيلها بعد إنشاء أول مستخدم admin واستبدال UUID بمعرفه.
-- مؤقتاً نتركها بـ NULL لتتمكن من التشغيل الفوري.

INSERT INTO public.market_prices
  (city, karat, origin, market_type, price_basis, unit, price_iqd, price_per_gram_iqd, confidence_level, source_count, is_verified)
VALUES
  ('البصرة', 21, 'iraqi',   'retail', 'raw_gold', 'gram', 95000, 95000, 'medium', 2, TRUE),
  ('البصرة', 21, 'gulf',    'retail', 'raw_gold', 'gram', 97000, 97000, 'medium', 1, TRUE),
  ('بغداد',  21, 'general', 'retail', 'raw_gold', 'gram', 96000, 96000, 'medium', 3, TRUE),
  ('أربيل',  21, 'general', 'retail', 'raw_gold', 'gram', 96500, 96500, 'low',    1, FALSE)
ON CONFLICT DO NOTHING;


-- ════════════════════════════════════════════════════════════════
-- ✅ انتهى — راجع README.md لخطوات إنشاء أول مستخدم admin
-- ════════════════════════════════════════════════════════════════
