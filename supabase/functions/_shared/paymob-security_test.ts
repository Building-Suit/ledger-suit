import { assertEquals } from "jsr:@std/assert@1";
import {
  verifyPaymobSubscriptionHmac,
  verifyPaymobTransactionHmac,
} from "./paymob.ts";

const transactionFields = [
  "amount_cents",
  "created_at",
  "currency",
  "error_occured",
  "has_parent_transaction",
  "id",
  "integration_id",
  "is_3d_secure",
  "is_auth",
  "is_capture",
  "is_refunded",
  "is_standalone_payment",
  "is_voided",
  "order.id",
  "owner",
  "pending",
  "source_data.pan",
  "source_data.sub_type",
  "source_data.type",
  "success",
] as const;

type JsonRecord = Record<string, unknown>;

function nested(record: JsonRecord, path: string): unknown {
  return path.split(".").reduce<unknown>(
    (value, key) =>
      value && typeof value === "object"
        ? (value as JsonRecord)[key]
        : undefined,
    record,
  );
}

async function hmac(message: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  const bytes = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(message),
  );
  return [...new Uint8Array(bytes)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

const transaction: JsonRecord = {
  amount_cents: 59900,
  created_at: "2026-09-13T12:00:00Z",
  currency: "EGP",
  error_occured: false,
  has_parent_transaction: false,
  id: 9001,
  integration_id: 5902990,
  is_3d_secure: true,
  is_auth: false,
  is_capture: false,
  is_refunded: false,
  is_standalone_payment: true,
  is_voided: false,
  order: { id: 7001 },
  owner: 42,
  pending: false,
  source_data: { pan: "2346", sub_type: "MasterCard", type: "card" },
  success: true,
};

Deno.test("verified transaction HMAC rejects payload tampering", async () => {
  const secret = "step22-hmac-secret";
  Deno.env.set("PAYMOB_HMAC_SECRET", secret);
  const message = transactionFields
    .map((field) => String(nested(transaction, field) ?? ""))
    .join("");
  const signature = await hmac(message, secret);

  assertEquals(await verifyPaymobTransactionHmac(transaction, signature), true);
  assertEquals(
    await verifyPaymobTransactionHmac(
      { ...transaction, amount_cents: 1 },
      signature,
    ),
    false,
  );
  assertEquals(await verifyPaymobTransactionHmac(transaction, null), false);
  Deno.env.delete("PAYMOB_HMAC_SECRET");
});

Deno.test("verified subscription HMAC rejects identity tampering", async () => {
  const secret = "step22-subscription-secret";
  Deno.env.set("PAYMOB_HMAC_SECRET", secret);
  const signature = await hmac(
    "successful transactionforsubscription-42",
    secret,
  );

  assertEquals(
    await verifyPaymobSubscriptionHmac(
      "subscription-42",
      "successful transaction",
      signature,
    ),
    true,
  );
  assertEquals(
    await verifyPaymobSubscriptionHmac(
      "subscription-43",
      "successful transaction",
      signature,
    ),
    false,
  );
  Deno.env.delete("PAYMOB_HMAC_SECRET");
});
