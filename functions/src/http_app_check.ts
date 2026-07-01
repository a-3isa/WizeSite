import {getAppCheck} from "firebase-admin/app-check";
import {HttpsError} from "firebase-functions/v2/https";

export async function verifyHttpAppCheck(
  appCheckToken: string | undefined,
  verifyToken: (token: string) => Promise<unknown> =
    (token: string) => getAppCheck().verifyToken(token),
): Promise<void> {
  if (!appCheckToken) {
    throw new HttpsError("failed-precondition", "Missing App Check token");
  }

  try {
    await verifyToken(appCheckToken);
  } catch {
    console.warn("HTTP callable endpoint received an invalid App Check token");
    throw new HttpsError("failed-precondition", "Invalid App Check token");
  }
}
