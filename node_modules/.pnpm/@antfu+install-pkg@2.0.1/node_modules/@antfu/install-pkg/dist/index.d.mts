import { Agent, Agent as Agent$1 } from "package-manager-detector";
//#region src/detect.d.ts
type PackageManager = 'pnpm' | 'yarn' | 'npm' | 'bun';
declare function detectPackageManager(cwd?: string): Promise<Agent$1 | null>;
//#endregion
//#region src/install.d.ts
interface InstallPackageOptions {
  cwd?: string;
  dev?: boolean;
  silent?: boolean;
  packageManager?: string;
  preferOffline?: boolean;
  additionalArgs?: string[] | ((agent: string, detectedAgent: string) => string[] | undefined);
}
declare function installPackage(names: string | string[], options?: InstallPackageOptions): Promise<import("tinyexec").Output>;
//#endregion
//#region src/uninstall.d.ts
interface UninstallPackageOptions {
  cwd?: string;
  dev?: boolean;
  silent?: boolean;
  packageManager?: string;
  additionalArgs?: string[];
}
declare function uninstallPackage(names: string | string[], options?: UninstallPackageOptions): Promise<import("tinyexec").Output>;
//#endregion
export { type Agent, InstallPackageOptions, PackageManager, UninstallPackageOptions, detectPackageManager, installPackage, uninstallPackage };