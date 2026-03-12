# Firebase Android setup (fix reCAPTCHA / App Check errors)

## 1. Fix "CONFIGURATION_NOT_FOUND" for sign-up (reCAPTCHA)

This error means Firebase Auth cannot verify your Android app because the app’s **SHA-1** and **SHA-256** are not registered in Firebase.

### Get your SHA fingerprints

**Option A – keytool (recommended on Windows):**

Uses the default debug keystore. In PowerShell or Command Prompt:

```powershell
keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```

In the output, find **SHA1:** and **SHA256:** and copy those values (without colons, or as shown—Firebase accepts both).

**Option B – Gradle signing report:**

```powershell
cd android
.\gradlew signingReport
```

Under **Variant: debug**, copy the **SHA-1** and **SHA-256** values. (If this fails, use Option A.)

(For release builds, use your release keystore path and alias with keytool, or your signing config in Gradle.)

### Add them in Firebase Console

1. Open [Firebase Console](https://console.firebase.google.com/) → your project.
2. Go to **Project settings** (gear) → **Your apps**.
3. Select your **Android** app (`com.ahmed.buildozer`).
4. Click **Add fingerprint** and add:
   - The **SHA-1** from the signing report.
   - The **SHA-256** from the signing report.
5. Download the updated **google-services.json** and replace `android/app/google-services.json`.
6. Rebuild and run the app. Email/password sign-up should work.

---

## 2. App Check debug token (optional)

If you see "No AppCheckProvider installed" or use App Check in debug:

1. Run the app in debug once.
2. In logcat/console, look for a line like:
   ```
   D DebugAppCheckProvider: Enter this debug secret into the allow list in the Firebase Console for your project: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   ```
3. In Firebase Console go to **App Check** → **Manage debug tokens**.
4. Click **Add debug token**, paste the token, name it (e.g. "Local dev"), and save.

After adding SHA-1/SHA-256 and (if needed) the App Check debug token, rebuild and run the app again.

---

## 3. Fix "DEVELOPER_ERROR" / "Unknown calling package" (Google Sign-In)

If you see `ConnectionResult{statusCode=DEVELOPER_ERROR}` or `Unknown calling package name` when using **Google Sign-In**:

1. **Confirm SHA-1 and SHA-256** are added in **Firebase Console** (Project settings → Your apps → Android app) as in section 1 above. Google Sign-In uses the same fingerprints.

2. **Check the OAuth client in Google Cloud Console:**
   - Open [Google Cloud Console](https://console.cloud.google.com/) → your project (same as Firebase).
   - Go to **APIs & Services** → **Credentials**.
   - Under **OAuth 2.0 Client IDs**, find the **Android** client (or create one).
   - Its **Package name** must be exactly: `com.ahmed.buildozer`.
   - It must have your app’s **SHA-1** (and ideally SHA-256) added. Edit the client and add the same SHA-1 you added in Firebase.

3. **Download `google-services.json` again** from Firebase (Project settings → Your apps → Android) after adding SHA fingerprints, then replace `android/app/google-services.json`.

4. **Clean and rebuild:**  
   `flutter clean` then `flutter run`.

If the Android OAuth client was created by Firebase, updating the SHA in Firebase and re-downloading `google-services.json` can update the client. If the error persists, add the SHA-1 explicitly to the Android OAuth client in Google Cloud Console.
