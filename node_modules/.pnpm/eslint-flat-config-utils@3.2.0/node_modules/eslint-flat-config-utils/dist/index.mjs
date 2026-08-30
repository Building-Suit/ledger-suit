import { defineConfig } from '@eslint/config-helpers';

function hijackPluginRule(plugin, name, factory) {
  const original = plugin.rules?.[name];
  if (!original) {
    throw new Error(`Rule "${name}" not found in plugin "${plugin.meta?.name || plugin.name}"`);
  }
  const patched = factory(original);
  if (patched !== plugin.rules[name])
    plugin.rules[name] = patched;
  return plugin;
}
const disabledRuleFixes = /* @__PURE__ */ new WeakSet();
function disableRuleFixes(rule) {
  if (disabledRuleFixes.has(rule)) {
    return rule;
  }
  const originalCreate = rule.create.bind(rule);
  rule.create = (context) => {
    const clonedContext = { ...context };
    const proxiedContext = new Proxy(clonedContext, {
      get(target, prop, receiver) {
        if (prop === "report") {
          return function(report) {
            if (report.fix) {
              delete report.fix;
            }
            return Reflect.get(context, prop, receiver)({
              ...report,
              fix: void 0
            });
          };
        }
        return Reflect.get(context, prop, receiver);
      },
      set(target, prop, value, receiver) {
        return Reflect.set(context, prop, value, receiver);
      }
    });
    const proxy = originalCreate(proxiedContext);
    return proxy;
  };
  disabledRuleFixes.add(rule);
  return rule;
}

function mergeConfigs(...configs) {
  const keys = new Set(configs.flatMap((i) => Object.keys(i)));
  const merged = configs.reduce((acc, cur) => {
    return {
      ...acc,
      ...cur,
      files: [
        ...acc.files || [],
        ...cur.files || []
      ],
      ignores: [
        ...acc.ignores || [],
        ...cur.ignores || []
      ],
      plugins: {
        ...acc.plugins,
        ...cur.plugins
      },
      rules: {
        ...acc.rules,
        ...cur.rules
      },
      languageOptions: {
        ...acc.languageOptions,
        ...cur.languageOptions
      },
      linterOptions: {
        ...acc.linterOptions,
        ...cur.linterOptions
      }
    };
  }, {});
  for (const key of Object.keys(merged)) {
    if (!keys.has(key))
      delete merged[key];
  }
  return merged;
}
function mergePlugins(...plugins) {
  const uniquePlugins = [...new Set(plugins)];
  if (uniquePlugins.length <= 1)
    return uniquePlugins[0];
  const shallowMergeInto = (a, b) => Object.assign(a, b);
  const mergedPlugin = {
    meta: {
      name: `merged plugin of [${uniquePlugins.map((p) => p.meta?.name ?? p.name ?? "unnamed").join(", ")}]`
    }
  };
  const environments = new Set(uniquePlugins.map((p) => p?.environments).filter((a) => a !== void 0));
  if (environments.size > 0) {
    mergedPlugin.environments = [...environments].reduce(shallowMergeInto, {});
  }
  const languages = new Set(uniquePlugins.map((p) => p?.languages).filter((a) => a !== void 0));
  if (languages.size > 0) {
    mergedPlugin.languages = [...languages].reduce(shallowMergeInto, {});
  }
  const processors = new Set(uniquePlugins.map((p) => p?.processors).filter((a) => a !== void 0));
  if (processors.size > 0) {
    mergedPlugin.processors = [...processors].reduce(shallowMergeInto, {});
  }
  const rules = new Set(uniquePlugins.map((p) => p?.rules).filter((a) => a !== void 0));
  if (rules.size > 0) {
    mergedPlugin.rules = [...rules].reduce(shallowMergeInto, {});
  }
  return mergedPlugin;
}

function parseRuleId(ruleId) {
  let plugin;
  let rule = ruleId;
  if (ruleId.includes("/")) {
    if (ruleId.startsWith("@")) {
      plugin = ruleId.slice(0, ruleId.lastIndexOf("/"));
    } else {
      plugin = ruleId.slice(0, ruleId.indexOf("/"));
    }
    rule = ruleId.slice(plugin.length + 1);
  } else {
    plugin = null;
    rule = ruleId;
  }
  return {
    plugin,
    rule
  };
}

