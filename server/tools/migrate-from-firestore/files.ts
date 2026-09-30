/**
 * Copies attachment files from Firebase Storage to the VPS file store (tasks.md T037) and
 * checksums both sides for the verification report. Paths are preserved exactly
 * (`<FILES_ROOT>/<storagePath>`), so record metadata needs no rewrite.
 */
import { createHash } from "node:crypto";
import { chmod, mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

/** Minimal slice of @google-cloud/storage's Bucket used here (keeps this testable). */
export interface BucketLike {
  getFiles(options: { prefix: string; autoPaginate?: boolean }): Promise<
    [Array<{ name: string; metadata: { md5Hash?: string; size?: string | number }; download(): Promise<[Buffer]> }>]
  >;
}

export const ATTACHMENT_PREFIXES = ["receipts/", "attachments/", "voice-expenses/", "profile-photos/"];

export interface FileCheck {
  storagePath: string;
  sourceMd5: string;
  targetMd5: string | null;
}

function hexMd5(data: Buffer): string {
  return createHash("md5").update(data).digest("hex");
}

/** Resolves `storagePath` under `root`, refusing anything that would escape it. */
export function safeTarget(root: string, storagePath: string): string {
  const resolvedRoot = path.resolve(root);
  const target = path.resolve(resolvedRoot, storagePath);
  if (!target.startsWith(resolvedRoot + path.sep)) {
    throw new Error(`Refusing to write outside FILES_ROOT: ${storagePath}`);
  }
  return target;
}

export async function copyStorageFiles(
  bucket: BucketLike,
  root: string,
  prefixes: string[] = ATTACHMENT_PREFIXES,
): Promise<FileCheck[]> {
  const checks: FileCheck[] = [];
  for (const prefix of prefixes) {
    const [files] = await bucket.getFiles({ prefix, autoPaginate: true });
    for (const file of files) {
      if (file.name.endsWith("/")) continue; // folder placeholder
      const [data] = await file.download();
      // GCS reports MD5 as base64; compare as hex. Fall back to hashing the download.
      const sourceMd5 = file.metadata.md5Hash
        ? Buffer.from(file.metadata.md5Hash, "base64").toString("hex")
        : hexMd5(data);
      const target = safeTarget(root, file.name);
      await mkdir(path.dirname(target), { recursive: true });
      await writeFile(target, data);
      await chmod(target, 0o600);
      const written = await readFile(target);
      checks.push({ storagePath: file.name, sourceMd5, targetMd5: hexMd5(written) });
    }
  }
  return checks;
}
