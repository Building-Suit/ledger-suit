import type { FlatConfigComposer } from "../node_modules/.pnpm/eslint-flat-config-utils@3.2.0/node_modules/eslint-flat-config-utils/dist/index.mjs"
import { defineFlatConfigs } from "../node_modules/.pnpm/@nuxt+eslint-config@1.17.0_@typescript-eslint+utils@8.68.0_eslint@9.39.5_jiti@2.7.0__ty_903a1563afb1f0d5dff58eba1b010aeb/node_modules/@nuxt/eslint-config/dist/flat.mjs"
import type { NuxtESLintConfigOptionsResolved } from "../node_modules/.pnpm/@nuxt+eslint-config@1.17.0_@typescript-eslint+utils@8.68.0_eslint@9.39.5_jiti@2.7.0__ty_903a1563afb1f0d5dff58eba1b010aeb/node_modules/@nuxt/eslint-config/dist/flat.mjs"

declare const configs: FlatConfigComposer
declare const options: NuxtESLintConfigOptionsResolved
declare const withNuxt: typeof defineFlatConfigs
export default withNuxt
export { withNuxt, defineFlatConfigs, configs, options }