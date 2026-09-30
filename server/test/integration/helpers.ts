/**
 * Shared setup for integration tests. Requires a migrated Postgres:
 *   docker compose -f compose.test.yml up -d --wait postgres
 *   DATABASE_URL=$TEST_DATABASE_URL npm run migrate
 * Tests are skipped (not failed) when TEST_DATABASE_URL is unset, and say so.
 */
import type { FastifyInstance } from "fastify";

import { buildApp } from "../../src/app";
import type { TokenVerifier, VerifiedCaller } from "../../src/auth/verify";
import { createPool, type Sql } from "../../src/db/pool";
import { RpcError } from "../../src/domain/errors";
import type { RpcRegistry } from "../../src/rpc/types";

export const TEST_DATABASE_URL = process.env.TEST_DATABASE_URL ?? "";
export const skipReason = TEST_DATABASE_URL
  ? false
  : "TEST_DATABASE_URL not set (start compose.test.yml and run migrations)";

/** Token "valid:<uid>" authenticates as <uid>; App Check token must be "ok". */
export const stubVerifier: TokenVerifier = {
  async verifyIdToken(token: string): Promise<VerifiedCaller> {
    if (!token.startsWith("valid:")) {
      throw new RpcError("unauthenticated", "Invalid ID token");
    }
    return { uid: token.slice("valid:".length) };
  },
  async verifyAppCheck(token: string): Promise<void> {
    if (token !== "ok") {
      throw new RpcError("unauthenticated", "Invalid App Check token");
    }
  },
};

export function testSql(): Sql {
  return createPool(TEST_DATABASE_URL, { max: 4 });
}

export async function resetDatabase(sql: Sql): Promise<void> {
  const tables = await sql<{ tablename: string }[]>`
    SELECT tablename FROM pg_tables
    WHERE schemaname = 'public' AND tablename <> 'pgmigrations'`;
  if (tables.length > 0) {
    await sql.unsafe(
      `TRUNCATE ${tables.map((t) => `"${t.tablename}"`).join(", ")} CASCADE`,
    );
  }
}

export async function seedWorkspace(
  sql: Sql,
  input: { workspaceId: string; ownerUid: string; members?: Record<string, string> },
): Promise<void> {
  await sql`INSERT INTO workspaces (id, owner_uid, name)
            VALUES (${input.workspaceId}, ${input.ownerUid}, 'Test Workspace')`;
  const members = { [input.ownerUid]: "owner", ...(input.members ?? {}) };
  for (const [uid, role] of Object.entries(members)) {
    await sql`INSERT INTO memberships (id, workspace_id, user_uid, role)
              VALUES (${`${input.workspaceId}_${uid}`}, ${input.workspaceId}, ${uid}, ${role})`;
  }
}

export async function buildTestApp(
  sql: Sql,
  registry: RpcRegistry,
  overrides: { rateLimitMax?: number } = {},
): Promise<FastifyInstance> {
  const app = await buildApp({
    sql,
    verifier: stubVerifier,
    registry,
    logLevel: "silent",
    rateLimitMax: overrides.rateLimitMax,
  });
  await app.ready();
  return app;
}

export function authHeaders(uid: string, idempotencyKey?: string): Record<string, string> {
  return {
    authorization: `Bearer valid:${uid}`,
    "x-firebase-appcheck": "ok",
    ...(idempotencyKey ? { "x-idempotency-key": idempotencyKey } : {}),
  };
}
