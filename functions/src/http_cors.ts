const defaultOrigins = [
  "https://wize-site.web.app",
  "https://wize-site.firebaseapp.com",
];

const allowedHeaders = "Content-Type, Authorization, X-Firebase-AppCheck";

type CorsRequest = {
  method: string;
  header(name: string): string | undefined;
};

type CorsResponse = {
  set(name: string, value: string): unknown;
  status(code: number): {send(body: string): unknown};
};

type CorsOptions = {
  allowedOrigins?: readonly string[];
};

export function defaultCorsAllowedOrigins(): string[] {
  const configured = process.env.CORS_ALLOWED_ORIGINS;
  if (configured?.trim()) {
    return configured
      .split(",")
      .map((origin) => origin.trim())
      .filter((origin) => origin.length > 0);
  }
  return [...defaultOrigins];
}

export function isAllowedCorsOrigin(
  origin: string | undefined,
  options: CorsOptions = {},
): boolean {
  if (!origin) {
    return false;
  }
  const allowedOrigins = options.allowedOrigins ?? defaultCorsAllowedOrigins();
  return allowedOrigins.includes(origin);
}

export function applyCorsHeaders(
  request: CorsRequest,
  response: CorsResponse,
  options: CorsOptions = {},
): boolean {
  const origin = request.header("Origin");
  response.set("Vary", "Origin");
  response.set("Access-Control-Allow-Headers", allowedHeaders);
  response.set("Access-Control-Allow-Methods", "POST, OPTIONS");

  if (isAllowedCorsOrigin(origin, options)) {
    response.set("Access-Control-Allow-Origin", origin as string);
  } else if (request.method === "OPTIONS" && origin) {
    response.status(403).send("");
    return true;
  }

  if (request.method === "OPTIONS") {
    response.status(204).send("");
    return true;
  }

  return false;
}
