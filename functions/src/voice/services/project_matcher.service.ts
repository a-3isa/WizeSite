import {VoiceProjectInput} from "../types/expense";
import {normalizeTranscript} from "../utils/arabicNormalize";

export type ProjectMatchResult = {
  projectId: string | null;
  projectName: string | null;
  confidence: number;
};

function tokenize(input: string): string[] {
  return input
    .split(/[\s\-_./]+/)
    .map((x) => x.trim())
    .filter((x) => x.length > 1);
}

function tokenOverlapScore(a: string, b: string): number {
  const aTokens = new Set(tokenize(a));
  const bTokens = new Set(tokenize(b));
  if (aTokens.size === 0 || bTokens.size === 0) {
    return 0;
  }
  let common = 0;
  for (const token of aTokens) {
    if (bTokens.has(token)) {
      common += 1;
    }
  }
  return common / Math.max(aTokens.size, bTokens.size);
}

function diceCoefficient(a: string, b: string): number {
  const left = a.replace(/\s+/g, "");
  const right = b.replace(/\s+/g, "");
  if (left.length < 2 || right.length < 2) {
    return 0;
  }

  const makeBigrams = (value: string): Map<string, number> => {
    const map = new Map<string, number>();
    for (let i = 0; i < value.length - 1; i += 1) {
      const pair = value.slice(i, i + 2);
      map.set(pair, (map.get(pair) ?? 0) + 1);
    }
    return map;
  };

  const leftMap = makeBigrams(left);
  const rightMap = makeBigrams(right);

  let intersection = 0;
  for (const [pair, count] of leftMap.entries()) {
    const rightCount = rightMap.get(pair) ?? 0;
    intersection += Math.min(count, rightCount);
  }
  return (2 * intersection) / (left.length - 1 + right.length - 1);
}

export function matchProjectFromTranscript(params: {
  normalizedTranscript: string;
  projects: VoiceProjectInput[];
  threshold?: number;
}): ProjectMatchResult {
  const threshold = params.threshold ?? 0.65;
  const transcript = normalizeTranscript(params.normalizedTranscript);
  if (transcript.length === 0 || params.projects.length === 0) {
    return {projectId: null, projectName: null, confidence: 0};
  }

  for (const project of params.projects) {
    const normalizedName = normalizeTranscript(project.name);
    if (normalizedName.length > 0 && transcript.includes(normalizedName)) {
      return {
        projectId: project.id,
        projectName: project.name,
        confidence: 0.95,
      };
    }
  }

  let best: {project: VoiceProjectInput; score: number} | null = null;
  for (const project of params.projects) {
    const normalizedName = normalizeTranscript(project.name);
    const tokenScore = tokenOverlapScore(normalizedName, transcript);
    const diceScore = diceCoefficient(normalizedName, transcript);
    const score = (tokenScore * 0.6) + (diceScore * 0.4);
    if (!best || score > best.score) {
      best = {project, score};
    }
  }

  if (!best || best.score < threshold) {
    return {projectId: null, projectName: null, confidence: best?.score ?? 0};
  }

  return {
    projectId: best.project.id,
    projectName: best.project.name,
    confidence: Number(best.score.toFixed(2)),
  };
}

