/**
 * T057 parity scenario: the same sequence of writes against the Cloud Functions code (run
 * in-process on the Firestore + Storage emulators) and against the new API's handlers (Postgres).
 * Each step is named by a label; ids differ between backends, so results are compared by label.
 */
import { createRequire } from "node:module";
import path from "node:path";

import type { Sql } from "../../src/db/pool";
import { withTransaction } from "../../src/db/tx";
import { periodKey } from "../../src/rpc/quota";
import * as expenses from "../../src/rpc/expenses";
import * as payments from "../../src/rpc/payments";
import * as projects from "../../src/rpc/projects";
import * as workers from "../../src/rpc/workers";
import { rowToDoc } from "../../src/recompute/rows";

export const WORKSPACE = "ws_parity";
export const OWNER = "owner_parity";

type Data = Record<string, unknown>;

/** The writes the scenario needs, on either backend. */
export interface Backend {
  name: string;
  seed(): Promise<void>;
  createProject(data: Data): Promise<string>;
  updateProject(data: Data): Promise<void>;
  archiveProject(data: Data): Promise<void>;
  createExpense(data: Data): Promise<string>;
  updateExpense(data: Data): Promise<void>;
  archiveExpense(data: Data): Promise<void>;
  createPayment(data: Data): Promise<string>;
  updatePayment(data: Data): Promise<void>;
  archivePayment(data: Data): Promise<void>;
  createWorker(data: Data): Promise<string>;
  createWorkerEntry(data: Data): Promise<string>;
  deleteProjectCascade(data: Data): Promise<void>;
  /** Final state, keyed by collection then id. */
  snapshot(): Promise<Snapshot>;
}

export interface Snapshot {
  records: Record<string, Map<string, Data>>;
  counters: { expenses: number; payments: number; workerEntries: number; activeProjects: number };
  projectMetrics: Map<string, Data>;
  workspaceMetrics: Data | undefined;
}

export const RECORD_COLLECTIONS = ["projects", "expenses", "payments", "workers", "worker_entries"] as const;

const ATTACHMENT = {
  id: "att1",
  fileName: "إيصال.jpg",
  storagePath: "receipts/owner_parity/r1.jpg",
  downloadUrl: "https://firebasestorage.googleapis.com/v0/b/demo/o/receipts%2Fowner_parity%2Fr1.jpg",
  contentType: "image/jpeg",
  uploadedAt: "2026-06-01T10:00:00.000Z",
  size: 1234,
};

