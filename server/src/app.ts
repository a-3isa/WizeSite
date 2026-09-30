import Fastify, { type FastifyInstance } from "fastify";

import { firebaseAuthAdmin, firebaseVerifier, type TokenVerifier } from "./auth/verify";
import { loadConfig } from "./config";
import { createPool, type Sql } from "./db/pool";
import { RpcError } from "./domain/errors";
import { registerSignedFileRoute } from "./files/download";
import type { FilesConfig } from "./files/signing";
import { buildRegistry } from "./rpc/registry";
import { registerRpcRoutes, sendRpcError } from "./rpc/router";
import type { RpcRegistry } from "./rpc/types";
import type { AuthAdmin } from "./rpc/user";
import { registerRevenueCatWebhook } from "./webhooks/revenuecat";

export interface AppDeps {
  sql: Sql;
  verifier: TokenVerifier;
  /** Defaults to buildRegistry({ files }); tests pass a custom registry. */
  registry?: RpcRegistry;
  /** Attachment store + URL signing; enables GET /v1/files/signed/*. */
  files?: FilesConfig;
  /** Firebase sign-in admin for updateUserProfile / deleteOwnAccount (default registry only). */
  authAdmin?: AuthAdmin;
  logLevel?: string;
  rateLimitMax?: number;
  /** REVENUECAT_WEBHOOK_SECRET; when set (even empty) POST /v1/webhooks/revenuecat is served. */
  revenueCatWebhookSecret?: string;
  /** PowerSync base URL probed by /healthz; omitted in tests. */
  syncHealthUrl?: string;
}

const BODY_LIMIT_BYTES = 1024 * 1024;

export async function buildApp(deps: AppDeps): Promise<FastifyInstance> {
  const app = Fastify({
    bodyLimit: BODY_LIMIT_BYTES,
    logger: deps.logLevel === "silent" ? false : { level: deps.logLevel ?? "info" },
  });

  app.setErrorHandler((error, request, reply) => {
    if (error instanceof RpcError) {
      return sendRpcError(reply, error);
    }
    const statusCode = (error as { statusCode?: number }).statusCode;
    if (statusCode === 413) {
      return reply
        .status(413)
        .send({ error: { code: "invalid-argument", message: "Request body too large" } });
    }
    if (statusCode === 400 || (error as { validation?: unknown }).validation) {
      return sendRpcError(reply, new RpcError("invalid-argument", "Malformed request"));
    }
    request.log.error({ err: error }, "unhandled RPC error");
    return sendRpcError(reply, new RpcError("internal", "Something went wrong. Please try again."));
  });

  app.get("/healthz", async (_request, reply) => {
    let db = "ok";
    let sync = "skipped";
    try {
      await deps.sql`SELECT 1`;
    } catch {
      db = "down";
    }
    if (deps.syncHealthUrl) {
      try {
        const res = await fetch(`${deps.syncHealthUrl}/probes/liveness`, {
          signal: AbortSignal.timeout(3000),
        });
        sync = res.ok ? "ok" : "down";
      } catch {
        sync = "down";
      }
    }
    const healthy = db === "ok" && sync !== "down";
    return reply.status(healthy ? 200 : 503).send({ status: healthy ? "ok" : "degraded", db, sync });
  });

  if (deps.files) {
    registerSignedFileRoute(app, deps.files);
  }
  if (deps.revenueCatWebhookSecret !== undefined) {
    registerRevenueCatWebhook(app, { sql: deps.sql, secret: deps.revenueCatWebhookSecret });
  }
  const registry =
    deps.registry ?? (deps.files ? buildRegistry({ files: deps.files, authAdmin: deps.authAdmin }) : undefined);
  if (!registry) {
    throw new Error("buildApp needs either a registry or files config");
  }
  await registerRpcRoutes(app, {
    sql: deps.sql,
    verifier: deps.verifier,
    registry,
    rateLimitMax: deps.rateLimitMax,
  });
  return app;
}

async function main(): Promise<void> {
  const config = loadConfig();
  const sql = createPool(config.databaseUrl);
  const app = await buildApp({
    sql,
    verifier: firebaseVerifier(config.firebaseProjectId),
    authAdmin: firebaseAuthAdmin(config.firebaseProjectId),
    revenueCatWebhookSecret: config.revenueCatWebhookSecret,
    files: { root: config.filesRoot, signingKey: config.filesSigningKey, publicUrl: config.publicApiUrl },
    logLevel: config.logLevel,
    syncHealthUrl: process.env.SYNC_HEALTH_URL,
  });
  const shutdown = async () => {
    await app.close();
    await sql.end({ timeout: 5 });
    process.exit(0);
  };
  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
  await app.listen({ host: "0.0.0.0", port: config.port });
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
