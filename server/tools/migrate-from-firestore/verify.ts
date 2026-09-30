/**
 * Migration verification report (tasks.md T038, FR-012, SC-001). Pure: the CLI gathers the inputs.
 * `ok` is false on ANY mismatch; the CLI then exits non-zero.
 */
import type { PrecisionFlag } from "./transform";

export interface Totals {
  totalExpenses: number;
  totalPayments: number;
  netProfit: number;
}

export interface VerifyInput {
  counts: Array<{ collection: string; table: string; source: number; skipped: number; target: number }>;
  projects: Array<{
    projectId: string;
    /** Totals computed from the exported Firestore documents. */
    fromSource: Totals;
    /** Totals computed from the rows now in Postgres. */
    fromMigratedRows: Totals;
    /** Totals in the project_metrics row the recompute stored. */
    stored: Totals;
    /** Firestore's own project_metrics doc, if any: differences are pre-existing drift. */
    firestoreMetrics?: Totals;
  }>;
  files: Array<{ storagePath: string; sourceMd5: string; targetMd5: string | null }>;
  precisionFlags: PrecisionFlag[];
}

export interface Report {
  ok: boolean;
  mismatches: string[];
  warnings: string[];
  summary: {
    tables: number;
    projects: number;
    files: number;
    precisionFlags: number;
  };
}

const HALF_CENT = 0.005;
const KEYS: Array<keyof Totals> = ["totalExpenses", "totalPayments", "netProfit"];

function differs(a: number, b: number): boolean {
  return Math.abs(a - b) >= HALF_CENT;
}

export function buildReport(input: VerifyInput): Report {
  const mismatches: string[] = [];
  const warnings: string[] = [];

  for (const c of input.counts) {
    if (c.source - c.skipped !== c.target) {
      mismatches.push(`${c.table}: source ${c.source} - skipped ${c.skipped} != target ${c.target}`);
    }
  }

  for (const p of input.projects) {
    for (const key of KEYS) {
      const s = p.fromSource[key];
      if (differs(s, p.fromMigratedRows[key])) {
        mismatches.push(`${p.projectId} ${key}: source ${s} != migrated rows ${p.fromMigratedRows[key]}`);
      }
      if (differs(s, p.stored[key])) {
        mismatches.push(`${p.projectId} ${key}: source ${s} != stored metrics ${p.stored[key]}`);
      }
      if (p.firestoreMetrics && differs(s, p.firestoreMetrics[key])) {
        warnings.push(
          `${p.projectId} ${key}: old Firestore metrics said ${p.firestoreMetrics[key]}, records sum to ${s} (pre-existing drift; recomputed value is used)`,
        );
      }
    }
  }

  for (const f of input.files) {
    if (f.targetMd5 === null) {
      mismatches.push(`${f.storagePath}: missing on the new file store`);
    } else if (f.targetMd5 !== f.sourceMd5) {
      mismatches.push(`${f.storagePath}: MD5 ${f.targetMd5} != source ${f.sourceMd5}`);
    }
  }

  for (const flag of input.precisionFlags) {
    mismatches.push(
      `${flag.table}/${flag.id}.${flag.column} = ${flag.value} has more decimals than the column holds (not rounded; fix the source value)`,
    );
  }

  return {
    ok: mismatches.length === 0,
    mismatches,
    warnings,
    summary: {
      tables: input.counts.length,
      projects: input.projects.length,
      files: input.files.length,
      precisionFlags: input.precisionFlags.length,
    },
  };
}
