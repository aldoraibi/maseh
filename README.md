# الماسح — Maseh

تطبيق ماك صغير في شريط القوائم للمسح الضوئي والطباعة من طابعات **Canon PIXMA G-series**، عربي بالكامل من اليمين لليسار.

> **المشكلة:** طابعات Canon PIXMA G-series لا تدعم بروتوكول المسح القياسي `eSCL/AirScan`، وكانون لا توفّر تعريف ماسح ضوئي لنظام macOS. النتيجة أن الماسح لا يظهر إطلاقاً في «التقاط الصور» — الطابعة تطبع فقط.
>
> **الحل:** هذا التطبيق يستخدم [pixma-rs](https://github.com/pdrgds/pixma-rs) الذي فكّ بروتوكول كانون الخاص `CHMP` بالهندسة العكسية، ويضيف فوقه واجهة عربية كاملة.

![لقطة من التطبيق](docs/screenshot.png)

---

## المزايا

**المسح الضوئي**

- مسح متعدد الصفحات يُجمع في ملف PDF واحد
- معاينة كل صفحة قبل الحفظ، مع تدوير أو حذف أي صفحة
- **PDF قابل للبحث** — استخراج النص العربي عبر محرك التعرّف الضوئي المدمج في macOS
- نافذة حفظ ماك المعتادة: تختار المجلد والاسم بنفسك
- دقة 150 / 300 / 600 نقطة، ملوّن أو تدرّج رمادي

**الطباعة**

- **تصوير مستندات**: مسح ← طباعة مباشرة، فتصير الطابعة آلة تصوير
- طباعة أي ملف PDF أو صورة (شامل HEIC)
- **سحب وإفلات**: اسحب ملفاً أو صورة (أو عدة ملفات) وأفلته على لوحة التطبيق ليُطبع مباشرة
- طباعة الصور من **مكتبة صور macOS** مباشرة داخل التطبيق
- **قوالب تقسيم الصفحة**: صورة، صورتان، ٤، ٦، ٩ صور في الصفحة
- **ورقة صور شخصية**: ٤×٦ سم أو ٣٥×٤٥ مم مع خطوط قص — تكرّر صورة واحدة لملء الورقة
- **خيارات الطابعة الكاملة** مقروءة من ملف تعريفها: نوع الورق، الجودة، المقاس، بلا حدود، أبيض وأسود
- **متابعة الطباعة**: طابور مباشر يعرض المهمة قيد الطباعة وما ينتظر، مع إمكانية الإلغاء
- **اكتشاف تلقائي للطابعة**: عند فتح التطبيق يبحث عبر Bonjour عن الطابعة المتصلة على الشبكة الحالية ويختارها تلقائياً — مفيد إذا كانت لديك الطابعة نفسها في أكثر من مكان أو شبكة، مع زر «بحث عن الطابعات المتصلة» للبحث اليدوي في أي وقت
- تعمل الطباعة مع **أي طابعة مضافة في الماك**، ليست محصورة بكانون

---

## الطابعات المدعومة

| الطابعة | الحالة |
|---|---|
| Canon PIXMA G3010 | مختبرة ✅ |
| Canon PIXMA G2010 / G2020 / G3020 / G4010 | غالباً تعمل (نفس بروتوكول CHMP) — غير مختبرة |
| بقية سلسلة Canon PIXMA G | محتملة |
| طابعات كانون التي تدعم eSCL | لا تحتاج هذا التطبيق — macOS يراها أصلاً |
| العلامات الأخرى | المسح لا يعمل، أما **الطباعة فتعمل مع أي طابعة** |

المتطلب التقني: أن تُعلن الطابعة خدمة `_ipp._tcp` مع الخاصية `Scan=T`، وأن تتكلم `CHMP` على المنفذ 80.

---

## التركيب

**جاهز للاستخدام**

1. نزّل `Maseh.zip` من صفحة [الإصدارات](../../releases)
2. فكّ الضغط وانقل **الماسح.app** إلى مجلد التطبيقات
3. أول تشغيل: اضغط بزر الفأرة الأيمن على التطبيق ← **فتح** ← **فتح**
   (التطبيق غير موقّع من Apple، وهذه الخطوة تُفعل مرة واحدة فقط)
4. اسمح بإذن **الشبكة المحلية** حين يطلبه — بدونه لن يصل للطابعة
5. تظهر أيقونة الماسح في شريط القوائم

**البناء من المصدر**

```bash
git clone https://github.com/aldoraibi/maseh.git
cd maseh
./build.sh
```

يحتاج: macOS 14 فأحدث، أدوات Xcode، و[Rust](https://rustup.rs) لبناء محرك المسح.

السكربت يجلب `pixma-rs` ويبنيه، ثم يبني التطبيق ويضعه في `~/Applications`.

---

## الأذونات المطلوبة

| الإذن | السبب |
|---|---|
| الشبكة المحلية | الاتصال بالطابعة — **إلزامي** |
| مكتبة الصور | فقط عند استخدام «طباعة صور» |

التطبيق لا يتصل بالإنترنت إطلاقاً ولا يرسل أي بيانات لأي جهة. كل شيء يحدث على جهازك وشبكتك المحلية.

---

## الشكر والمصادر

- **[pixma-rs](https://github.com/pdrgds/pixma-rs)** بواسطة [@pdrgds](https://github.com/pdrgds) — الهندسة العكسية لبروتوكول `CHMP` ومحرك المسح. هذا هو الجزء الصعب، وبدونه لا وجود لهذا المشروع. رخصة MIT / Apache-2.0
- التعرّف الضوئي على النصوص عبر إطار **Vision** من Apple
- خط الواجهة: [ثمانية](https://thmanyah.com)

---

## الرخصة

MIT — انظر [LICENSE](LICENSE)

---

<div dir="ltr">

## English

**Maseh** is a small Arabic-first macOS menu bar app for scanning and printing with **Canon PIXMA G-series** printers.

Canon PIXMA G-series printers don't speak `eSCL/AirScan`, and Canon ships no macOS scanner driver — so the scanner never appears in Image Capture. Maseh builds on [pixma-rs](https://github.com/pdrgds/pixma-rs), which reverse-engineered Canon's proprietary `CHMP` protocol, and adds a full Arabic UI on top.

**Features:** multi-page PDF scanning, searchable PDFs via Arabic OCR (Apple Vision), native save panel, scan-to-print photocopying, printing any PDF or image, printing straight from the macOS Photos library, N-up photo layouts and ID-photo sheets, full printer options read from the PPD, and a live print queue.

**Tested on:** Canon PIXMA G3010. Likely compatible with other PIXMA G models. Printing works with any printer configured in macOS.

**Install:** download `Maseh.zip` from Releases, move the app to Applications, right-click and Open on first launch, then allow Local Network access.

**Build:** run `./build.sh` — requires macOS 14+, Xcode command line tools, and Rust.

MIT licensed. Credit to [@pdrgds](https://github.com/pdrgds) for pixma-rs.

</div>
