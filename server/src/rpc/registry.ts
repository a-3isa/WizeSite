import { fileRpcs } from "../files/download";
import { accountingRecordRpcs } from "./accounting_records";
import { entityRpcs } from "./entities";
import { expenseRpcs } from "./expenses";
import { memberRpcs } from "./members";
import { notificationRpcs } from "./notifications";
import { paymentRpcs } from "./payments";
import { projectRpcs } from "./projects";
import { sessionRpcs } from "./session";
import { type AuthAdmin, unavailableAuthAdmin, userRpcs } from "./user";
import { type VoiceDeps, voiceRpcs } from "./voice";
import { workerRpcs } from "./workers";
import type { FilesConfig } from "../files/signing";
import type { RpcRegistry } from "./types";
import { workspaceRpcs } from "./workspace";

export interface RegistryDeps {
  files: FilesConfig;
  /** Firebase sign-in admin; without it account changes fail with `unavailable`. */
  authAdmin?: AuthAdmin;
  /** OpenRouter settings for processVoiceExpense; without a key it answers failed-precondition. */
  openRouter?: VoiceDeps["openRouter"];
}

const NO_OPENROUTER: VoiceDeps["openRouter"] = { apiKey: "", model: "openai/gpt-4o-mini", transcriptionModel: "openai/gpt-audio-mini" };

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
    ...entityRpcs,
    ...accountingRecordRpcs,
    ...notificationRpcs,
    ...sessionRpcs,
    ...voiceRpcs({ files: deps.files, openRouter: deps.openRouter ?? NO_OPENROUTER }),
    ...userRpcs({ authAdmin: deps.authAdmin ?? unavailableAuthAdmin, files: deps.files }),
    ...fileRpcs(deps.files),
  };
}
