import {RpcError as HttpsError} from "../../errors";

const MAX_AUDIO_BYTES = 25 * 1024 * 1024;
const ALLOWED_EXTENSIONS = new Set([".m4a", ".mp3", ".wav", ".webm", ".aac", ".mp4"]);

const TRANSCRIPTION_PROMPT = "You are a strict speech-to-text transcription engine for construction expense notes. " +
  "Transcribe the speech exactly as spoken. " +
  "Do not translate. Do not summarize. Do not explain. Do not normalize into another language. " +
  "Preserve the original spoken language and script exactly. " +
  "If the speaker uses Arabic, return Arabic. If the speaker uses English, return English. " +
  "If the speaker mixes Arabic and English, preserve the mixed-language transcript. " +
  "Preserve numbers, currency words, and project names exactly as spoken. " +
  "Return only the raw transcript text with no intro, no quotes, and no extra commentary.";

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

function audioFormatOf(storagePath: string): string {
  switch (extensionOf(storagePath)) {
  case ".m4a":
  case ".mp4":
    return "m4a";
  case ".mp3":
    return "mp3";
  case ".wav":
    return "wav";
  case ".webm":
    return "webm";
  case ".aac":
    return "aac";
  default:
    return "m4a";
  }
}

function readResponseText(payload: unknown): string {
  if (!payload || typeof payload !== "object") {
    return "";
  }

  const directText = (payload as Record<string, unknown>).text;
  if (typeof directText === "string") {
    return directText.trim();
  }

  const choices = (payload as Record<string, unknown>).choices;
  if (!Array.isArray(choices) || choices.length == 0) {
    return "";
  }

  const firstChoice = choices[0];
  if (!firstChoice || typeof firstChoice !== "object") {
    return "";
  }

  const message = (firstChoice as Record<string, unknown>).message;
  if (!message || typeof message !== "object") {
    return "";
  }

  const content = (message as Record<string, unknown>).content;
  if (typeof content === "string") {
    return content.trim();
  }

  if (Array.isArray(content)) {
    const merged = content
      .map((part) => {
        if (typeof part === "string") {
          return part;
        }
        if (!part || typeof part !== "object") {
          return "";
        }
        const candidate = (part as Record<string, unknown>).text;
        return typeof candidate === "string" ? candidate : "";
      })
      .join("\n")
      .trim();
    if (merged) {
      return merged;
    }
  }

  return "";
}

function cleanupTranscript(text: string): string {
  let normalized = text.trim();
  if (!normalized) {
    return "";
  }

  normalized = normalized.replace(/\r\n/g, "\n");

  // Strip common assistant-style wrappers if the model still adds them.
  normalized = normalized.replace(
    /^(sure|certainly|here(?:'s| is)|below is|the transcription(?: of the voice note)? is)[:,]?\s*/i,
    "",
  );
  normalized = normalized.replace(
    /^(?:sure,\s*)?here is the transcription(?: of the voice note)?[:\s]*/i,
    "",
  );

  const quotedMatch = normalized.match(/^["'](.*)["']$/s);
  if (quotedMatch?.[1]) {
    normalized = quotedMatch[1].trim();
  }

  return normalized.trim();
}

function readProviderErrorMessage(payload: unknown): string {
  if (!payload || typeof payload !== "object") {
    return "";
  }

  const error = (payload as Record<string, unknown>).error;
  if (!error || typeof error !== "object") {
    return "";
  }

  const message = (error as Record<string, unknown>).message;
  return typeof message === "string" ? message.trim() : "";
}

function transcriptionFailureForStatus(
  status: number,
  providerMessage: string,
): HttpsError {
  switch (status) {
  case 401:
  case 403:
    return new HttpsError(
      "failed-precondition",
      "Voice transcription is not configured correctly. Please check the OpenRouter API key and billing setup.",
    );
  case 429:
    return new HttpsError(
      "resource-exhausted",
      "Voice transcription quota has been exceeded. Please top up or enable billing for the OpenRouter API key.",
    );
  case 500:
  case 502:
  case 503:
  case 504:
    return new HttpsError(
      "unavailable",
      "Voice transcription is temporarily unavailable. Please try again in a moment.",
    );
  default:
    if (providerMessage) {
      return new HttpsError("internal", `Voice transcription failed [${status}]: ${providerMessage}`);
    }
    return new HttpsError("internal", `Voice transcription failed [${status}]`);
  }
}

/** Reads a stored audio file; resolves null when it does not exist. */
export type AudioReader = (storagePath: string) => Promise<Buffer | null>;

export async function transcribeAudioFromStorage(params: {
  storagePath: string;
  openRouterApiKey: string;
  model: string;
  languageHint?: string | null;
  readAudio: AudioReader;
}): Promise<string> {
  const storagePath = params.storagePath.trim();
  if (!storagePath) {
    throw new HttpsError("invalid-argument", "storagePath is required");
  }
  assertSupportedAudioPath(storagePath);

  const buffer = await params.readAudio(storagePath);
  if (buffer == null) {
    throw new HttpsError("not-found", "Voice file was not found in storage");
  }
  if (buffer.length === 0) {
    throw new HttpsError("failed-precondition", "Audio file is empty");
  }
  if (buffer.length > MAX_AUDIO_BYTES) {
    throw new HttpsError("invalid-argument", "Audio file is too large");
  }

  const base64Audio = buffer.toString("base64");
  const audioFormat = audioFormatOf(storagePath);
  const transcriptionInstruction = params.languageHint && params.languageHint.trim().length > 0 ?
    `${TRANSCRIPTION_PROMPT} The likely spoken language code is ${params.languageHint.trim()}. Keep the transcript in that original spoken language unless the audio is clearly mixed.` :
    TRANSCRIPTION_PROMPT;

  let response: Response;
  try {
    response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${params.openRouterApiKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://buildtrack.app",
        "X-Title": "BuildTrack",
      },
      body: JSON.stringify({
        model: params.model,
        messages: [
          {
            role: "user",
            content: [
              {
                type: "text",
                text: transcriptionInstruction,
              },
              {
                type: "input_audio",
                input_audio: {
                  data: base64Audio,
                  format: audioFormat,
                },
              },
            ],
          },
        ],
      }),
    });
  } catch (_error) {
    throw new HttpsError("internal", "Failed to reach transcription provider");
  }

  if (!response.ok) {
    const bodyText = await response.text();
    console.error(`[transcription] HTTP ${response.status} from OpenRouter. model=${params.model}`);
    let providerMessage = "";
    try {
      providerMessage = readProviderErrorMessage(JSON.parse(bodyText));
    } catch {
      providerMessage = bodyText.trim().slice(0, 180);
    }

    throw transcriptionFailureForStatus(response.status, providerMessage);
  }

  const payload = await response.json();
  const transcript = cleanupTranscript(readResponseText(payload));
  if (!transcript) {
    throw new HttpsError("failed-precondition", "Transcription was empty");
  }
  return transcript;
}
