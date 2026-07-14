/**
 * Seeds the store-review demo account with a realistic workspace.
 *
 * Reviewers (Google Play / App Store) sign in with a shared account and must see
 * a working app, not an empty shell. This script provisions that data, mirroring
 * exactly what the Cloud Functions write — the callable/HTTP endpoints enforce
 * App Check, so they cannot be driven from a script.
 *
 * It talks to the Firestore + Identity Toolkit REST APIs with an OAuth access
 * token (the Admin SDK's Firestore client refuses a bare token and demands ADC or
 * a service-account key, neither of which we have here).
 *
 * It is idempotent: re-running wipes the demo user's previous projects/expenses/
 * payments and rebuilds them, so it never double-counts.
 *
 * It also mirrors the *derived* writes the functions perform — `project_metrics`
 * (the totals the dashboard actually reads) and `usage_counters` (quota
 * enforcement). Writing only the raw documents would leave the app showing zero
 * totals and the quotas out of sync.
 *
 * Usage:
 *   GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)" \
 *     node scripts/seed_demo_account.js
 */

const PROJECT_ID = "wize-site";
const DEMO_EMAIL = "demo.reviewer@buildozer.app";
const WORKSPACE_NAME = "Buildozer Demo";
const CURRENCY = "EGP";

const TOKEN = process.env.GOOGLE_OAUTH_ACCESS_TOKEN;
if (!TOKEN) {
  console.error(
    'Missing GOOGLE_OAUTH_ACCESS_TOKEN. Run:\n  GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)" node scripts/seed_demo_account.js',
  );
  process.exit(1);
}

const FS = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const IDP = `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT_ID}`;

const headers = {
  Authorization: `Bearer ${TOKEN}`,
  "Content-Type": "application/json",
  "X-Goog-User-Project": PROJECT_ID,
};

async function api(url, options = {}) {
  const res = await fetch(url, { ...options, headers });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`${options.method ?? "GET"} ${url} -> ${res.status}\n${text}`);
  }
  return text ? JSON.parse(text) : {};
}

// ---- Firestore REST value helpers (REST needs every value explicitly typed) --
const S = (v) => ({ stringValue: `${v}` });
const N = (v) => ({ doubleValue: v });
const B = (v) => ({ booleanValue: v });
const NULL = { nullValue: null };
const TS = (d) => ({ timestampValue: d.toISOString() });
const ARR = (items) => ({ arrayValue: { values: items } });
const now = () => TS(new Date());

const daysAgo = (n) => {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return TS(d);
};

/** Matches periodKey() in functions/src/index.ts — usage counters key on this. */
function periodKey(d = new Date()) {
  const month = `${d.getUTCMonth() + 1}`.padStart(2, "0");
  return `${d.getUTCFullYear()}${month}`;
}

const newId = () =>
  "demo" + Math.random().toString(36).slice(2, 12) + Date.now().toString(36);

async function setDoc(collection, docId, fields) {
  return api(`${FS}/${collection}?documentId=${docId}`, {
    method: "POST",
    body: JSON.stringify({ fields }),
  }).catch(async (err) => {
    // Already exists -> overwrite via PATCH.
    if (`${err.message}`.includes("ALREADY_EXISTS")) {
      return api(`${FS}/${collection}/${docId}`, {
        method: "PATCH",
        body: JSON.stringify({ fields }),
      });
    }
    throw err;
  });
}

async function runQuery(collection, field, value) {
  const res = await api(`${FS}:runQuery`, {
    method: "POST",
    body: JSON.stringify({
      structuredQuery: {
        from: [{ collectionId: collection }],
        where: {
          fieldFilter: {
            field: { fieldPath: field },
            op: "EQUAL",
            value: S(value),
          },
        },
      },
    }),
  });
  return res.filter((r) => r.document).map((r) => r.document);
}

async function wipe(collection, workspaceId) {
  const docs = await runQuery(collection, "workspaceId", workspaceId);
  for (const doc of docs) {
    await api(`https://firestore.googleapis.com/v1/${doc.name}`, {
      method: "DELETE",
    });
  }
  return docs.length;
}

