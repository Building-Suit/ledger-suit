import { createBirpc } from "birpc";
//#region src/rpc/client.ts
function createRpcClient(functions, options) {
	const { channel, rpcOptions = {} } = options;
	return createBirpc(functions, {
		...channel,
		timeout: -1,
		...rpcOptions,
		proxify: false
	});
}
//#endregion
export { createRpcClient };
