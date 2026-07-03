package com.meshsdk

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Trampoline for notification taps.
 *
 * Core BitChat's [com.bitchat.android.ui.NotificationManager] hardcodes its tap
 * PendingIntents to `Intent(context, com.bitchat.android.MainActivity::class.java)`.
 * That Activity is vendored (compiled) but never declared in the host app's
 * manifest — the host has its own launcher — so tapping a notification did
 * nothing. We can't edit Core, so the library manifest maps that component name
 * to THIS activity via an `<activity-alias android:name="com.bitchat.android.MainActivity">`.
 *
 * It simply brings the host app's own launcher activity to the front and
 * finishes, so a notification tap opens the app regardless of which activity the
 * consumer uses. (Any extras Core attached — e.g. the peer id — are available on
 * the incoming intent for future deep-linking, but are not required to open.)
 */
class NotificationLauncherActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        runCatching {
            packageManager.getLaunchIntentForPackage(packageName)?.let { launch ->
                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                startActivity(launch)
            }
        }
        finish()
    }
}
