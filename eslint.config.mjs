import withNuxt from './.nuxt/eslint.config.mjs'

export default withNuxt({
  // `supabase/.temp` holds generated runtime scaffolding written by the
  // Supabase CLI. It is not our source and is not committed.
  ignores: ['supabase/.temp/**', 'types/database.types.ts'],
})
