import withNuxt from './.nuxt/eslint.config.mjs'

export default withNuxt({
  // `supabase/.temp` holds generated runtime scaffolding written by the
  // Supabase CLI. It is not our source and is not committed.
  // Edge Functions are checked by Deno in their own runtime. Nuxt's browser
  // globals and module resolver do not understand Deno.serve or npm: imports.
  ignores: ['supabase/.temp/**', 'supabase/functions/**', 'types/database.types.ts'],
})
