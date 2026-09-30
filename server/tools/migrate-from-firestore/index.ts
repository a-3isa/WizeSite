/**
 * Firestore → Postgres migration CLI (tasks.md T038, quickstart §2–3).
 *
 *   npm run migrate:firestore -- --target=staging [--report=out/report.json] [--reset] [--dry-run] [--skip-files]
 *
 * Env: DATABASE_URL, GOOGLE_APPLICATION_CREDENTIALS, FIREBASE_PROJECT_ID (default wize-site),
 *      FIREBASE_STORAGE_BUCKET (default <project>.firebasestorage.app), FILES_ROOT.
 *
 * Read-only against Firebase. Exits 1 when the report has any mismatch (SC-001), and refuses to
 * load at all when money would be rounded or a record points at something missing.
 */
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

import { getApps, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";

import { createPool, type Sql } from "../../src/db/pool";
import type { TriggerDocData } from "../../src/domain/accounting";
import { computeProjectDerived } from "../../src/recompute/project";
import { rowToDoc } from "../../src/recompute/rows";
import { exportCollections, listLiveUids, writeSnapshot } from "./export";
import { copyStorageFiles, type FileCheck } from "./files";
import { findOrphans, loadMigration, readTableColumns } from "./load";
import { COLLECTION_TABLES, transformExport, type ExportedCollections } from "./transform";
import { buildReport, type Totals, type VerifyInput } from "./verify";

function arg(name: string): string | undefined {
  const hit = process.argv.find((a) => a === `--${name}` || a.startsWith(`--${name}=`));
  if (!hit) return undefined;
  return hit.includes("=") ? hit.slice(hit.indexOf("=") + 1) : "true";
}

function totalsFrom(metrics: Record<string, unknown>): Totals {
  return {
    totalExpenses: Number(metrics.totalExpenses ?? 0),
    totalPayments: Number(metrics.totalPayments ?? 0),
    netProfit: Number(metrics.netProfit ?? 0),
  };
}

function projectTotals(
  project: TriggerDocData,
  expenses: TriggerDocData[],
  payments: TriggerDocData[],
  workerEntries: TriggerDocData[],
): Totals {
  const live = (d: TriggerDocData) => d.projectId === project.id && d.isArchived !== true;
  const { projectMetrics } = computeProjectDerived({
    workspaceId: `${project.workspaceId}`,
    projectId: `${project.id}`,
    project,
    expenses: expenses.filter(live),
    payments: payments.filter(live),
    workerEntries: workerEntries.filter(live),
    workerNames: new Map(),
    now: new Date(),
  });
  return totalsFrom(projectMetrics);
}

const docsOf = (exported: ExportedCollections, name: string): TriggerDocData[] =>
  (exported[name] ?? []).map((d) => ({ id: d.id, ...d.data }));

async function main(): Promise<void> {
  const target = arg("target") ?? "unspecified";
  const reportPath = arg("report") ?? `out/report-${target}.json`;
  const dryRun = arg("dry-run") === "true";
  const projectId = process.env.FIREBASE_PROJECT_ID ?? "wize-site";
  const databaseUrl = process.env.DATABASE_URL;
  const filesRoot = process.env.FILES_ROOT;
  if (!databaseUrl) throw new Error("DATABASE_URL is required");
  if (!dryRun && arg("skip-files") !== "true" && !filesRoot) throw new Error("FILES_ROOT is required");

  const app =
    getApps()[0] ??
    // No explicit credential: firebase-admin then uses GOOGLE_APPLICATION_CREDENTIALS in
    // production and talks to the emulators when *_EMULATOR_HOST is set.
    initializeApp({
      projectId,
      storageBucket: process.env.FIREBASE_STORAGE_BUCKET ?? `${projectId}.firebasestorage.app`,
    });
  const sql: Sql = createPool(databaseUrl, { max: 4 });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");

  try {
    console.log(`[${target}] exporting Firestore (${projectId})...`);
    const collections = [...Object.keys(COLLECTION_TABLES), "project_metrics"];
    const exported = await exportCollections(getFirestore(app), collections);
    const liveUids = await listLiveUids(getAuth(app));
    await writeSnapshot(path.join("out", "export", stamp), exported);

    const columns = await readTableColumns(sql);
    const transformed = transformExport(exported, columns, liveUids);
    const orphans = findOrphans(transformed.rows);

    let files: FileCheck[] = [];
    let migratedDocs = new Map<string, TriggerDocData[]>();
    let storedMetrics = new Map<string, Record<string, unknown>>();

    const conflicts = transformed.duplicates.filter((d) => d.conflicting);
    if (!dryRun && transformed.precisionFlags.length === 0 && orphans.length === 0 && conflicts.length === 0) {
      console.log(`[${target}] loading into Postgres...`);
      await loadMigration(sql, transformed.rows, { reset: arg("reset") === "true" });
      if (arg("skip-files") !== "true") {
        console.log(`[${target}] copying attachment files...`);
        files = await copyStorageFiles(getStorage(app).bucket() as never, filesRoot!);
      }
      const read = async (table: string) =>
        (await sql.unsafe(`SELECT * FROM "${table}"`)).map((r) => rowToDoc(r as Record<string, unknown>));
      migratedDocs = new Map(
        await Promise.all(
          ["projects", "expenses", "payments", "worker_entries"].map(
            async (t) => [t, await read(t)] as [string, TriggerDocData[]],
          ),
        ),
      );
      storedMetrics = new Map(
        (await sql<{ project_id: string; payload: Record<string, unknown> }[]>`
          SELECT project_id, payload FROM project_metrics`).map((r) => [r.project_id, r.payload]),
      );
    }

    const targetCounts = new Map<string, number>();
    for (const table of new Set(Object.values(COLLECTION_TABLES))) {
      const [{ count }] = await sql.unsafe(`SELECT count(*) FROM "${table}"`);
      targetCounts.set(table, Number(count));
    }

    const firestoreMetrics = new Map(
      (exported.project_metrics ?? []).map((d) => [d.id, totalsFrom(d.data)] as [string, Totals]),
    );
    const sourceProjects = docsOf(exported, "projects").filter((p) =>
      transformed.rows.get("projects")?.some((r) => r.id === p.id),
    );
    const verifyInput: VerifyInput = {
      counts: Object.entries(COLLECTION_TABLES).map(([collection, table]) => ({
        collection,
        table,
        source: (exported[collection] ?? []).length,
        skipped: transformed.skipped.get(collection) ?? 0,
        target: dryRun ? (exported[collection] ?? []).length - (transformed.skipped.get(collection) ?? 0) : targetCounts.get(table) ?? 0,
      })),
      projects: dryRun
        ? []
        : sourceProjects.map((project) => {
            const id = `${project.id}`;
            const migratedProject = migratedDocs.get("projects")?.find((p) => p.id === id) ?? project;
            return {
              projectId: id,
              fromSource: projectTotals(project, docsOf(exported, "expenses"), docsOf(exported, "payments"), docsOf(exported, "worker_entries")),
              fromMigratedRows: projectTotals(
                migratedProject,
                migratedDocs.get("expenses") ?? [],
                migratedDocs.get("payments") ?? [],
                migratedDocs.get("worker_entries") ?? [],
              ),
              stored: totalsFrom(storedMetrics.get(id) ?? {}),
              firestoreMetrics: firestoreMetrics.get(id),
            };
          }),
      files,
      precisionFlags: transformed.precisionFlags,
    };
    const report = buildReport(verifyInput);
    for (const orphan of orphans) report.mismatches.push(`orphan: ${orphan}`);
    for (const d of transformed.duplicates) {
      const line =
        `memberships: ${d.dropped.length + 1} docs for workspace ${d.workspaceId} / user ${d.userId}; ` +
        `kept ${d.kept}, dropped ${d.dropped.join(", ")}`;
      if (d.conflicting) report.mismatches.push(`${line} (role/status differ: resolve in Firestore)`);
      else report.warnings.push(line);
    }
    report.ok = report.mismatches.length === 0;

    await mkdir(path.dirname(reportPath), { recursive: true });
    await writeFile(
      reportPath,
      JSON.stringify({ target, dryRun, generatedAt: new Date().toISOString(), ...report, verifyInput }, null, 2),
      "utf8",
    );
    console.log(
      `[${target}] ${report.ok ? "OK" : "MISMATCHES"}: ${report.mismatches.length} mismatch(es), ` +
        `${report.warnings.length} warning(s); ${report.summary.projects} project(s), ${report.summary.files} file(s). Report: ${reportPath}`,
    );
    for (const line of report.mismatches) console.log(`  ✖ ${line}`);
    for (const line of report.warnings) console.log(`  ! ${line}`);
    process.exitCode = report.ok ? 0 : 1;
  } finally {
    await sql.end({ timeout: 5 });
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
