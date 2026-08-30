import stylistic$1 from '@stylistic/eslint-plugin';
import { g as GLOB_SRC, i as GLOB_VUE } from '../shared/eslint-config.BPH_F8lM.mjs';

const stylistic = (options) => {
  return {
    name: "nuxt/stylistic",
    files: [GLOB_SRC, GLOB_VUE],
    ...stylistic$1.configs.customize(options)
  };
};

export { stylistic as default };