/** Runs the scenario; returns label → id for this backend. */
export async function runScenario(b: Backend): Promise<Map<string, string>> {
  const step = async <T>(name: string, fn: () => Promise<T>): Promise<T> => {
    try {
      return await fn();
    } catch (error) {
      throw new Error(`${b.name} step ${name} failed: ${(error as Error).message}`, { cause: error });
    }
  };
  const ids = new Map<string, string>();
  const ws = { workspaceId: WORKSPACE };
  await b.seed();

  ids.set("P1", await step("1:createProject", () => b.createProject({ ...ws, name: "برج", clientName: "عميل", contractValue: 10000, budgetLimit: 6000, completionPercentage: 25, startDate: "2026-05-01T00:00:00.000Z", clientMutationId: "cm-p1" })));
  ids.set("P2", await step("2:createProject", () => b.createProject({ ...ws, name: "Ledger", clientMutationId: "cm-p2" })));
  ids.set("P3", await step("3:createProject", () => b.createProject({ ...ws, name: "To delete", contractValue: 500, clientMutationId: "cm-p3" })));
  // Replay of P1's mutation: must not create a second project.
  await step("4:createProject", () => b.createProject({ ...ws, name: "برج", contractValue: 10000, clientMutationId: "cm-p1" }));

  const P1 = ids.get("P1")!;
  const P2 = ids.get("P2")!;
  const P3 = ids.get("P3")!;

  ids.set("E1", await step("5:createExpense", () => b.createExpense({ ...ws, projectId: P1, category: "materials", amount: 250.5, date: "2026-06-01T10:00:00.000Z", supplierName: "مورد", paymentStatus: "paid", attachments: [ATTACHMENT], clientMutationId: "cm-e1" })));
  ids.set("E2", await step("6:createExpense", () => b.createExpense({ ...ws, projectId: P2, category: "transport", amount: 100, date: "2026-06-02T10:00:00.000Z", clientMutationId: "cm-e2" })));
  ids.set("E3", await step("7:createExpense", () => b.createExpense({ ...ws, projectId: P3, category: "equipment", amount: 75, date: "2026-06-03T10:00:00.000Z", clientMutationId: "cm-e3" })));
  ids.set("PAY1", await step("8:createPayment", () => b.createPayment({ ...ws, projectId: P1, amount: 1000, paymentStatus: "partial", paidAmount: 300, date: "2026-06-04T10:00:00.000Z", entityName: "عميل", clientMutationId: "cm-pay1" })));
  ids.set("PAY2", await step("9:createPayment", () => b.createPayment({ ...ws, projectId: P1, amount: 400, date: "2026-06-05T10:00:00.000Z", clientMutationId: "cm-pay2" })));
  ids.set("W1", await step("10:createWorker", () => b.createWorker({ ...ws, name: "علي", dailyWage: 150, billingType: "daily", clientMutationId: "cm-w1" })));
  ids.set("WE1", await step("11:createWorkerEntry", () => b.createWorkerEntry({ ...ws, workerId: ids.get("W1"), projectId: P1, daysWorked: 2, dailyWage: 150, date: "2026-06-06T00:00:00.000Z", clientMutationId: "cm-we1" })));
  ids.set("WE3", await step("12:createWorkerEntry", () => b.createWorkerEntry({ ...ws, workerId: ids.get("W1"), projectId: P3, daysWorked: 1, dailyWage: 150, date: "2026-06-07T00:00:00.000Z", clientMutationId: "cm-we3" })));

  await step("13:updateExpense", () => b.updateExpense({ ...ws, expenseId: ids.get("E1"), projectId: P1, category: "materials", amount: 300, date: "2026-06-01T10:00:00.000Z", supplierName: "مورد", paymentStatus: "paid", clientMutationId: "cm-e1-u" }));
  // paidAmount is sent unchanged: the new API stores an edited one (owner's fix), Firebase did not.
  await step("14:updatePayment", () => b.updatePayment({ ...ws, paymentId: ids.get("PAY1"), projectId: P1, amount: 1200, paymentStatus: "partial", paidAmount: 300, date: "2026-06-04T10:00:00.000Z", clientMutationId: "cm-pay1-u" }));
  await step("15:updateProject", () => b.updateProject({ ...ws, projectId: P1, name: "برج 2", clientName: "عميل", contractValue: 12000, budgetLimit: 6000, completionPercentage: 40, startDate: "2026-05-01T00:00:00.000Z", status: "active", clientMutationId: "cm-p1-u" }));
  await step("16:archiveExpense", () => b.archiveExpense({ ...ws, expenseId: ids.get("E2") }));
  await step("17:archivePayment", () => b.archivePayment({ ...ws, paymentId: ids.get("PAY2") }));
  await step("18:archiveProject", () => b.archiveProject({ ...ws, projectId: P2 }));
  await step("19:deleteProjectCascade", () => b.deleteProjectCascade({ ...ws, projectId: P3 }));
  return ids;
}

// ---------------------------------------------------------------- Firebase (functions/ in-process)

type FirestoreLike = {
  collection(name: string): {
    doc(id: string): { set(data: Data): Promise<unknown>; get(): Promise<{ exists: boolean; data(): Data | undefined }> };
    where(field: string, op: string, value: unknown): { get(): Promise<{ docs: Array<{ id: string; data(): Data }> }> };
  };
};

/** Firestore Timestamps → ISO strings so both sides compare alike. */
function plain(value: unknown): unknown {
  if (value && typeof value === "object" && typeof (value as { toDate?: unknown }).toDate === "function") {
    return (value as { toDate(): Date }).toDate().toISOString();
  }
  if (value instanceof Date) return value.toISOString();
  if (Array.isArray(value)) return value.map(plain);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value as Data).map(([k, v]) => [k, plain(v)]));
  }
  return value;
}

/**
 * Known Cloud Functions bug found by this harness: archiveExpenseWithQuotaRefund and
 * archivePaymentWithQuotaRefund update the record, then read the usage counter in the same
 * transaction, which Firestore rejects ("transactions require all reads to be executed before all
 * writes"), so those archives always fail. The new API does what they intend; for the comparison
 * the harness applies that intent on the Firebase side and records each time it had to.
 */
export const firebaseBugsHit: string[] = [];

const READS_BEFORE_WRITES = "transactions require all reads to be executed before all writes";