// Categories must be one of the five createExpenseWithQuota accepts.
const PROJECTS = [
  {
    name: "Villa October",
    clientName: "Hassan Group",
    location: "6th of October City",
    description: "Two-storey villa — structure and finishing.",
    contractValue: 2400000,
    budgetLimit: 1800000,
    completionPercentage: 62,
    expenses: [
      { category: "materials", amount: 145000, supplierName: "El-Nasr Supplies", notes: "Cement and steel", paymentMethod: "bank", day: 26 },
      { category: "labor", amount: 62000, supplierName: "", notes: "Site crew — 3 weeks", paymentMethod: "cash", day: 19 },
      { category: "equipment", amount: 38500, supplierName: "Cairo Cranes", notes: "Crane rental", paymentMethod: "bank", day: 12 },
      { category: "materials", amount: 74000, supplierName: "Delta Tiles", notes: "Flooring", paymentMethod: "cash", day: 5 },
      { category: "transport", amount: 12500, supplierName: "Fast Trucks", notes: "Material delivery", paymentMethod: "cash", day: 2 },
    ],
    payments: [
      { amount: 800000, paymentMethod: "bank", notes: "Owner deposit", day: 30 },
      { amount: 450000, paymentMethod: "bank", notes: "Progress payment", day: 9 },
    ],
  },
  {
    name: "Tower B Renovation",
    clientName: "Nile Properties",
    location: "Maadi",
    description: "Full renovation of a 9-floor office tower.",
    contractValue: 1650000,
    budgetLimit: 1200000,
    completionPercentage: 38,
    expenses: [
      { category: "materials", amount: 210000, supplierName: "Alpha Cement", notes: "Concrete", paymentMethod: "bank", day: 22 },
      { category: "labor", amount: 88000, supplierName: "", notes: "Demolition crew", paymentMethod: "cash", day: 15 },
      { category: "other", amount: 24000, supplierName: "", notes: "Permits and fees", paymentMethod: "bank", day: 8 },
    ],
    payments: [
      { amount: 500000, paymentMethod: "bank", notes: "Owner deposit", day: 28 },
    ],
  },
  {
    name: "Warehouse Fit-out",
    clientName: "Delta Logistics",
    location: "10th of Ramadan",
    description: "Racking, lighting and loading-bay fit-out.",
    contractValue: 900000,
    budgetLimit: 700000,
    completionPercentage: 84,
    expenses: [
      { category: "equipment", amount: 156000, supplierName: "Racking Co.", notes: "Storage racking", paymentMethod: "bank", day: 20 },
      { category: "labor", amount: 41000, supplierName: "", notes: "Installation crew", paymentMethod: "cash", day: 11 },
    ],
    payments: [
      { amount: 600000, paymentMethod: "bank", notes: "Owner deposit", day: 24 },
      { amount: 150000, paymentMethod: "cheque", notes: "Second instalment", day: 4 },
    ],
  },
];

