import {ConfidenceScores} from "../types/expense";

export function clampConfidence(value: number): number {
  if (!Number.isFinite(value)) {
    return 0;
  }
  if (value < 0) {
    return 0;
  }
  if (value > 1) {
    return 1;
  }
  return Number(value.toFixed(2));
}

export function calculateOverallConfidence(
  amount: number,
  category: number,
  project: number,
): number {
  const weighted = (amount * 0.45) + (category * 0.3) + (project * 0.25);
  return clampConfidence(weighted);
}

export function buildConfidenceScores(params: {
  amount: number;
  category: number;
  project: number;
}): ConfidenceScores {
  const amount = clampConfidence(params.amount);
  const category = clampConfidence(params.category);
  const project = clampConfidence(params.project);
  return {
    amount,
    category,
    project,
    overall: calculateOverallConfidence(amount, category, project),
  };
}

