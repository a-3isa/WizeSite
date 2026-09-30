import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import path from "node:path";

import type { FastifyInstance } from "fastify";

import { assertMember } from "../auth/roles";
import { RpcError } from "../domain/errors";
import { isAllowedAttachmentStoragePath } from "../domain/storage_lifecycle";
import type { RpcRegistry } from "../rpc/types";
import { asRecord, requireString } from "../rpc/validation";
import { SIGNED_URL_TTL_SECONDS, signedFileUrl, verifySignedFile, type FilesConfig } from "./signing";

const CONTENT_TYPES: Record<string, string> = {
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".png": "image/png",
  ".webp": "image/webp",
  ".heic": "image/heic",
  ".gif": "image/gif",
  ".pdf": "application/pdf",
  ".m4a": "audio/mp4",
  ".mp3": "audio/mpeg",
  ".wav": "audio/wav",
  ".webm": "audio/webm",
  ".aac": "audio/aac",
  ".mp4": "video/mp4",
};

/** Port of getAttachmentDownloadUrl: financial roles only, same messages, same result shape. */
export function fileRpcs(files: FilesConfig): RpcRegistry {
  return {
    getAttachmentDownloadUrl: {
      mutating: false,
      async handler(ctx, raw) {
        const data = asRecord(raw);
        const workspaceId = requireString(data, "workspaceId");
        const storagePath = requireString(data, "storagePath");
        const role = await assertMember(ctx.sql, workspaceId, ctx.uid);
        if (role !== "owner" && role !== "admin" && role !== "accountingApproved") {
          throw new RpcError("permission-denied", "Accounting access required to download attachments");
        }
        if (!isAllowedAttachmentStoragePath(storagePath)) {
          throw new RpcError("invalid-argument", "Invalid attachment storage path");
        }
        return { downloadUrl: signedFileUrl(files, storagePath), expiresInSeconds: SIGNED_URL_TTL_SECONDS };
      },
    },
  };
}

/** GET /v1/files/signed/<storagePath>?exp=&sig= — the signature is the authorisation. */
export function registerSignedFileRoute(app: FastifyInstance, files: FilesConfig): void {
  const root = path.resolve(files.root);
  app.get<{ Params: { "*": string }; Querystring: { exp?: string; sig?: string } }>(
    "/v1/files/signed/*",
    async (request, reply) => {
      const storagePath = request.params["*"];
      const exp = Number(request.query.exp);
      if (!verifySignedFile(files, storagePath, exp, `${request.query.sig ?? ""}`)) {
        return reply.status(403).send({ error: { code: "permission-denied", message: "Link expired or invalid" } });
      }
      const target = path.resolve(root, storagePath);
      if (!target.startsWith(root + path.sep)) {
        return reply.status(403).send({ error: { code: "permission-denied", message: "Link expired or invalid" } });
      }
      try {
        const info = await stat(target);
        if (!info.isFile()) throw new Error("not a file");
      } catch {
        return reply.status(404).send({ error: { code: "not-found", message: "File not found" } });
      }
      const fileName = path.basename(storagePath);
      return reply
        .header("content-type", CONTENT_TYPES[path.extname(fileName).toLowerCase()] ?? "application/octet-stream")
        .header("cache-control", `private, max-age=${SIGNED_URL_TTL_SECONDS}`)
        .header("content-disposition", `inline; filename*=UTF-8''${encodeURIComponent(fileName)}`)
        .send(createReadStream(target));
    },
  );
}
