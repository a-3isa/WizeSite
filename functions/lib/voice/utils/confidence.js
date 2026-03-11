"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.clampConfidence = clampConfidence;
exports.calculateOverallConfidence = calculateOverallConfidence;
exports.buildConfidenceScores = buildConfidenceScores;
function clampConfidence(value) {
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
function calculateOverallConfidence(amount, category, project) {
    const weighted = (amount * 0.45) + (category * 0.3) + (project * 0.25);
    return clampConfidence(weighted);
}
function buildConfidenceScores(params) {
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
//# sourceMappingURL=confidence.js.map