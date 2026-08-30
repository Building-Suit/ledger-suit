import { createStreamingPlugin as createStreamingPlugin$1 } from './unplugin.mjs';
export { VIRTUAL_CLIENT_ID, VIRTUAL_IIFE_ID, buildStreamingPluginOptions } from './unplugin.mjs';
import 'unplugin';

function createStreamingPlugin(options) {
  return createStreamingPlugin$1.vite(options);
}

export { createStreamingPlugin };
