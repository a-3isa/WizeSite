import { readFile } from "node:fs/promises";
import path from "node:path";

import { assertCanMutateMoney } from "../auth/roles";
import type { Sql } from "../db/pool";
import { RpcError as HttpsError } from "../domain/errors";
import { extractReceipt } from "../domain/voice/services/receipt_extraction.service";
import { transcribeAudioFromStorage } from "../domain/voice/services/transcription.service";
import type {
  CurrencyCode,
  EntityInput,
  ExpenseCategory,
  ExpenseProposal,
  ExpenseProposalResponse,
  ProcessVoiceExpenseResponse,
  VoiceProjectInput,
} from "../domain/voice/types/expense";
import { buildConfidenceScores } from "../domain/voice/utils/confidence";
import type { RpcRegistry } from "./types";
import { asRecord, requireString } from "./validation";

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

type ExtractionContext = { projects: VoiceProjectInput[]; entities: EntityInput[] };

const named = (rows: { id: string; name: string }[]) =>
  rows.map((r) => ({ id: r.id, name: `${r.name ?? ""}`.trim() })).filter((r) => r.name.length > 0);

/** Live projects (≤100) and suppliers/entities (≤200) of one workspace, names only go to the AI. */
export async function loadExtractionContext(sql: Sql, workspaceId: string): Promise<ExtractionContext> {
  if (!workspaceId) {
    return { projects: [], entities: [] };
  }
  const projects = await sql<{ id: string; name: string }[]>`
    SELECT id, name FROM projects WHERE workspace_id = ${workspaceId} AND NOT is_archived
    ORDER BY created_at LIMIT 100`;
  const entities = await sql<{ id: string; name: string }[]>`
    SELECT id, name FROM entities WHERE workspace_id = ${workspaceId} AND NOT is_archived
    ORDER BY name LIMIT 200`;
  return { projects: named(projects), entities: named(entities) };
}

/** loadWorkspaceProjectsForUser: the caller's active workspace (voice keeps using it). */
async function activeWorkspaceContext(sql: Sql, uid: string): Promise<ExtractionContext> {
  const [profile] = await sql<{ active_workspace_id: string | null }[]>`
    SELECT active_workspace_id FROM user_profiles WHERE uid = ${uid}`;
  return loadExtractionContext(sql, `${profile?.active_workspace_id ?? ""}`.trim());
}

/** Today in Cairo as YYYY-MM-DD (en-CA formats dates that way). */
export function cairoToday(now: Date = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Africa/Cairo" }).format(now);
}

function parseToday(input: unknown): string {
  const value = `${input ?? ""}`.trim();
  return /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : cairoToday();
}

const LEGACY_CATEGORIES: ExpenseCategory[] = ["labor", "materials", "equipment", "transport", "other"];

/**
 * Legacy `parsed`/`confidence` fields derived from the proposal, so a client older than feature 005
 * still gets a sensible single total (contracts/rpc-expense-items.md §4).
 */
function legacyFields(proposal: ExpenseProposal) {
  const amounts = proposal.items.map((i) => i.amount).filter((a): a is number => a !== null);
  const total = amounts.length ? Math.round(amounts.reduce((s, a) => s + Math.round(a * 100), 0)) / 100 : null;
  const category = LEGACY_CATEGORIES.includes(proposal.category as ExpenseCategory)
    ? (proposal.category as ExpenseCategory)
    : proposal.category ? "other" : null;
  const flagged = proposal.items.some((i) => i.needsReview);
  return {
    parsed: {
      amount: total,
      currency: total === null ? null : proposal.currency,
      category,
      matchedProjectId: proposal.projectId,
      matchedProjectName: proposal.projectName,
      note: proposal.title ?? proposal.items[0]?.name ?? null,
    },
    confidence: buildConfidenceScores({
      amount: total === null ? 0 : flagged ? 0.5 : 0.9,
      category: category ? 0.8 : 0,
      project: proposal.projectId ? 0.85 : 0,
    }),
  };
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
  const context = await activeWorkspaceContext(sql, uid);
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
  // Feature 005: AI-first; the rules extractor only runs inside extractReceipt as the fallback.
  const { proposal, source } = await extractReceipt({
    text: transcript,
    projects: context.projects,
    entities: context.entities,
    currency,
    today: parseToday(payload.today),
    openRouterApiKey: deps.openRouter.apiKey,
    model: deps.openRouter.model,
  });
  return { transcript, ...legacyFields(proposal), source, needsConfirmation: true, storagePath, proposal };
}

const MAX_ORGANIZE_TEXT = 4000;

/** organizeExpenseText: pasted receipt text → AI proposal; writes nothing (contract §3). */
export async function organizeExpenseTextForUser(
  sql: Sql,
  deps: VoiceDeps,
  uid: string,
  payload: Record<string, unknown>,
): Promise<ExpenseProposalResponse> {
  const workspaceId = requireString(payload, "workspaceId");
  await assertCanMutateMoney(sql, workspaceId, uid);
  const text = typeof payload.text === "string" ? payload.text.trim() : "";
  if (text.length < 1 || text.length > MAX_ORGANIZE_TEXT) {
    throw new HttpsError("invalid-argument", `text must be between 1 and ${MAX_ORGANIZE_TEXT} characters`);
  }
  if (!deps.openRouter.apiKey) {
    throw new HttpsError("failed-precondition", "OPENROUTER_API_KEY is not configured");
  }
  const context = await loadExtractionContext(sql, workspaceId);
  const { proposal, source } = await extractReceipt({
    text,
    projects: context.projects,
    entities: context.entities,
    currency: parseCurrency(payload.currency),
    today: parseToday(payload.today),
    openRouterApiKey: deps.openRouter.apiKey,
    model: deps.openRouter.model,
  });
  return { text, proposal, source, needsConfirmation: true };
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
    organizeExpenseText: {
      // Like processVoiceExpense: no records written, but a retry must not pay for a second AI call.
      mutating: true,
      timeoutMs: 60_000,
      handler: (ctx, data) => organizeExpenseTextForUser(ctx.sql, deps, ctx.uid, asRecord(data)),
    },
  };
}
