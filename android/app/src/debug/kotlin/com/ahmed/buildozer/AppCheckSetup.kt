package com.ahmed.buildozer

import android.content.Context
import android.util.Log
import com.google.firebase.appcheck.FirebaseAppCheck
import com.google.firebase.appcheck.debug.DebugAppCheckProviderFactory

object AppCheckSetup {
    // Token registered in Firebase Console under com.ahmed.buildozer > App Check > Debug tokens
    private const val DEBUG_TOKEN = "4977E101-6CA1-4EAF-B50D-6B32AD6A1B3B"
    private const val PREFS_NAME = "com.google.firebase.appcheck.debug.store.[DEFAULT]"
    private const val PREFS_KEY = "com.google.firebase.appcheck.debug.DEBUG_SECRET"

    fun install(firebaseAppCheck: FirebaseAppCheck, context: Context) {
        // Pre-populate the SharedPreferences key that DebugAppCheckProvider reads,
        // so it uses the token already registered in Firebase Console.
        context
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(PREFS_KEY, DEBUG_TOKEN)
            .apply()

        firebaseAppCheck.installAppCheckProviderFactory(
            DebugAppCheckProviderFactory.getInstance(),
        )
        Log.i("AppCheckSetup", "Debug App Check provider installed (token=$DEBUG_TOKEN)")
    }
}
