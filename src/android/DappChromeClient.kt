/*
       Licensed to the Apache Software Foundation (ASF) under one
       or more contributor license agreements.  See the NOTICE file
       distributed with this work for additional information
       regarding copyright ownership.  The ASF licenses this file
       to you under the Apache License, Version 2.0 (the
       "License"); you may not use this file except in compliance
       with the License.  You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

       Unless required by applicable law or agreed to in writing,
       software distributed under the License is distributed on an
       "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
       KIND, either express or implied.  See the License for the
       specific language governing permissions and limitations
       under the License.
*/
package io.cochain.dappbrowser

import org.apache.cordova.CordovaWebView
import org.apache.cordova.LOG
import org.apache.cordova.PluginResult
import org.json.JSONArray
import org.json.JSONException

import android.webkit.JsPromptResult
import android.webkit.WebChromeClient
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.GeolocationPermissions.Callback

open class DappChromeClient(private val webView: CordovaWebView) : WebChromeClient() {
  private val LOG_TAG = "DappChromeClient"
  private val MAX_QUOTA = (100 * 1024 * 1024).toLong()

  /**
   * Handle database quota exceeded notification.
   *
   * @param url
   * @param databaseIdentifier
   * @param currentQuota
   * @param estimatedSize
   * @param totalUsedQuota
   * @param quotaUpdater
   */
  override fun onExceededDatabaseQuota(
    url: String, databaseIdentifier: String, currentQuota: Long, estimatedSize: Long,
    totalUsedQuota: Long, quotaUpdater: WebStorage.QuotaUpdater
  ) {
    LOG.d(
      LOG_TAG, "onExceededDatabaseQuota estimatedSize: %d  currentQuota: %d  totalUsedQuota: %d",
      estimatedSize, currentQuota, totalUsedQuota
    )
    quotaUpdater.updateQuota(MAX_QUOTA)
  }

  /**
   * Instructs the client to show a prompt to ask the user to set the Geolocation permission state for the specified origin.
   *
   * @param origin
   * @param callback
   */
  override fun onGeolocationPermissionsShowPrompt(origin: String, callback: Callback) {
    super.onGeolocationPermissionsShowPrompt(origin, callback)
    callback.invoke(origin, true, false)
  }

  /**
   * Tell the client to display a prompt dialog to the user.
   * If the client returns true, WebView will assume that the client will
   * handle the prompt dialog and call the appropriate JsPromptResult method.
   *
   * The prompt bridge provided for the InAppBrowser is capable of executing any
   * oustanding callback belonging to the InAppBrowser plugin. Care has been
   * taken that other callbacks cannot be triggered, and that no other code
   * execution is possible.
   *
   * To trigger the bridge, the prompt default value should be of the form:
   *
   * gap-iab://<callbackId>
   *
   * where <callbackId> is the string id of the callback to trigger (something
   * like "InAppBrowser0123456789")
   *
   * If present, the prompt message is expected to be a JSON-encoded value to
   * pass to the callback. A JSON_EXCEPTION is returned if the JSON is invalid.
   *
   * @param view
   * @param url
   * @param message
   * @param defaultValue
   * @param result
  </callbackId></callbackId> */
  override fun onJsPrompt(view: WebView, url: String, message: String?, defaultValue: String?, result: JsPromptResult): Boolean {
    // See if the prompt string uses the 'gap-iab' protocol. If so, the remainder should be the id of a callback to execute.
    if (defaultValue != null && defaultValue.startsWith("gap")) {
      if (defaultValue.startsWith("gap-iab://")) {
        val scriptCallbackId = defaultValue.substring(10)
        if (scriptCallbackId.startsWith("DappBrowser")) {
          val scriptResult = if (message == null || message.isEmpty()) {
            PluginResult(PluginResult.Status.OK, JSONArray())
          } else {
            try {
              PluginResult(PluginResult.Status.OK, JSONArray(message))
            } catch (e: JSONException) {
              PluginResult(PluginResult.Status.JSON_EXCEPTION, e.message)
            }

          }
          this.webView.sendPluginResult(scriptResult, scriptCallbackId)
          result.confirm("")
          return true
        }
      } else {
        // Anything else with a gap: prefix should get this message
        LOG.w(LOG_TAG, "InAppBrowser does not support Cordova API calls: $url $defaultValue")
        result.cancel()
        return true
      }
    }
    return false
  }
}
