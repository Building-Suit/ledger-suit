import { createBirpcGroup } from "birpc";
//#region src/rpc/server.ts
function createRpcServer(functions, options = {}) {
	return createBirpcGroup(functions, [], {
		...options.rpcOptions,
		proxify: false
	});
}
//#endregion
export { createRpcServer };
