import {EntityInput} from "../types/expense";
import {normalizeTranscript} from "../utils/arabicNormalize";

/**
 * Supplier name from the AI → existing entity (feature 005). Mirrors mapLlmProjectNameToProvided:
 * exact normalized match first, then containment either way. An unmatched name is kept as a new
 * supplier name with no id.
 */
export function matchEntityName(
  name: string | null,
  entities: EntityInput[],
): {entityId: string | null; entityName: string | null} {
  const raw = `${name ?? ""}`.trim();
  const target = normalizeTranscript(raw);
  if (!target) {
    return {entityId: null, entityName: null};
  }
  const normalized = entities.map((entity) => ({entity, key: normalizeTranscript(entity.name)}));
  const exact = normalized.find(({key}) => key === target);
  if (exact) {
    return {entityId: exact.entity.id, entityName: exact.entity.name};
  }
  const partial = normalized.find(({key}) => key && (key.includes(target) || target.includes(key)));
  if (partial) {
    return {entityId: partial.entity.id, entityName: partial.entity.name};
  }
  return {entityId: null, entityName: raw};
}