async function main() {
  // --- look up the demo user ---
  const lookup = await api(`${IDP}/accounts:lookup`, {
    method: "POST",
    body: JSON.stringify({ email: [DEMO_EMAIL] }),
  });
  const account = lookup.users?.[0];
  if (!account) throw new Error(`No auth user for ${DEMO_EMAIL}`);
  const uid = account.localId;
  console.log(`demo user: ${DEMO_EMAIL} (${uid})`);

  // --- workspace + membership + user doc (mirrors bootstrapWorkspaceForUser) ---
  const memberships = await runQuery("memberships", "userId", uid);
  let workspaceId;
  if (memberships.length > 0) {
    workspaceId = memberships[0].fields.workspaceId.stringValue;
    console.log(`reusing workspace ${workspaceId}`);
  } else {
    workspaceId = newId();
    console.log(`creating workspace ${workspaceId}`);
  }

  await setDoc("workspaces", workspaceId, {
    id: S(workspaceId),
    name: S(WORKSPACE_NAME),
    ownerId: S(uid),
    createdAt: now(),
    updatedAt: now(),
  });
  await setDoc("memberships", `${workspaceId}_${uid}`, {
    workspaceId: S(workspaceId),
    userId: S(uid),
    role: S("owner"),
    createdAt: now(),
    updatedAt: now(),
  });
  await setDoc("users", uid, {
    id: S(uid),
    workspaceId: S(workspaceId),
    email: S(DEMO_EMAIL),
    fullName: S(account.displayName || "Store Reviewer"),
    defaultCurrency: S(CURRENCY),
    riskAlertsEnabled: B(true),
    // Skip the first-run setup wizard so reviewers land straight on the
    // dashboard with data already in it.
    setupCompleted: B(true),
    createdAt: now(),
    updatedAt: now(),
  });

  // --- wipe previous demo content so re-runs don't double-count ---
  const wiped = {
    expenses: await wipe("expenses", workspaceId),
    payments: await wipe("payments", workspaceId),
    projects: await wipe("projects", workspaceId),
    project_metrics: await wipe("project_metrics", workspaceId),
  };
  console.log("wiped:", wiped);

  let expenseCount = 0;
  let paymentCount = 0;

  for (const p of PROJECTS) {
    const projectId = newId();
    await setDoc("projects", projectId, {
      id: S(projectId),
      workspaceId: S(workspaceId),
      ownerId: S(uid),
      name: S(p.name),
      clientName: S(p.clientName),
      contractValue: N(p.contractValue),
      startDate: daysAgo(90),
      expectedEndDate: NULL,
      location: S(p.location),
      description: S(p.description),
      budgetLimit: N(p.budgetLimit),
      completionPercentage: N(p.completionPercentage),
      status: S("active"),
      clientMutationId: S(""),
      clientCreatedAt: NULL,
      clientUpdatedAt: NULL,
      createdAt: now(),
      updatedAt: now(),
      createdBy: S(uid),
      isArchived: B(false),
    });

    let expensesTotal = 0;
    for (const e of p.expenses) {
      const id = newId();
      await setDoc("expenses", id, {
        id: S(id),
        workspaceId: S(workspaceId),
        projectId: S(projectId),
        projectName: S(p.name),
        category: S(e.category),
        amount: N(e.amount),
        currency: S(CURRENCY),
        date: daysAgo(e.day),
        notes: S(e.notes),
        supplierName: S(e.supplierName),
        paymentMethod: S(e.paymentMethod),
        inputMethod: S("manual"),
        transcript: S(""),
        source: S(""),
        storagePath: S(""),
        attachments: ARR([]),
        clientMutationId: S(""),
        clientCreatedAt: NULL,
        clientUpdatedAt: NULL,
        createdBy: S(uid),
        createdAt: now(),
        updatedAt: now(),
        isArchived: B(false),
      });
      expensesTotal += e.amount;
      expenseCount++;
    }

    let paymentsTotal = 0;
    for (const pay of p.payments) {
      const id = newId();
      await setDoc("payments", id, {
        id: S(id),
        workspaceId: S(workspaceId),
        projectId: S(projectId),
        amount: N(pay.amount),
        date: daysAgo(pay.day),
        paymentMethod: S(pay.paymentMethod),
        notes: S(pay.notes),
        attachments: ARR([]),
        clientMutationId: S(""),
        clientCreatedAt: NULL,
        clientUpdatedAt: NULL,
        createdBy: S(uid),
        createdAt: now(),
        updatedAt: now(),
        isArchived: B(false),
      });
      paymentsTotal += pay.amount;
      paymentCount++;
    }

    // Mirrors applyMetricsDeltaInTx: the dashboard reads totals from here, it
    // does not sum the raw documents.
    await setDoc("project_metrics", projectId, {
      workspaceId: S(workspaceId),
      projectId: S(projectId),
      totalExpenses: N(expensesTotal),
      totalPayments: N(paymentsTotal),
      netProfit: N(paymentsTotal - expensesTotal),
    });

    console.log(
      `  ${p.name}: ${p.expenses.length} expenses (${expensesTotal}), ` +
        `${p.payments.length} payments (${paymentsTotal}), ` +
        `net ${paymentsTotal - expensesTotal}`,
    );
  }

  await setDoc("usage_counters", `${workspaceId}_${periodKey()}`, {
    workspaceId: S(workspaceId),
    periodKey: S(periodKey()),
    expensesCount: N(expenseCount),
    paymentsCount: N(paymentCount),
    updatedAt: now(),
  });

  console.log(
    `\ndone: ${PROJECTS.length} projects, ${expenseCount} expenses, ` +
      `${paymentCount} payments in workspace ${workspaceId}`,
  );
}

main().catch((err) => {
  console.error(err.message ?? err);
  process.exit(1);
});
