//#region src/utils/hash.d.ts
/**
 * Stable, deterministic hash of any structured-cloneable value.
 */
declare function hash(value: unknown): string;
//#endregion
export { hash };