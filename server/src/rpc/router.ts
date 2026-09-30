import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import rateLimit from "@fastify/rate-limit";

import type { TokenVerifier, VerifiedCaller } from "../auth/verify";
import type { Sql } from "../db/pool";
import { RpcError, type RpcErrorCode } from "../domain/errors";
import type { FilesConfig } from "../files/signing";
import { registerUploadRoute } from "../files/upload";
import { runIdempotent } from "./idempotency";
import type { RpcRegistry } from "./types";

/** HTTP status per error code (contracts/rpc-api.md). */
export const HTTP_STATUS: Record<RpcErrorCode, number> = {
  ok: 200,
  cancelled: 499,
  unknown: 500,
  "invalid-argument": 400,
  "deadline-exceeded": 504,
  "not-found": 404,
  "already-exists": 409,
  "permission-denied": 403,
  "resource-exhausted": 429,
  "failed-precondition": 412,
  aborted: 409,
  "out-of-range": 400,
  unimplemented: 501,
  internal: 500,
  unavailable: 503,
  "data-loss": 500,
  unauthenticated: 401,
};

const DEFAULT_TIMEOUT_MS = 30_000;

declare module "fastify" {
  interface FastifyRequest {
    uid?: string;
    caller?: VerifiedCaller;
  }
}

function header(request: FastifyRequest, name: string): string {
  const value = request.headers[name];
  return (Array.isArray(value) ? value[0] : value ?? "").trim();
}

export function sendRpcError(reply: FastifyReply, error: RpcError): FastifyReply {
  const body: { code: string; message: string; details?: unknown } = {
    code: error.code,
    message: error.message,
  };
  if (error.details !== undefined) {
    body.details = error.details;
  }
  return reply.status(HTTP_STATUS[error.code] ?? 500).send({ error: body });
}

async function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  let timer: NodeJS.Timeout | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(
      () => reject(new RpcError("deadline-exceeded", "The request took too long.")),
      ms,
    );
  });
  try {
    return await Promise.race([promise, timeout]);
  } finally {
    clearTimeout(timer);
  }
}

export async function registerRpcRoutes(
  app: FastifyInstance,
  deps: { sql: Sql; verifier: TokenVerifier; registry: RpcRegistry; rateLimitMax?: number; upload?: FilesConfig },
): Promise<void> {
  await app.register(async (scope) => {
    // 1. Authenticate every RPC: Firebase ID token + App Check token.
    scope.addHook("preValidation", async (request) => {
      const authorization = header(request, "authorization");
      const idToken = authorization.toLowerCase().startsWith("bearer ")
        ? authorization.slice(7).trim()
        : "";
      if (!idToken) {
        throw new RpcError("unauthenticated", "Please sign in to continue.");
      }
      const caller = await deps.verifier.verifyIdToken(idToken);
      await deps.verifier.verifyAppCheck(header(request, "x-firebase-appcheck"));
      request.uid = caller.uid;
      request.caller = caller;
    });

    // 2. Per-uid rate limit, after authentication so the key is the caller, not the IP.
    await scope.register(rateLimit, {
      hook: "preHandler",
      max: deps.rateLimitMax ?? 120,
      timeWindow: "1 minute",
      keyGenerator: (request) => request.uid ?? request.ip,
      errorResponseBuilder: (_request, context) =>
        Object.assign(
          new RpcError("resource-exhausted", "Too many requests. Please slow down.", {
            retryAfterSeconds: Math.max(1, Math.ceil(context.ttl / 1000)),
          }),
          { statusCode: 429 },
        ),
    });

    // 3. POST /v1/files shares the same authentication and rate limit.
    if (deps.upload) {
      await registerUploadRoute(scope, { sql: deps.sql, files: deps.upload });
    }

    scope.post<{ Params: { name: string }; Body: { data?: unknown } }>(
      "/v1/rpc/:name",
      async (request, reply) => {
        const name = request.params.name;
        const fn = Object.prototype.hasOwnProperty.call(deps.registry, name)
          ? deps.registry[name]
          : undefined;
        if (!fn) {
          throw new RpcError("not-found", `Unknown function: ${name}`);
        }
        const data = request.body?.data ?? {};
        const uid = request.uid as string;
        const { email, name: callerName, picture, authTime } = request.caller ?? { uid };
        const timeoutMs = fn.timeoutMs ?? DEFAULT_TIMEOUT_MS;

        let result: unknown;
        if (fn.mutating) {
          const idempotencyKey = header(request, "x-idempotency-key");
          if (!idempotencyKey) {
            throw new RpcError("invalid-argument", "Missing X-Idempotency-Key header");
          }
          result = await withTimeout(
            runIdempotent(deps.sql, { uid, functionName: name, idempotencyKey }, (tx) =>
              fn.handler({ uid, email, name: callerName, picture, authTime, sql: tx }, data),
            ),
            timeoutMs,
          );
        } else {
          result = await withTimeout(
            fn.handler({ uid, email, name: callerName, picture, authTime, sql: deps.sql }, data),
            timeoutMs,
          );
        }
        return reply.send({ result: result ?? null });
      },
    );
  });
}
