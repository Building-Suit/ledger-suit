-- Static reference rows belong in migrations because seed.sql is only used
-- for local/demo data and is not deployed by a normal `supabase db push`.
-- Keep this repair idempotent so it also protects environments whose schema
-- history exists but whose required catalogue rows were never populated.

insert into public.currencies (code, name, symbol, minor_unit, is_active) values
  ('EGP', 'Egyptian Pound',        E'ج.م',  2, true),
  ('USD', 'US Dollar',             '$',     2, true),
  ('EUR', 'Euro',                  E'€',    2, true),
  ('GBP', 'Pound Sterling',        E'£',    2, true),
  ('SAR', 'Saudi Riyal',           E'﷼',    2, true),
  ('AED', 'UAE Dirham',            E'د.إ',  2, true),
  ('KWD', 'Kuwaiti Dinar',         E'د.ك',  3, true),
  ('QAR', 'Qatari Riyal',          E'ر.ق',  2, true),
  ('BHD', 'Bahraini Dinar',        E'.د.ب', 3, true),
  ('OMR', 'Omani Rial',            E'ر.ع',  3, true),
  ('JOD', 'Jordanian Dinar',       E'د.ا',  3, true),
  ('TRY', 'Turkish Lira',          E'₺',    2, true),
  ('JPY', 'Japanese Yen',          E'¥',    0, true),
  ('CNY', 'Chinese Yuan',          E'¥',    2, true),
  ('CAD', 'Canadian Dollar',       'CA$',   2, true),
  ('AUD', 'Australian Dollar',     'A$',    2, true),
  ('CHF', 'Swiss Franc',           'CHF',   2, true),
  ('SEK', 'Swedish Krona',         'kr',    2, true),
  ('NOK', 'Norwegian Krone',       'kr',    2, true),
  ('ZAR', 'South African Rand',    'R',     2, true),
  ('NGN', 'Nigerian Naira',        E'₦',    2, true),
  ('KES', 'Kenyan Shilling',       'KSh',   2, true),
  ('MAD', 'Moroccan Dirham',       E'د.م.', 2, true),
  ('TND', 'Tunisian Dinar',        E'د.ت',  3, true),
  ('INR', 'Indian Rupee',          E'₹',    2, true),
  ('PKR', 'Pakistani Rupee',       E'₨',    2, true),
  ('SGD', 'Singapore Dollar',      'S$',    2, true)
on conflict (code) do update
set name = excluded.name,
    symbol = excluded.symbol,
    minor_unit = excluded.minor_unit,
    is_active = true;

insert into public.capabilities (key, domain, description) values
  ('organization.read',               'organization', 'View organization profile and settings'),
  ('organization.update',             'organization', 'Edit organization profile and settings'),
  ('organization.archive',            'organization', 'Archive the organization'),
  ('organization.transfer_ownership', 'organization', 'Transfer ownership to another member'),
  ('members.read',                     'members', 'List organization members'),
  ('members.invite',                   'members', 'Invite new members'),
  ('members.update',                   'members', 'Change member roles and capabilities'),
  ('members.remove',                   'members', 'Remove members'),
  ('accounts.read',                    'accounts', 'View the chart of accounts'),
  ('accounts.create',                  'accounts', 'Create accounts'),
  ('accounts.update',                  'accounts', 'Edit accounts'),
  ('accounts.archive',                 'accounts', 'Archive accounts'),
  ('categories.read',                  'categories', 'View categories'),
  ('categories.manage',                'categories', 'Create, edit and archive categories'),
  ('counterparties.read',              'counterparties', 'View counterparties'),
  ('counterparties.manage',            'counterparties', 'Create and edit counterparties'),
  ('tags.read',                        'tags', 'View tags'),
  ('tags.manage',                      'tags', 'Create and edit tags'),
  ('transactions.read',                'transactions', 'View transactions and ledger entries'),
  ('transactions.create',              'transactions', 'Create draft transactions'),
  ('transactions.update_draft',        'transactions', 'Edit draft transactions'),
  ('transactions.post',                'transactions', 'Post transactions to the ledger'),
  ('transactions.void',                'transactions', 'Void unposted transactions'),
  ('transactions.reverse',             'transactions', 'Reverse posted transactions'),
  ('transactions.adjust',              'transactions', 'Create manual journal adjustments'),
  ('commitments.read',                  'commitments', 'View commitments'),
  ('commitments.create',                'commitments', 'Create commitments'),
  ('commitments.update',                'commitments', 'Edit commitments'),
  ('commitments.settle',                'commitments', 'Settle commitments into the ledger'),
  ('recurring.read',                    'recurring', 'View recurring rules'),
  ('recurring.manage',                  'recurring', 'Create and edit recurring rules'),
  ('attachments.read',                  'attachments', 'Download attachments'),
  ('attachments.create',                'attachments', 'Upload attachments'),
  ('attachments.delete',                'attachments', 'Delete attachments'),
  ('reports.read',                      'reports', 'View financial reports'),
  ('reports.export',                    'reports', 'Export reports'),
  ('imports.create',                    'imports', 'Import data from CSV/XLSX'),
  ('exports.create',                    'exports', 'Export organization data'),
  ('audit.read',                        'audit', 'Read the audit log'),
  ('books.override_lock',               'books', 'Post into a locked accounting period'),
  ('billing.read',                      'billing', 'View subscription and invoices'),
  ('billing.manage',                    'billing', 'Start, change or cancel the subscription')
