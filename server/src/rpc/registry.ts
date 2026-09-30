import { fileRpcs } from "../files/download";
import type { FilesConfig } from "../files/signing";
import type { RpcRegistry } from "./types";
import { workspaceRpcs } from "./workspace";

export interface RegistryDeps {
  files: FilesConfig;
}

/**
 * Every RPC the app can call (contracts/rpc-api.md "Function catalogue").
 * Handlers are added per user story (tasks.md US1/US2); a static test (tasks.md T079) checks
 * that this registry covers every callable exported by functions/src/index.ts.
 */
export function buildRegistry(deps: RegistryDeps): RpcRegistry {
  return {
    ...workspaceRpcs,
    ...fileRpcs(deps.files),
  };
}
