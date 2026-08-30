import { configs } from 'eslint-plugin-regexp';
import { g as GLOB_SRC, i as GLOB_VUE } from '../shared/eslint-config.BPH_F8lM.mjs';

function regexp() {
  return [
    {
      ...configs["flat/recommended"],
      name: "nuxt/tooling/regexp",
      files: [GLOB_SRC, GLOB_VUE]
    }
  ];
}

export { regexp as default };
