import {
  authenticatedClient,
  handleOptions,
  json,
  publicError,
  readJson,
  requiredEnv,
} from "../_shared/http.ts";
import { paymobCheckoutUrl, paymobRequest } from "../_shared/paymob.ts";
import {
  assertCheckoutAccessState,
  parseCheckoutRequest,
  paymobPlanId,
  signCheckoutMetadata,
} from "../_shared/paymob-checkout-contract.ts";

interface CheckoutContext {
  organization_id: string;
  organization_name: string;
  billing_email: string;
  billing_name: string | null;
  billing_phone: string | null;
  access_state: string;
  plan_key: "solo" | "starter" | "business";
  price_id: string;
  amount_minor: number;
  currency_code: string;
}
interface PaymobIntention {
  id: string;
  intention_order_id: number;
  client_secret: string;
}

function customerName(
  fullName: string | null,
): { firstName: string; lastName: string } {
  const parts = fullName?.trim().split(/\s+/).filter(Boolean) ?? [];
  return {
    firstName: parts[0] ?? "Ledger",
    lastName: parts.slice(1).join(" ") || "Suit Customer",
  };
}

Deno.serve(async (request) => {
  const preflight = handleOptions(request);
  if (preflight) return preflight;
  try {
    const { organizationId, planKey, interval } = parseCheckoutRequest(
      await readJson<unknown>(request),
    );

    const supabase = await authenticatedClient(request);
    const { data, error } = await supabase.rpc("billing_checkout_context", {
      p_organization_id: organizationId,
      p_plan_key: planKey,
      p_interval: interval,
    });
    if (error) throw error;
    const context = (data as CheckoutContext[] | null)?.[0];
    if (!context) throw new Error("Organization not found");
    assertCheckoutAccessState(context.access_state);
    if (!context.billing_phone) {
      throw new Error("A billing phone number is required before checkout.");
    }

    const amount = Number(context.amount_minor);
    const planId = paymobPlanId(planKey, interval);
    // Initial enrollment is customer-present and must use the online 3DS
    // integration. The separate MOTO ID belongs to the Paymob plan and is
    // used by Paymob itself for later automatic deductions.
    const integrationId = Number(requiredEnv("PAYMOB_CARD_INTEGRATION_ID"));
    if (
      ![amount, planId, integrationId].every(Number.isSafeInteger) ||
      amount <= 0 ||
      context.currency_code.trim() !== "EGP" || context.plan_key !== planKey
    ) {
      throw new Error("Paymob billing configuration is invalid");
    }

    const appUrl = requiredEnv("APP_BASE_URL").replace(/\/$/, "");
    const functionUrl = requiredEnv("SUPABASE_URL").replace(/\/$/, "");
    const { firstName, lastName } = customerName(context.billing_name);
    const metadata = {
      organizationId,
      planKey,
      interval,
      priceId: context.price_id,
      amountMinor: amount,
    };
    const checkoutSignature = await signCheckoutMetadata(
      metadata,
      requiredEnv("PAYMOB_HMAC_SECRET"),
    );
    const reference =
      `ledger_suit:${organizationId}:${planKey}:${interval}:${crypto.randomUUID()}`;
    const intention = await paymobRequest<PaymobIntention>("/v1/intention/", {
      amount,
      currency: "EGP",
      payment_methods: [integrationId],
      subscription_plan_id: planId,
      items: [{
        name: `Ledger Suit ${planKey} ${interval} subscription`,
        amount,
        description:
          `Ledger Suit subscription for ${context.organization_name}`,
        quantity: 1,
      }],
      billing_data: {
        first_name: firstName,
        last_name: lastName,
        email: context.billing_email,
        phone_number: context.billing_phone,
        apartment: "NA",
        floor: "NA",
        street: "NA",
        building: "NA",
        shipping_method: "NA",
        postal_code: "NA",
        city: "Cairo",
        state: "Cairo",
        country: "EGY",
      },
      customer: {
        first_name: firstName,
        last_name: lastName,
        email: context.billing_email,
      },
      extras: {
        organization_id: organizationId,
        plan_key: planKey,
        billing_interval: interval,
        price_id: context.price_id,
        amount_minor: String(amount),
        checkout_signature: checkoutSignature,
      },
      special_reference: reference,
      expiration: 1800,
      notification_url: `${functionUrl}/functions/v1/paymob-webhook`,
      redirection_url: `${appUrl}/subscribe?checkout=complete`,
    });
    if (!intention.client_secret) {
      throw new Error("Paymob did not return a checkout client secret");
    }
    return json({
      id: intention.id,
      orderId: intention.intention_order_id,
      url: paymobCheckoutUrl(intention.client_secret),
    });
  } catch (error) {
    return json({ error: publicError(error) }, 400);
  }
});
