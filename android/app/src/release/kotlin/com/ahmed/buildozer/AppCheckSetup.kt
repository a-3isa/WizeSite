package com.ahmed.buildozer

import android.util.Log
import com.google.firebase.appcheck.FirebaseAppCheck
import com.google.firebase.appcheck.playintegrity.PlayIntegrityAppCheckProviderFactory

object AppCheckSetup {
    fun install(firebaseAppCheck: FirebaseAppCheck, @Suppress("UNUSED_PARAMETER") context: android.content.Context) {
        val factory = PlayIntegrityAppCheckProviderFactory.getInstance()
        firebaseAppCheck.installAppCheckProviderFactory(factory)
        Log.i("AppCheckSetup", "Play Integrity App Check provider installed")
    }
}