function renamePluginsInRules(rules, map) {
  const entries = Object.entries(map).sort(([a], [b]) => b.length - a.length);
  return Object.fromEntries(
    Object.entries(rules).map(([key, value]) => {
      for (const [from, to] of entries) {
        if (key.startsWith(`${from}/`))
          return [to + key.slice(from.length), value];
      }
      return [key, value];
    })
  );
}
function renamePluginsInConfigs(configs, map, options) {
  return configs.map((i) => {
    const clone = { ...i };
    if (clone.rules)
      clone.rules = renamePluginsInRules(clone.rules, map);
    if (clone.plugins) {
      const renamed = Object.entries(clone.plugins).map(([key, value]) => {
        if (key in map)
          return [map[key], value];
        return [key, value];
      });
      const grouped = Object.groupBy(renamed, (entry) => entry[0]);
      const shouldMerge = options?.mergePlugins ?? false;
      clone.plugins = Object.fromEntries(
        Object.entries(grouped).map(([key, values]) => {
          if (shouldMerge)
            return [key, mergePlugins(...values.map((entry) => entry[1]))];
          if (values.length > 1)
            console.warn(`ESLintFlatConfigUtils: Trying to rename multiple plugins to the name "${key}", using the last one`);
          return values.at(-1);
        })
      );
    }
    return clone;
  });
}