export function firebaseBackend(): Backend {
  // functions/lib initialises its own firebase-admin app (emulators via env) at import.
  const requireFromHere = createRequire(__filename);
  const fn = requireFromHere(path.resolve(__dirname, "../../../../functions/lib/index.js")) as Record<string, any>;
  const { getFirestore } = requireFromHere(
    requireFromHere.resolve("firebase-admin/firestore", { paths: [path.resolve(__dirname, "../../../../functions")] }),
  ) as { getFirestore(): FirestoreLike };
  const db = getFirestore();
  const call = async (name: string, data: Data) => fn[name].run({ data, auth: { uid: OWNER, token: {} } });
  const { FieldValue } = requireFromHere(
    requireFromHere.resolve("firebase-admin/firestore", { paths: [path.resolve(__dirname, "../../../../functions")] }),
  ) as { FieldValue: { serverTimestamp(): unknown } };
  /** The archive + refund the function intends, when it hits the reads-before-writes bug. */
  const archiveWithRefund = async (name: string, collection: string, idField: string, counterField: string, d: Data) => {
    try {
      await call(name, d);
    } catch (error) {
      if (!`${(error as Error).message}`.includes(READS_BEFORE_WRITES)) throw error;
      firebaseBugsHit.push(name);
      const ref = db.collection(collection).doc(`${d[idField]}`);
      const doc = await ref.get();
      if (doc.data()?.isArchived === true) return;
      await ref.set({ ...doc.data(), isArchived: true, archivedAt: FieldValue.serverTimestamp() });
      const counter = db.collection("usage_counters").doc(`${WORKSPACE}_${periodKey()}`);
      const current = Number((await counter.get()).data()?.[counterField] ?? 0);
      await counter.set({ ...(await counter.get()).data(), [counterField]: Math.max(0, current - 1) });
    }
  };
  const idOf = (result: unknown) => `${(result as { id?: string })?.id ?? ""}`;

  return {
    name: "firebase",
    async seed() {
      await db.collection("workspaces").doc(WORKSPACE).set({ ownerId: OWNER, name: "Parity" });
      await db.collection("memberships").doc(`${WORKSPACE}_${OWNER}`).set({ workspaceId: WORKSPACE, userId: OWNER, role: "owner" });
      await db.collection("subscriptions").doc(WORKSPACE).set({ tier: "pro", status: "active" });
    },
    createProject: async (d) => idOf(await fn.createProjectWithQuotaForUser(OWNER, d)),
    updateProject: async (d) => void (await fn.updateProjectForUser(OWNER, d)),
    archiveProject: async (d) => void (await fn.archiveProjectForUser(OWNER, d)),
    createExpense: async (d) => idOf(await fn.createExpenseWithQuotaForUser(OWNER, d)),
    updateExpense: async (d) => void (await call("updateExpense", d)),
    archiveExpense: (d) => archiveWithRefund("archiveExpenseWithQuotaRefund", "expenses", "expenseId", "expensesCount", d),
    createPayment: async (d) => idOf(await fn.createPaymentWithQuotaForUser(OWNER, d)),
    updatePayment: async (d) => void (await fn.updatePaymentForUser(OWNER, d)),
    archivePayment: (d) => archiveWithRefund("archivePaymentWithQuotaRefund", "payments", "paymentId", "paymentsCount", d),
    createWorker: async (d) => idOf(await call("createWorker", d)),
    createWorkerEntry: async (d) => idOf(await fn.createWorkerEntryWithQuotaForUser(OWNER, d)),
    deleteProjectCascade: async (d) => void (await call("deleteProjectCascade", d)),
    async snapshot() {
      // In production the onDocumentWritten triggers recompute after every write; run the project
      // trigger once per live project for the final state.
      const live = await db.collection("projects").where("workspaceId", "==", WORKSPACE).get();
      for (const doc of live.docs) {
        await fn.handleProjectWriteRecompute({ data: { after: { exists: true, data: () => doc.data() } }, params: { projectId: doc.id } });
      }
      const records: Snapshot["records"] = {};
      for (const collection of RECORD_COLLECTIONS) {
        const snap = await db.collection(collection).where("workspaceId", "==", WORKSPACE).get();
        records[collection] = new Map(snap.docs.map((d) => [d.id, plain(d.data()) as Data]));
      }
      const monthly = (await db.collection("usage_counters").doc(`${WORKSPACE}_${periodKey()}`).get()).data() ?? {};
      const projectsCounter = (await db.collection("usage_counters").doc(`${WORKSPACE}_projects`).get()).data() ?? {};
      const metrics = await db.collection("project_metrics").where("workspaceId", "==", WORKSPACE).get();
      const workspace = await db.collection("workspace_metrics").doc(WORKSPACE).get();
      return {
        records,
        counters: {
          expenses: Number(monthly.expensesCount ?? 0),
          payments: Number(monthly.paymentsCount ?? 0),
          workerEntries: Number(monthly.workerEntriesCount ?? 0),
          activeProjects: Number(projectsCounter.activeProjectsCount ?? 0),
        },
        projectMetrics: new Map(metrics.docs.map((d) => [d.id, plain(d.data()) as Data])),
        workspaceMetrics: workspace.exists ? (plain(workspace.data()) as Data) : undefined,
      };
    },
  };
}

