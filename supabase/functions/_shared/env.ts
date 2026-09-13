export function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing server secret: ${name}`);
  return value;
}