const RE_PLUGIN_NAME = /\{\{pluginName\}\}/g;
const RE_CONFIG_NAME1 = /\{\{configName1\}\}/g;
const RE_CONFIG_NAME2 = /\{\{configName2\}\}/g;
const RE_CONFIG_NAMES = /\{\{configNames\}\}/g;
const DEFAULT_PLUGIN_CONFLICTS_ERROR = `Different instances of plugin "{{pluginName}}" found in multiple configs: {{configNames}}. It's likely you misconfigured the merge of these configs.`;
function composer(...configs) {
  return new FlatConfigComposer(
    ...configs
  );
}
class FlatConfigComposer extends Promise {
  _operations = [];
  _operationsOverrides = [];
  _operationsResolved = [];
  _renames = {};
  _renamesOptions;
  _defaultIgnores = [];
  _pluginsConflictsError = /* @__PURE__ */ new Map();
  constructor(...configs) {
    super(() => {
    });
    if (configs.length)
      this.append(...configs);
  }
  /**
   * Set plugin renames, like `n` -> `node`, `import-x` -> `import`, etc.
   *
   * This will runs after all config items are resolved. Applies to `plugins` and `rules`.
   */
  renamePlugins(renames, options) {
    Object.assign(this._renames, renames);
    this._renamesOptions = options;
    return this;
  }
  /**
   * Set default `ignores` globs for configs that have rules but no explicit
   * scoping (`files` / `ignores` / `language`).
   *
   * The callback receives the composer's previously-accumulated globs and
   * returns the new list, so calls compose:
   *
   * ```ts
   * composer
   *   .setDefaultIgnores(() => ['**\/*.md'])
   *   .setDefaultIgnores(prev => [...prev, '**\/*.json'])
   * ```
   *
   * Useful when mixing fundamentally different languages (e.g. JS + Markdown)
   * and you want global rule configs to not "leak" into a foreign language
   * whose `SourceCode` lacks JS-only methods.
   */
  setDefaultIgnores(fn) {
    this._defaultIgnores = fn(this._defaultIgnores);
    return this;
  }
  /**
   * Absorb another composer's accumulated state when it is appended/prepended/etc.
   * into this one, so renames and default-ignores globs declared on the inner
   * composer apply to the parent's other configs as well.
   */
  _absorbComposer(other) {
    this._renames = { ...other._renames, ...this._renames };
    if (!this._renamesOptions && other._renamesOptions)
      this._renamesOptions = other._renamesOptions;
    this._defaultIgnores = [.../* @__PURE__ */ new Set([...this._defaultIgnores, ...other._defaultIgnores])];
  }
  /**
   * Append configs to the end of the current configs array.
   */
  append(...items) {
    for (const item of items) {
      if (item instanceof FlatConfigComposer)
        this._absorbComposer(item);
    }
    const promise = Promise.all(items);
    this._operations.push(async (configs) => {
      const resolved = (await promise).flat().filter(Boolean);
      return [...configs, ...resolved];
    });
    return this;
  }
  /**
   * Prepend configs to the beginning of the current configs array.
   */
  prepend(...items) {
    for (const item of items) {
      if (item instanceof FlatConfigComposer)
        this._absorbComposer(item);
    }
    const promise = Promise.all(items);
    this._operations.push(async (configs) => {
      const resolved = (await promise).flat().filter(Boolean);
      return [...resolved, ...configs];
    });
    return this;
  }
  /**
   * Insert configs before a specific config.
   */
  insertBefore(nameOrIndex, ...items) {
    for (const item of items) {
      if (item instanceof FlatConfigComposer)
        this._absorbComposer(item);
    }
    const promise = Promise.all(items);
    this._operations.push(async (configs) => {
      const resolved = (await promise).flat().filter(Boolean);
      const index = getConfigIndex(configs, nameOrIndex);
      configs.splice(index, 0, ...resolved);
      return configs;
    });
    return this;
  }
  /**
   * Insert configs after a specific config.
   */
  insertAfter(nameOrIndex, ...items) {
    for (const item of items) {
      if (item instanceof FlatConfigComposer)
        this._absorbComposer(item);
    }
    const promise = Promise.all(items);
    this._operations.push(async (configs) => {
      const resolved = (await promise).flat().filter(Boolean);
      const index = getConfigIndex(configs, nameOrIndex);
      configs.splice(index + 1, 0, ...resolved);
      return configs;
    });
    return this;
  }
  /**
   * Provide overrides to a specific config.
   *
   * It will be merged with the original config, or provide a custom function to replace the config entirely.
   */
  override(nameOrIndex, config) {
    this._operationsOverrides.push(async (configs) => {
      const index = getConfigIndex(configs, nameOrIndex);
      const extended = typeof config === "function" ? await config(configs[index]) : mergeConfigs(configs[index], config);
      configs.splice(index, 1, extended);
      return configs;
    });
    return this;
  }
  /**
   * Provide overrides to multiple configs as an object map.
   *
   * Same as calling `override` multiple times.
   */
  overrides(overrides) {
    for (const [name, config] of Object.entries(overrides)) {
      if (config)
        this.override(name, config);
    }
    return this;
  }
  /**
   * Override rules and it's options in **all configs**.
   *
   * Pass `null` as the value to remove the rule.
   *
   * @example
   * ```ts
   * composer
   *   .overrideRules({
   *      'no-console': 'off',
   *      'no-unused-vars': ['error', { vars: 'all', args: 'after-used' }],
   *      // remove the rule from all configs
   *      'no-undef': null,
   *   })
   * ```
   */
  overrideRules(rules) {
    this._operationsOverrides.push(async (configs) => {
      for (const config of configs) {
        if (!("rules" in config) || !config.rules)
          continue;
        const configRules = config.rules;
        for (const [key, value] of Object.entries(rules)) {
          if (!(key in configRules))
            continue;
          if (value == null)
            delete configRules[key];
          else
            configRules[key] = value;
        }
      }
      return configs;
    });
    return this;
  }
  /**
   * Remove rules from **all configs**.
   *
   * @example
   * ```ts
   * composer
   *  .removeRules(
   *    'no-console',
   *    'no-unused-vars'
   *  )
   * ```
   */
  removeRules(...rules) {
    return this.overrideRules(Object.fromEntries(
      rules.map((rule) => [rule, null])
    ));
  }
  /**
   * Remove plugins by name and all the rules referenced by them.
   *
   * @example
   * ```ts
   * composer
   *   .removePlugins(
   *     'node'
   *   )
   * ```
   *
   * The `plugins: { node }` and `rules: { 'node/xxx': 'error' }` will be removed from all configs.
   */
  removePlugins(...names) {
    this._operationsOverrides.push(async (configs) => {
      for (const config of configs) {
        if ("plugins" in config && typeof config.plugins === "object" && config.plugins) {
          for (const name of names) {
            if (name in config.plugins)
              delete config.plugins[name];
          }
        }
        if ("rules" in config && typeof config.rules === "object" && config.rules) {
          for (const key of Object.keys(config.rules)) {
            if (names.some((n) => key.startsWith(`${n}/`)))
              delete config.rules[key];
          }
        }
      }
      return configs;
    });
    return this;
  }
  /**
   * Remove a specific config by name or index.
   */
  remove(nameOrIndex) {
    this._operations.push(async (configs) => {
      const index = getConfigIndex(configs, nameOrIndex);
      configs.splice(index, 1);
      return configs;
    });
    return this;
  }
  /**
   * Replace a plugin with another.
   *
   * @example
   * ```ts
   * composer
   *   .replacePlugin('foo', (fooPlugin) => ({
   *     ...fooPlugin,
   *     rules: {
   *       ...fooPlugin.rules,
   *       someNewRule,
   *     },
   *   }))
   * ```
   *
   * The `plugins: { foo }` will be replaced from all configs with a new plugin that is a merge of it and the `bar` plugin
   */
  replacePlugin(name, replacement) {
    this._operationsOverrides.push(async (configs) => {
      for (const config of configs) {
        if ("plugins" in config && typeof config.plugins === "object" && config.plugins) {
          if (name in config.plugins) {
            const value = typeof replacement === "function" ? replacement(config.plugins[name]) : replacement;
            config.plugins[name] = await value;
          }
        }
      }
      return configs;
    });
    return this;
  }
  /**
   * Replace a specific config by name or index.
   *
   * The original config will be removed and replaced with the new one.
   */
  replace(nameOrIndex, ...items) {
    for (const item of items) {
      if (item instanceof FlatConfigComposer)
        this._absorbComposer(item);
    }
    const promise = Promise.all(items);
    this._operations.push(async (configs) => {
      const resolved = (await promise).flat().filter(Boolean);
      const index = getConfigIndex(configs, nameOrIndex);
      configs.splice(index, 1, ...resolved);
      return configs;
    });
    return this;
  }
  /**
   * Hijack into plugins to disable fixes for specific rules.
   *
   * Note this mutates the plugin object, use with caution.
   *
   * @example
   * ```ts
   * const config = await composer(...)
   *  .disableRulesFix([
   *    'unused-imports/no-unused-imports',
   *    'vitest/no-only-tests'
   *  ])
   * ```
   */
  disableRulesFix(ruleIds, options = {}) {
    this._operations.push(async (configs) => {
      for (const name of ruleIds) {
        const parsed = parseRuleId(name);
        if (!parsed.plugin) {
          if (!options.builtinRules)
            throw new Error(`Patching core rule "${name}" require pass \`{ builtinRules: () => import('eslint/use-at-your-own-risk').then(r => r.builtinRules) }\` in the options`);
          const builtinRules = typeof options.builtinRules === "function" ? await options.builtinRules() : options.builtinRules;
          const rule = builtinRules.get(name);
          if (!rule)
            throw new Error(`Rule "${name}" not found in core rules`);
          disableRuleFixes(rule);
        } else {
          const plugins = new Set(configs.map((c) => c.plugins?.[parsed.plugin]).filter((x) => !!x));
          for (const plugin of plugins) {
            hijackPluginRule(plugin, parsed.rule, (rule) => disableRuleFixes(rule));
          }
        }
      }
      return configs;
    });
    return this;
  }
  setPluginConflictsError(arg1 = DEFAULT_PLUGIN_CONFLICTS_ERROR, arg2) {
    if (arg2 != null)
      this._pluginsConflictsError.set(arg1, arg2);
    else
      this._pluginsConflictsError.set("*", arg1);
    return this;
  }
  _verifyPluginsConflicts(configs) {
    if (!this._pluginsConflictsError.size)
      return;
    const plugins = /* @__PURE__ */ new Map();
    const names = /* @__PURE__ */ new Set();
    for (const config of configs) {
      if (!config.plugins)
        continue;
      for (const [name, plugin] of Object.entries(config.plugins)) {
        names.add(name);
        if (!plugins.has(plugin))
          plugins.set(plugin, { name, configs: [] });
        plugins.get(plugin).configs.push(config);
      }
    }
    function getConfigName(config) {
      return config.name || `#${configs.indexOf(config)}`;
    }
    const errors = [];
    for (const name of names) {
      const instancesOfName = [...plugins.values()].filter((p) => p.name === name);
      if (instancesOfName.length <= 1)
        continue;
      const configsOfName = instancesOfName.map((p) => p.configs[0]);
      const message = this._pluginsConflictsError.get(name) || this._pluginsConflictsError.get("*");
      if (typeof message === "function") {
        errors.push(message(name, configsOfName));
      } else if (message) {
        errors.push(
          message.replace(RE_PLUGIN_NAME, name).replace(RE_CONFIG_NAME1, getConfigName(configsOfName[0])).replace(RE_CONFIG_NAME2, getConfigName(configsOfName[1])).replace(RE_CONFIG_NAMES, configsOfName.map(getConfigName).join(", "))
        );
      }
    }
    if (errors.length) {
      if (errors.length === 1)
        throw new Error(`ESLintFlatConfigUtils: ${errors[0]}`);
      else
        throw new Error(`ESLintFlatConfigUtils:
${errors.map((e, i) => `  ${i + 1}: ${e}`).join("\n")}`);
    }
  }
  /**
   * Hook when all configs are resolved but before returning the final configs.
   *
   * You can modify the final configs here.
   */
  onResolved(callback) {
    this._operationsResolved.push(callback);
    return this;
  }
  /**
   * Clone the composer object.
   */
  clone() {
    const composer2 = new FlatConfigComposer();
    composer2._operations = this._operations.slice();
    composer2._operationsOverrides = this._operationsOverrides.slice();
    composer2._operationsResolved = this._operationsResolved.slice();
    composer2._renames = { ...this._renames };
    composer2._renamesOptions = this._renamesOptions;
    composer2._defaultIgnores = this._defaultIgnores.slice();
    composer2._pluginsConflictsError = new Map(this._pluginsConflictsError);
    return composer2;
  }
  /**
   * Resolve the pipeline and return the final configs.
   *
   * This returns a promise. Calling `.then()` has the same effect.
   */
  async toConfigs() {
    let configs = [];
    for (const promise of this._operations)
      configs = await promise(configs);
    for (const promise of this._operationsOverrides)
      configs = await promise(configs);
    configs = renamePluginsInConfigs(configs, this._renames, this._renamesOptions);
    if (this._defaultIgnores.length) {
      for (const config of configs) {
        if (!config.rules || Object.keys(config.rules).length === 0)
          continue;
        if (config.files)
          continue;
        if (config.ignores)
          continue;
        if (config.language)
          continue;
        config.ignores = [...this._defaultIgnores];
      }
    }
    for (const promise of this._operationsResolved)
      configs = await promise(configs) || configs;
    const resolved = defineConfig(configs);
    this._verifyPluginsConflicts(resolved);
    return resolved;
  }
  then(onFulfilled, onRejected) {
    return this.toConfigs().then(onFulfilled, onRejected);
  }
  // eslint-disable-next-line ts/explicit-function-return-type
  catch(onRejected) {
    return this.toConfigs().catch(onRejected);
  }
  finally(onFinally) {
    return this.toConfigs().finally(onFinally);
  }
}
function getConfigIndex(configs, nameOrIndex) {
  if (typeof nameOrIndex === "number") {
    if (nameOrIndex < 0 || nameOrIndex >= configs.length)
      throw new Error(`ESLintFlatConfigUtils: Failed to locate config at index ${nameOrIndex}
(${configs.length} configs in total)`);
    return nameOrIndex;
  } else {
    const index = configs.findIndex((config) => config.name === nameOrIndex);
    if (index === -1) {
      const named = configs.map((config) => config.name).filter(Boolean);
      const countUnnamed = configs.length - named.length;
      const messages = [
        `Failed to locate config with name "${nameOrIndex}"`,
        `Available names are: ${named.join(", ")}`,
        countUnnamed ? `(${countUnnamed} unnamed configs)` : ""
      ].filter(Boolean).join("\n");
      throw new Error(`ESLintFlatConfigUtils: ${messages}`);
    }
    return index;
  }
}
const pipe = composer;
class FlatConfigPipeline extends FlatConfigComposer {
}