on conflict (key) do update
set domain = excluded.domain,
    description = excluded.description;

update public.capabilities set description_ar = v.description_ar
from (values
  ('organization.read',               'عرض ملف المؤسسة والإعدادات'),
  ('organization.update',             'تعديل ملف المؤسسة والإعدادات'),
  ('organization.archive',            'أرشفة المؤسسة'),
  ('organization.transfer_ownership', 'نقل الملكية إلى عضو آخر'),
  ('members.read',                    'عرض أعضاء المؤسسة'),
  ('members.invite',                  'دعوة أعضاء جدد'),
  ('members.update',                  'تغيير أدوار الأعضاء والصلاحيات'),
  ('members.remove',                  'إزالة الأعضاء'),
  ('accounts.read',                   'عرض دليل الحسابات'),
  ('accounts.create',                 'إنشاء حسابات'),
  ('accounts.update',                 'تعديل الحسابات'),
  ('accounts.archive',                'أرشفة الحسابات'),
  ('categories.read',                 'عرض الفئات'),
  ('categories.manage',               'إنشاء وتعديل وأرشفة الفئات'),
  ('counterparties.read',             'عرض الأطراف'),
  ('counterparties.manage',           'إنشاء وتعديل الأطراف'),
  ('tags.read',                       'عرض الوسوم'),
  ('tags.manage',                     'إنشاء وتعديل الوسوم'),
  ('transactions.read',               'عرض المعاملات وقيود اليومية'),
  ('transactions.create',             'إنشاء معاملات مسودة'),
  ('transactions.update_draft',       'تعديل المعاملات المسودة'),
  ('transactions.post',               'ترحيل المعاملات إلى دفتر الأستاذ'),
  ('transactions.void',               'إلغاء المعاملات غير المرحّلة'),
  ('transactions.reverse',            'عكس المعاملات المرحّلة'),
  ('transactions.adjust',             'إنشاء قيود تسوية يدوية'),
  ('commitments.read',                'عرض الالتزامات'),
  ('commitments.create',              'إنشاء التزامات'),
  ('commitments.update',              'تعديل الالتزامات'),
  ('commitments.settle',              'تسوية الالتزامات في دفتر الأستاذ'),
  ('recurring.read',                  'عرض القواعد المتكررة'),
  ('recurring.manage',                'إنشاء وتعديل القواعد المتكررة'),
  ('attachments.read',                'تنزيل المرفقات'),
  ('attachments.create',              'رفع المرفقات'),
  ('attachments.delete',              'حذف المرفقات'),
  ('reports.read',                    'عرض التقارير المالية'),
  ('reports.export',                  'تصدير التقارير'),
  ('imports.create',                  'استيراد البيانات من CSV/XLSX'),
  ('exports.create',                  'تصدير بيانات المؤسسة'),
  ('audit.read',                      'عرض سجل التدقيق'),
  ('books.override_lock',             'الترحيل في فترة محاسبية مقفلة'),
  ('billing.read',                    'عرض الاشتراك والفواتير'),
  ('billing.manage',                  'بدء الاشتراك أو تغييره أو إلغائه')
) as v(key, description_ar)
where public.capabilities.key = v.key;