// ---------------------------------------------------------------- new API (Postgres)

export function serverBackend(sql: Sql, filesRoot: string): Backend {
  const tx = <T>(fn: (t: Sql) => Promise<T>) => withTransaction(sql, fn);
  return {
    name: "server",
    async seed() {
      await sql`INSERT INTO workspaces (id, owner_uid, name) VALUES (${WORKSPACE}, ${OWNER}, 'Parity')`;
      await sql`INSERT INTO memberships (id, workspace_id, user_uid, role) VALUES (${`${WORKSPACE}_${OWNER}`}, ${WORKSPACE}, ${OWNER}, 'owner')`;
      await sql`INSERT INTO subscriptions (workspace_id, tier, status) VALUES (${WORKSPACE}, 'pro', 'active')`;
    },
    createProject: async (d) => (await tx((t) => projects.createProjectWithQuotaForUser(t, OWNER, d))).id,
    updateProject: (d) => tx((t) => projects.updateProjectForUser(t, OWNER, d)),
    archiveProject: (d) => tx((t) => projects.archiveProjectForUser(t, OWNER, d)),
    createExpense: async (d) => (await tx((t) => expenses.createExpenseWithQuotaForUser(t, OWNER, d))).id,
    updateExpense: (d) => tx((t) => expenses.updateExpenseForUser(t, OWNER, d)),
    archiveExpense: (d) => tx((t) => expenses.archiveExpenseWithQuotaRefundForUser(t, OWNER, d)),
    createPayment: async (d) => (await tx((t) => payments.createPaymentWithQuotaForUser(t, OWNER, d))).id,
    updatePayment: (d) => tx((t) => payments.updatePaymentForUser(t, OWNER, d)),
    archivePayment: (d) => tx((t) => payments.archivePaymentWithQuotaRefundForUser(t, OWNER, d)),
    createWorker: async (d) => (await tx((t) => workers.createWorkerForUser(t, OWNER, d))).id,
    createWorkerEntry: async (d) => (await tx((t) => workers.createWorkerEntryWithQuotaForUser(t, OWNER, d))).id,
    deleteProjectCascade: (d) => tx((t) => projects.deleteProjectCascadeForUser(t, OWNER, d, { root: filesRoot })),
    async snapshot() {
      const records: Snapshot["records"] = {};
      for (const collection of RECORD_COLLECTIONS) {
        const rows = await sql.unsafe(`SELECT * FROM "${collection}" WHERE workspace_id = $1`, [WORKSPACE]);
        records[collection] = new Map(rows.map((r) => [`${r.id}`, plain(rowToDoc(r as Data)) as Data]));
      }
      const [monthly] = await sql`SELECT * FROM usage_counters WHERE id = ${`${WORKSPACE}_${periodKey()}`}`;
      const [projectsCounter] = await sql`SELECT * FROM usage_counters WHERE id = ${`${WORKSPACE}_projects`}`;
      const metrics = await sql<{ project_id: string; payload: Data }[]>`
        SELECT project_id, payload FROM project_metrics WHERE workspace_id = ${WORKSPACE}`;
      const [workspace] = await sql<{ payload: Data }[]>`SELECT payload FROM workspace_metrics WHERE workspace_id = ${WORKSPACE}`;
      return {
        records,
        counters: {
          expenses: Number(monthly?.expenses_count ?? 0),
          payments: Number(monthly?.payments_count ?? 0),
          workerEntries: Number(monthly?.worker_entries_count ?? 0),
          activeProjects: Number(projectsCounter?.active_projects ?? 0),
        },
        projectMetrics: new Map(metrics.map((m) => [m.project_id, m.payload])),
        workspaceMetrics: workspace?.payload,
      };
    },
  };
}
