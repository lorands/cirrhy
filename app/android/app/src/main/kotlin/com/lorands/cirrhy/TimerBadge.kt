// Copyright 2026 Lóránd Somogyi
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package com.lorands.cirrhy

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The Android half of the running-timer badge (TimerBadge on the Dart side).
 *
 * Android has no direct "badge my icon" API — launcher badges belong to
 * notifications. So a running timer is a silent ongoing notification in a
 * badge-enabled channel: the launcher shows its dot, the shade shows the
 * ticking elapsed time (the system chronometer, so no updates are pushed),
 * and tapping it opens the app. Stopping the timer cancels it.
 *
 * All user-visible text arrives localized from Dart — the ARB files are the
 * single home for strings, and this class must not grow literals of its own.
 *
 * On API 33+ a notification needs the POST_NOTIFICATIONS runtime permission.
 * It is asked for the first time a timer starts — the one moment the request
 * explains itself — and the pending notification is posted on grant. A
 * refusal is respected: the timer runs on, only the badge goes missing.
 */
class TimerBadge(private val activity: Activity) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.lorands.cirrhy/badge"
        private const val NOTIFICATION_CHANNEL = "running_timer"
        private const val NOTIFICATION_ID = 0x0C18
        private const val PERMISSION_REQUEST = 0x0C19
    }

    /** The call held back while the permission prompt is up. */
    private var pending: Notification? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "setTimer") {
            result.notImplemented()
            return
        }
        if (call.argument<Boolean>("running") == true) show(call) else hide()
        result.success(null)
    }

    /** MainActivity forwards permission answers here; true when consumed. */
    fun onRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pending?.takeIf { granted }?.let { manager().notify(NOTIFICATION_ID, it) }
        pending = null
        return true
    }

    private fun show(call: MethodCall) {
        val title = call.argument<String>("title") ?: return
        val startedAt = call.argument<Long>("startedAt")
        ensureChannel(call.argument<String>("channelName") ?: title)

        val open = PendingIntent.getActivity(
            activity,
            0,
            Intent(activity, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(activity, NOTIFICATION_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(activity).setPriority(Notification.PRIORITY_LOW)
        }
        builder
            .setSmallIcon(R.drawable.ic_stat_timer)
            .setContentTitle(title)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_STOPWATCH)
            .setNumber(1)
            .setContentIntent(open)
        call.argument<String>("subject")?.let { builder.setContentText(it) }
        if (startedAt != null) {
            builder.setWhen(startedAt).setShowWhen(true).setUsesChronometer(true)
        }
        val notification = builder.build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            activity.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            pending = notification
            activity.requestPermissions(
                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                PERMISSION_REQUEST,
            )
            return
        }
        manager().notify(NOTIFICATION_ID, notification)
    }

    private fun hide() {
        pending = null
        manager().cancel(NOTIFICATION_ID)
    }

    /**
     * Silent (IMPORTANCE_LOW) but badge-enabled — the badge is the point.
     * Re-created on every show: creating an existing channel only updates its
     * mutable fields, which is exactly how the name follows a language change.
     */
    private fun ensureChannel(name: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL,
            name,
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.setShowBadge(true)
        manager().createNotificationChannel(channel)
    }

    private fun manager(): NotificationManager =
        activity.getSystemService(NotificationManager::class.java)
}
