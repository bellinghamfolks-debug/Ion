# مصفوفة إثبات متطلبات بصير 4.4.0

هذه الوثيقة تربط كل تحسين كان مفقودًا من 4.3 بموضع تنفيذه واختبار يمنع فقده لاحقًا.

| رقم | المطلب المتفق عليه | التنفيذ | دليل الاختبار |
|---:|---|---|---|
| 1 | مستوى تفكير مستقل لكل مهمة | `AITaskPolicy.thinkingLevel` وإرساله في `GeminiClient` و`ProxyAiProvider` | `testAllTaskPolicySignaturesMatchV44Contract` و`testDirectGenerationConfigCarriesPolicyControls` والفحص المحمول |
| 2 | حرارة مستقلة لكل مهمة | `AITaskPolicy.temperature` وإرسالها في المسارين | الاختباران السابقان و`testProxyContractMatchesDirectPolicyAndSeparatesUntrustedInput` |
| 3 | ميزانية إخراج مستقلة | `maxOutputTokens` لكل واحدة من 23 مهمة | `testAllTaskPolicySignaturesMatchV44Contract` و`testEveryTaskHasACompleteBoundedPolicy` |
| 4 | مهلة ومحاولات مستقلة | `timeoutSeconds` و`attemptsPerModel` | اختبار التوقيعات، واختبار قرارات الإعادة والفشل النهائي |
| 5 | محرك سياسات حقيقي لـ23 مهمة | `TaskKind` و`AITaskPolicyCatalog` | `testCatalogContainsExactlyTwentyThreeDistinctTasks` واختبار التوقيعات الكامل |
| 6 | حدود عشوائية للبيانات غير الموثوقة | `GeminiPrompts.userMessage` باستخدام UUID | `testRandomDataBoundariesDifferAndNeverEnterSystemPrompt` |
| 7 | محاولة إصلاح عامة وآمنة | `repairEnabled` و`QUALITY REPAIR PASS` و`boundedFailureReason` | `testRepairPromptContainsBoundedReasonButNotRejectedCandidate` و`testRetryDecisionDistinguishesTransientAndTerminalFailures` |
| 8 | مراقبة جودة شاملة | `AIResponseValidator` للتكرار والمقدمات والقيم والسلامة وJSON | `testStructuredTaskSchemasExistAndAreSemanticallyChecked` واختبارات القيم والجدول والوصف المباشر |
| 9 | قياسات محلية بلا محتوى خاص | `AIEngineMetricsStore` وشرط `privacyMode` | `testMetricEncodingContainsNoPromptOrUserContentFields` وقواعد `verify_project.py` |
| 10 | قراءة الاستهلاك والنموذج المنفذ | `extractGenerationResult` وقراءة `usageMetadata` و`modelVersion` | `testUsageAndExecutedModelAreParsed` والفحص المحمول |
| 11 | تكافؤ Direct وProxy | عقد v5، نفس السياسات والمخططات والتحقق | `testProxyContractMatchesDirectPolicyAndSeparatesUntrustedInput` والفحص المحمول |
| 12 | مخرجات منظمة حديثة | `generationConfig.responseFormat.text` | `testStructuredConfigUsesCurrentResponseFormat` و`testDirectGenerationConfigCarriesPolicyControls` |
| 13 | مخططات محدودة تمنع التضخم | `AIResponseSchemas` مع `minItems` و`maxItems` و`additionalProperties` | فحوص المخططات والتحقق الدلالي واختبار الجدول غير المستطيل |
| 14 | حماية الأرقام والروابط والمعرفات | `criticalTokens` وشرط الاستدعاء 90% | `testCriticalIdentifiersMustSurviveTranslation` والفحص المحمول |
| 15 | منع حقن الأوامر من المستند | قناة نظام منفصلة وحدود بيانات عشوائية | اختبارات الحدود، عقد Proxy، وتعليمة صفحة المستند |
| 16 | عدم إعادة المرشح المرفوض | سبب إصلاح مختصر مصنف فقط | `testRepairPromptContainsBoundedReasonButNotRejectedCandidate` و`testFailureCategoriesNeverEchoProviderOrDocumentContent` |
| 17 | التحقق من الجداول لقارئ الشاشة | تحقق مستطيل ثم إخراج «العمود: القيمة» | `testStructuredTableIsRenderedForScreenReader` والفحص المحمول |
| 18 | سلامة المشي والوصف المباشر | `visualSafety` ومخططات ثابتة ورفض أوامر الحركة | اختبارات `liveScene` و`walkingSnapshot` |
| 19 | طب وقانون بلا قرارات مولدة | أوامر موثوقة وفحص نصائح عالية الخطورة | اختبار السياسات الحساسة واختبار JSON الطبي/القانوني |
| 20 | تحويل Word لا يحذف الصفحات بسبب نموذج | سياسة تحويل مستقلة ومخطط صفحة وفحص دلالي | الفحص المحمول لصفحة المستند واختبارات بنية DOCX |

## بوابة منع الانحدار

لا تُعتمد النسخة إذا فشل أي مما يلي:

1. `python3 scripts/run_portable_core_checks.py`
2. `python3 scripts/verify_project.py`
3. تحليل جميع ملفات Swift.
4. اختبارات XCTest في Xcode أو CI.
5. إنشاء DOCX وفتح حزمة OOXML وفحص الجداول والقوائم والروابط والاتجاه.

وجود الميزة في تقرير أو تعليق لا يكفي؛ يجب أن يكون لها تنفيذ واختبار ظاهر في هذا الجدول.
