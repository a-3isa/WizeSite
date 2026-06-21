import path from "node:path";
import {readFile} from "node:fs/promises";
import test from "node:test";
import {
  RulesTestEnvironment,
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";

const emulatorHost = process.env.FIREBASE_STORAGE_EMULATOR_HOST;

if (!emulatorHost) {
  test(
    "Storage security rules tests require FIREBASE_STORAGE_EMULATOR_HOST (skipped)",
    {skip: true},
    () => {},
  );
} else {
  const projectId = "buildtrack-storage-rules-test";
  const bucketUrl = `gs://${projectId}.appspot.com`;
  let env: RulesTestEnvironment;

  function attachmentRef(uid: string, pathSuffix: string) {
    return env
      .authenticatedContext(uid)
      .storage(bucketUrl)
      .ref(`attachments/${pathSuffix}`);
  }

  function putRawString(uid: string, pathSuffix: string) {
    return attachmentRef(uid, pathSuffix)
      .putString("receipt", "raw", {contentType: "application/pdf"})
      .then(() => undefined);
  }

  test.before(async () => {
    env = await initializeTestEnvironment({
      projectId,
      storage: {
        host: emulatorHost.split(":")[0],
        port: Number(emulatorHost.split(":")[1]),
        rules: await readFile(
          path.resolve(__dirname, "../../storage.rules"),
          "utf8",
        ),
      },
    });
  });

  test.beforeEach(async () => {
    await env.clearStorage();
  });

  test.after(async () => {
    await env.cleanup();
  });

  test("authenticated users can upload only their own attachments", async () => {
    await assertSucceeds(
      putRawString("owner_1", "owner_1/receipt.pdf"),
    );

    await assertFails(
      putRawString("attacker_1", "owner_1/receipt.pdf"),
    );
  });
}
