export default index;
/**
 * @type {((
 *   cfg?: import('eslint').Linter.Config & {
 *     config?: import('./index-cjs.js').FlatConfigNames,
 *     mergeSettings?: boolean,
 *     settings?: Partial<import('./iterateJsdoc.js').Settings>,
 *     rules?: {[key in keyof import('./rules.d.ts').Rules]?: import('eslint').Linter.RuleEntry<import('./rules.d.ts').Rules[key]>},
 *     extraRuleDefinitions?: {
 *       forbid?: {
 *         [contextName: string]: {
 *           description?: string,
 *           url?: string,
 *           contexts: (string|{
 *             message: string,
 *             context: string,
 *             comment: string
 *           })[]
 *         }
 *       },
 *       preferTypes?: {
 *         [typeName: string]: {
 *           description: string,
 *           overrideSettings: {
 *             [typeNodeName: string]: {
 *               message: string,
 *               replacement?: false|string,
 *               unifyParentAndChildTypeChecks?: boolean,
 *             }
 *           },
 *           url: string,
 *         }
 *       }
 *     }
 *   }
 * ) => import('eslint').Linter.Config)}
 */
export const jsdoc: ((cfg?: import("eslint").Linter.Config & {
    config?: import("./index-cjs.js").FlatConfigNames;
    mergeSettings?: boolean;
    settings?: Partial<import("./iterateJsdoc.js").Settings>;
    rules?: { [key in keyof import("./rules.d.ts").Rules]?: import("eslint").Linter.RuleEntry<import("./rules.d.ts").Rules[key]>; };
    extraRuleDefinitions?: {
        forbid?: {
            [contextName: string]: {
                description?: string;
                url?: string;
                contexts: (string | {
                    message: string;
                    context: string;
                    comment: string;
                })[];
            };
        };
        preferTypes?: {
            [typeName: string]: {
                description: string;
                overrideSettings: {
                    [typeNodeName: string]: {
                        message: string;
                        replacement?: false | string;
                        unifyParentAndChildTypeChecks?: boolean;
                    };
                };
                url: string;
            };
        };
    };
}) => import("eslint").Linter.Config);
export { getJsdocProcessorPlugin } from "./getJsdocProcessorPlugin.js";
import index from './index-cjs.js';
//# sourceMappingURL=index-esm.d.ts.map