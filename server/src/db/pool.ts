import postgres from "postgres";

/** Tagged-template SQL client; the same type is used for pooled and transaction scopes. */
export type Sql = postgres.Sql;

export function createPool(url: string, options: { max?: number } = {}): Sql {
  return postgres(url, {
    max: options.max ?? 10,
    idle_timeout: 30,
    connect_timeout: 10,
    // NUMERIC arrives as a string, so money never passes through a float on the way in.
    onnotice: () => undefined,
  });
}
