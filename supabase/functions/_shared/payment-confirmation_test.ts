import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import type { EmailInput } from "./resend.ts";
import {
  type PaymentAdminClient,
  type PaymentConfirmation,
  safePaymobPaymentMethod,
  sanitizePaymobPayload,
  sendVerifiedSuccessfulPaymentConfirmation,
} from "./payment-confirmation.ts";

function fakeAdmin(): PaymentAdminClient {
  const records = {
    organizations: { name: "Alpha Trading", created_by: "owner-1" },
    profiles: {
      email: "owner@alpha.test",
      full_name: "Alpha Owner",
      locale: "en",
    },
  };
  return {
    from(table: keyof typeof records) {
      return {
        select() {
          return {
            eq() {
              return {
                single: async () => ({ data: records[table], error: null }),
              };
            },
          };
        },
      };
    },
  };
}

const payment: PaymentConfirmation = {
  eventId: "transaction-9001",
  organizationId: "organization-1",
  planKey: "starter",
  interval: "yearly",
  amountMinor: 488784,
  currency: "EGP",
  occurredAt: "2026-09-14T12:30:00Z",
  paymentMethod: "MasterCard card •••• 2346",
};

Deno.test("verified successful Paymob payment triggers a complete confirmation email", async () => {
  const sent: EmailInput[] = [];
  await sendVerifiedSuccessfulPaymentConfirmation(
    fakeAdmin(),
    true,
    payment,
    async (input) => {
      sent.push(input);
      return "email-1";
    },
  );

  assertEquals(sent.length, 1);
  assertEquals(sent[0]?.to, "owner@alpha.test");
  assertEquals(sent[0]?.subject, "Ledger Suit Payment Confirmation");
  assertEquals(sent[0]?.idempotencyKey, "paymob-payment/transaction-9001");
  assertStringIncludes(sent[0]?.body ?? "", "Ledger Suit by Building Suit");
  assertStringIncludes(sent[0]?.body ?? "", "Subscription plan: Starter");
  assertStringIncludes(sent[0]?.body ?? "", "Billing cycle: Yearly");
  assertStringIncludes(sent[0]?.body ?? "", "Amount: 4,887.84 EGP");
  assertStringIncludes(sent[0]?.body ?? "", "Status: Successful");
  assertStringIncludes(
    sent[0]?.body ?? "",
    "Payment method: MasterCard card •••• 2346",
  );
  assertStringIncludes(
    sent[0]?.body ?? "",
    "Support email: support@building-suit.com",
  );
});

Deno.test("retried Paymob payment uses one receipt identity and does not duplicate delivery", async () => {
  const delivered = new Set<string>();
  let deliveryCount = 0;
  const resend = async (input: EmailInput) => {
    if (!delivered.has(input.idempotencyKey)) {
      delivered.add(input.idempotencyKey);
      deliveryCount++;
    }
    return "email-1";
  };

  await sendVerifiedSuccessfulPaymentConfirmation(
    fakeAdmin(),
    true,
    payment,
    resend,
  );
  await sendVerifiedSuccessfulPaymentConfirmation(
    fakeAdmin(),
    true,
    payment,
    resend,
  );

  assertEquals(deliveryCount, 1);
  assertEquals([...delivered], ["paymob-payment/transaction-9001"]);
});

Deno.test("failed payment sends no confirmation and stored payloads exclude card credentials", async () => {
  let attempts = 0;
  await sendVerifiedSuccessfulPaymentConfirmation(
    fakeAdmin(),
    false,
    payment,
    async () => {
      attempts++;
      return "unexpected";
    },
  );
  assertEquals(attempts, 0);

  const callback = {
    obj: {
      source_data: {
        type: "card",
        sub_type: "MasterCard",
        pan: "2346",
        cvv: "123",
      },
      payment_token: "secret",
    },
  };
  assertEquals(
    safePaymobPaymentMethod(callback.obj),
    "MasterCard card •••• 2346",
  );
  assertEquals(sanitizePaymobPayload(callback), {
    obj: { source_data: { type: "card", sub_type: "MasterCard" } },
  });
});
