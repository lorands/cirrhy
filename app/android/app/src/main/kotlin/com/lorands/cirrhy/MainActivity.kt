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

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var documents: DocumentFolders? = null
    private var badge: TimerBadge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val folders = DocumentFolders(this)
        documents = folders
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DocumentFolders.CHANNEL,
        ).setMethodCallHandler(folders)

        val timerBadge = TimerBadge(this)
        badge = timerBadge
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TimerBadge.CHANNEL,
        ).setMethodCallHandler(timerBadge)
    }

    // The folder picker is an activity, so its answer arrives here.
    @Deprecated("startActivityForResult is how a FlutterActivity receives this")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (documents?.onActivityResult(requestCode, resultCode, data) == true) return
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    // The notification-permission prompt's answer arrives the same way.
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (badge?.onRequestPermissionsResult(requestCode, grantResults) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        documents?.dispose()
        documents = null
        badge = null
        super.onDestroy()
    }
}
