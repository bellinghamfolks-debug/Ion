# عقد الخادم الاختياري

عنوان الخادم يحدده المستخدم. المحتوى الأساسي لا يحتاج خادمًا. يجب استخدام HTTPS، ولا توضع مفاتيح مزودي الذكاء الاصطناعي داخل تطبيق iOS.

## POST /v1/tutor/message

Request:

```json
{
  "sessionId": "uuid",
  "locale": "ar",
  "level": "A1",
  "message": "I go school yesterday",
  "context": "past simple practice"
}
```

Response:

```json
{
  "reply": "الصحيح: I went to school yesterday.",
  "corrections": [
    {"original":"go","replacement":"went","reason":"الفعل في الماضي"}
  ],
  "suggestedReplies": ["I went by bus."]
}
```

## POST /v1/coach/conversation

يرسل التطبيق النص المفرغ، لا ملف الصوت الخام.

Request:

```json
{
  "sessionID": "voice-job-interview",
  "scenarioID": "job-interview",
  "level": "B1",
  "accent": "american",
  "prompt": "Tell me about yourself.",
  "learnerTranscript": "I graduated in law and I worked on governance projects.",
  "localScore": 0.78,
  "previousTurns": []
}
```

Response:

```json
{
  "reply": "That is a strong start. What kind of governance project did you work on?",
  "translationAr": "هذه بداية قوية. ما نوع مشروع الحوكمة الذي عملت عليه؟",
  "feedbackAr": "الإجابة مرتبطة بالسؤال. أضف نتيجة عملية واحدة.",
  "suggestedAnswer": null,
  "source": "remote"
}
```

متطلبات الخادم:

- تحديد حد أقصى لطول النص والسجل.
- عدم إعادة تعليمات نظام أو أسرار في الاستجابة.
- عدم الاحتفاظ بالنصوص إلا وفق سياسة معلنة.
- إرجاع UTF-8 وJSON صالح.
- مهلة مناسبة، لأن التطبيق يملك بديلًا محليًا عند الفشل.

## POST /v1/pronunciation/analyze

نقطة مستقبلية اختيارية لتحليل فونيمات متخصص. رفع الصوت يجب أن يكون خيارًا منفصلًا وصريحًا، مع بيان مدة الاحتفاظ وطريقة الحذف. النسخة 0.3.0 لا تستخدم هذه النقطة تلقائيًا.

## GET /v1/content/manifest

يعيد:

- `version`
- `minimumAppVersion`
- `publishedAt`
- `notesAr`
- `curriculumURL`
- `sha256`

يجب أن يشير `curriculumURL` إلى HTTPS، ويطابق الملف بصمة SHA-256 قبل التثبيت.

## GET /v1/audio-packs/index

Response:

```json
{
  "version": 1,
  "packs": [
    {
      "id": "a1-human-voice-v1",
      "titleAr": "الصوت البشري للمستوى A1",
      "titleEn": "A1 Human Voice",
      "level": "A1",
      "voiceName": "Studio Voice 1",
      "approximateBytes": 42000000,
      "version": 1,
      "clips": [
        {
          "id": "a1-u1-l1-e2",
          "text": "Hello, my name is Sara.",
          "relativePath": "a1/u1/l1/e2.m4a",
          "remoteURL": "https://cdn.example.com/audio/a1/u1/l1/e2.m4a",
          "sha256": "lowercase-hex-sha256"
        }
      ]
    }
  ]
}
```

قواعد الحزم:

- كل رابط ملف HTTPS.
- `relativePath` لا يبدأ بشرطة مائلة ولا يحتوي `..`.
- يفضّل توفير SHA-256 لكل مقطع.
- الملفات صغيرة ومستقلة حتى يمكن استئناف الحزمة دون إعادة تنزيلها كاملة.
- يظل صوت النظام المحلي بديلًا عند عدم وجود الملف.
