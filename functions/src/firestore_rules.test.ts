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
import {doc, getDoc, setDoc} from "firebase/firestore";

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
      });
      await setDoc(doc(db, "projects", "project_owner"), {
        id: "project_owner",
        workspaceId: "workspace_owner",
      });
      await setDoc(doc(db, "memberships", "workspace_owner_member_1"), {
        workspaceId: "workspace_owner",
        userId: "member_1",
        role: "member",
      });
    });
  }

  test.before(async () => {
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
}
