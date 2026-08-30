import { u as useSupabaseUser, n as navigateTo } from '../virtual/entry.mjs';
import { u as useSupabaseClient } from './useSupabaseClient-CiQT_e2V.mjs';
import { defineComponent, ref, watchEffect, mergeProps, unref, useSSRContext } from 'vue';
import { ssrRenderAttrs, ssrRenderAttr, ssrInterpolate, ssrIncludeBooleanAttr } from 'vue/server-renderer';
import '../nitro/nitro.mjs';
import 'node:http';
import 'node:https';
import 'node:events';
import 'node:buffer';
import 'node:fs';
import 'node:path';
import 'node:crypto';
import 'node:url';
import '../routes/renderer.mjs';
import 'unhead/server';
import 'unhead/legacy';
import 'unhead/plugins';
import 'nostics';
import 'vue-bundle-renderer/runtime';
import 'devalue';
import 'vue-router';
import 'unhead/utils';

//#region app/pages/login.vue?vue&type=script&setup=true&lang.ts
var login_vue_vue_type_script_setup_true_lang_default = /*@__PURE__*/ defineComponent({
	__name: "login",
	__ssrInlineRender: true,
	setup(__props) {
		useSupabaseClient();
		const user = useSupabaseUser();
		const email = ref("");
		const password = ref("");
		const pending = ref(false);
		const error = ref(null);
		watchEffect(() => {
			if (user.value) navigateTo("/");
		});
		return (_ctx, _push, _parent, _attrs) => {
			_push(`<main${ssrRenderAttrs(mergeProps({ class: "grid min-h-dvh place-items-center px-4" }, _attrs))}><form class="w-full max-w-sm space-y-5 rounded-xl border border-neutral-200 bg-white p-8 dark:border-neutral-800 dark:bg-neutral-900"><div><h1 class="text-xl font-semibold">Ledger Suit</h1><p class="mt-1 text-sm text-neutral-500">Sign in to your organization.</p></div><div class="space-y-1"><label for="email" class="block text-sm font-medium">Email</label><input id="email"${ssrRenderAttr("value", unref(email))} type="email" autocomplete="email" required class="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm focus:border-neutral-900 focus:outline-2 focus:outline-offset-2 focus:outline-neutral-900 dark:border-neutral-700 dark:bg-neutral-950"></div><div class="space-y-1"><label for="password" class="block text-sm font-medium">Password</label><input id="password"${ssrRenderAttr("value", unref(password))} type="password" autocomplete="current-password" required class="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm focus:border-neutral-900 focus:outline-2 focus:outline-offset-2 focus:outline-neutral-900 dark:border-neutral-700 dark:bg-neutral-950"></div>`);
			if (unref(error)) _push(`<p role="alert" class="text-sm text-red-600">${ssrInterpolate(unref(error))}</p>`);
			else _push(`<!---->`);
			_push(`<button type="submit"${ssrIncludeBooleanAttr(unref(pending)) ? " disabled" : ""} class="w-full rounded-md bg-neutral-900 px-3 py-2 text-sm font-medium text-white disabled:opacity-50 dark:bg-white dark:text-neutral-900">${ssrInterpolate(unref(pending) ? "Signing in…" : "Sign in")}</button></form></main>`);
		};
	}
});
//#endregion
//#region app/pages/login.vue
var _sfc_setup = login_vue_vue_type_script_setup_true_lang_default.setup;
login_vue_vue_type_script_setup_true_lang_default.setup = (props, ctx) => {
	const ssrContext = useSSRContext();
	(ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/login.vue");
	return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};
var login_default = login_vue_vue_type_script_setup_true_lang_default;

export { login_default as default };
//# sourceMappingURL=login-Dv97gahO.mjs.map
