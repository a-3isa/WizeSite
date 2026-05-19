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
}
