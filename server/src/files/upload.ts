import { createHash, randomUUID } from "node:crypto";
import { createWriteStream } from "node:fs";
import { chmod, mkdir, rename, rm } from "node:fs/promises";
import path from "node:path";
import { pipeline } from "node:stream/promises";

import multipart from "@fastify/multipart";
import type { FastifyInstance, FastifyRequest } from "fastify";

import type { Sql } from "../db/pool";
import { RpcError } from "../domain/errors";
import { runIdempotent } from "../rpc/idempotency";
import type { FilesConfig } from "./signing";

/**
 * POST /v1/files (contracts/files-api.md), replacing Firebase Storage uploads. Limits are copied
 * from storage.rules: 10 MB, content types per kind (full match, like `matches()`), and the owner
 * segment is always the caller, so `owner(userId)` holds by construction.
 */
const MAX_BYTES = 10 * 1024 * 1024;

const ATTACHMENT_TYPES =
  /^(application\/pdf|image\/(jpeg|png|gif)|text\/(plain|csv)|application\/(msword|vnd\.openxmlformats-officedocument\.wordprocessingml\.document|vnd\.ms-excel|vnd\.openxmlformats-officedocument\.spreadsheetml\.sheet|vnd\.ms-powerpoint|vnd\.openxmlformats-officedocument\.presentationml\.presentation|zip))$/;

const KINDS: Record<string, RegExp> = {
  receipts: ATTACHMENT_TYPES,
  attachments: ATTACHMENT_TYPES,
  "voice-expenses": /^audio\/(wav|mpeg|aac|webm|mp4)$/,
  "profile-photos": /^image\/(jpeg|png)$/,
};

const EXTENSIONS: Record<string, string> = {
  "application/pdf": "pdf",
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/gif": "gif",
  "text/plain": "txt",
  "text/csv": "csv",
  "application/msword": "doc",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
  "application/vnd.ms-excel": "xls",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xlsx",
  "application/vnd.ms-powerpoint": "ppt",
  "application/vnd.openxmlformats-officedocument.presentationml.presentation": "pptx",
  "application/zip": "zip",
  "audio/wav": "wav",
  "audio/mpeg": "mp3",
  "audio/aac": "aac",
  "audio/webm": "webm",
  "audio/mp4": "m4a",
};

export interface UploadResult {
  storagePath: string;
  contentType: string;
  sizeBytes: number;
  sha256: string;
}

function header(request: FastifyRequest, name: string): string {
  const value = request.headers[name];
  return (Array.isArray(value) ? value[0] : value ?? "").trim();
}

/** Registered inside the authenticated RPC scope (router.ts), so request.uid is set. */
export async function registerUploadRoute(scope: FastifyInstance, deps: { sql: Sql; files: FilesConfig }): Promise<void> {
  await scope.register(multipart, { limits: { fileSize: MAX_BYTES, files: 1, fields: 5 } });
  const root = path.resolve(deps.files.root);

  scope.post("/v1/files", async (request, reply) => {
    const uid = request.uid as string;
    const idempotencyKey = header(request, "x-idempotency-key");
    if (!idempotencyKey) {
      throw new RpcError("invalid-argument", "Missing X-Idempotency-Key header");
    }
    if (!request.isMultipart()) {
      throw new RpcError("invalid-argument", "Expected a multipart upload");
    }

    let kind = "";
    let result: UploadResult | null = null;
    for await (const part of request.parts()) {
      if (part.type === "field") {
        if (part.fieldname === "kind") kind = `${part.value ?? ""}`.trim();
        continue;
      }
      if (part.fieldname !== "file" || result) {
        part.file.resume();
        continue;
      }
      const allowed = KINDS[kind];
      if (!allowed) {
        part.file.resume();
        throw new RpcError("invalid-argument", "Unsupported upload kind");
      }
      const contentType = part.mimetype.trim().toLowerCase();
      if (!allowed.test(contentType)) {
        part.file.resume();
        throw new RpcError("invalid-argument", "Unsupported file type");
      }
      result = (await runIdempotent(deps.sql, { uid, functionName: "files.upload", idempotencyKey }, async () => {
        const storagePath = `${kind}/${uid}/${randomUUID()}.${EXTENSIONS[contentType] ?? "bin"}`;
        const target = path.resolve(root, storagePath);
        if (!target.startsWith(root + path.sep)) {
          throw new RpcError("invalid-argument", "Invalid upload path");
        }
        await mkdir(path.dirname(target), { recursive: true });
        const partial = `${target}.part`;
        const hash = createHash("sha256");
        let size = 0;
        part.file.on("data", (chunk: Buffer) => {
          hash.update(chunk);
          size += chunk.length;
        });
        try {
          await pipeline(part.file, createWriteStream(partial, { mode: 0o600 }));
          if (part.file.truncated) {
            throw new RpcError("invalid-argument", "File is too large");
          }
          await chmod(partial, 0o600);
          await rename(partial, target);
        } catch (error) {
          await rm(partial, { force: true });
          if ((error as { code?: string }).code === "FST_REQ_FILE_TOO_LARGE") {
            throw new RpcError("invalid-argument", "File is too large");
          }
          throw error;
        }
        return { storagePath, contentType, sizeBytes: size, sha256: hash.digest("hex") } satisfies UploadResult;
      })) as UploadResult;
      // A replay returns the stored result without reading this upload.
      if (!part.file.readableEnded) part.file.resume();
    }
    if (!result) {
      throw new RpcError("invalid-argument", "Missing file");
    }
    return reply.status(201).send(result);
  });
}
