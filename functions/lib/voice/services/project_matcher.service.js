"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.matchProjectFromTranscript = matchProjectFromTranscript;
const arabicNormalize_1 = require("../utils/arabicNormalize");
function tokenize(input) {
    return input
        .split(/[\s\-_./]+/)
        .map((x) => x.trim())
        .filter((x) => x.length > 1);
}
function tokenOverlapScore(a, b) {
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
function diceCoefficient(a, b) {
    const left = a.replace(/\s+/g, "");
    const right = b.replace(/\s+/g, "");
    if (left.length < 2 || right.length < 2) {
        return 0;
    }
    const makeBigrams = (value) => {
        const map = new Map();
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
function matchProjectFromTranscript(params) {
    const threshold = params.threshold ?? 0.65;
    const transcript = (0, arabicNormalize_1.normalizeTranscript)(params.normalizedTranscript);
    if (transcript.length === 0 || params.projects.length === 0) {
        return { projectId: null, projectName: null, confidence: 0 };
    }
    for (const project of params.projects) {
        const normalizedName = (0, arabicNormalize_1.normalizeTranscript)(project.name);
        if (normalizedName.length > 0 && transcript.includes(normalizedName)) {
            return {
                projectId: project.id,
                projectName: project.name,
                confidence: 0.95,
            };
        }
    }
    let best = null;
    for (const project of params.projects) {
        const normalizedName = (0, arabicNormalize_1.normalizeTranscript)(project.name);
        const tokenScore = tokenOverlapScore(normalizedName, transcript);
        const diceScore = diceCoefficient(normalizedName, transcript);
        const score = (tokenScore * 0.6) + (diceScore * 0.4);
        if (!best || score > best.score) {
            best = { project, score };
        }
    }
    if (!best || best.score < threshold) {
        return { projectId: null, projectName: null, confidence: best?.score ?? 0 };
    }
    return {
        projectId: best.project.id,
        projectName: best.project.name,
        confidence: Number(best.score.toFixed(2)),
    };
}
//# sourceMappingURL=project_matcher.service.js.map