import { sendEmail } from "./resend.ts";

type JsonRecord = Record<string, unknown>;

interface PaymentQueryResult {
  data: unknown;
  error: unknown;
}

export interface PaymentAdminClient {
  from(table: string): {
    select(columns: string): {
      eq(column: string, value: unknown): {
        single(): PromiseLike<PaymentQueryResult>;
      };
    };
  };
}

export interface PaymentConfirmation {
  eventId: string;
  organizationId: string;
  planKey: string;
  interval: "monthly" | "yearly";
  amountMinor: number;
  currency: string;
  occurredAt: string;
  paymentMethod: string | null;
}

interface PaymentRecipient {
  email: string;
  fullName: string | null;
  locale: string;
  organizationName: string;
}

type EmailSender = typeof sendEmail;

const supportEmail = "support@building-suit.com";

function record(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : {};
}

/** Keep only non-sensitive method labels and an explicitly last-four Paymob value. */
export function safePaymobPaymentMethod(object: JsonRecord): string | null {
  const source = record(object.source_data);
  const type = typeof source.type === "string" ? source.type.trim() : "";
  const subtype = typeof source.sub_type === "string"
    ? source.sub_type.trim()
    : "";
  const paymobLastFour =
    typeof source.pan === "string" && /^\d{4}$/.test(source.pan)
      ? source.pan
      : null;
  const label = [subtype, type].filter(Boolean).join(" ");
  if (!label && !paymobLastFour) return null;
  return `${label || "Payment method"}${
    paymobLastFour ? ` •••• ${paymobLastFour}` : ""
  }`;
}

/** Remove card credentials before the callback is persisted in billing_events. */
export function sanitizePaymobPayload(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sanitizePaymobPayload);
  if (!value || typeof value !== "object") return value;

  const sensitiveKeys = new Set([
    "pan",
    "card_number",
    "cardnumber",
    "cvv",
    "cvc",
    "card_security_code",
    "payment_token",
  ]);
  return Object.fromEntries(
    Object.entries(value as JsonRecord)
      .filter(([key]) => !sensitiveKeys.has(key.toLowerCase()))
      .map(([key, nested]) => [key, sanitizePaymobPayload(nested)]),
  );
}

function planName(planKey: string, arabic: boolean): string {
  const names: Record<string, [string, string]> = {
    solo: ["Solo", "فردي"],
    starter: ["Starter", "المبتدئة"],
    business: ["Business", "الأعمال"],
  };
  const namesForPlan = names[planKey];
  return namesForPlan ? namesForPlan[arabic ? 1 : 0] : planKey;
}

function formatAmount(
  amountMinor: number,
  currency: string,
  arabic: boolean,
): string {
  return `${
    new Intl.NumberFormat(arabic ? "ar-EG" : "en-US", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    }).format(amountMinor / 100)
  } ${currency}`;
}

function formatDateTime(value: string, arabic: boolean): string {
  return new Intl.DateTimeFormat(arabic ? "ar-EG" : "en-US", {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
    timeZone: "UTC",
    timeZoneName: "short",
  }).format(new Date(value));
}

async function paymentRecipient(
  admin: PaymentAdminClient,
  organizationId: string,
): Promise<PaymentRecipient> {
  const { data: organization, error: organizationError } = await admin
    .from("organizations")
    .select("name,created_by")
    .eq("id", organizationId)
    .single();
  const organizationRecord = record(organization);
  if (organizationError || !organizationRecord.created_by) {
    throw organizationError ??
      new Error("Payment organization could not be loaded");
  }

  const { data: owner, error: ownerError } = await admin
    .from("profiles")
    .select("email,full_name,locale")
    .eq("id", organizationRecord.created_by)
    .single();
  const ownerRecord = record(owner);
  if (ownerError || !ownerRecord.email) {
    throw ownerError ?? new Error("Payment recipient could not be loaded");
  }

  return {
    email: String(ownerRecord.email),
    fullName: ownerRecord.full_name ? String(ownerRecord.full_name) : null,
    locale: String(ownerRecord.locale ?? "en"),
    organizationName: String(organizationRecord.name ?? "Ledger Suit"),
  };
}

export async function sendPaymentConfirmation(
  admin: PaymentAdminClient,
  payment: PaymentConfirmation,
  sender: EmailSender = sendEmail,
): Promise<string> {
  const recipient = await paymentRecipient(admin, payment.organizationId);
  const arabic = recipient.locale.toLowerCase().startsWith("ar");
  const name = recipient.fullName ?? recipient.email;
  const lines = arabic
    ? [
      "Ledger Suit by Building Suit",
      `البريد الإلكتروني للحساب: ${recipient.email}`,
      `خطة الاشتراك: ${planName(payment.planKey, true)}`,
      `دورة الفوترة: ${payment.interval === "yearly" ? "سنوية" : "شهرية"}`,
      `المبلغ: ${formatAmount(payment.amountMinor, payment.currency, true)}`,
      `مرجع الدفع: ${payment.eventId}`,
      `تاريخ ووقت الدفع: ${formatDateTime(payment.occurredAt, true)}`,
      "الحالة: ناجحة",
      ...(payment.paymentMethod
        ? [`طريقة الدفع: ${payment.paymentMethod}`]
        : []),
      `البريد الإلكتروني للدعم: ${supportEmail}`,
    ]
    : [
      "Ledger Suit by Building Suit",
      `Customer/account email: ${recipient.email}`,
      `Subscription plan: ${planName(payment.planKey, false)}`,
      `Billing cycle: ${payment.interval === "yearly" ? "Yearly" : "Monthly"}`,
      `Amount: ${formatAmount(payment.amountMinor, payment.currency, false)}`,
      `Transaction/payment reference: ${payment.eventId}`,
      `Payment date/time: ${formatDateTime(payment.occurredAt, false)}`,
      "Status: Successful",
      ...(payment.paymentMethod
        ? [`Payment method: ${payment.paymentMethod}`]
        : []),
      `Support email: ${supportEmail}`,
    ];

  return await sender({
    to: recipient.email,
    recipientName: name,
    organizationName: recipient.organizationName,
    subject: arabic
      ? "تأكيد عملية الدفع — Ledger Suit"
      : "Ledger Suit Payment Confirmation",
    body: lines.join("\n"),
    greeting: arabic ? `مرحبًا ${name}،` : `Hello ${name},`,
    footer: arabic
      ? `للاستفسارات عن هذه الدفعة، تواصل معنا عبر ${supportEmail}.`
      : `For questions about this payment, contact ${supportEmail}.`,
    idempotencyKey: `paymob-payment/${payment.eventId}`,
  });
}

/** Called only after the webhook has verified HMAC and checkout metadata. */
export async function sendVerifiedSuccessfulPaymentConfirmation(
  admin: PaymentAdminClient,
  succeeded: boolean,
  payment: PaymentConfirmation,
  sender: EmailSender = sendEmail,
): Promise<string | null> {
  if (!succeeded) return null;
  return await sendPaymentConfirmation(admin, payment, sender);
}
