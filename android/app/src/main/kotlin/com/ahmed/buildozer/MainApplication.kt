package com.ahmed.buildozer

import android.app.Application
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.appcheck.FirebaseAppCheck

class MainApplication : Application() {
    companion object {
        private const val TAG = "AppCheckSetup"
    }

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "MainApplication.onCreate — installing App Check")
        FirebaseApp.initializeApp(this)
        val firebaseAppCheck = FirebaseAppCheck.getInstance()
        AppCheckSetup.install(firebaseAppCheck, this)
        firebaseAppCheck.getAppCheckToken(false)
            .addOnSuccessListener { result ->
                Log.i(TAG, "App Check token obtained (len=${result.token.length})")
            }
            .addOnFailureListener { error ->
                Log.e(TAG, "App Check token failed: ${error.message}")
            }
    }
}
