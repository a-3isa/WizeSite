import { fileRpcs } from "../files/download";
import { expenseRpcs } from "./expenses";
import { memberRpcs } from "./members";
import { paymentRpcs } from "./payments";
import { projectRpcs } from "./projects";
import { type AuthAdmin, unavailableAuthAdmin, userRpcs } from "./user";
import { workerRpcs } from "./workers";
import type { FilesConfig } from "../files/signing";
import type { RpcRegistry } from "./types";
import { workspaceRpcs } from "./workspace";

export interface RegistryDeps {
  files: FilesConfig;
  /** Firebase sign-in admin; without it account changes fail with `unavailable`. */
  authAdmin?: AuthAdmin;
}

/**
 * Every RPC the app can call (contracts/rpc-api.md "Function catalogue").
 * Handlers are added per user story (tasks.md US1/US2); a static test (tasks.md T079) checks
 * that this registry covers every callable exported by functions/src/index.ts.
 */
export function buildRegistry(deps: RegistryDeps): RpcRegistry {
  return {
    ...workspaceRpcs,
    ...memberRpcs,
    ...projectRpcs(deps.files),
    ...expenseRpcs,
    ...paymentRpcs,
    ...workerRpcs,
    ...userRpcs({ authAdmin: deps.authAdmin ?? unavailableAuthAdmin, files: deps.files }),
    ...fileRpcs(deps.files),
  };
}
