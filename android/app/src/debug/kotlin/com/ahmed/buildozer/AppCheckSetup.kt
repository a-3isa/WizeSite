package com.ahmed.buildozer

import android.content.Context
import android.util.Log
import com.google.firebase.appcheck.FirebaseAppCheck
import com.google.firebase.appcheck.debug.DebugAppCheckProviderFactory

object AppCheckSetup {
    // Token registered in Firebase Console under com.ahmed.buildozer > App Check > Debug tokens
    private const val DEBUG_TOKEN = "4977E101-6CA1-4EAF-B50D-6B32AD6A1B3B"

    fun install(firebaseAppCheck: FirebaseAppCheck, context: Context) {
        // Pre-populate the SharedPreferences key that DebugAppCheckProvider reads,
        // so it uses the token already registered in Firebase Console.
        context
            .getSharedPreferences("FirebaseAppCheckDebug.[DEFAULT]", Context.MODE_PRIVATE)
            .edit()
            .putString("debug_secret", DEBUG_TOKEN)
            .apply()

        firebaseAppCheck.installAppCheckProviderFactory(
            DebugAppCheckProviderFactory.getInstance(),
        )
        Log.i("AppCheckSetup", "Debug App Check provider installed (token=$DEBUG_TOKEN)")
    }
}
