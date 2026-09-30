import { getApps, initializeApp } from "firebase-admin/app";
import { getAppCheck } from "firebase-admin/app-check";
import { getAuth } from "firebase-admin/auth";

import { RpcError } from "../domain/errors";

export interface VerifiedCaller {
  uid: string;
  email?: string;
  /** Display name and photo from the ID token (used by workspace bootstrap). */
  name?: string;
  picture?: string;
}

/** Verifies the two tokens every request carries (contracts/rpc-api.md). */
export interface TokenVerifier {
  verifyIdToken(token: string): Promise<VerifiedCaller>;
  verifyAppCheck(token: string): Promise<void>;
}

/** Production verifier: Firebase Auth ID tokens + App Check tokens, as enforced today. */
export function firebaseVerifier(projectId: string): TokenVerifier {
  // No explicit credential: ID-token and App Check verification use Google's public keys; account
  // deletion uses GOOGLE_APPLICATION_CREDENTIALS, which firebase-admin picks up by default.
  const app = getApps()[0] ?? initializeApp({ projectId });
  const auth = getAuth(app);
  const appCheck = getAppCheck(app);
  return {
    async verifyIdToken(token) {
      try {
        const decoded = await auth.verifyIdToken(token);
        return {
          uid: decoded.uid,
          email: decoded.email,
          name: typeof decoded.name === "string" ? decoded.name : undefined,
          picture: decoded.picture,
        };
      } catch {
        throw new RpcError("unauthenticated", "Please sign in to continue.");
      }
    },
    async verifyAppCheck(token) {
      try {
        await appCheck.verifyToken(token);
      } catch {
        throw new RpcError("unauthenticated", "App verification failed.");
      }
    },
  };
}
