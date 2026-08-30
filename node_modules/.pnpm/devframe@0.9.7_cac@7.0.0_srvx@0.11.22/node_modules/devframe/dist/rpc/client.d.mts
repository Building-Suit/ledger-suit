import { BirpcOptions, BirpcReturn, ChannelOptions } from "birpc";
//#region src/rpc/client.d.ts
declare function createRpcClient<ServerFunctions extends object = Record<string, never>, ClientFunctions extends object = Record<string, never>>(functions: ClientFunctions, options: {
  channel: ChannelOptions;
  rpcOptions?: Partial<BirpcOptions<ServerFunctions, ClientFunctions, boolean>>;
}): BirpcReturn<ServerFunctions, ClientFunctions, false>;
//#endregion
export { createRpcClient };