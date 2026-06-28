package com.ahmed.buildozer

import android.content.Context
import android.util.Log
import com.google.firebase.appcheck.FirebaseAppCheck
import com.google.firebase.appcheck.debug.DebugAppCheckProviderFactory

object AppCheckSetup {
    @Suppress("UNUSED_PARAMETER")
    fun install(firebaseAppCheck: FirebaseAppCheck, context: Context) {
        firebaseAppCheck.installAppCheckProviderFactory(
            DebugAppCheckProviderFactory.getInstance(),
        )
        Log.i("AppCheckSetup", "Debug App Check provider installed")
    }
}
