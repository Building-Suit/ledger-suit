export type LegalLocale = 'en' | 'ar'

export interface LegalSection {
  title: string
  paragraphs?: string[]
  bullets?: string[]
}

export interface LegalDocument {
  title: string
  intro: string
  updated: string
  sections: LegalSection[]
}

export const publicBusiness = {
  brand: 'Ledger Suit by Building Suit',
  supportEmail: 'support@building-suit.com',
  // Approved public customer-support number.
  phone: '+201500240770',
  addressEn: 'Cairo, Egypt',
  addressAr: 'القاهرة، مصر',
} as const

export const legalDocuments: Record<
  'about' | 'privacy' | 'delivery' | 'refund' | 'terms',
  Record<LegalLocale, LegalDocument>
> = {
  about: {
    en: {
      title: 'About Us',
      intro: 'Ledger Suit is a digital accounting and financial-management software service for businesses. Ledger Suit is a product by Building Suit.',
      updated: '14 September 2026',
      sections: [
        {
          title: 'What Ledger Suit does',
          paragraphs: [
            'Ledger Suit provides a secure online workspace for recording business transactions, organizing accounts, monitoring cash flow, managing commitments and recurring activity, collaborating with team members, and generating financial reports.',
            'The service is delivered digitally as software-as-a-service (SaaS). No physical product is supplied.',
          ],
        },
        {
          title: 'Who we serve',
          paragraphs: [
            'Ledger Suit is designed for freelancers, owner-managed businesses, small teams, and growing businesses that need a practical way to organize their financial records and understand business performance.',
          ],
        },
        {
          title: 'Brand and operator',
          paragraphs: [
            'Ledger Suit is a product by Building Suit. Building Suit is the parent brand and merchant name used for the service and its payment processing arrangements.',
          ],
        },
        {
          title: 'Contact',
          paragraphs: [
            `For questions about Ledger Suit, billing, subscriptions, or support, contact ${publicBusiness.supportEmail}.`,
          ],
        },
      ],
    },
    ar: {
      title: 'من نحن',
      intro: 'Ledger Suit هو برنامج رقمي للمحاسبة والإدارة المالية للأعمال، وهو أحد منتجات Building Suit.',
      updated: '14 سبتمبر 2026',
      sections: [
        {
          title: 'ماذا يقدم Ledger Suit؟',
          paragraphs: [
            'يوفر Ledger Suit مساحة عمل إلكترونية آمنة لتسجيل المعاملات المالية، وتنظيم الحسابات، ومتابعة التدفقات النقدية، وإدارة الالتزامات والعمليات المتكررة، والتعاون مع أعضاء الفريق، وإعداد التقارير المالية.',
            'الخدمة رقمية بالكامل بنظام البرمجيات كخدمة (SaaS)، ولا يتم بيع أو شحن أي منتج مادي.',
          ],
        },
        {
          title: 'لمن صُمم Ledger Suit؟',
          paragraphs: [
            'Ledger Suit مناسب للمستقلين وأصحاب الأعمال الصغيرة والفرق الصغيرة والأعمال النامية التي تحتاج إلى طريقة عملية لتنظيم سجلاتها المالية وفهم أداء النشاط.',
          ],
        },
        {
          title: 'العلامة التجارية والجهة المشغلة',
          paragraphs: [
            'Ledger Suit هو منتج تابع لـ Building Suit، وBuilding Suit هي العلامة التجارية الأم واسم التاجر المستخدم في ترتيبات تقديم الخدمة ومعالجة المدفوعات.',
          ],
        },
        {
          title: 'التواصل',
          paragraphs: [
            `للاستفسارات المتعلقة بـ Ledger Suit أو الفواتير أو الاشتراكات أو الدعم، تواصل معنا عبر ${publicBusiness.supportEmail}.`,
          ],
        },
      ],
    },
  },
  privacy: {
    en: {
      title: 'Privacy Policy',
      intro: 'This Privacy Policy explains how Ledger Suit by Building Suit collects, uses, stores, and protects information when you use our website and software service.',
      updated: '14 September 2026',
      sections: [
        {
          title: '1. Information we collect',
          bullets: [
            'Account information, such as your name, email address, phone number, authentication information, and organization details.',
            'Business and financial information that you or authorized members enter into Ledger Suit, including accounts, transactions, counterparties, commitments, recurring rules, reports, attachments, and related records.',
            'Subscription and billing metadata, such as your selected plan, billing interval, payment status, transaction references, and payment-provider identifiers.',
            'Technical and security information needed to operate and protect the service, such as device/browser information, request metadata, logs, and security events.',
            'Support communications and information you provide when you contact us.',
          ],
        },
        {
          title: '2. How we use information',
          bullets: [
            'To create and operate your Ledger Suit account and business workspace.',
            'To provide accounting, reporting, collaboration, subscription, and support functionality.',
            'To process and verify subscription payments and maintain billing records.',
            'To secure the service, prevent abuse, investigate incidents, and maintain auditability.',
            'To improve reliability, usability, and performance.',
            'To comply with applicable legal, regulatory, accounting, and dispute-resolution obligations.',
          ],
        },
        {
          title: '3. Payments',
          paragraphs: [
            'Card payments are processed by Paymob or another payment provider that we clearly identify at checkout. Payment-card details are entered into the payment provider’s payment environment.',
            'Ledger Suit does not store your full card number or card security code (CVV). We may receive and store payment references, transaction status, subscription identifiers, and other non-sensitive billing metadata required to operate your subscription.',
          ],
        },
        {
          title: '4. Service providers',
          paragraphs: [
            'We use trusted service providers to operate Ledger Suit, including infrastructure, database/authentication, email-delivery, monitoring, and payment-processing providers. These providers process information only as needed to provide their services to us and are subject to their own security and privacy obligations.',
            'Where processing takes place outside Egypt, we take reasonable steps to use appropriate contractual, technical, and organizational safeguards as required by applicable law.',
          ],
        },
        {
          title: '5. Data security',
          paragraphs: [
            'We use reasonable technical and organizational measures designed to protect information against unauthorized access, alteration, disclosure, or loss. No internet-based service can guarantee absolute security, so users should also protect their credentials and devices.',
          ],
        },
        {
          title: '6. Data retention',
          paragraphs: [
            'We retain information for as long as needed to provide the service, maintain legitimate business and security records, resolve disputes, and satisfy applicable legal or regulatory requirements. Retention periods may differ by data category.',
          ],
        },
        {
          title: '7. Your choices and rights',
          paragraphs: [
            'Subject to applicable law and the nature of the requested data, you may ask us to access, correct, update, export, restrict, or delete personal information associated with your account. Some information may need to be retained where required for security, billing, accounting, legal, or dispute-resolution purposes.',
            `To make a privacy request, contact ${publicBusiness.supportEmail}.`,
          ],
        },
        {
          title: '8. Children',
          paragraphs: [
            'Ledger Suit is a business software service and is not intended for children.',
          ],
        },
        {
          title: '9. Changes to this policy',
          paragraphs: [
            'We may update this Privacy Policy when our service, providers, or legal requirements change. The latest version will be published on this page with an updated effective date.',
          ],
        },
        {
          title: '10. Contact',
          paragraphs: [
            `${publicBusiness.brand} — ${publicBusiness.addressEn}. Email: ${publicBusiness.supportEmail}.`,
          ],
        },
      ],
    },
    ar: {
      title: 'سياسة الخصوصية',
      intro: 'توضح سياسة الخصوصية هذه كيفية جمع واستخدام وحفظ وحماية المعلومات عند استخدام موقع وخدمة Ledger Suit by Building Suit.',
      updated: '14 سبتمبر 2026',
      sections: [
        {
          title: '1. المعلومات التي نجمعها',
          bullets: [
            'بيانات الحساب مثل الاسم والبريد الإلكتروني ورقم الهاتف وبيانات تسجيل الدخول وبيانات النشاط أو المؤسسة.',
            'البيانات التجارية والمالية التي تدخلها أنت أو أعضاء فريقك المصرح لهم، ومنها الحسابات والمعاملات والأطراف والالتزامات والقواعد المتكررة والتقارير والمرفقات والسجلات المرتبطة بها.',
            'بيانات الاشتراك والفوترة مثل الخطة المختارة ودورة الفوترة وحالة الدفع ومراجع المعاملات ومعرّفات مزود الدفع.',
            'بيانات تقنية وأمنية لازمة لتشغيل الخدمة وحمايتها، مثل بيانات الجهاز والمتصفح وبيانات الطلبات والسجلات والأحداث الأمنية.',
            'المراسلات والمعلومات التي تقدمها عند التواصل مع الدعم.',
          ],
        },
        {
          title: '2. كيفية استخدام المعلومات',
          bullets: [
            'إنشاء وتشغيل حسابك ومساحة العمل الخاصة بنشاطك.',
            'تقديم وظائف المحاسبة والتقارير والتعاون والاشتراكات والدعم.',
            'معالجة مدفوعات الاشتراك والتحقق منها والاحتفاظ بسجلات الفوترة.',
            'حماية الخدمة ومنع إساءة الاستخدام والتحقيق في الحوادث والحفاظ على سجلات المراجعة.',
            'تحسين الاعتمادية وسهولة الاستخدام والأداء.',
            'الالتزام بالمتطلبات القانونية والتنظيمية والمحاسبية وتسوية المنازعات عند انطباقها.',
          ],
        },
        {
          title: '3. المدفوعات',
          paragraphs: [
            'تتم معالجة مدفوعات البطاقات من خلال Paymob أو أي مزود دفع آخر يتم توضيحه في صفحة الدفع. يتم إدخال بيانات البطاقة داخل بيئة الدفع التابعة لمزود الدفع.',
            'لا يخزن Ledger Suit رقم البطاقة الكامل أو رمز الأمان (CVV). وقد نحتفظ بمراجع الدفع وحالة المعاملة ومعرّفات الاشتراك وغيرها من بيانات الفوترة غير الحساسة اللازمة لتشغيل الاشتراك.',
          ],
        },
        {
          title: '4. مزودو الخدمة',
          paragraphs: [
            'نستخدم مزودي خدمات موثوقين لتشغيل Ledger Suit، بما في ذلك خدمات البنية التحتية وقواعد البيانات وتسجيل الدخول وإرسال البريد الإلكتروني والمراقبة ومعالجة المدفوعات. ويقوم هؤلاء المزودون بمعالجة المعلومات بالقدر اللازم لتقديم خدماتهم.',
            'إذا تمت معالجة بيانات خارج مصر، نتخذ إجراءات معقولة لاستخدام الضمانات التعاقدية والتقنية والتنظيمية المناسبة وفقاً للقانون المعمول به.',
          ],
        },
        {
          title: '5. أمن البيانات',
          paragraphs: [
            'نستخدم إجراءات تقنية وتنظيمية معقولة تهدف إلى حماية المعلومات من الوصول أو التعديل أو الإفصاح أو الفقد غير المصرح به. ولا يمكن لأي خدمة عبر الإنترنت ضمان الأمان المطلق، لذلك يجب على المستخدم أيضاً حماية بيانات تسجيل الدخول وأجهزته.',
          ],
        },
        {
          title: '6. مدة الاحتفاظ بالبيانات',
          paragraphs: [
            'نحتفظ بالمعلومات طوال المدة اللازمة لتقديم الخدمة والاحتفاظ بالسجلات التجارية والأمنية المشروعة وحل النزاعات والوفاء بالمتطلبات القانونية أو التنظيمية المطبقة. وقد تختلف مدة الاحتفاظ حسب نوع البيانات.',
          ],
        },
        {
          title: '7. اختياراتك وحقوقك',
          paragraphs: [
            'وفقاً للقانون المعمول به وطبيعة البيانات المطلوبة، يمكنك طلب الوصول إلى بياناتك الشخصية أو تصحيحها أو تحديثها أو تصديرها أو تقييد استخدامها أو حذفها. وقد يلزم الاحتفاظ ببعض البيانات لأسباب أمنية أو متعلقة بالفوترة أو المحاسبة أو الالتزامات القانونية أو النزاعات.',
            `لطلب أي إجراء متعلق بالخصوصية، تواصل معنا عبر ${publicBusiness.supportEmail}.`,
          ],
        },
        {
          title: '8. الأطفال',
          paragraphs: [
            'Ledger Suit خدمة برمجية مخصصة للأعمال وليست موجهة للأطفال.',
          ],
        },
        {
          title: '9. تحديثات السياسة',
          paragraphs: [
            'قد نقوم بتحديث سياسة الخصوصية عند تغير الخدمة أو مزوديها أو المتطلبات القانونية. وسيتم نشر أحدث نسخة في هذه الصفحة مع تاريخ آخر تحديث.',
          ],
        },
        {
          title: '10. التواصل',
          paragraphs: [
            `${publicBusiness.brand} — ${publicBusiness.addressAr}. البريد الإلكتروني: ${publicBusiness.supportEmail}.`,
          ],
        },
      ],
    },
  },
  delivery: {
    en: {
      title: 'Delivery & Shipping Policy',
      intro: 'Ledger Suit is a digital software-as-a-service product. We do not sell or ship physical goods.',
      updated: '14 September 2026',
      sections: [
        {
          title: 'Digital delivery',
          paragraphs: [
            'Ledger Suit is delivered electronically through your online account and business workspace. There is no courier, physical shipment, or shipping fee.',
          ],
        },
        {
          title: 'When access is provided',
          paragraphs: [
            'New users may receive access to a free trial according to the plan and offer displayed on the website.',
            'For paid subscriptions, paid-plan access is normally activated after the payment provider confirms a successful payment and our systems successfully process that confirmation.',
          ],
        },
        {
          title: 'Delivery delays',
          paragraphs: [
            'In most cases activation is automatic. A delay may occur because of payment-provider processing, security checks, service interruption, or a technical error. If payment was successfully charged but your paid access is not available, contact support and include the account email and payment reference if available.',
          ],
        },
        {
          title: 'Geographic delivery',
          paragraphs: [
            'Because Ledger Suit is a digital service, there is no physical delivery location. Access is provided online, subject to account eligibility, service availability, and applicable law.',
          ],
        },
        {
          title: 'Support',
          paragraphs: [
            `For delivery or activation issues, contact ${publicBusiness.supportEmail}.`,
          ],
        },
      ],
    },
    ar: {
      title: 'سياسة التسليم والشحن',
      intro: 'Ledger Suit منتج برمجي رقمي بنظام البرمجيات كخدمة (SaaS)، ولا نقوم ببيع أو شحن منتجات مادية.',
      updated: '14 سبتمبر 2026',
      sections: [
        {
          title: 'التسليم الرقمي',
          paragraphs: [
            'يتم تقديم Ledger Suit إلكترونيًا من خلال حسابك ومساحة العمل الخاصة بنشاطك. ولا يوجد شحن مادي أو شركة توصيل أو رسوم شحن.',
          ],
        },
        {
          title: 'موعد تفعيل الوصول',
          paragraphs: [
            'قد يحصل المستخدم الجديد على فترة تجريبية مجانية وفقًا للخطة أو العرض الموضح على الموقع.',
            'بالنسبة إلى الاشتراكات المدفوعة، تُفعّل مزايا الخطة المدفوعة عادةً بعد تأكيد مزود الدفع نجاح العملية ومعالجة أنظمتنا لهذا التأكيد.',
          ],
        },
        {
          title: 'تأخر التفعيل',
          paragraphs: [
            'يتم التفعيل تلقائيًا في معظم الحالات. وقد يحدث تأخير بسبب معالجة مزود الدفع أو إجراءات الأمان أو توقف مؤقت للخدمة أو خطأ تقني. إذا تم خصم المبلغ بنجاح ولم تُفعّل الخطة المدفوعة، فتواصل مع الدعم وأرفق البريد الإلكتروني للحساب ومرجع الدفع إن كان متاحًا.',
          ],
        },
        {
          title: 'نطاق تقديم الخدمة',
          paragraphs: [
            'لأن Ledger Suit خدمة رقمية، فلا يوجد عنوان للتسليم المادي. ويتوفر الوصول عبر الإنترنت وفقًا لأهلية الحساب وتوفر الخدمة والقانون المعمول به.',
          ],
        },
        {
          title: 'الدعم',
          paragraphs: [
            `في حالة وجود مشكلة في التسليم الرقمي أو التفعيل، تواصل معنا عبر ${publicBusiness.supportEmail}.`,
          ],
        },
      ],
    },
  },
  terms: {
    en: {
      title: 'Terms & Conditions',
      intro: 'These Terms & Conditions govern your access to and use of Ledger Suit, a digital accounting and financial-management software-as-a-service product by Building Suit.',
      updated: '14 September 2026',
      sections: [
        {
          title: '1. The service',
          paragraphs: [
            'Ledger Suit provides online tools for recording business transactions, organizing accounts, managing financial workflows, collaborating with team members, and generating reports. The service is delivered digitally through your account and workspace; no physical product is supplied.',
            'Ledger Suit is a product by Building Suit. Building Suit is the parent brand and merchant identity used for the service and its payment-processing arrangements.',
          ],
        },
        {
          title: '2. Accounts and authorized use',
          paragraphs: [
            'You must provide accurate account information, keep your login credentials secure, and promptly update information that changes. You are responsible for activity performed through your account unless you have notified us of suspected unauthorized access.',
            'Workspace owners and administrators are responsible for granting appropriate access to their team members and for the business and financial information entered into the service.',
          ],
        },
        {
          title: '3. Subscriptions and billing',
          paragraphs: [
            'Available plans, prices, billing periods, limits, and trial terms are shown on the website or at checkout. Your paid subscription begins after the payment provider confirms a successful payment and our systems process that confirmation.',
            'Card payments and recurring billing are processed by Paymob or another payment provider clearly identified at checkout. Ledger Suit may retain payment references, subscription identifiers, transaction status, and other non-sensitive billing metadata, but does not store full card numbers or card security codes (CVV).',
            'Where automatic renewal applies, the renewal schedule and price are those presented for the selected plan and billing cycle, subject to any change communicated as required by applicable law.',
          ],
        },
        {
          title: '4. Acceptable use',
          paragraphs: [
            'You must not use Ledger Suit for unlawful activity, attempt to gain unauthorized access, interfere with the service or its security, introduce malicious code, misuse another person’s data, or use the service in a way that infringes the rights of others.',
            'We may restrict or suspend access when reasonably necessary to protect the service, its users, or other parties, or to address suspected unlawful or abusive use.',
          ],
        },
        {
          title: '5. Service availability and changes',
          paragraphs: [
            'We work to keep Ledger Suit available and reliable, but do not guarantee uninterrupted or error-free operation. Access may occasionally be limited by maintenance, technical faults, security measures, payment-provider processing, or circumstances outside our reasonable control.',
            'We may improve, update, or change service functionality. Material changes affecting a paid subscription will be handled with reasonable notice where required by applicable law.',
          ],
        },
        {
          title: '6. Cancellation and refunds',
          paragraphs: [
            'You may cancel future renewal through the available account controls or by contacting support. Unless otherwise stated at purchase, paid access normally continues until the end of the current paid billing period.',
            'Refund eligibility and processing are governed by the Refund & Cancellation Policy available on this website. Nothing in these terms removes any mandatory right to a refund or other remedy under applicable law.',
          ],
        },
        {
          title: '7. Privacy',
          paragraphs: [
            'Our Privacy Policy explains how Ledger Suit collects, uses, stores, and protects account, business, financial, technical, and support information. Please review the Privacy Policy available on this website before using the service.',
          ],
        },
        {
          title: '8. Responsibility and liability',
          paragraphs: [
            'Ledger Suit is a tool for organizing financial information and does not replace professional accounting, tax, legal, or financial advice. You remain responsible for reviewing your records, reports, filings, and business decisions.',
            'To the extent permitted by applicable law, Building Suit is not responsible for indirect, incidental, or consequential loss arising from use of or inability to use the service. Nothing in these terms excludes or limits liability or remedies that cannot lawfully be excluded or limited.',
          ],
        },
        {
          title: '9. Applicable mandatory rights',
          paragraphs: [
            'These terms operate subject to applicable law. Nothing in them limits any non-waivable consumer right, remedy, or protection that applies under Egyptian law or another applicable law.',
          ],
        },
        {
          title: '10. Contact',
          paragraphs: [
            `For questions about these terms or the service, contact ${publicBusiness.supportEmail}.`,
          ],
        },
      ],
    },
    ar: {
      title: 'الشروط والأحكام',
      intro: 'تنظم هذه الشروط والأحكام وصولك إلى Ledger Suit واستخدامك له، وهو منتج رقمي للمحاسبة والإدارة المالية بنظام البرمجيات كخدمة (SaaS) من Building Suit.',
      updated: '14 سبتمبر 2026',
      sections: [
        {
          title: '1. الخدمة',
          paragraphs: [
            'يوفر Ledger Suit أدوات إلكترونية لتسجيل معاملات النشاط وتنظيم الحسابات وإدارة العمليات المالية والتعاون مع أعضاء الفريق وإعداد التقارير. وتُقدّم الخدمة رقميًا من خلال حسابك ومساحة العمل، ولا يتم توفير أي منتج مادي.',
            'Ledger Suit هو منتج من Building Suit، وهي العلامة التجارية الأم وهوية التاجر المستخدمة في تقديم الخدمة وترتيبات معالجة مدفوعاتها.',
          ],
        },
        {
          title: '2. الحسابات والاستخدام المصرح به',
          paragraphs: [
            'يجب تقديم بيانات حساب صحيحة، والحفاظ على سرية بيانات تسجيل الدخول، وتحديث البيانات عند تغيرها. وتتحمل مسؤولية الأنشطة التي تتم من خلال حسابك ما لم تبلغنا باشتباهك في وصول غير مصرح به.',
            'يتحمل مالكو مساحات العمل ومسؤولوها مسؤولية منح أعضاء الفريق صلاحيات مناسبة، كما يتحملون مسؤولية البيانات التجارية والمالية التي تُدخل إلى الخدمة.',
          ],
        },
        {
          title: '3. الاشتراكات والفوترة',
          paragraphs: [
            'تظهر الخطط والأسعار ودورات الفوترة والحدود وشروط التجربة المتاحة على الموقع أو عند الدفع. ويبدأ الاشتراك المدفوع بعد تأكيد مزود الدفع نجاح العملية ومعالجة أنظمتنا لهذا التأكيد.',
            'تتم معالجة مدفوعات البطاقات والفوترة المتكررة من خلال Paymob أو مزود دفع آخر يتم توضيحه عند الدفع. وقد يحتفظ Ledger Suit بمراجع الدفع ومعرّفات الاشتراك وحالة المعاملة وغيرها من بيانات الفوترة غير الحساسة، لكنه لا يخزن أرقام البطاقات الكاملة أو رموز الأمان (CVV).',
            'عندما ينطبق التجديد التلقائي، يكون موعد التجديد وسعره وفق الخطة ودورة الفوترة المختارتين، مع مراعاة أي تغيير يتم إبلاغك به على النحو الذي يتطلبه القانون المعمول به.',
          ],
        },
        {
          title: '4. الاستخدام المقبول',
          paragraphs: [
            'يُحظر استخدام Ledger Suit في أي نشاط غير قانوني، أو محاولة الوصول دون تصريح، أو تعطيل الخدمة أو إجراءات حمايتها، أو إدخال برمجيات ضارة، أو إساءة استخدام بيانات الغير، أو استخدام الخدمة بطريقة تنتهك حقوق الآخرين.',
            'يجوز لنا تقييد الوصول أو تعليقه عندما يكون ذلك ضروريًا بصورة معقولة لحماية الخدمة أو مستخدميها أو أطراف أخرى، أو للتعامل مع استخدام يُشتبه في كونه غير قانوني أو مسيئًا.',
          ],
        },
        {
          title: '5. توفر الخدمة والتغييرات',
          paragraphs: [
            'نعمل على إبقاء Ledger Suit متاحًا وموثوقًا، لكننا لا نضمن عمله دون انقطاع أو أخطاء. وقد يتأثر الوصول أحيانًا بأعمال الصيانة أو الأعطال التقنية أو إجراءات الأمان أو معالجة مزود الدفع أو ظروف خارجة عن سيطرتنا المعقولة.',
            'قد نُحسّن وظائف الخدمة أو نحدثها أو نغيرها. وسيتم التعامل مع التغييرات الجوهرية التي تؤثر في اشتراك مدفوع بإشعار معقول عندما يتطلب القانون المعمول به ذلك.',
          ],
        },
        {
          title: '6. الإلغاء والاسترداد',
          paragraphs: [
            'يمكنك إلغاء التجديد المستقبلي من خلال أدوات الحساب المتاحة أو بالتواصل مع الدعم. وما لم يُذكر خلاف ذلك عند الشراء، يستمر الوصول المدفوع عادةً حتى نهاية فترة الفوترة المدفوعة الحالية.',
            'تخضع أهلية الاسترداد وإجراءاته لسياسة الاسترداد والإلغاء المتاحة على هذا الموقع. ولا تلغي هذه الشروط أي حق إلزامي في الاسترداد أو أي وسيلة حماية أخرى يقررها القانون المعمول به.',
          ],
        },
        {
          title: '7. الخصوصية',
          paragraphs: [
            'توضح سياسة الخصوصية كيفية جمع Ledger Suit لبيانات الحساب والأعمال والبيانات المالية والتقنية وبيانات الدعم، وكيفية استخدامها وحفظها وحمايتها. يُرجى مراجعة سياسة الخصوصية المتاحة على هذا الموقع قبل استخدام الخدمة.',
          ],
        },
        {
          title: '8. المسؤولية وحدودها',
          paragraphs: [
            'Ledger Suit أداة لتنظيم المعلومات المالية، ولا يحل محل المشورة المهنية في المحاسبة أو الضرائب أو القانون أو الشؤون المالية. وتظل مسؤولًا عن مراجعة سجلاتك وتقاريرك وإقراراتك وقرارات نشاطك.',
            'في الحدود التي يسمح بها القانون المعمول به، لا تتحمل Building Suit المسؤولية عن الخسائر غير المباشرة أو العرضية أو التبعية الناتجة عن استخدام الخدمة أو تعذر استخدامها. ولا تستبعد هذه الشروط أو تقيد أي مسؤولية أو وسيلة حماية لا يجوز قانونًا استبعادها أو تقييدها.',
          ],
        },
        {
          title: '9. الحقوق الإلزامية المطبقة',
          paragraphs: [
            'تسري هذه الشروط مع مراعاة القانون المعمول به، ولا تحد من أي حق أو وسيلة حماية إلزامية لا يجوز التنازل عنها بموجب القانون المصري أو أي قانون آخر واجب التطبيق.',
          ],
        },
        {
          title: '10. التواصل',
          paragraphs: [
            `للاستفسار عن هذه الشروط أو الخدمة، تواصل معنا عبر ${publicBusiness.supportEmail}.`,
          ],
        },
      ],
    },
  },
  refund: {
    en: {
      title: 'Refund & Cancellation Policy',
      intro: 'This policy explains how subscription cancellation and refund requests are handled for Ledger Suit.',
      updated: '14 September 2026',
      sections: [
        {
          title: 'Cancellation',
          paragraphs: [
            'You may request cancellation of your Ledger Suit subscription at any time through the available account controls or by contacting support.',
            'Unless otherwise stated at the time of purchase, cancellation stops future renewals. Your paid access remains available until the end of the current paid billing period, after which the subscription will not renew.',
          ],
        },
        {
          title: 'Refunds',
          paragraphs: [
            'Subscription charges are generally non-refundable once the paid billing period has started, except where a refund is required by applicable law or where we confirm a duplicate charge, incorrect charge, or other billing error attributable to us or our payment processing flow.',
            'We do not normally provide partial or prorated refunds for unused time remaining in a billing period after cancellation.',
          ],
        },
        {
          title: 'Failed or duplicated payments',
          paragraphs: [
            'If you believe you were charged more than once for the same subscription period, charged an incorrect amount, or charged despite a failed activation, contact us promptly so we can investigate the payment records with the payment provider.',
          ],
        },
        {
          title: 'How to request a refund or cancellation',
          paragraphs: [
            `Email ${publicBusiness.supportEmail} from the email address associated with your Ledger Suit account. Include the organization/workspace name, payment date, amount, and payment reference if available.`,
            'We may ask for additional information needed to verify the account and transaction before completing the request.',
          ],
        },
        {
          title: 'Processing time',
          paragraphs: [
            'Approved refunds are submitted to the original payment method where possible. The time for the refunded amount to appear depends on the payment provider, card issuer, or bank and is outside our direct control.',
          ],
        },
        {
          title: 'Mandatory consumer rights',
          paragraphs: [
            'Nothing in this policy limits any non-waivable rights or remedies that apply under Egyptian law or other applicable law.',
          ],
        },
      ],
    },
    ar: {
      title: 'سياسة الاسترداد والإلغاء',
      intro: 'توضح هذه السياسة كيفية التعامل مع إلغاء اشتراك Ledger Suit وطلبات استرداد المدفوعات.',
      updated: '14 سبتمبر 2026',
      sections: [
        {
          title: 'إلغاء الاشتراك',
          paragraphs: [
            'يمكنك طلب إلغاء اشتراك Ledger Suit في أي وقت من خلال أدوات الحساب المتاحة أو عن طريق التواصل مع الدعم.',
            'ما لم يتم توضيح خلاف ذلك وقت الشراء، يؤدي الإلغاء إلى إيقاف التجديدات المستقبلية. ويستمر الوصول إلى الخطة المدفوعة حتى نهاية فترة الفوترة الحالية، وبعدها لا يتم تجديد الاشتراك.',
          ],
        },
        {
          title: 'استرداد المدفوعات',
          paragraphs: [
            'بوجه عام، لا تكون رسوم الاشتراك قابلة للاسترداد بعد بدء فترة الفوترة المدفوعة، إلا إذا كان الاسترداد مطلوبًا بموجب القانون أو تأكد وجود خصم مكرر أو مبلغ غير صحيح أو خطأ في الفوترة راجع إلينا أو إلى مسار معالجة الدفع.',
            'لا نقدم عادةً استردادًا جزئيًا أو محسوبًا بالتناسب عن المدة غير المستخدمة بعد إلغاء الاشتراك.',
          ],
        },
        {
          title: 'المدفوعات الفاشلة أو المكررة',
          paragraphs: [
            'إذا كنت تعتقد أن المبلغ خُصم أكثر من مرة عن فترة الاشتراك نفسها، أو خُصم مبلغ غير صحيح، أو تم الخصم دون تفعيل الخدمة بنجاح، فتواصل معنا في أقرب وقت لنراجع سجلات الدفع مع مزود الدفع.',
          ],
        },
        {
          title: 'طريقة طلب الإلغاء أو الاسترداد',
          paragraphs: [
            `أرسل رسالة إلى ${publicBusiness.supportEmail} من البريد الإلكتروني المرتبط بحساب Ledger Suit، مع ذكر اسم النشاط أو مساحة العمل وتاريخ الدفع والمبلغ ومرجع العملية إن كان متاحًا.`,
            'قد نطلب معلومات إضافية للتحقق من الحساب والمعاملة قبل إتمام الطلب.',
          ],
        },
        {
          title: 'مدة معالجة الاسترداد',
          paragraphs: [
            'عند الموافقة على الاسترداد، يُعاد المبلغ إلى وسيلة الدفع الأصلية متى كان ذلك ممكنًا. وقد يستغرق ظهوره وقتًا إضافيًا لدى مزود الدفع أو البنك أو جهة إصدار البطاقة، وهو أمر خارج سيطرتنا المباشرة.',
          ],
        },
        {
          title: 'الحقوق الإلزامية للمستهلك',
          paragraphs: [
            'لا تحد هذه السياسة من أي حقوق أو وسائل حماية إلزامية لا يجوز التنازل عنها بموجب القانون المصري أو أي قانون آخر واجب التطبيق.',
          ],
        },
      ],
    },
  },
}
