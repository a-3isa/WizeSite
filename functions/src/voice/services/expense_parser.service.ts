import {
  ConfidenceScores,
  CurrencyCode,
  ParsedExpense,
  ParseSource,
  ProcessVoiceExpenseResponse,
  VoiceProjectInput,
} from "../types/expense";
import {buildConfidenceScores} from "../utils/confidence";
import {extractExpenseByLlm, mapLlmProjectNameToProvided} from "./llm_extraction.service";
import {matchProjectFromTranscript} from "./project_matcher.service";
import {extractExpenseByRules} from "./rule_extraction.service";
import {normalizeTranscript} from "../utils/arabicNormalize";

function clampNote(note: string | null): string | null {
  if (!note) {
    return null;
  }
  const compact = note.replace(/\s+/g, " ").trim();
  if (!compact) {
    return null;
  }
  if (compact.length <= 120) {
    return compact;
  }
  return `${compact.slice(0, 117).trim()}...`;
}

function mergeConfidence(params: {
  fromRules: ConfidenceScores;
  fromLlm: {
    amountUsed: boolean;
    categoryUsed: boolean;
    projectUsed: boolean;
  };
  projectConfidence: number;
}): ConfidenceScores {
  const amount = params.fromLlm.amountUsed ? Math.max(params.fromRules.amount, 0.82) : params.fromRules.amount;
  const category = params.fromLlm.categoryUsed ?
    Math.max(params.fromRules.category, 0.72) :
    params.fromRules.category;
  const project = params.fromLlm.projectUsed ?
    Math.max(params.fromRules.project, params.projectConfidence) :
    params.fromRules.project;
  return buildConfidenceScores({amount, category, project});
}

export type ParseExpenseInput = {
  transcript: string;
  projects: VoiceProjectInput[];
  currency: CurrencyCode;
  storagePath: string;
  openRouterApiKey: string;
  openRouterModel: string;
};

export type LlmExtractorFn = typeof extractExpenseByLlm;

export async function parseExpenseFromTranscript(
  input: ParseExpenseInput,
  llmExtractor: LlmExtractorFn = extractExpenseByLlm,
): Promise<ProcessVoiceExpenseResponse> {
  const transcript = input.transcript.trim();
  const normalized = normalizeTranscript(transcript);
  const rules = extractExpenseByRules({
    transcript,
    projects: input.projects,
    currency: input.currency,
  });

  if (!rules.shouldFallback) {
    return {
      transcript,
      parsed: rules.parsed,
      confidence: rules.confidence,
      source: "rules",
      needsConfirmation: true,
      storagePath: input.storagePath,
    };
  }

  try {
    const llm = await llmExtractor({
      openRouterApiKey: input.openRouterApiKey,
      model: input.openRouterModel,
      transcriptOriginal: transcript,
      transcriptNormalized: normalized,
      projects: input.projects,
      defaultCurrency: input.currency,
    });

    const llmProject = mapLlmProjectNameToProvided({
      matchedProjectName: llm.matchedProjectName,
      projects: input.projects,
    });

    const llmProjectConfidence = llmProject.projectId == null ? 0 : matchProjectFromTranscript({
      normalizedTranscript: normalizeTranscript(llmProject.projectName ?? ""),
      projects: input.projects,
      threshold: 0.3,
    }).confidence;

    const amountFromLlm = rules.parsed.amount == null && llm.amount != null ? llm.amount : rules.parsed.amount;
    const canOverrideCategory = rules.parsed.category == null ||
      (rules.parsed.category === "other" && llm.category != null && llm.category !== "other");
    const categoryFromLlm = canOverrideCategory && llm.category != null ?
      llm.category :
      rules.parsed.category;
    const currency = llm.currency ?? rules.parsed.currency ?? input.currency;
    const projectId = rules.parsed.matchedProjectId ?? llmProject.projectId;
    const projectName = rules.parsed.matchedProjectName ?? llmProject.projectName;
    const note = clampNote(llm.note ?? rules.parsed.note);

    const mergedParsed: ParsedExpense = {
      amount: amountFromLlm,
      currency,
      category: categoryFromLlm,
      matchedProjectId: projectId,
      matchedProjectName: projectName,
      note,
    };

    const usedLlm = {
      amountUsed: rules.parsed.amount == null && llm.amount != null,
      categoryUsed: canOverrideCategory && llm.category != null,
      projectUsed: rules.parsed.matchedProjectId == null && llmProject.projectId != null,
    };

    const confidence = mergeConfidence({
      fromRules: rules.confidence,
      fromLlm: usedLlm,
      projectConfidence: llmProjectConfidence,
    });

    const source: ParseSource = usedLlm.amountUsed || usedLlm.categoryUsed || usedLlm.projectUsed ?
      (rules.parsed.amount == null && rules.parsed.category == null ? "llm" : "hybrid") :
      "rules";

    return {
      transcript,
      parsed: mergedParsed,
      confidence,
      source,
      needsConfirmation: true,
      storagePath: input.storagePath,
    };
  } catch {
    return {
      transcript,
      parsed: rules.parsed,
      confidence: rules.confidence,
      source: "rules",
      needsConfirmation: true,
      storagePath: input.storagePath,
    };
  }
}
