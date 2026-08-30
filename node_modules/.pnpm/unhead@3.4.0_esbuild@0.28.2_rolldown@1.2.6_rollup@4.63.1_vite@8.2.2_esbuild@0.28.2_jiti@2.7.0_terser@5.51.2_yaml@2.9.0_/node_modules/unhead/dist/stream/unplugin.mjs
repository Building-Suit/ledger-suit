import { createUnplugin } from 'unplugin';

const VIRTUAL_CLIENT_ID = "virtual:@unhead/streaming-client";
const VIRTUAL_IIFE_ID = "virtual:@unhead/streaming-iife.js";
const RESOLVED_ID = `\0${VIRTUAL_CLIENT_ID}`;
const RESOLVED_IIFE_ID = `\0${VIRTUAL_IIFE_ID}`;
const VIRTUAL_RE = /virtual:@unhead\/streaming/;
const RESOLVED_RE = /^\0virtual:@unhead\/streaming/;
let iifeCode;
let iifeCodeLoading;
async function loadIifeCode() {
  if (iifeCode)
    return;
  iifeCodeLoading ||= import('unhead/stream/iife').then((mod) => {
    iifeCode = mod.streamingIifeCode;
  });
  await iifeCodeLoading;
}
function resolveNonce(nonce) {
  if (!nonce)
    return void 0;
  return typeof nonce === "function" ? nonce() : nonce;
}
function buildClientStub(framework, streamKey, warnOnMissing) {
  const key = JSON.stringify(streamKey);
  const warnBranch = warnOnMissing ? `else{console.warn('[unhead] streaming client loaded but window['+${key}+'] is undefined; did the server call wrapStream()/renderSSRHeadShell()?')}` : "";
  return `import{createHead}from'${framework}/client'
const s=window[${key}];if(s){const q=s._q;s._q=[];const h=createHead({document});h._wrapped=!0;const p=b=>{for(const e of b){const a=h.push(e),t=h.entries.get(a._i);if(t)t._streamed=!0}};q.forEach(p);s.push=p;s._head=h}${warnBranch}`;
}
function buildStreamingPluginOptions(options, meta = {}) {
  const {
    framework,
    name,
    mode = "async",
    nonce,
    streamKey = "__unhead__",
    warnOnMissingServerBootstrap
  } = options;
  const state = {
    isVite: meta.framework === "vite",
    isBuild: false,
    ssr: false
  };
  function isSSRCall(hookThis, opts) {
    const envName = hookThis?.environment?.name;
    return envName === "ssr" || envName === "server" || opts?.ssr === true || state.ssr;
  }
  function warnEnabled() {
    return warnOnMissingServerBootstrap ?? !state.isBuild;
  }
  function resolveEmittedIifePath(hookThis, ctx) {
    const ref = state.emittedIifeFileId;
    if (!ref)
      return;
    for (const asset of Object.values(ctx?.bundle || {})) {
      if (asset?.type === "asset" && asset.fileName && (asset.name === "unhead-streaming.js" || asset.names?.includes("unhead-streaming.js")))
        return asset.fileName;
    }
    if (typeof hookThis?.getFileName === "function") {
      const fileName = hookThis.getFileName(ref);
      if (fileName && fileName !== ref)
        return fileName;
    }
  }
  return {
    name: name ?? `${framework}:streaming`,
    enforce: "pre",
    async buildStart() {
      if (!state.isVite || mode === "module")
        return;
      await loadIifeCode();
      if (mode === "async" && state.isBuild && typeof this.emitFile === "function") {
        if (!iifeCode)
          throw new Error("[unhead] Streaming IIFE not built. Run `pnpm build` in packages/unhead first.");
        state.emittedIifeFileId = this.emitFile({
          type: "asset",
          name: "unhead-streaming.js",
          source: iifeCode
        });
      }
    },
    resolveId: {
      filter: { id: VIRTUAL_RE },
      handler(id) {
        if (id === VIRTUAL_CLIENT_ID || id === `/${VIRTUAL_CLIENT_ID}`)
          return RESOLVED_ID;
        if (state.isVite && (id === VIRTUAL_IIFE_ID || id === `/${VIRTUAL_IIFE_ID}`))
          return RESOLVED_IIFE_ID;
      }
    },
    load: {
      filter: { id: RESOLVED_RE },
      handler(id, opts) {
        const isSSR = isSSRCall(this, opts);
        if (id === RESOLVED_ID) {
          if (isSSR)
            return { code: "export {}", moduleType: "js" };
          return {
            code: buildClientStub(framework, streamKey, warnEnabled()),
            moduleType: "js"
          };
        }
        if (id === RESOLVED_IIFE_ID) {
          if (!state.isVite)
            return;
          if (isSSR)
            return { code: "", moduleType: "js" };
          if (!iifeCode)
            throw new Error("[unhead] Streaming IIFE not built. Run `pnpm build` in packages/unhead first.");
          return { code: iifeCode, moduleType: "js" };
        }
      }
    },
    ...options.transform && options.filter ? {
      transform: {
        filter: options.codeFilter ? { id: options.filter, code: options.codeFilter } : { id: options.filter },
        handler(code, id, opts) {
          return options.transform(code, id, { ssr: isSSRCall(this, opts) });
        }
      }
    } : {},
    webpack(compiler) {
      const { name: n, target } = compiler.options;
      if (n === "server" || target === "node" || target === "async-node")
        state.ssr = true;
    },
    rspack(compiler) {
      const { name: n, target } = compiler.options;
      if (n === "server" || target === "node" || target === "async-node")
        state.ssr = true;
    },
    vite: {
      apply(_config, env) {
        state.isVite = true;
        if (env.isSsrBuild)
          state.ssr = true;
        if (env.command === "build")
          state.isBuild = true;
        return true;
      },
      configResolved(config) {
        state.isVite = true;
        if (config.command === "build")
          state.isBuild = true;
      },
      transformIndexHtml: {
        // `order: 'pre'` is separate from the plugin-level `enforce: 'pre'`:
        // it runs this HTML transform before other non-pre HTML transforms
        // so the virtual module `<script>` tags we inject go through the
        // full Vite plugin pipeline (resolveId/load) and aren't stripped or
        // rewritten by downstream HTML transforms.
        order: "pre",
        handler(_html, ctx) {
          const nonceValue = resolveNonce(nonce);
          const nonceAttr = nonceValue ? { nonce: nonceValue } : {};
          if (mode === "inline") {
            if (!iifeCode)
              throw new Error("[unhead] Streaming IIFE not built. Run `pnpm build` in packages/unhead first.");
            return [{
              tag: "script",
              attrs: nonceAttr,
              children: iifeCode,
              injectTo: "head-prepend"
            }];
          }
          if (mode === "async") {
            const fileName = state.isBuild ? resolveEmittedIifePath(this, ctx) : void 0;
            const src = fileName ? `/${fileName}` : `/${VIRTUAL_IIFE_ID}`;
            return [{
              tag: "script",
              attrs: { ...nonceAttr, async: true, src },
              injectTo: "head-prepend"
            }];
          }
          return [{
            tag: "script",
            attrs: nonceAttr,
            children: `import("/${VIRTUAL_CLIENT_ID}")`,
            injectTo: "head-prepend"
          }];
        }
      }
    }
  };
}
const createStreamingPlugin = /* @__PURE__ */ createUnplugin(buildStreamingPluginOptions);

export { VIRTUAL_CLIENT_ID, VIRTUAL_IIFE_ID, buildStreamingPluginOptions, createStreamingPlugin };
