export const launchPlanKeys = ["solo", "starter", "business"] as const;
export const billingIntervals = ["monthly", "yearly"] as const;

export type LaunchPlanKey = typeof launchPlanKeys[number];
export type BillingInterval = typeof billingIntervals[number];

export interface CheckoutRequest {
  organizationId: string;
  planKey: LaunchPlanKey;
  interval: BillingInterval;
}

export interface CheckoutMetadata extends CheckoutRequest {
  priceId: string;
  amountMinor: number;
}

export function assertCheckoutAccessState(accessState: string): void {
  if (!["trialing", "checkout_required", "read_only"].includes(accessState)) {
    throw new Error("Subscription is already active");
  }
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function parseCheckoutRequest(value: unknown): CheckoutRequest {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Invalid checkout request");
  }
  const body = value as Record<string, unknown>;
  if (
    Object.keys(body).some((key) =>
      !["organizationId", "planKey", "interval"].includes(key)
    ) ||
    typeof body.organizationId !== "string" ||
    !uuidPattern.test(body.organizationId) ||
    !launchPlanKeys.includes(body.planKey as LaunchPlanKey) ||
    !billingIntervals.includes(body.interval as BillingInterval)
  ) {
    throw new Error("Invalid checkout request");
  }
  return body as unknown as CheckoutRequest;
}

export function paymobPlanId(
  planKey: LaunchPlanKey,
  interval: BillingInterval,
): number {
  const name =
    `PAYMOB_${planKey.toUpperCase()}_${interval.toUpperCase()}_PLAN_ID`;
  const value = Number(Deno.env.get(name)?.trim());
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`Paymob billing configuration is invalid: ${name}`);
  }
  return value;
}

function canonical(metadata: CheckoutMetadata): string {
  return [
    "v1",
    metadata.organizationId.toLowerCase(),
    metadata.planKey,
    metadata.interval,
    metadata.priceId.toLowerCase(),
    String(metadata.amountMinor),
  ].join("|");
}

function bytesToHex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)].map((value) =>
    value.toString(16).padStart(2, "0")
  ).join("");
}

async function signature(
  metadata: CheckoutMetadata,
  secret: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  return bytesToHex(
    await crypto.subtle.sign(
      "HMAC",
      key,
      new TextEncoder().encode(canonical(metadata)),
    ),
  );
}

export async function signCheckoutMetadata(
  metadata: CheckoutMetadata,
  secret: string,
): Promise<string> {
  validateMetadata(metadata);
  if (!secret) throw new Error("Paymob checkout metadata secret is missing");
  return await signature(metadata, secret);
}

export async function verifyCheckoutMetadata(
  value: Record<string, unknown>,
  secret: string,
): Promise<CheckoutMetadata | null> {
  const metadata: CheckoutMetadata = {
    organizationId: typeof value.organization_id === "string"
      ? value.organization_id
      : "",
    planKey: value.plan_key as LaunchPlanKey,
    interval: value.billing_interval as BillingInterval,
    priceId: typeof value.price_id === "string" ? value.price_id : "",
    amountMinor: Number(value.amount_minor),
  };
  try {
    validateMetadata(metadata);
  } catch {
    return null;
  }
  const supplied = typeof value.checkout_signature === "string"
    ? value.checkout_signature.toLowerCase()
    : "";
  const expected = await signature(metadata, secret);
  if (supplied.length !== expected.length) return null;
  let difference = 0;
  for (let index = 0; index < expected.length; index++) {
    difference |= supplied.charCodeAt(index) ^ expected.charCodeAt(index);
  }
  return difference === 0 ? metadata : null;
}

function validateMetadata(metadata: CheckoutMetadata): void {
  if (
    !uuidPattern.test(metadata.organizationId) ||
    !uuidPattern.test(metadata.priceId) ||
    !launchPlanKeys.includes(metadata.planKey) ||
    !billingIntervals.includes(metadata.interval) ||
    !Number.isSafeInteger(metadata.amountMinor) || metadata.amountMinor <= 0
  ) {
    throw new Error("Invalid checkout metadata");
  }
}
