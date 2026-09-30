/**
 * Typed access to server configuration. Every variable is documented in `.env.example`.
 * Required values throw at startup so a misconfigured server fails fast instead of at first request.
 */
export interface ServerConfig {
  databaseUrl: string;
  firebaseProjectId: string;
  filesRoot: string;
  filesSigningKey: string;
  openRouterApiKey: string;
  openRouterModel: string;
  openRouterTranscriptionModel: string;
  revenueCatWebhookSecret: string;
  publicApiUrl: string;
  port: number;
  logLevel: string;
}

function required(env: NodeJS.ProcessEnv, name: string): string {
  const value = env[name]?.trim();
  if (!value) {
    throw new Error(`Missing required environment variable ${name}`);
  }
  return value;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): ServerConfig {
  return {
    databaseUrl: required(env, "DATABASE_URL"),
    firebaseProjectId: env.FIREBASE_PROJECT_ID?.trim() || "wize-site",
    filesRoot: required(env, "FILES_ROOT"),
    filesSigningKey: required(env, "FILES_SIGNING_KEY"),
    openRouterApiKey: env.OPENROUTER_API_KEY?.trim() ?? "",
    openRouterModel: env.OPENROUTER_MODEL?.trim() || "openai/gpt-4o-mini",
    openRouterTranscriptionModel:
      env.OPENROUTER_TRANSCRIPTION_MODEL?.trim() || "openai/gpt-audio-mini",
    revenueCatWebhookSecret: env.REVENUECAT_WEBHOOK_SECRET?.trim() ?? "",
    publicApiUrl: required(env, "PUBLIC_API_URL").replace(/\/+$/, ""),
    port: Number.parseInt(env.PORT ?? "8080", 10),
    logLevel: env.LOG_LEVEL?.trim() || "info",
  };
}
