import { readFile } from "node:fs/promises";
import path from "node:path";

import type { Sql } from "../db/pool";
import { RpcError as HttpsError } from "../domain/errors";
import { parseExpenseFromTranscript } from "../domain/voice/services/expense_parser.service";
import { transcribeAudioFromStorage } from "../domain/voice/services/transcription.service";
import type { CurrencyCode, ProcessVoiceExpenseResponse, VoiceProjectInput } from "../domain/voice/types/expense";
import type { RpcRegistry } from "./types";
import { asRecord } from "./validation";

/**
 * processVoiceExpense, ported from functions/src/voice/process_voice_expense.ts. The audio is read
 * from the file store (uploaded through POST /v1/files) instead of Firebase Storage; the
 * transcription and extraction code is unchanged (src/domain/voice). Timeout 120 s, as before.
 */
export interface VoiceDeps {
  files: { root: string };
  openRouter: { apiKey: string; model: string; transcriptionModel: string };
}

function parseCurrency(input: unknown): CurrencyCode {
  const value = `${input ?? ""}`.trim().toUpperCase();
  return value === "EGP" || value === "USD" || value === "SAR" || value === "AED" ? value : "EGP";
}

function parseLanguageHint(input: unknown): string | null {
  const value = `${input ?? ""}`.trim().toLowerCase();
  if (!value) {
    return null;
  }
  return /^[a-z]{2,5}(-[a-z]{2,5})?$/i.test(value) ? value.split("-")[0] : null;
}

function emptyResult(storagePath: string): ProcessVoiceExpenseResponse {
  return {
    transcript: "",
    parsed: { amount: null, currency: null, category: null, matchedProjectId: null, matchedProjectName: null, note: null },
    confidence: { amount: 0, category: 0, project: 0, overall: 0 },
    source: "rules",
    needsConfirmation: true,
    storagePath,
  };
}

/** loadWorkspaceProjectsForUser: live projects of the caller's active workspace (up to 100). */
async function workspaceProjects(sql: Sql, uid: string): Promise<VoiceProjectInput[]> {
  const [profile] = await sql<{ active_workspace_id: string | null }[]>`
    SELECT active_workspace_id FROM user_profiles WHERE uid = ${uid}`;
  const workspaceId = `${profile?.active_workspace_id ?? ""}`.trim();
  if (!workspaceId) {
    return [];
  }
  const rows = await sql<{ id: string; name: string }[]>`
    SELECT id, name FROM projects WHERE workspace_id = ${workspaceId} AND NOT is_archived
    ORDER BY created_at LIMIT 100`;
  return rows.map((r) => ({ id: r.id, name: `${r.name ?? ""}`.trim() })).filter((p) => p.name.length > 0);
}

export async function processVoiceExpenseForUser(
  sql: Sql,
  deps: VoiceDeps,
  uid: string,
  payload: Record<string, unknown>,
): Promise<ProcessVoiceExpenseResponse> {
  const storagePath = `${payload.storagePath ?? ""}`.trim();
  if (!storagePath) {
    throw new HttpsError("invalid-argument", "storagePath is required");
  }
  if (!storagePath.startsWith(`voice-expenses/${uid}/`)) {
    throw new HttpsError("permission-denied", "storagePath is not owned by current user");
  }
  const projects = await workspaceProjects(sql, uid);
  const currency = parseCurrency(payload.currency);
  const languageHint = parseLanguageHint(payload.languageHint);
  if (!deps.openRouter.apiKey) {
    throw new HttpsError("failed-precondition", "OPENROUTER_API_KEY is not configured");
  }

  const root = path.resolve(deps.files.root);
  const readAudio = async (audioPath: string): Promise<Buffer | null> => {
    const target = path.resolve(root, audioPath);
    if (!target.startsWith(root + path.sep)) {
      return null;
    }
    try {
      return await readFile(target);
    } catch {
      return null;
    }
  };

  let transcript = "";
  try {
    transcript = await transcribeAudioFromStorage({
      storagePath,
      openRouterApiKey: deps.openRouter.apiKey,
      model: deps.openRouter.transcriptionModel.replace(/^﻿|\r?\n/g, "").trim(),
      languageHint,
      readAudio,
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError("internal", "Failed to transcribe voice expense");
  }
  if (!transcript.trim()) {
    return emptyResult(storagePath);
  }
  return parseExpenseFromTranscript({
    transcript,
    projects,
    currency,
    storagePath,
    openRouterApiKey: deps.openRouter.apiKey,
    openRouterModel: deps.openRouter.model,
  });
}

export function voiceRpcs(deps: VoiceDeps): RpcRegistry {
  return {
    processVoiceExpense: {
      // No records are written, but a retry must not pay for a second transcription:
      // the idempotency key returns the first result.
      mutating: true,
      timeoutMs: 120_000,
      handler: (ctx, data) => processVoiceExpenseForUser(ctx.sql, deps, ctx.uid, asRecord(data)),
    },
  };
}
