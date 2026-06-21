import assert from "node:assert/strict";
import path from "node:path";
import {readFile} from "node:fs/promises";
import test from "node:test";
import {
  RulesTestEnvironment,
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {deleteDoc, doc, getDoc, setDoc, updateDoc} from "firebase/firestore";

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;

if (!emulatorHost) {
  test(
    "Firestore security rules tests require FIRESTORE_EMULATOR_HOST (skipped)",
    {skip: true},
    () => {},
  );
} else {
  const projectId = "buildtrack-rules-test";
  let env: RulesTestEnvironment;
  let bootstrapWorkspaceForUser: (input: {
    uid: string;
    email?: string | null;
    fullName?: string | null;
    photoUrl?: string | null;
  }) => Promise<{workspaceId: string; created: boolean}>;
  let setActiveWorkspaceForUser: (input: {
    uid: string;
    workspaceId: string;
  }) => Promise<{workspaceId: string}>;
  let inviteMemberByEmailForUser: (input: {
    ownerUid: string;
    workspaceId: string;
    email: string;
    role?: string;
  }) => Promise<{userId: string; workspaceId: string}>;

  async function seedBaseData() {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, "workspaces", "workspace_owner"), {
        id: "workspace_owner",
        ownerId: "owner_1",
      });
      await setDoc(doc(db, "workspaces", "workspace_other"), {
        id: "workspace_other",
        ownerId: "owner_2",
      });
      await setDoc(doc(db, "users", "owner_1"), {
        id: "owner_1",
        workspaceId: "workspace_owner",
      });
      await setDoc(doc(db, "users", "member_1"), {
        id: "member_1",
        workspaceId: "workspace_owner",
      });
      await setDoc(doc(db, "users", "attacker_1"), {
        id: "attacker_1",
        workspaceId: "workspace_owner",
      });
      await setDoc(doc(db, "projects", "project_other"), {
        id: "project_other",
        workspaceId: "workspace_other",
        name: "Other Project",
        clientName: "Other Client",
        contractValue: 900,
        startDate: new Date().toISOString(),
        completionPercentage: 5,
        status: "active",
        isArchived: false,
      });
      await setDoc(doc(db, "projects", "project_owner"), {
        id: "project_owner",
        workspaceId: "workspace_owner",
        name: "Owner Project",
        clientName: "Client",
        contractValue: 1200,
        startDate: new Date().toISOString(),
        completionPercentage: 10,
        status: "active",
        isArchived: false,
      });
      await setDoc(doc(db, "expenses", "expense_owner"), {
        id: "expense_owner",
        workspaceId: "workspace_owner",
        projectId: "project_owner",
        category: "materials",
        amount: 100,
        date: new Date().toISOString(),
        isArchived: false,
      });
      await setDoc(doc(db, "payments", "payment_owner"), {
        id: "payment_owner",
        workspaceId: "workspace_owner",
        projectId: "project_owner",
        amount: 120,
        date: new Date().toISOString(),
        paymentMethod: "cash",
        isArchived: false,
      });
      await setDoc(doc(db, "workers", "worker_owner"), {
        id: "worker_owner",
        workspaceId: "workspace_owner",
        name: "Worker Owner",
        phoneNumber: "0100",
        dailyWage: 100,
        billingType: "daily",
        workerType: "laborer",
        notes: "",
        isArchived: false,
        createdBy: "owner_1",
        createdAt: new Date(),
        updatedAt: new Date(),
      });
      await setDoc(doc(db, "worker_entries", "entry_owner"), {
        id: "entry_owner",
        workspaceId: "workspace_owner",
        workerId: "worker_1",
        projectId: "project_owner",
        daysWorked: 1,
        dailyWage: 90,
        totalCost: 90,
        date: new Date().toISOString(),
        isArchived: false,
      });
      await setDoc(doc(db, "memberships", "workspace_owner_member_1"), {
        workspaceId: "workspace_owner",
        userId: "member_1",
        role: "member",
      });
      await setDoc(doc(db, "memberships", "workspace_owner_admin_1"), {
        workspaceId: "workspace_owner",
        userId: "admin_1",
        role: "admin",
      });
      await setDoc(doc(db, "memberships", "workspace_owner_accounting_1"), {
        workspaceId: "workspace_owner",
        userId: "accounting_1",
        role: "accountingApproved",
      });
      await setDoc(doc(db, "memberships", "workspace_owner_entry_1"), {
        workspaceId: "workspace_owner",
        userId: "entry_1",
        role: "entryOnly",
      });
      await setDoc(doc(db, "entity_summaries", "entity_summary_owner"), {
        id: "entity_summary_owner",
        workspaceId: "workspace_owner",
        projectId: "project_owner",
        entityId: "entity_1",
        entityName: "Acme Materials",
        entityType: "supplier",
        totalExpenses: 100,
        totalPayments: 25,
      });
      await setDoc(doc(db, "attachments", "attachment_owner"), {
        id: "attachment_owner",
        workspaceId: "workspace_owner",
        ownerType: "expense",
        ownerId: "expense_owner",
        fileName: "receipt.pdf",
        storagePath: "attachments/owner/receipt.pdf",
        contentType: "application/pdf",
      });
      await setDoc(doc(db, "entities", "entity_owner"), {
        id: "entity_owner",
        workspaceId: "workspace_owner",
        name: "Acme Contractors",
        normalizedName: "acme contractors",
        type: "contractor",
        lastUsedAt: new Date(),
        createdAt: new Date(),
      });
      await setDoc(doc(db, "notifications", "notification_owner"), {
        workspaceId: "workspace_owner",
        targetUserId: "member_1",
        title: "Budget updated",
        message: "Review the latest totals",
        createdAt: new Date(),
      });
      await setDoc(doc(db, "workspace_metrics", "workspace_owner"), {
        workspaceId: "workspace_owner",
        totalExpenses: 100,
      });
      await setDoc(doc(db, "project_metrics", "project_owner"), {
        workspaceId: "workspace_owner",
        projectId: "project_owner",
        totalExpenses: 100,
      });
      await setDoc(doc(db, "worker_accounting_records", "worker_record_owner"), {
        workspaceId: "workspace_owner",
        projectId: "project_owner",
        workerId: "worker_owner",
        workerName: "Worker Owner",
        description: "Weekly settlement",
        amount: 300,
        date: new Date(),
        paymentMethod: "cash",
        paymentStatus: "partial",
        paidAmount: 125,
        notes: "",
      });
      await setDoc(doc(db, "contractor_accounting_records", "contractor_record_owner"), {
        workspaceId: "workspace_owner",
        projectId: "project_owner",
        contractorId: "contractor_owner",
        contractorName: "Contractor Owner",
        description: "Contractor invoice",
        amount: 400,
        date: new Date(),
        paymentMethod: "cash",
        paymentStatus: "paid",
        notes: "",
      });
      await setDoc(doc(db, "worker_accounting_summaries", "workspace_owner_worker_owner"), {
        workspaceId: "workspace_owner",
        workerId: "worker_owner",
        totalAmount: 300,
        confirmedPaid: 125,
        confirmedOutstanding: 175,
        unresolvedLegacyCount: 0,
        recordCount: 1,
      });
    });
  }

  test.before(async () => {
    process.env.GCLOUD_PROJECT = projectId;
    process.env.FIREBASE_CONFIG = JSON.stringify({projectId});
    env = await initializeTestEnvironment({
      projectId,
      firestore: {
        host: emulatorHost.split(":")[0],
        port: Number(emulatorHost.split(":")[1]),
        rules: await readFile(
          path.resolve(__dirname, "../../firestore.rules"),
          "utf8",
        ),
      },
    });

    const indexModule = await import("./index");
    bootstrapWorkspaceForUser = indexModule.bootstrapWorkspaceForUser;
    setActiveWorkspaceForUser = indexModule.setActiveWorkspaceForUser;
    inviteMemberByEmailForUser = indexModule.inviteMemberByEmailForUser;
  });

  test.after(async () => {
    await env.cleanup();
  });

  test("user cannot change own workspace claim", async () => {
    await seedBaseData();
    const attackerDb = env.authenticatedContext("attacker_1").firestore();
    const attackerUserDoc = doc(attackerDb, "users", "attacker_1");

    await assertFails(
      setDoc(
        attackerUserDoc,
        {workspaceId: "workspace_other"},
        {merge: true},
      ),
    );

    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      const snap = await getDoc(doc(db, "users", "attacker_1"));
      assert.equal(snap.data()?.workspaceId, "workspace_owner");
    });
  });

  test("non-owner cannot self-add membership to another workspace", async () => {
    await seedBaseData();
    const attackerDb = env.authenticatedContext("attacker_1").firestore();
    const membershipDoc = doc(
      attackerDb,
      "memberships",
      "workspace_other_attacker_1",
    );

    await assertFails(
      setDoc(membershipDoc, {
        workspaceId: "workspace_other",
        userId: "attacker_1",
        role: "member",
      }),
    );
  });

  test("non-member cannot read another workspace project", async () => {
    await seedBaseData();
    const attackerDb = env.authenticatedContext("attacker_1").firestore();

    await assertFails(getDoc(doc(attackerDb, "projects", "project_other")));
  });

  test("member can read project in own workspace", async () => {
    await seedBaseData();
    const memberDb = env.authenticatedContext("member_1").firestore();

    await assertSucceeds(getDoc(doc(memberDb, "projects", "project_owner")));
  });

  test("ordinary members cannot read role-restricted accounting summaries or attachments", async () => {
    await seedBaseData();
    const memberDb = env.authenticatedContext("member_1").firestore();

    await assertFails(getDoc(doc(memberDb, "entity_summaries", "entity_summary_owner")));
    await assertFails(getDoc(doc(memberDb, "attachments", "attachment_owner")));
  });

  test("accounting-approved roles can read role-restricted summaries and attachments", async () => {
    await seedBaseData();
    const adminDb = env.authenticatedContext("admin_1").firestore();
    const accountingDb = env.authenticatedContext("accounting_1").firestore();

    await assertSucceeds(getDoc(doc(adminDb, "entity_summaries", "entity_summary_owner")));
    await assertSucceeds(getDoc(doc(accountingDb, "attachments", "attachment_owner")));
  });

  test("workspace members can read the entity directory; non-members cannot", async () => {
    await seedBaseData();
    const memberDb = env.authenticatedContext("member_1").firestore();
    const attackerDb = env.authenticatedContext("attacker_1").firestore();

    await assertSucceeds(getDoc(doc(memberDb, "entities", "entity_owner")));
    await assertFails(getDoc(doc(attackerDb, "entities", "entity_owner")));
  });

  test("workspace members can create and touch entities but not reassign workspace", async () => {
    await seedBaseData();
    const memberDb = env.authenticatedContext("member_1").firestore();

    await assertSucceeds(
      setDoc(doc(memberDb, "entities", "entity_new"), {
        workspaceId: "workspace_owner",
        name: "New Supplier",
        normalizedName: "new supplier",
        type: "supplier",
        createdAt: new Date(),
        lastUsedAt: new Date(),
      }),
    );
    await assertSucceeds(
      updateDoc(doc(memberDb, "entities", "entity_owner"), {
        lastUsedAt: new Date(),
      }),
    );
    await assertFails(
      updateDoc(doc(memberDb, "entities", "entity_owner"), {
        workspaceId: "workspace_other",
      }),
    );
  });

  test("notification target can change only readAt", async () => {
    await seedBaseData();
    const memberDb = env.authenticatedContext("member_1").firestore();
    const ownerDb = env.authenticatedContext("owner_1").firestore();
    const notificationRef = doc(memberDb, "notifications", "notification_owner");

    await assertSucceeds(updateDoc(notificationRef, {readAt: new Date()}));
    await assertFails(updateDoc(notificationRef, {title: "Changed"}));
    await assertFails(
      updateDoc(doc(ownerDb, "notifications", "notification_owner"), {
        readAt: new Date(),
      }),
    );
  });

  test("financial metrics are accounting-role restricted", async () => {
    await seedBaseData();
    const memberDb = env.authenticatedContext("member_1").firestore();
    const entryDb = env.authenticatedContext("entry_1").firestore();
    const adminDb = env.authenticatedContext("admin_1").firestore();

    await assertFails(getDoc(doc(memberDb, "workspace_metrics", "workspace_owner")));
    await assertFails(getDoc(doc(memberDb, "project_metrics", "project_owner")));
    await assertFails(getDoc(doc(entryDb, "workspace_metrics", "workspace_owner")));
    await assertFails(getDoc(doc(entryDb, "project_metrics", "project_owner")));
    await assertSucceeds(getDoc(doc(adminDb, "workspace_metrics", "workspace_owner")));
    await assertSucceeds(getDoc(doc(adminDb, "project_metrics", "project_owner")));
  });

  test("domain accounting records and worker summaries are accounting-role restricted", async () => {
    await seedBaseData();
    const memberDb = env.authenticatedContext("member_1").firestore();
    const entryDb = env.authenticatedContext("entry_1").firestore();
    const accountingDb = env.authenticatedContext("accounting_1").firestore();

    await assertFails(getDoc(doc(memberDb, "worker_accounting_records", "worker_record_owner")));
    await assertFails(getDoc(doc(entryDb, "worker_accounting_records", "worker_record_owner")));
    await assertFails(getDoc(doc(memberDb, "contractor_accounting_records", "contractor_record_owner")));
    await assertFails(getDoc(doc(entryDb, "worker_accounting_summaries", "workspace_owner_worker_owner")));
    await assertSucceeds(getDoc(doc(accountingDb, "worker_accounting_records", "worker_record_owner")));
    await assertSucceeds(getDoc(doc(accountingDb, "contractor_accounting_records", "contractor_record_owner")));
    await assertSucceeds(getDoc(doc(accountingDb, "worker_accounting_summaries", "workspace_owner_worker_owner")));
  });

  test("worker accounting partial writes require a valid paid amount", async () => {
    await seedBaseData();
    const accountingDb = env.authenticatedContext("accounting_1").firestore();
    const validRecord = {
      workspaceId: "workspace_owner",
      projectId: "project_owner",
      workerId: "worker_owner",
      workerName: "Worker Owner",
      description: "Valid partial",
      amount: 300,
      date: new Date(),
      paymentMethod: "cash",
      paymentStatus: "partial",
      notes: "",
    };

    await assertFails(
      setDoc(doc(accountingDb, "worker_accounting_records", "partial_missing"), {
        ...validRecord,
      }),
    );
    await assertFails(
      setDoc(doc(accountingDb, "worker_accounting_records", "partial_too_high"), {
        ...validRecord,
        paidAmount: 300,
      }),
    );
    await assertSucceeds(
      setDoc(doc(accountingDb, "worker_accounting_records", "partial_valid"), {
        ...validRecord,
        paidAmount: 125,
      }),
    );
  });

  test("workspace owner can add members", async () => {
    await seedBaseData();
    const ownerDb = env.authenticatedContext("owner_1").firestore();
    const membershipDoc = doc(ownerDb, "memberships", "workspace_owner_member_2");

    await assertSucceeds(
      setDoc(membershipDoc, {
        workspaceId: "workspace_owner",
        userId: "member_2",
        role: "member",
      }),
    );
  });

  test("direct project create is denied even for workspace members", async () => {
    await seedBaseData();
    const memberDb = env.authenticatedContext("member_1").firestore();

    await assertFails(
      setDoc(doc(memberDb, "projects", "project_new"), {
        id: "project_new",
        workspaceId: "workspace_owner",
        name: "New Project",
        clientName: "Client",
        contractValue: 500,
        startDate: new Date().toISOString(),
        completionPercentage: 0,
        status: "active",
        isArchived: false,
      }),
    );
  });

  test("direct expense create is denied", async () => {
    await seedBaseData();
    const memberDb = env.authenticatedContext("member_1").firestore();

    await assertFails(
      setDoc(doc(memberDb, "expenses", "expense_new"), {
        id: "expense_new",
        workspaceId: "workspace_owner",
        projectId: "project_owner",
        category: "materials",
        amount: -10,
        date: new Date().toISOString(),
        isArchived: false,
      }),
    );
  });

  test("direct payment delete is denied", async () => {
    await seedBaseData();
    const memberDb = env.authenticatedContext("member_1").firestore();

    await assertFails(deleteDoc(doc(memberDb, "payments", "payment_owner")));
  });

  test("expense update cannot move records across workspaces", async () => {
    await seedBaseData();
    const memberDb = env.authenticatedContext("member_1").firestore();

    await assertFails(
      updateDoc(doc(memberDb, "expenses", "expense_owner"), {
        workspaceId: "workspace_other",
      }),
    );
  });

  test("worker entry update rejects negative fields", async () => {
    await seedBaseData();
    const memberDb = env.authenticatedContext("member_1").firestore();

    await assertFails(
      updateDoc(doc(memberDb, "worker_entries", "entry_owner"), {
        daysWorked: -1,
      }),
    );
  });

  test("worker create allows project billing with zero daily wage", async () => {
    await seedBaseData();
    const memberDb = env.authenticatedContext("member_1").firestore();

    await assertSucceeds(
      setDoc(doc(memberDb, "workers", "worker_project"), {
        id: "worker_project",
        workspaceId: "workspace_owner",
        name: "Project Billed Worker",
        phoneNumber: "0100111",
        dailyWage: 0,
        billingType: "project",
        workerType: "laborer",
        notes: "",
        isArchived: false,
      }),
    );
  });

  test("worker create rejects daily billing with zero wage", async () => {
    await seedBaseData();
    const memberDb = env.authenticatedContext("member_1").firestore();

    await assertFails(
      setDoc(doc(memberDb, "workers", "worker_daily_invalid"), {
        id: "worker_daily_invalid",
        workspaceId: "workspace_owner",
        name: "Daily Billed Worker",
        phoneNumber: "0100111",
        dailyWage: 0,
        billingType: "daily",
        workerType: "laborer",
        notes: "",
        isArchived: false,
      }),
    );
  });

  test("worker update rejects invalid billing type", async () => {
    await seedBaseData();
    const memberDb = env.authenticatedContext("member_1").firestore();

    await assertFails(
      updateDoc(doc(memberDb, "workers", "worker_owner"), {
        billingType: "weekly",
        updatedAt: new Date(),
      }),
    );
  });

  test("worker writes reject invalid status while preserving legacy default", async () => {
    await seedBaseData();
    const memberDb = env.authenticatedContext("member_1").firestore();

    await assertFails(
      setDoc(doc(memberDb, "workers", "worker_bad_status"), {
        id: "worker_bad_status",
        workspaceId: "workspace_owner",
        name: "Invalid Status Worker",
        phoneNumber: "0100111",
        dailyWage: 100,
        billingType: "daily",
        workerType: "laborer",
        notes: "",
        isArchived: false,
        status: "suspended",
      }),
    );

    await assertSucceeds(
      updateDoc(doc(memberDb, "workers", "worker_owner"), {
        status: "inactive",
        updatedAt: new Date(),
      }),
    );
  });

  test("bootstrap function creates workspace user and membership for first-time auth user", async () => {
    await env.clearFirestore();

    const result = await bootstrapWorkspaceForUser({
      uid: "google_user_1",
      email: "google@example.com",
      fullName: "Google User",
      photoUrl: "https://example.com/photo.png",
    });

    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      const workspaceSnap = await getDoc(doc(db, "workspaces", result.workspaceId));
      const userSnap = await getDoc(doc(db, "users", "google_user_1"));
      const membershipSnap = await getDoc(
        doc(db, "memberships", `${result.workspaceId}_google_user_1`),
      );

      assert.equal(result.created, true);
      assert.equal(workspaceSnap.exists(), true);
      assert.equal(userSnap.data()?.workspaceId, result.workspaceId);
      assert.equal(membershipSnap.data()?.role, "owner");
    });
  });

  test("bootstrap preserves existing user settings and profile fields", async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, "users", "existing_user"), {
        id: "existing_user",
        workspaceId: "legacy_workspace",
        email: "saved@example.com",
        fullName: "Saved Name",
        photoUrl: "https://example.com/saved.png",
        defaultCurrency: "USD",
        riskAlertsEnabled: false,
      });
      await setDoc(doc(db, "workspaces", "legacy_workspace"), {
        id: "legacy_workspace",
        ownerId: "existing_user",
        name: "Existing Workspace",
      });
    });

    const result = await bootstrapWorkspaceForUser({
      uid: "existing_user",
      email: "incoming@example.com",
      fullName: "Incoming Name",
      photoUrl: "https://example.com/incoming.png",
    });

    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      const userSnap = await getDoc(doc(db, "users", "existing_user"));
      const membershipSnap = await getDoc(
        doc(db, "memberships", `${result.workspaceId}_existing_user`),
      );

      assert.equal(result.workspaceId, "legacy_workspace");
      assert.equal(userSnap.data()?.defaultCurrency, "USD");
      assert.equal(userSnap.data()?.riskAlertsEnabled, false);
      assert.equal(userSnap.data()?.fullName, "Saved Name");
      assert.equal(userSnap.data()?.photoUrl, "https://example.com/saved.png");
      assert.equal(userSnap.data()?.email, "saved@example.com");
      assert.equal(membershipSnap.data()?.role, "owner");
    });
  });

  test("bootstrap omits missing optional profile fields for new users", async () => {
    await env.clearFirestore();

    const result = await bootstrapWorkspaceForUser({
      uid: "minimal_user",
      email: "minimal@example.com",
      fullName: null,
      photoUrl: null,
    });

    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      const userSnap = await getDoc(doc(db, "users", "minimal_user"));

      assert.equal(result.created, true);
      assert.equal(userSnap.data()?.email, "minimal@example.com");
      assert.equal("fullName" in (userSnap.data() ?? {}), false);
      assert.equal("photoUrl" in (userSnap.data() ?? {}), false);
    });
  });

  test("bootstrap preserves missing default currency on existing users without writing undefined", async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, "users", "existing_without_currency"), {
        id: "existing_without_currency",
        workspaceId: "legacy_workspace",
        riskAlertsEnabled: false,
      });
      await setDoc(doc(db, "workspaces", "legacy_workspace"), {
        id: "legacy_workspace",
        ownerId: "existing_without_currency",
        name: "Legacy Workspace",
      });
    });

    const result = await bootstrapWorkspaceForUser({
      uid: "existing_without_currency",
      email: "existing@example.com",
      fullName: "",
      photoUrl: "",
    });

    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      const userSnap = await getDoc(doc(db, "users", "existing_without_currency"));

      assert.equal(result.workspaceId, "legacy_workspace");
      assert.equal(userSnap.data()?.riskAlertsEnabled, false);
      assert.equal("defaultCurrency" in (userSnap.data() ?? {}), false);
      assert.equal("fullName" in (userSnap.data() ?? {}), false);
      assert.equal("photoUrl" in (userSnap.data() ?? {}), false);
      assert.equal(userSnap.data()?.email, "existing@example.com");
    });
  });

  test("bootstrap fails when legacy workspace belongs to someone else without membership", async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, "users", "legacy_user"), {
        id: "legacy_user",
        workspaceId: "shared_workspace",
        defaultCurrency: "USD",
        riskAlertsEnabled: false,
      });
      await setDoc(doc(db, "workspaces", "shared_workspace"), {
        id: "shared_workspace",
        ownerId: "different_owner",
        name: "Shared Workspace",
      });
    });

    await assert.rejects(
      bootstrapWorkspaceForUser({
        uid: "legacy_user",
        email: "legacy@example.com",
        fullName: "Legacy User",
        photoUrl: "https://example.com/legacy.png",
      }),
      (error: unknown) => {
        assert.equal((error as {code?: string}).code, "failed-precondition");
        assert.match(
          `${(error as {message?: string}).message ?? ""}`,
          /legacy workspace/i,
        );
        return true;
      },
    );

    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      const workspaceSnap = await getDoc(doc(db, "workspaces", "shared_workspace"));
      const membershipSnap = await getDoc(doc(db, "memberships", "shared_workspace_legacy_user"));
      const userSnap = await getDoc(doc(db, "users", "legacy_user"));

      assert.equal(workspaceSnap.data()?.ownerId, "different_owner");
      assert.equal(membershipSnap.exists(), false);
      assert.equal(userSnap.data()?.workspaceId, "shared_workspace");
    });
  });

  test("active workspace switch persists only valid memberships", async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, "users", "member_1"), {
        id: "member_1",
        workspaceId: "personal_ws",
      });
      await setDoc(doc(db, "workspaces", "personal_ws"), {
        id: "personal_ws",
        ownerId: "member_1",
        name: "Personal Workspace",
      });
      await setDoc(doc(db, "workspaces", "shared_ws"), {
        id: "shared_ws",
        ownerId: "owner_2",
        name: "Shared Workspace",
      });
      await setDoc(doc(db, "workspaces", "other_ws"), {
        id: "other_ws",
        ownerId: "owner_3",
        name: "Other Workspace",
      });
      await setDoc(doc(db, "memberships", "personal_ws_member_1"), {
        workspaceId: "personal_ws",
        userId: "member_1",
        role: "owner",
      });
      await setDoc(doc(db, "memberships", "shared_ws_member_1"), {
        workspaceId: "shared_ws",
        userId: "member_1",
        role: "member",
      });
    });

    const result = await setActiveWorkspaceForUser({
      uid: "member_1",
      workspaceId: "shared_ws",
    });

    assert.equal(result.workspaceId, "shared_ws");
    await assert.rejects(
      setActiveWorkspaceForUser({
        uid: "member_1",
        workspaceId: "other_ws",
      }),
      (error: unknown) => {
        assert.equal((error as {code?: string}).code, "permission-denied");
        return true;
      },
    );

    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      const userSnap = await getDoc(doc(db, "users", "member_1"));
      assert.equal(userSnap.data()?.workspaceId, "shared_ws");
    });
  });

  test("active workspace switch repairs owned workspace without membership", async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, "users", "owner_1"), {
        id: "owner_1",
        workspaceId: "other_ws",
      });
      await setDoc(doc(db, "workspaces", "personal_ws"), {
        id: "personal_ws",
        ownerId: "owner_1",
        name: "Personal Workspace",
      });
    });

    const result = await setActiveWorkspaceForUser({
      uid: "owner_1",
      workspaceId: "personal_ws",
    });

    assert.equal(result.workspaceId, "personal_ws");
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      const userSnap = await getDoc(doc(db, "users", "owner_1"));
      const membershipSnap = await getDoc(
        doc(db, "memberships", "personal_ws_owner_1"),
      );
      assert.equal(userSnap.data()?.workspaceId, "personal_ws");
      assert.equal(membershipSnap.data()?.role, "owner");
    });
  });

  test("email invite adds membership without changing invitee active workspace", async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, "users", "owner_1"), {
        id: "owner_1",
        email: "owner@example.com",
        workspaceId: "owner_ws",
      });
      await setDoc(doc(db, "users", "invitee_1"), {
        id: "invitee_1",
        email: "invitee@example.com",
        workspaceId: "personal_ws",
      });
      await setDoc(doc(db, "workspaces", "owner_ws"), {
        id: "owner_ws",
        ownerId: "owner_1",
        name: "Owner Workspace",
      });
      await setDoc(doc(db, "memberships", "owner_ws_owner_1"), {
        workspaceId: "owner_ws",
        userId: "owner_1",
        role: "owner",
      });
    });

    const result = await inviteMemberByEmailForUser({
      ownerUid: "owner_1",
      workspaceId: "owner_ws",
      email: "INVITEE@example.com",
      role: "member",
    });

    assert.equal(result.userId, "invitee_1");
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      const userSnap = await getDoc(doc(db, "users", "invitee_1"));
      const membershipSnap = await getDoc(
        doc(db, "memberships", "owner_ws_invitee_1"),
      );
      const notificationSnap = await getDoc(
        doc(db, "notifications", "team_invite_added_workspace_invitee_1"),
      );
      assert.equal(userSnap.data()?.workspaceId, "personal_ws");
      assert.equal(membershipSnap.data()?.role, "member");
      assert.equal(notificationSnap.data()?.workspaceId, "owner_ws");
      assert.equal(notificationSnap.data()?.targetUserId, "invitee_1");
    });
  });

}
