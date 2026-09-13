import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1";
import {
  assertCheckoutAccessState,
  parseCheckoutRequest,
  paymobPlanId,
  signCheckoutMetadata,
  verifyCheckoutMetadata,
} from "./paymob-checkout-contract.ts";

const request = {
  organizationId: "10000000-0000-4000-8000-000000000001",
  planKey: "starter" as const,
  interval: "yearly" as const,
};
const metadata = {
  ...request,
  priceId: "20000000-0000-4000-8000-000000000001",
  amountMinor: 488784,
};

Deno.test("checkout request accepts only launch plan identity and interval", () => {
  assertEquals(parseCheckoutRequest(request), request);
  for (
    const body of [
      { ...request, amount: 1 },
      { ...request, planKey: "scale" },
      { ...request, planKey: "enterprise" },
      { ...request, interval: "weekly" },
    ]
  ) {
    assertThrows(
      () => parseCheckoutRequest(body),
      Error,
      "Invalid checkout request",
    );
  }
});

Deno.test("stale clients cannot bypass checkout access-state restrictions", () => {
  for (const state of ["trialing", "checkout_required", "read_only"]) {
    assertCheckoutAccessState(state);
  }
  for (const state of ["active", "grace_period", "loading", "unknown"]) {
    assertThrows(
      () => assertCheckoutAccessState(state),
      Error,
      "Subscription is already active",
    );
  }
});

Deno.test("provider plan mapping is server-only and configuration-sensitive", () => {
  Deno.env.set("PAYMOB_STARTER_YEARLY_PLAN_ID", "1234");
  assertEquals(paymobPlanId("starter", "yearly"), 1234);
  Deno.env.delete("PAYMOB_STARTER_YEARLY_PLAN_ID");
  assertThrows(
    () => paymobPlanId("starter", "yearly"),
    Error,
    "PAYMOB_STARTER_YEARLY_PLAN_ID",
  );
});

Deno.test("signed metadata detects plan and amount tampering", async () => {
  const secret = "test-only-secret";
  const checkoutSignature = await signCheckoutMetadata(metadata, secret);
  const extras = {
    organization_id: metadata.organizationId,
    plan_key: metadata.planKey,
    billing_interval: metadata.interval,
    price_id: metadata.priceId,
    amount_minor: String(metadata.amountMinor),
    checkout_signature: checkoutSignature,
  };
  assertEquals(await verifyCheckoutMetadata(extras, secret), metadata);
  assertEquals(
    await verifyCheckoutMetadata({ ...extras, plan_key: "business" }, secret),
    null,
  );
  assertEquals(
    await verifyCheckoutMetadata({ ...extras, amount_minor: "1" }, secret),
    null,
  );
  assertEquals(
    await verifyCheckoutMetadata({
      ...extras,
      price_id: "30000000-0000-4000-8000-000000000001",
    }, secret),
    null,
  );
  await assertRejects(
    () => signCheckoutMetadata(metadata, ""),
    Error,
    "secret is missing",
  );
});
