//#region src/utils/structured-clone.d.ts
/**
 * Serialize a structured-cloneable value (`Map`, `Set`, `Date`, `BigInt`,
 * cycles, class instances, …) into a JSON-safe records array.
 */
declare function structuredCloneSerialize(value: unknown): unknown[];
/**
 * Inverse of {@link structuredCloneSerialize}.
 */
declare function structuredCloneDeserialize<T = unknown>(value: unknown[]): T;
/**
 * Serialize a structured-cloneable value to a single string. Equivalent
 * to `JSON.stringify(structuredCloneSerialize(value))`.
 */
declare function structuredCloneStringify(value: unknown): string;
/**
 * Inverse of {@link structuredCloneStringify}.
 */
declare function structuredCloneParse<T = unknown>(value: string): T;
//#endregion
export { structuredCloneDeserialize, structuredCloneParse, structuredCloneSerialize, structuredCloneStringify };