insert into public.role_capabilities (role, capability_key)
select 'owner', key from public.capabilities
on conflict do nothing;

insert into public.role_capabilities (role, capability_key)
select 'admin', key from public.capabilities
where key not in (
  'organization.transfer_ownership',
  'organization.archive',
  'billing.manage'
)
on conflict do nothing;

insert into public.role_capabilities (role, capability_key) values
  ('accountant', 'organization.read'),
  ('accountant', 'members.read'),
  ('accountant', 'accounts.read'),
  ('accountant', 'accounts.create'),
  ('accountant', 'accounts.update'),
  ('accountant', 'accounts.archive'),
  ('accountant', 'categories.read'),
  ('accountant', 'categories.manage'),
  ('accountant', 'counterparties.read'),
  ('accountant', 'counterparties.manage'),
  ('accountant', 'tags.read'),
  ('accountant', 'tags.manage'),
  ('accountant', 'transactions.read'),
  ('accountant', 'transactions.create'),
  ('accountant', 'transactions.update_draft'),
  ('accountant', 'transactions.post'),
  ('accountant', 'transactions.void'),
  ('accountant', 'transactions.reverse'),
  ('accountant', 'transactions.adjust'),
  ('accountant', 'commitments.read'),
  ('accountant', 'commitments.create'),
  ('accountant', 'commitments.update'),
  ('accountant', 'commitments.settle'),
  ('accountant', 'recurring.read'),
  ('accountant', 'recurring.manage'),
  ('accountant', 'attachments.read'),
  ('accountant', 'attachments.create'),
  ('accountant', 'attachments.delete'),
  ('accountant', 'reports.read'),
  ('accountant', 'reports.export'),
  ('accountant', 'imports.create'),
  ('accountant', 'exports.create'),
  ('accountant', 'audit.read'),
  ('accountant', 'books.override_lock'),
  ('accountant', 'billing.read')
on conflict do nothing;

insert into public.role_capabilities (role, capability_key) values
  ('data_entry', 'organization.read'),
  ('data_entry', 'members.read'),
  ('data_entry', 'accounts.read'),
  ('data_entry', 'categories.read'),
  ('data_entry', 'counterparties.read'),
  ('data_entry', 'counterparties.manage'),
  ('data_entry', 'tags.read'),
  ('data_entry', 'transactions.read'),
  ('data_entry', 'transactions.create'),
  ('data_entry', 'transactions.update_draft'),
  ('data_entry', 'transactions.post'),
  ('data_entry', 'transactions.void'),
  ('data_entry', 'commitments.read'),
  ('data_entry', 'commitments.create'),
  ('data_entry', 'commitments.update'),
  ('data_entry', 'attachments.read'),
  ('data_entry', 'attachments.create'),
  ('data_entry', 'reports.read')
on conflict do nothing;

insert into public.role_capabilities (role, capability_key) values
  ('viewer', 'organization.read'),
  ('viewer', 'members.read'),
  ('viewer', 'accounts.read'),
  ('viewer', 'categories.read'),
  ('viewer', 'counterparties.read'),
  ('viewer', 'tags.read'),
  ('viewer', 'transactions.read'),
  ('viewer', 'commitments.read'),
  ('viewer', 'recurring.read'),
  ('viewer', 'attachments.read'),
  ('viewer', 'reports.read')
on conflict do nothing;

insert into public.subscription_plans (
  key, name, description, is_public, is_active, sort_order
) values (
  'ledger_suit',
  'Ledger Suit',
  'Complete multi-tenant financial management with a 14-day trial.',
  true,
  true,
  0
)
on conflict (key) do update
set name = excluded.name,
    description = excluded.description,
    is_public = true,
    is_active = true,
    sort_order = 0;

insert into public.subscription_entitlements (
  plan_id, feature_key, is_enabled, limit_value
)
select p.id, e.feature_key, true, null
from public.subscription_plans p
cross join (
  values
    ('max_members'),
    ('max_monthly_transactions'),
    ('max_storage_bytes'),
    ('max_recurring_rules'),
    ('multi_currency'),
    ('advanced_reports'),
    ('imports'),
    ('exports'),
    ('audit_log_retention_days'),
    ('api_access')
) as e(feature_key)
where p.key = 'ledger_suit'
on conflict (plan_id, feature_key) do update
set is_enabled = true,
    limit_value = null;
