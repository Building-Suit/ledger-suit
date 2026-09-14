interface PaymobPlan {
  id: number;
  name: string;
  frequency: number;
  amount_cents: number;
  integration: number;
  use_transaction_amount: boolean;
  is_active: boolean;
  webhook_url: string | null;
}

interface PlanSpec {
  envName: string;
  name: string;
  frequency: 30 | 360;
  amountCents: number;
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`${name} is required`);
  return value;
}

function positiveInteger(name: string): number {
  const value = Number(requiredEnv(name));
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }
  return value;
}

function webhookUrl(): string {
  const argument = Deno.args.find((value) => value.startsWith("--webhook-url="))
    ?.slice("--webhook-url=".length);
  if (!argument) {
    throw new Error(
      "Pass the deployed callback as --webhook-url=https://<project-ref>.supabase.co/functions/v1/paymob-webhook",
    );
  }
  const url = new URL(argument);
  if (
    url.protocol !== "https:" ||
    !url.pathname.endsWith("/functions/v1/paymob-webhook")
  ) {
    throw new Error(
      "The webhook URL must be HTTPS and end with /functions/v1/paymob-webhook",
    );
  }
  return url.toString();
}

const baseUrl =
  (Deno.env.get("PAYMOB_BASE_URL")?.trim() || "https://accept.paymob.com")
    .replace(/\/$/, "");
const apiKey = requiredEnv("PAYMOB_API_KEY");
const motoIntegrationId = positiveInteger("PAYMOB_MOTO_INTEGRATION_ID");
const callbackUrl = webhookUrl();

async function responseJson<T>(response: Response): Promise<T> {
  const payload = await response.json().catch(() => ({})) as Record<
    string,
    unknown
  >;
  if (!response.ok) {
    const message = payload.detail ?? payload.message ??
      `Paymob request failed (${response.status})`;
    throw new Error(
      typeof message === "string" ? message : JSON.stringify(message),
    );
  }
  return payload as T;
}

async function authToken(): Promise<string> {
  const response = await fetch(`${baseUrl}/api/auth/tokens`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ api_key: apiKey }),
  });
  const payload = await responseJson<{ token?: string }>(response);
  if (!payload.token) {
    throw new Error("Paymob authentication did not return a token");
  }
  return payload.token;
}

async function listPlans(token: string): Promise<PaymobPlan[]> {
  const plans: PaymobPlan[] = [];
  let next: string | null = `${baseUrl}/api/acceptance/subscription-plans`;
  while (next) {
    const response: Response = await fetch(next, {
      headers: { Authorization: `Bearer ${token}` },
    });
    const page: { results?: PaymobPlan[]; next?: string | null } =
      await responseJson(response);
    plans.push(...(page.results ?? []));
    next = page.next ?? null;
  }
  return plans;
}

function matches(plan: PaymobPlan, spec: PlanSpec): boolean {
  return plan.frequency === spec.frequency &&
    plan.amount_cents === spec.amountCents &&
    plan.integration === motoIntegrationId &&
    plan.use_transaction_amount === true &&
    plan.is_active === true &&
    plan.webhook_url === callbackUrl;
}

async function ensurePlan(
  token: string,
  plans: PaymobPlan[],
  spec: PlanSpec,
): Promise<PaymobPlan> {
  const namedPlans = plans.filter((plan) => plan.name === spec.name);
  const existing = namedPlans.find((plan) => matches(plan, spec));
  if (existing) return existing;
  if (namedPlans.length) {
    throw new Error(
      `${spec.name} already exists with different billing settings; review it in Paymob instead of creating a duplicate`,
    );
  }

  const response = await fetch(`${baseUrl}/api/acceptance/subscription-plans`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      frequency: spec.frequency,
      name: spec.name,
      webhook_url: callbackUrl,
      plan_type: "rent",
      number_of_deductions: null,
      amount_cents: spec.amountCents,
      use_transaction_amount: true,
      is_active: true,
      integration: motoIntegrationId,
    }),
  });
  return await responseJson<PaymobPlan>(response);
}

const token = await authToken();
const plans = await listPlans(token);
const specs: PlanSpec[] = [
  {
    envName: "PAYMOB_SOLO_MONTHLY_PLAN_ID",
    name: "Ledger Suit Solo Monthly",
    frequency: 30,
    amountCents: 39900,
  },
  {
    envName: "PAYMOB_SOLO_YEARLY_PLAN_ID",
    name: "Ledger Suit Solo Yearly",
    frequency: 360,
    amountCents: 325584,
  },
  {
    envName: "PAYMOB_STARTER_MONTHLY_PLAN_ID",
    name: "Ledger Suit Starter Monthly",
    frequency: 30,
    amountCents: 59900,
  },
  {
    envName: "PAYMOB_STARTER_YEARLY_PLAN_ID",
    name: "Ledger Suit Starter Yearly",
    frequency: 360,
    amountCents: 488784,
  },
  {
    envName: "PAYMOB_BUSINESS_MONTHLY_PLAN_ID",
    name: "Ledger Suit Business Monthly",
    frequency: 30,
    amountCents: 109900,
  },
  {
    envName: "PAYMOB_BUSINESS_YEARLY_PLAN_ID",
    name: "Ledger Suit Business Yearly",
    frequency: 360,
    amountCents: 896784,
  },
];
const readyPlans = await Promise.all(
  specs.map(async (spec) => ({
    spec,
    plan: await ensurePlan(token, plans, spec),
  })),
);

console.log("Paymob subscription plans are ready:");
for (const { spec, plan } of readyPlans) {
  console.log(`${spec.envName}="${plan.id}"`);
}
