import * as admin from "firebase-admin";
import {HttpsError} from "firebase-functions/v2/https";

const MAX_AUDIO_BYTES = 25 * 1024 * 1024;
const ALLOWED_EXTENSIONS = new Set([".m4a", ".mp3", ".wav", ".webm", ".aac", ".mp4"]);

const TRANSCRIPTION_PROMPT = "Transcribe this construction-site expense voice note accurately. " +
  "The language may be Arabic, English, or mixed Arabic-English. " +
  "Expect vocabulary related to labor, materials, equipment, transport, contractors, workers, projects, and expenses. " +
  "Preserve numbers and project names exactly.";

function extensionOf(path: string): string {
  const index = path.lastIndexOf(".");
  if (index < 0) {
    return "";
  }
  return path.slice(index).toLowerCase();
}

function assertSupportedAudioPath(storagePath: string): void {
  const ext = extensionOf(storagePath);
  if (!ALLOWED_EXTENSIONS.has(ext)) {
    throw new HttpsError("invalid-argument", "Unsupported audio file type");
  }
}

function readResponseText(payload: unknown): string {
  if (payload && typeof payload === "object") {
    const candidate = (payload as Record<string, unknown>).text;
    if (typeof candidate === "string") {
      return candidate.trim();
    }
  }
  return "";
}

export async function transcribeAudioFromStorage(params: {
  storagePath: string;
  openAiApiKey: string;
  languageHint?: string | null;
}): Promise<string> {
  const storagePath = params.storagePath.trim();
  if (!storagePath) {
    throw new HttpsError("invalid-argument", "storagePath is required");
  }
  assertSupportedAudioPath(storagePath);

  const bucket = admin.storage().bucket();
  const file = bucket.file(storagePath);
  const [exists] = await file.exists();
  if (!exists) {
    throw new HttpsError("not-found", "Voice file was not found in Firebase Storage");
  }

  const [buffer] = await file.download();
  if (!buffer || buffer.length === 0) {
    throw new HttpsError("failed-precondition", "Audio file is empty");
  }
  if (buffer.length > MAX_AUDIO_BYTES) {
    throw new HttpsError("invalid-argument", "Audio file is too large");
  }

  const form = new FormData();
  form.append("model", "whisper-1");
  form.append("prompt", TRANSCRIPTION_PROMPT);
  if (params.languageHint && params.languageHint.trim().length > 0) {
    form.append("language", params.languageHint.trim());
  }

  const filename = storagePath.split("/").pop() ?? "voice-note.m4a";
  const bytes = new Uint8Array(buffer);
  const blob = new Blob([bytes], {type: "audio/mp4"});
  form.append("file", blob, filename);

  let response: Response;
  try {
    response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${params.openAiApiKey}`,
      },
      body: form,
    });
  } catch (_error) {
    throw new HttpsError("internal", "Failed to reach transcription provider");
  }

  if (!response.ok) {
    const bodyText = await response.text();
    throw new HttpsError(
      "internal",
      `Transcription failed (${response.status}): ${bodyText.slice(0, 180)}`,
    );
  }

  const payload = await response.json();
  const transcript = readResponseText(payload);
  if (!transcript) {
    throw new HttpsError("failed-precondition", "Transcription was empty");
  }
  return transcript;
}
