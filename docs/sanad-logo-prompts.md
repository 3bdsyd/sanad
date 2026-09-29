# سند — أوامر توليد اللوغو

Mode الأصلي: built-in `image_gen` (مهارة imagegen)، وليس CLI/API. تاريخ التنفيذ: 2026-09-25.

النسخة النهائية المعتمدة: [sanad-logo.png](../assets/images/sanad-logo.png)، وهي علامة شفافة لشخصين يعبّران عن السند والمساندة. نسخة الإطلاق عالية التباين [sanad-logo-contrast.png](../assets/images/sanad-logo-contrast.png) مشتقة حتميًا من حدودها نفسها، وليست توليدًا جديدًا: خلفية `#20508A` وعلامة بين `#F2F7FC` و`#9CC9FA`. وضع أيقونات iOS الداكن يستخدم أبيض نقيًا على أسود حتى لا يجمع تحويل النظام اللونين في درجة رمادية واحدة. أيقونات الأفعال متجهة مولّدة بالكود من [الكتالوج](../assets/icons/fursa-symbols.json)، وليست قصاصات نقطية من اللوغو.

مواصفة تعديل التباين المنفذة محليًا، دون استدعاء نموذج صور:

```text
Preserve the approved two-person support silhouette exactly. Change only the launcher and splash packaging: use a full-bleed deep Sanad blue #20508A canvas and lift every opaque mark pixel into the pale #F2F7FC to sky #9CC9FA range. Keep smooth antialiased edges, no text, no new objects, no shadow, no texture, and no change to the transparent master used inside the app. For the iOS luminosity-dark rendition, use the identical silhouette in pure white on pure black for maximum post-treatment contrast.
```

## استكشاف سابق غير مستخدم

```text
Use case: logo-brand.
Asset type: production app logo and square launcher artwork for "سند", a Syrian Arabic job opportunities app about people supporting each other's next step.
Create one beautifully resolved, original premium logo, not a presentation sheet. Full square 1024 by 1024 canvas, solid deep blue #20508A background extending to every edge. Center a large perfectly legible Arabic wordmark "سند" (letters س ن د, exactly this word, no extra words) in pale blue-white #F2F7FC. Custom bold fluid geometric Arabic lettering, beautifully connected, generous clear counters, simple memorable silhouette. Let a small ascending sky blue #9CC9FA stroke suggest support or a step within the lettering, never interfering with reading the word. Contemporary calm design, exceptionally polished clean smooth flat vector-like edges, confident minimal shapes. The wordmark occupies approximately 68 percent of the square width, optically centered vertically and horizontally. Flat pure colors, no shadows, no texture, no bevel, no gradients, no border, no rounded outer container (the operating system will apply the corners), no mockup, no watermark, no extra decorative objects. It must work as a clear recognizable icon at small sizes.
```

## تعديل سابق غير مستخدم

```text
Edit this Sanad Arabic logo into a clean opaque square app icon. Preserve the exact Arabic lettering "سند" and its lime accent; retain its appealing bold geometric form. Crucial correction: the entire square background MUST be solid opaque deep blue #20508A, no transparency anywhere. Clean up ALL white speckles, messy ragged pixels, smears and thin outlines around the letters; only crisp smooth edges and solid pale blue-white #F2F7FC lettering should remain. No texture, no gradients, no shadow, no gritty distressed effect. Make the word occupy 72% of canvas width, optical center. Sky blue accent #9CC9FA. The output is a flat finished full-bleed square app icon, not a transparent cutout and not a mockup.
```

المقطَعان أعلاه محفوظان كسجل لاستكشاف سابق ولا يصفان علامة الشخصين الحالية. التغليف الحالي للمنصات: `python3 tools/generate_brand_assets.py` يحافظ على silhouette الماستر، يرفع تباينه، يعيد تحجيمه ويقنّع الزوايا حسب المنصة. [نظام الحركة والهوية](sanad-brand-motion.md).