async function concat(...configs) {
  const resolved = await Promise.all(configs);
  return resolved.flat();
}

function defineFlatConfig(config) {
  return config;
}

async function extend(configs, relativePath) {
  const { join } = await import('pathe');
  const resolved = await configs;
  if (relativePath === "")
    return resolved;
  function renameGlobs(i) {
    if (typeof i !== "string")
      return i;
    if (i.startsWith("!"))
      return `!${join(relativePath, i.slice(1))}`;
    return join(relativePath, i);
  }
  return resolved.map((i) => {
    if (!i || !i.files && !i.ignores)
      return i;
    const clone = { ...i };
    if (clone.files) {
      clone.files = clone.files.map(
        (f) => Array.isArray(f) ? f.map((t) => renameGlobs(t)) : renameGlobs(f)
      );
    }
    if (clone.ignores) {
      clone.ignores = clone.ignores.map(
        (f) => renameGlobs(f)
      );
    }
    return clone;
  });
}

export { DEFAULT_PLUGIN_CONFLICTS_ERROR, FlatConfigComposer, FlatConfigPipeline, composer, concat, defineFlatConfig, disableRuleFixes, extend, hijackPluginRule, mergeConfigs, mergePlugins, parseRuleId, pipe, renamePluginsInConfigs, renamePluginsInRules };
