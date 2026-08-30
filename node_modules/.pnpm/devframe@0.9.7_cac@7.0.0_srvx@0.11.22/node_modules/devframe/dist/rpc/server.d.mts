import { BirpcGroup, EventOptions } from "birpc";
//#region src/rpc/server.d.ts
declare function createRpcServer<ClientFunctions extends object = Record<string, never>, ServerFunctions extends object = Record<string, never>>(functions: ServerFunctions, options?: {
  rpcOptions?: EventOptions<ClientFunctions, ServerFunctions, false>;
}): BirpcGroup<ClientFunctions, ServerFunctions, false>;
//#endregion
export { createRpcServer };