import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import path from "node:path";

import type { FastifyInstance } from "fastify";

import type { FilesConfig } from "./signing";

/**
 * GET /v1/public/profile-photos/{uid}/{uuid}.{jpg|png}: profile photos are shown from a permanent
 * link (user profile photoUrl, Firebase Auth photoURL), which signed 15-minute URLs cannot give.
 * Only uploaded profile photos are served: the path must be exactly profile-photos/{uid}/{uuid}
 * with an image extension, and upload names are random UUIDs, so links cannot be guessed and a
 * new photo gets a new URL (hence immutable caching). Every other file stays signed-URL only.
 */
const AVATAR_PATH = /^profile-photos\/[A-Za-z0-9_-]{1,128}\/[0-9a-f-]{36}\.(jpg|png)$/;
const CONTENT_TYPES: Record<string, string> = { jpg: "image/jpeg", png: "image/png" };

export function registerPublicAvatarRoute(app: FastifyInstance, files: FilesConfig): void {
  const root = path.resolve(files.root);
  app.get<{ Params: { "*": string } }>("/v1/public/*", async (request, reply) => {
    const storagePath = request.params["*"];
    const match = AVATAR_PATH.exec(storagePath);
    const target = path.resolve(root, storagePath);
    if (!match || !target.startsWith(root + path.sep)) {
      return reply.status(404).send({ error: { code: "not-found", message: "File not found" } });
    }
    try {
      const info = await stat(target);
      if (!info.isFile()) throw new Error("not a file");
    } catch {
      return reply.status(404).send({ error: { code: "not-found", message: "File not found" } });
    }
    return reply
      .header("content-type", CONTENT_TYPES[match[1]])
      .header("cache-control", "public, max-age=31536000, immutable")
      .header("x-content-type-options", "nosniff")
      .send(createReadStream(target));
  });
}
