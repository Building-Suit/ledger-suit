Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });
let ufo = require("ufo");
//#region src/runtime.ts
function createRendererContext({ manifest, precomputed, buildAssetsURL, dependencySetsCacheSize }) {
	if (!manifest && !precomputed) throw new Error("Either manifest or precomputed data must be provided");
	const ctx = {
		buildAssetsURL: buildAssetsURL || ufo.withLeadingSlash,
		manifest,
		precomputed,
		updateManifest,
		_dependencies: {},
		_dependencySets: /* @__PURE__ */ new Map(),
		_dependencySetsCacheSize: typeof dependencySetsCacheSize === "number" && Number.isFinite(dependencySetsCacheSize) && dependencySetsCacheSize > 0 ? Math.floor(dependencySetsCacheSize) : dependencySetsCacheSize === void 0 ? 1e3 : 0,
		_entrypoints: [],
		_renderedCache: /* @__PURE__ */ new WeakMap()
	};
	function updateManifest(manifest) {
		ctx.manifest = manifest;
		ctx._dependencies = {};
		ctx._dependencySets.clear();
		ctx._renderedCache = /* @__PURE__ */ new WeakMap();
		const entrypoints = [];
		for (const id in manifest) if (manifest[id].isEntry) entrypoints.push(id);
		ctx._entrypoints = entrypoints;
	}
	if (precomputed) {
		ctx._dependencies = precomputed.dependencies;
		ctx._entrypoints = precomputed.entrypoints;
	} else if (manifest) updateManifest(manifest);
	return ctx;
}
function getModuleDependencies(id, rendererContext) {
	if (rendererContext._dependencies[id]) return rendererContext._dependencies[id];
	const dependencies = rendererContext._dependencies[id] = {
		scripts: {},
		styles: {},
		preload: {},
		prefetch: {}
	};
	if (!rendererContext.manifest) return dependencies;
	const meta = rendererContext.manifest[id];
	if (!meta) return dependencies;
	if (meta.file) {
		dependencies.preload[id] = meta;
		if (meta.isEntry || meta.sideEffects) dependencies.scripts[id] = meta;
	}
	for (const css of meta.css || []) dependencies.styles[css] = dependencies.preload[css] = dependencies.prefetch[css] = rendererContext.manifest[css];
	for (const asset of meta.assets || []) dependencies.preload[asset] = dependencies.prefetch[asset] = rendererContext.manifest[asset];
	if (meta.imports) for (const depId of meta.imports) {
		const depDeps = getModuleDependencies(depId, rendererContext);
		Object.assign(dependencies.styles, depDeps.styles);
		Object.assign(dependencies.preload, depDeps.preload);
		Object.assign(dependencies.prefetch, depDeps.prefetch);
	}
	const filteredPreload = {};
	for (const id in dependencies.preload) {
		const dep = dependencies.preload[id];
		if (dep.preload) filteredPreload[id] = dep;
	}
	dependencies.preload = filteredPreload;
	return dependencies;
}
function getAllDependencies(ids, rendererContext) {
	const cacheSize = rendererContext._dependencySetsCacheSize;
	const useCache = cacheSize > 0;
	let cacheKey = "";
	if (useCache) {
		if (ids.size <= 1) for (const id of ids) cacheKey = id;
		else cacheKey = [...ids].sort().join(",");
		const cached = rendererContext._dependencySets.get(cacheKey);
		if (cached !== void 0) {
			if (rendererContext._dependencySets.size >= cacheSize) {
				rendererContext._dependencySets.delete(cacheKey);
				rendererContext._dependencySets.set(cacheKey, cached);
			}
			return cached;
		}
	}
	const allDeps = {
		scripts: {},
		styles: {},
		preload: {},
		prefetch: {}
	};
	for (const id of ids) {
		const deps = getModuleDependencies(id, rendererContext);
		Object.assign(allDeps.scripts, deps.scripts);
		Object.assign(allDeps.styles, deps.styles);
		Object.assign(allDeps.preload, deps.preload);
		Object.assign(allDeps.prefetch, deps.prefetch);
		const dynamicImports = rendererContext.manifest?.[id]?.dynamicImports || rendererContext.precomputed?.modules[id]?.dynamicImports;
		if (dynamicImports) for (const dynamicDepId of dynamicImports) {
			const dynamicDeps = getModuleDependencies(dynamicDepId, rendererContext);
			Object.assign(allDeps.prefetch, dynamicDeps.scripts);
			Object.assign(allDeps.prefetch, dynamicDeps.styles);
			Object.assign(allDeps.prefetch, dynamicDeps.preload);
		}
	}
	const mergedPreload = allDeps.preload;
	const styles = allDeps.styles;
	const filteredPrefetch = {};
	for (const id in allDeps.prefetch) {
		const dep = allDeps.prefetch[id];
		if (dep.prefetch && !(id in mergedPreload) && !(id in styles)) filteredPrefetch[id] = dep;
	}
	allDeps.prefetch = filteredPrefetch;
	const filteredPreload = {};
	for (const id in mergedPreload) if (!(id in styles)) filteredPreload[id] = mergedPreload[id];
	allDeps.preload = filteredPreload;
	if (useCache) {
		rendererContext._dependencySets.set(cacheKey, allDeps);
		if (rendererContext._dependencySets.size > cacheSize) {
			const oldest = rendererContext._dependencySets.keys().next().value;
			if (oldest !== void 0) rendererContext._dependencySets.delete(oldest);
		}
	}
	return allDeps;
}
function getRequestDependencies(ssrContext, rendererContext, options) {
	const excluded = options?.exclude ? new Set(options.exclude) : void 0;
	const hasExcluded = excluded && excluded.size > 0;
	if (!hasExcluded && ssrContext._requestDependencies) return ssrContext._requestDependencies;
	let ids;
	const requestIds = ssrContext.modules || ssrContext._registeredComponents;
	if (hasExcluded) {
		ids = /* @__PURE__ */ new Set();
		for (const id of rendererContext._entrypoints) if (!excluded.has(id)) ids.add(id);
		if (requestIds) {
			for (const id of requestIds) if (!excluded.has(id)) ids.add(id);
		}
	} else {
		ids = new Set(rendererContext._entrypoints);
		if (requestIds) for (const id of requestIds) ids.add(id);
	}
	const deps = getAllDependencies(ids, rendererContext);
	if (!hasExcluded) ssrContext._requestDependencies = deps;
	return deps;
}
function getRenderedOutputs(rendererContext, deps) {
	let entry = rendererContext._renderedCache.get(deps);
	if (!entry) {
		entry = {};
		rendererContext._renderedCache.set(deps, entry);
	}
	return entry;
}
function renderStyles(ssrContext, rendererContext) {
	const deps = getRequestDependencies(ssrContext, rendererContext);
	const rendered = getRenderedOutputs(rendererContext, deps);
	if (rendered.styles !== void 0) return rendered.styles;
	const { styles } = deps;
	let result = "";
	for (const key in styles) {
		const resource = styles[key];
		result += `<link rel="stylesheet" href="${rendererContext.buildAssetsURL(resource.file)}" crossorigin>`;
	}
	rendered.styles = result;
	return result;
}
function getResources(ssrContext, rendererContext) {
	return [...getPreloadLinks(ssrContext, rendererContext), ...getPrefetchLinks(ssrContext, rendererContext)];
}
function renderResourceHints(ssrContext, rendererContext, options) {
	const deps = getRequestDependencies(ssrContext, rendererContext, options);
	const rendered = getRenderedOutputs(rendererContext, deps);
	if (rendered.hints !== void 0) return rendered.hints;
	const { preload, prefetch } = deps;
	let result = "";
	for (const key in preload) {
		const resource = preload[key];
		const href = rendererContext.buildAssetsURL(resource.file);
		const rel = resource.module ? "modulepreload" : "preload";
		const crossorigin = resource.resourceType === "style" || resource.resourceType === "font" || resource.resourceType === "script" || resource.module ? " crossorigin" : "";
		if (resource.resourceType && resource.mimeType) result += `<link rel="${rel}" as="${resource.resourceType}" type="${resource.mimeType}"${crossorigin} href="${href}">`;
		else if (resource.resourceType) result += `<link rel="${rel}" as="${resource.resourceType}"${crossorigin} href="${href}">`;
		else result += `<link rel="${rel}"${crossorigin} href="${href}">`;
	}
	for (const key in prefetch) {
		const resource = prefetch[key];
		const href = rendererContext.buildAssetsURL(resource.file);
		const crossorigin = resource.resourceType === "style" || resource.resourceType === "font" || resource.resourceType === "script" || resource.module ? " crossorigin" : "";
		if (resource.resourceType && resource.mimeType) result += `<link rel="prefetch" as="${resource.resourceType}" type="${resource.mimeType}"${crossorigin} href="${href}">`;
		else if (resource.resourceType) result += `<link rel="prefetch" as="${resource.resourceType}"${crossorigin} href="${href}">`;
		else result += `<link rel="prefetch"${crossorigin} href="${href}">`;
	}
	rendered.hints = result;
	return result;
}
const NON_ASCII_RE = /[^\0-\u007F]+/g;
function renderResourceHeaders(ssrContext, rendererContext, options) {
	const deps = getRequestDependencies(ssrContext, rendererContext, options);
	const rendered = getRenderedOutputs(rendererContext, deps);
	if (rendered.headerLink !== void 0) return { link: rendered.headerLink };
	const { preload, prefetch } = deps;
	const links = [];
	for (const key in preload) {
		const resource = preload[key];
		let header = `<${rendererContext.buildAssetsURL(resource.file).replace(NON_ASCII_RE, encodeURIComponent)}>; rel="${resource.module ? "modulepreload" : "preload"}"`;
		if (resource.resourceType) header += `; as="${resource.resourceType}"`;
		if (resource.mimeType) header += `; type="${resource.mimeType}"`;
		if (resource.resourceType === "style" || resource.resourceType === "font" || resource.resourceType === "script" || resource.module) header += "; crossorigin";
		links.push(header);
	}
	for (const key in prefetch) {
		const resource = prefetch[key];
		let header = `<${rendererContext.buildAssetsURL(resource.file).replace(NON_ASCII_RE, encodeURIComponent)}>; rel="prefetch"`;
		if (resource.resourceType) header += `; as="${resource.resourceType}"`;
		if (resource.mimeType) header += `; type="${resource.mimeType}"`;
		if (resource.resourceType === "style" || resource.resourceType === "font" || resource.resourceType === "script" || resource.module) header += "; crossorigin";
		links.push(header);
	}
	rendered.headerLink = links.join(", ");
	return { link: rendered.headerLink };
}
function getPreloadLinks(ssrContext, rendererContext, options) {
	const { preload } = getRequestDependencies(ssrContext, rendererContext, options);
	const result = [];
	for (const key in preload) {
		const resource = preload[key];
		result.push({
			rel: resource.module ? "modulepreload" : "preload",
			as: resource.resourceType,
			type: resource.mimeType ?? null,
			crossorigin: resource.resourceType === "style" || resource.resourceType === "font" || resource.resourceType === "script" || resource.module ? "" : null,
			href: rendererContext.buildAssetsURL(resource.file)
		});
	}
	return result;
}
function getPrefetchLinks(ssrContext, rendererContext, options) {
	const { prefetch } = getRequestDependencies(ssrContext, rendererContext, options);
	const result = [];
	for (const key in prefetch) {
		const resource = prefetch[key];
		result.push({
			rel: "prefetch",
			as: resource.resourceType,
			type: resource.mimeType ?? null,
			crossorigin: resource.resourceType === "style" || resource.resourceType === "font" || resource.resourceType === "script" || resource.module ? "" : null,
			href: rendererContext.buildAssetsURL(resource.file)
		});
	}
	return result;
}
function renderScripts(ssrContext, rendererContext) {
	const deps = getRequestDependencies(ssrContext, rendererContext);
	const rendered = getRenderedOutputs(rendererContext, deps);
	if (rendered.scripts !== void 0) return rendered.scripts;
	const { scripts } = deps;
	let result = "";
	for (const key in scripts) {
		const resource = scripts[key];
		if (resource.module) result += `<script type="module" src="${rendererContext.buildAssetsURL(resource.file)}" crossorigin><\/script>`;
		else result += `<script src="${rendererContext.buildAssetsURL(resource.file)}" defer crossorigin><\/script>`;
	}
	rendered.scripts = result;
	return result;
}
function createRenderer(createApp, renderOptions) {
	const rendererContext = createRendererContext(renderOptions);
	return {
		rendererContext,
		async renderToString(ssrContext) {
			ssrContext._registeredComponents = ssrContext._registeredComponents || /* @__PURE__ */ new Set();
			const app = await (await Promise.resolve(createApp).then((r) => "default" in r ? r.default : r))(ssrContext);
			const html = await renderOptions.renderToString(app, ssrContext);
			const wrap = (fn) => () => fn(ssrContext, rendererContext);
			return {
				html,
				renderResourceHeaders: wrap(renderResourceHeaders),
				renderResourceHints: wrap(renderResourceHints),
				renderStyles: wrap(renderStyles),
				renderScripts: wrap(renderScripts)
			};
		}
	};
}
//#endregion
exports.createRenderer = createRenderer;
exports.createRendererContext = createRendererContext;
exports.getAllDependencies = getAllDependencies;
exports.getModuleDependencies = getModuleDependencies;
exports.getPrefetchLinks = getPrefetchLinks;
exports.getPreloadLinks = getPreloadLinks;
exports.getRequestDependencies = getRequestDependencies;
exports.getResources = getResources;
exports.renderResourceHeaders = renderResourceHeaders;
exports.renderResourceHints = renderResourceHints;
exports.renderScripts = renderScripts;
exports.renderStyles = renderStyles;
