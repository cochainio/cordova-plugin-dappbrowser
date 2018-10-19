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

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.provider.Browser
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.text.InputType
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.Window
import android.view.WindowManager
import android.view.WindowManager.LayoutParams
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.webkit.CookieManager
import android.webkit.CookieSyncManager
import android.webkit.HttpAuthHandler
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.EditText
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.RelativeLayout
import android.widget.TextView

import org.apache.cordova.CallbackContext
import org.apache.cordova.CordovaArgs
import org.apache.cordova.CordovaHttpAuthHandler
import org.apache.cordova.CordovaPlugin
import org.apache.cordova.CordovaWebView
import org.apache.cordova.LOG
import org.apache.cordova.PluginResult
import org.json.JSONException
import org.json.JSONObject

import java.util.Arrays
import java.util.HashMap
import java.util.StringTokenizer

@SuppressLint("SetJavaScriptEnabled")
class DappBrowser : CordovaPlugin() {

    private var callbackContext: CallbackContext? = null

    private var dialog: DappBrowserDialog? = null
    private var dappWebView: WebView? = null
    private var edittext: EditText? = null

    private var showLocationBar = true
    private var showZoomControls = true
    private var openWindowHidden = false
    private var clearAllCache = false
    private var clearSessionCache = false
    private var hadwareBackButton = true
    private var mediaPlaybackRequiresUserGesture = false
    private var shouldPauseDappBrowser = false
    private var useWideViewPort = true

    private var mUploadCallback: ValueCallback<Uri>? = null
    private var mUploadCallbackLollipop: ValueCallback<Array<Uri>>? = null
    private var closeButtonCaption = ""
    private var closeButtonColor = ""
    private var toolbarColor = android.graphics.Color.LTGRAY
    private var hideNavigationButtons = false
    private var navigationButtonColor = ""
    private var hideUrlBar = false
    private var showFooter = false
    private var footerColor = ""
    private var allowedSchemes: Array<String>? = null

    /**
     * Executes the request and returns PluginResult.
     *
     * @param action the action to execute.
     * @param args JSONArray of arguments for the plugin.
     * @param callbackContext the callbackContext used when calling back into JavaScript.
     * @return A PluginResult object with a status and message.
     */
    override fun execute(action: String, args: CordovaArgs, callbackContext: CallbackContext): Boolean {
        when (action) {
            "open" -> {
                this.callbackContext = callbackContext

                val url = args.getString(0)
                var target = args.optString(1)
                if (target == "" || target == NULL) {
                    target = SELF
                }
                val features = parseFeature(args.optString(2))

                LOG.d(LOG_TAG, "target = $target")

                this.cordova.activity.runOnUiThread {
                    var result = ""
                    if (SELF == target) {
                        if (url.startsWith("javascript:") || webView.pluginManager.shouldAllowNavigation(url)) {
                            LOG.d(LOG_TAG, "loading in self webview")
                            webView.loadUrl(url)
                        } else if (url.startsWith(WebView.SCHEME_TEL)) {
                            try {
                                LOG.d(LOG_TAG, "loading in dialer")
                                val intent = Intent(Intent.ACTION_DIAL)
                                intent.data = Uri.parse(url)
                                cordova.activity.startActivity(intent)
                            } catch (e: android.content.ActivityNotFoundException) {
                                LOG.e(LOG_TAG, "Error dialing " + url + ": " + e.toString())
                            }
                        } else {
                            LOG.d(LOG_TAG, "loading in DappBrowser")
                            result = showWebPage(url, features)
                        }
                    } else if (SYSTEM == target) {
                        LOG.d(LOG_TAG, "loading in system browser")
                        result = openExternal(url)
                    } else {
                        LOG.d(LOG_TAG, "loading in DappBrowser")
                        result = showWebPage(url, features)
                    }

                    val pluginResult = PluginResult(PluginResult.Status.OK, result)
                    pluginResult.keepCallback = true
                    callbackContext.sendPluginResult(pluginResult)
                }
            }

            "close" -> closeDialog()

            "injectScriptCode" -> {
                var jsWrapper: String? = null
                if (args.getBoolean(1)) {
                    jsWrapper = String.format(
                        "(function(){prompt(JSON.stringify([eval(%%s)]), 'gap-iab://%s')})()",
                        callbackContext.callbackId
                    )
                }
                injectDeferredObject(args.getString(0), jsWrapper)
            }

            "injectScriptFile" -> {
                val jsWrapper = if (args.getBoolean(1)) {
                    String.format(
                        "(function(d) { var c = d.createElement('script'); c.src = %%s; c.onload = function() { prompt('', 'gap-iab://%s'); }; d.body.appendChild(c); })(document)",
                        callbackContext.callbackId
                    )
                } else {
                    "(function(d) { var c = d.createElement('script'); c.src = %s; d.body.appendChild(c); })(document)"
                }
                injectDeferredObject(args.getString(0), jsWrapper)
            }

            "injectStyleCode" -> {
                val jsWrapper = if (args.getBoolean(1)) {
                    String.format(
                        "(function(d) { var c = d.createElement('style'); c.innerHTML = %%s; d.body.appendChild(c); prompt('', 'gap-iab://%s');})(document)",
                        callbackContext.callbackId
                    )
                } else {
                    "(function(d) { var c = d.createElement('style'); c.innerHTML = %s; d.body.appendChild(c); })(document)"
                }
                injectDeferredObject(args.getString(0), jsWrapper)
            }

            "injectStyleFile" -> {
                val jsWrapper = if (args.getBoolean(1)) {
                    String.format(
                        "(function(d) { var c = d.createElement('link'); c.rel='stylesheet'; c.type='text/css'; c.href = %%s; d.head.appendChild(c); prompt('', 'gap-iab://%s');})(document)",
                        callbackContext.callbackId
                    )
                } else {
                    "(function(d) { var c = d.createElement('link'); c.rel='stylesheet'; c.type='text/css'; c.href = %s; d.head.appendChild(c); })(document)"
                }
                injectDeferredObject(args.getString(0), jsWrapper)
            }

            "show" -> {
                this.cordova.activity.runOnUiThread { dialog!!.show() }
                val pluginResult = PluginResult(PluginResult.Status.OK)
                pluginResult.keepCallback = true
                this.callbackContext!!.sendPluginResult(pluginResult)
            }

            "hide" -> {
                this.cordova.activity.runOnUiThread { dialog!!.hide() }
                val pluginResult = PluginResult(PluginResult.Status.OK)
                pluginResult.keepCallback = true
                this.callbackContext!!.sendPluginResult(pluginResult)
            }
            else -> return false
        }
        return true
    }

    /**
     * Called when the view navigates.
     */
    override fun onReset() {
        closeDialog()
    }

    /**
     * Called when the system is about to start resuming a previous activity.
     */
    override fun onPause(multitasking: Boolean) {
        if (shouldPauseDappBrowser) {
            dappWebView!!.onPause()
        }
    }

    /**
     * Called when the activity will start interacting with the user.
     */
    override fun onResume(multitasking: Boolean) {
        if (shouldPauseDappBrowser) {
            dappWebView!!.onResume()
        }
    }

    /**
     * Called by AccelBroker when listener is to be shut down.
     * Stop listener.
     */
    override fun onDestroy() {
        closeDialog()
    }

    /**
     * Inject an object (script or style) into the DappBrowser WebView.
     *
     * This is a helper method for the inject{Script|Style}{Code|File} API calls, which
     * provides a consistent method for injecting JavaScript code into the document.
     *
     * If a wrapper string is supplied, then the source string will be JSON-encoded (adding
     * quotes) and wrapped using string formatting. (The wrapper string should have a single
     * '%s' marker)
     *
     * @param source      The source object (filename or script/style text) to inject into
     * the document.
     * @param jsWrapper   A JavaScript string to wrap the source string in, so that the object
     * is properly injected, or null if the source string is JavaScript text
     * which should be executed directly.
     */
    private fun injectDeferredObject(source: String, jsWrapper: String?) {
        if (dappWebView != null) {
            val scriptToInject = if (jsWrapper != null) {
                val jsonEsc = org.json.JSONArray()
                jsonEsc.put(source)
                val jsonRepr = jsonEsc.toString()
                val jsonSourceString = jsonRepr.substring(1, jsonRepr.length - 1)
                String.format(jsWrapper, jsonSourceString)
            } else {
                source
            }
            this.cordova.activity.runOnUiThread {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.KITKAT) {
                    // This action will have the side-effect of blurring the currently focused element
                    dappWebView!!.loadUrl("javascript:$scriptToInject")
                } else {
                    dappWebView!!.evaluateJavascript(scriptToInject, null)
                }
            }
        } else {
            LOG.e(LOG_TAG, "Can't inject code into the system browser")
        }
    }

    /**
     * Put the list of features into a hash map
     *
     * @param optString
     * @return
     */
    private fun parseFeature(optString: String): HashMap<String, String>? {
        if (optString == NULL) {
            return null
        } else {
            val map = HashMap<String, String>()
            val features = StringTokenizer(optString, ",")
            var option: StringTokenizer
            while (features.hasMoreElements()) {
                option = StringTokenizer(features.nextToken(), "=")
                if (option.hasMoreElements()) {
                    val key = option.nextToken()
                    var value = option.nextToken()
                    if (!customizableOptions.contains(key)) {
                        value = if (value == "yes" || value == "no") value else "yes"
                    }
                    map[key] = value
                }
            }
            return map
        }
    }

    /**
     * Display a new browser with the specified URL.
     *
     * @param url the url to load.
     * @return "" if ok, or error message.
     */
    fun openExternal(url: String): String {
        try {
            val intent = Intent(Intent.ACTION_VIEW)
            // Omitting the MIME type for file: URLs causes "No Activity found to handle Intent".
            // Adding the MIME type to http: URLs causes them to not be handled by the downloader.
            val uri = Uri.parse(url)
            if ("file" == uri.scheme) {
                intent.setDataAndType(uri, webView.resourceApi.getMimeType(uri))
            } else {
                intent.data = uri
            }
            intent.putExtra(Browser.EXTRA_APPLICATION_ID, cordova.activity.packageName)
            this.cordova.activity.startActivity(intent)
            return ""
            // not catching FileUriExposedException explicitly because buildtools<24 doesn't know about it
        } catch (e: java.lang.RuntimeException) {
            LOG.e(LOG_TAG, "loading url " + url + ":" + e.toString())
            return e.toString()
        }
    }

    /**
     * Closes the dialog
     */
    fun closeDialog() {
        this.cordova.activity.runOnUiThread(Runnable {
            val childView = dappWebView ?: return@Runnable
            // The JS protects against multiple calls, so this should happen only when
            // closeDialog() is called by other native code.

            childView.webViewClient = object : WebViewClient() {
                // NB: wait for about:blank before dismissing
                override fun onPageFinished(view: WebView, url: String) {
                    if (dialog != null) {
                        dialog!!.dismiss()
                        dialog = null
                    }
                }
            }
            // NB: From SDK 19: "If you call methods on WebView from any thread
            // other than your app's UI thread, it can cause unexpected results."
            // http://developer.android.com/guide/webapps/migrating.html#Threads
            childView.loadUrl("about:blank")

            try {
                val obj = JSONObject()
                obj.put("type", EXIT_EVENT)
                sendUpdate(obj, false)
            } catch (ex: JSONException) {
                LOG.d(LOG_TAG, "Should never happen")
            }
        })
    }

    /**
     * Checks to see if it is possible to go back one page in history, then does so.
     */
    fun goBack() {
        if (this.dappWebView!!.canGoBack()) {
            this.dappWebView!!.goBack()
        }
    }

    /**
     * Can the web browser go back?
     * @return boolean
     */
    fun canGoBack(): Boolean {
        return this.dappWebView!!.canGoBack()
    }

    /**
     * Has the user set the hardware back button to go back
     * @return boolean
     */
    fun hardwareBack(): Boolean {
        return hadwareBackButton
    }

    /**
     * Checks to see if it is possible to go forward one page in history, then does so.
     */
    private fun goForward() {
        if (this.dappWebView!!.canGoForward()) {
            this.dappWebView!!.goForward()
        }
    }

    /**
     * Navigate to the new page
     *
     * @param url to load
     */
    private fun navigate(url: String) {
        val imm = this.cordova.activity.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        imm.hideSoftInputFromWindow(edittext!!.windowToken, 0)

        if (!url.startsWith("http") && !url.startsWith("file:")) {
            this.dappWebView!!.loadUrl("http://$url")
        } else {
            this.dappWebView!!.loadUrl(url)
        }
        this.dappWebView!!.requestFocus()
    }

    /**
     * Display a new browser with the specified URL.
     *
     * @param url the url to load.
     * @param features jsonObject
     */
    fun showWebPage(url: String, features: HashMap<String, String>?): String {
        // Determine if we should hide the location bar.
        showLocationBar = true
        showZoomControls = true
        openWindowHidden = false
        mediaPlaybackRequiresUserGesture = false

        if (features != null) {
            val show = features[LOCATION]
            if (show != null) {
                showLocationBar = show == "yes"
            }
            if (showLocationBar) {
                hideNavigationButtons = features[HIDE_NAVIGATION] == "yes"
                hideUrlBar = features[HIDE_URL] == "yes"
            }
            val zoom = features[ZOOM]
            if (zoom != null) {
                showZoomControls = zoom == "yes"
            }
            openWindowHidden = features[HIDDEN] == "yes"
            val hardwareBack = features[HARDWARE_BACK_BUTTON]
            if (hardwareBack != null) {
                hadwareBackButton = hardwareBack == "yes"
            }
            mediaPlaybackRequiresUserGesture = features[MEDIA_PLAYBACK_REQUIRES_USER_ACTION] == "yes"
            var cache: String? = features[CLEAR_ALL_CACHE]
            if (cache != null) {
                clearAllCache = cache == "yes"
            } else {
                cache = features[CLEAR_SESSION_CACHE]
                if (cache != null) {
                    clearSessionCache = cache == "yes"
                }
            }
            shouldPauseDappBrowser = features[SHOULD_PAUSE] == "yes"
            val wideViewPort = features[USER_WIDE_VIEW_PORT]
            if (wideViewPort != null) {
                useWideViewPort = wideViewPort == "yes"
            }
            closeButtonCaption = features[CLOSE_BUTTON_CAPTION] ?: ""
            closeButtonColor = features[CLOSE_BUTTON_COLOR] ?: ""
            val toolbarColorSet = features[TOOLBAR_COLOR]
            if (toolbarColorSet != null) {
                toolbarColor = android.graphics.Color.parseColor(toolbarColorSet)
            }
            navigationButtonColor = features[NAVIGATION_COLOR] ?: ""
            showFooter = features[FOOTER] == "yes"
            footerColor = features[FOOTER_COLOR] ?: ""
        }

        val thatDappBrowser = this
        val thatWebView = this.webView

        // Create dialog in new thread
        val runnable = object : Runnable {
            /**
             * Convert our DIP units to Pixels
             *
             * @return int
             */
            private fun dpToPixels(dipValue: Int): Int {
                return TypedValue.applyDimension(
                    TypedValue.COMPLEX_UNIT_DIP,
                    dipValue.toFloat(),
                    cordova.activity.resources.displayMetrics
                ).toInt()
            }

            private fun createCloseButton(id: Int): View {
                val _close: View
                val activityRes = cordova.activity.resources

                if (closeButtonCaption !== "") {
                    // Use TextView for text
                    val close = TextView(cordova.activity)
                    close.text = closeButtonCaption
                    close.textSize = 20f
                    if (closeButtonColor !== "") close.setTextColor(
                        android.graphics.Color.parseColor(
                            closeButtonColor
                        )
                    )
                    close.gravity = android.view.Gravity.CENTER_VERTICAL
                    close.setPadding(this.dpToPixels(10), 0, this.dpToPixels(10), 0)
                    _close = close
                } else {
                    val close = ImageButton(cordova.activity)
                    val closeResId = activityRes.getIdentifier(
                        "ic_action_remove",
                        "drawable",
                        cordova.activity.packageName
                    )
                    val closeIcon = activityRes.getDrawable(closeResId)
                    if (closeButtonColor !== "") close.setColorFilter(
                        android.graphics.Color.parseColor(
                            closeButtonColor
                        )
                    )
                    close.setImageDrawable(closeIcon)
                    close.scaleType = ImageView.ScaleType.FIT_CENTER
                    if (Build.VERSION.SDK_INT >= 16)
                        close.adjustViewBounds

                    _close = close
                }

                val closeLayoutParams = RelativeLayout.LayoutParams(
                    LayoutParams.WRAP_CONTENT,
                    LayoutParams.MATCH_PARENT
                )
                closeLayoutParams.addRule(RelativeLayout.ALIGN_PARENT_RIGHT)
                _close.layoutParams = closeLayoutParams

                if (Build.VERSION.SDK_INT >= 16)
                    _close.background = null
                else
                    _close.setBackgroundDrawable(null)

                _close.contentDescription = "Close Button"
                _close.id = Integer.valueOf(id)!!
                _close.setOnClickListener { closeDialog() }

                return _close
            }

            @SuppressLint("NewApi")
            override fun run() {
                // CB-6702 DappBrowser hangs when opening more than one instance
                if (dialog != null) {
                    dialog!!.dismiss()
                }

                // Let's create the main dialog
                dialog = DappBrowserDialog(cordova.activity, android.R.style.Theme_NoTitleBar, thatDappBrowser)
                dialog!!.window!!.attributes.windowAnimations = android.R.style.Animation_Dialog
                dialog!!.requestWindowFeature(Window.FEATURE_NO_TITLE)
                dialog!!.setCancelable(true)

                // Main container layout
                val main = LinearLayout(cordova.activity)
                main.orientation = LinearLayout.VERTICAL

                // Toolbar layout
                val toolbar = RelativeLayout(cordova.activity)
                // Please, no more black!
                toolbar.setBackgroundColor(toolbarColor)
                toolbar.layoutParams = RelativeLayout.LayoutParams(LayoutParams.MATCH_PARENT, this.dpToPixels(44))
                toolbar.setPadding(
                    this.dpToPixels(2),
                    this.dpToPixels(2),
                    this.dpToPixels(2),
                    this.dpToPixels(2)
                )
                toolbar.setHorizontalGravity(Gravity.START)
                toolbar.setVerticalGravity(Gravity.TOP)

                // Action Button Container layout
                val actionButtonContainer = RelativeLayout(cordova.activity)
                actionButtonContainer.layoutParams = RelativeLayout.LayoutParams(
                    LayoutParams.WRAP_CONTENT,
                    LayoutParams.WRAP_CONTENT
                )
                actionButtonContainer.setHorizontalGravity(Gravity.START)
                actionButtonContainer.setVerticalGravity(Gravity.CENTER_VERTICAL)
                actionButtonContainer.id = Integer.valueOf(1)!!

                // Back button
                val back = ImageButton(cordova.activity)
                val backLayoutParams = RelativeLayout.LayoutParams(
                    LayoutParams.WRAP_CONTENT,
                    LayoutParams.MATCH_PARENT
                )
                backLayoutParams.addRule(RelativeLayout.ALIGN_LEFT)
                back.layoutParams = backLayoutParams
                back.contentDescription = "Back Button"
                back.id = Integer.valueOf(2)!!
                val activityRes = cordova.activity.resources
                val backResId = activityRes.getIdentifier(
                    "ic_action_previous_item",
                    "drawable",
                    cordova.activity.packageName
                )
                val backIcon = activityRes.getDrawable(backResId, null)
                if (navigationButtonColor != "") {
                    back.setColorFilter(android.graphics.Color.parseColor(navigationButtonColor))
                }
                back.background = null
                back.setImageDrawable(backIcon)
                back.scaleType = ImageView.ScaleType.FIT_CENTER
                back.setPadding(0, this.dpToPixels(10), 0, this.dpToPixels(10))
                back.adjustViewBounds
                back.setOnClickListener { goBack() }

                // Forward button
                val forward = ImageButton(cordova.activity)
                val forwardLayoutParams = RelativeLayout.LayoutParams(
                    LayoutParams.WRAP_CONTENT,
                    LayoutParams.MATCH_PARENT
                )
                forwardLayoutParams.addRule(RelativeLayout.RIGHT_OF, 2)
                forward.layoutParams = forwardLayoutParams
                forward.contentDescription = "Forward Button"
                forward.id = Integer.valueOf(3)!!
                val fwdResId = activityRes.getIdentifier(
                    "ic_action_next_item",
                    "drawable",
                    cordova.activity.packageName
                )
                val fwdIcon = activityRes.getDrawable(fwdResId, null)
                if (navigationButtonColor !== "") {
                    forward.setColorFilter(android.graphics.Color.parseColor(navigationButtonColor))
                }
                forward.background = null
                forward.setImageDrawable(fwdIcon)
                forward.scaleType = ImageView.ScaleType.FIT_CENTER
                forward.setPadding(0, this.dpToPixels(10), 0, this.dpToPixels(10))
                forward.adjustViewBounds
                forward.setOnClickListener { goForward() }

                // Edit Text Box
                val edittext = EditText(cordova.activity)
                val textLayoutParams = RelativeLayout.LayoutParams(
                    LayoutParams.MATCH_PARENT,
                    LayoutParams.MATCH_PARENT
                )
                textLayoutParams.addRule(RelativeLayout.RIGHT_OF, 1)
                textLayoutParams.addRule(RelativeLayout.LEFT_OF, 5)
                edittext.layoutParams = textLayoutParams
                edittext.id = Integer.valueOf(4)!!
                edittext.setSingleLine(true)
                edittext.setText(url)
                edittext.inputType = InputType.TYPE_TEXT_VARIATION_URI
                edittext.imeOptions = EditorInfo.IME_ACTION_GO
                edittext.inputType = InputType.TYPE_NULL // Will not except input... Makes the text NON-EDITABLE
                edittext.setOnKeyListener(View.OnKeyListener { _, keyCode, event ->
                    // If the event is a key-down event on the "enter" button
                    if (event.action == KeyEvent.ACTION_DOWN && keyCode == KeyEvent.KEYCODE_ENTER) {
                        navigate(edittext.text.toString())
                        return@OnKeyListener true
                    }
                    false
                })
                thatDappBrowser.edittext = edittext

                // Header Close/Done button
                val close = createCloseButton(5)
                toolbar.addView(close)

                // Footer
                val footer = RelativeLayout(cordova.activity)
                footer.setBackgroundColor(if (footerColor != "") Color.parseColor(footerColor) else android.graphics.Color.LTGRAY)
                val footerLayout = RelativeLayout.LayoutParams(LayoutParams.MATCH_PARENT, this.dpToPixels(44))
                footerLayout.addRule(RelativeLayout.ALIGN_PARENT_BOTTOM, RelativeLayout.TRUE)
                footer.layoutParams = footerLayout
                if (closeButtonCaption !== "") footer.setPadding(
                    this.dpToPixels(8),
                    this.dpToPixels(8),
                    this.dpToPixels(8),
                    this.dpToPixels(8)
                )
                footer.setHorizontalGravity(Gravity.START)
                footer.setVerticalGravity(Gravity.BOTTOM)
                val footerClose = createCloseButton(7)
                footer.addView(footerClose)


                // WebView
                dappWebView = WebView(cordova.activity)
                dappWebView!!.layoutParams = LinearLayout.LayoutParams(
                    LayoutParams.MATCH_PARENT,
                    LayoutParams.MATCH_PARENT
                )
                dappWebView!!.id = Integer.valueOf(6)!!
                // File Chooser Implemented ChromeClient
                dappWebView!!.webChromeClient = object : DappChromeClient(thatWebView) {
                    // For Android 5.0+
                    override fun onShowFileChooser(
                        webView: WebView,
                        filePathCallback: ValueCallback<Array<Uri>>,
                        fileChooserParams: WebChromeClient.FileChooserParams
                    ): Boolean {
                        LOG.d(LOG_TAG, "File Chooser 5.0+")
                        // If callback exists, finish it.
                        if (mUploadCallbackLollipop != null) {
                            mUploadCallbackLollipop!!.onReceiveValue(null)
                        }
                        mUploadCallbackLollipop = filePathCallback

                        // Create File Chooser Intent
                        val content = Intent(Intent.ACTION_GET_CONTENT)
                        content.addCategory(Intent.CATEGORY_OPENABLE)
                        content.type = "*/*"

                        // Run cordova startActivityForResult
                        cordova.startActivityForResult(
                            this@DappBrowser,
                            Intent.createChooser(content, "Select File"),
                            FILECHOOSER_REQUESTCODE_LOLLIPOP
                        )
                        return true
                    }

                    // For Android 4.1+
                    fun openFileChooser(uploadMsg: ValueCallback<Uri>, acceptType: String, capture: String) {
                        LOG.d(LOG_TAG, "File Chooser 4.1+")
                        // Call file chooser for Android 3.0+
                        openFileChooser(uploadMsg, acceptType)
                    }

                    // For Android 3.0+
                    fun openFileChooser(uploadMsg: ValueCallback<Uri>, acceptType: String) {
                        LOG.d(LOG_TAG, "File Chooser 3.0+")
                        mUploadCallback = uploadMsg
                        val content = Intent(Intent.ACTION_GET_CONTENT)
                        content.addCategory(Intent.CATEGORY_OPENABLE)

                        // run startActivityForResult
                        cordova.startActivityForResult(
                            this@DappBrowser,
                            Intent.createChooser(content, "Select File"),
                            FILECHOOSER_REQUESTCODE
                        )
                    }
                }
                val client = DappBrowserClient(thatWebView, thatDappBrowser.edittext!!)
                dappWebView!!.webViewClient = client
                val settings = dappWebView!!.settings
                settings.javaScriptEnabled = true
                settings.javaScriptCanOpenWindowsAutomatically = true
                settings.builtInZoomControls = showZoomControls
                settings.pluginState = android.webkit.WebSettings.PluginState.ON

                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.JELLY_BEAN_MR1) {
                    settings.mediaPlaybackRequiresUserGesture = mediaPlaybackRequiresUserGesture
                }

                val overrideUserAgent = preferences.getString("OverrideUserAgent", null)
                val appendUserAgent = preferences.getString("AppendUserAgent", null)

                if (overrideUserAgent != null) {
                    settings.userAgentString = overrideUserAgent
                }
                if (appendUserAgent != null) {
                    settings.userAgentString = settings.userAgentString + appendUserAgent
                }

                //Toggle whether this is enabled or not!
                val appSettings = cordova.activity.intent.extras
                val enableDatabase =
                    appSettings?.getBoolean("DappBrowserStorageEnabled", true) ?: true
                if (enableDatabase) {
                    val databasePath = cordova.activity.applicationContext.getDir(
                        "DappBrowserDB",
                        Context.MODE_PRIVATE
                    ).path
                    settings.databasePath = databasePath
                    settings.databaseEnabled = true
                }
                settings.domStorageEnabled = true

                if (clearAllCache) {
                    CookieManager.getInstance().removeAllCookies(null)
                } else if (clearSessionCache) {
                    CookieManager.getInstance().removeSessionCookies(null)
                }

                // Enable Thirdparty Cookies on >=Android 5.0 device
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
                    CookieManager.getInstance().setAcceptThirdPartyCookies(dappWebView, true)
                }

                dappWebView!!.loadUrl(url)
                dappWebView!!.id = Integer.valueOf(6)!!
                dappWebView!!.settings.loadWithOverviewMode = true
                dappWebView!!.settings.useWideViewPort = useWideViewPort
                dappWebView!!.requestFocus()
                dappWebView!!.requestFocusFromTouch()

                // Add the back and forward buttons to our action button container layout
                actionButtonContainer.addView(back)
                actionButtonContainer.addView(forward)

                // Add the views to our toolbar if they haven't been disabled
                if (!hideNavigationButtons) toolbar.addView(actionButtonContainer)
                if (!hideUrlBar) toolbar.addView(edittext)

                // Don't add the toolbar if its been disabled
                if (showLocationBar) {
                    // Add our toolbar to our main view/layout
                    main.addView(toolbar)
                }

                // Add our webview to our main view/layout
                val webViewLayout = RelativeLayout(cordova.activity)
                webViewLayout.addView(dappWebView)
                main.addView(webViewLayout)

                // Don't add the footer unless it's been enabled
                if (showFooter) {
                    webViewLayout.addView(footer)
                }

                val lp = WindowManager.LayoutParams()
                lp.copyFrom(dialog!!.window!!.attributes)
                lp.width = WindowManager.LayoutParams.MATCH_PARENT
                lp.height = WindowManager.LayoutParams.MATCH_PARENT

                dialog!!.setContentView(main)
                dialog!!.show()
                dialog!!.window!!.attributes = lp
                // the goal of openhidden is to load the url and not display it
                // Show() needs to be called to cause the URL to be loaded
                if (openWindowHidden) {
                    dialog!!.hide()
                }
            }
        }

        this.cordova.activity.runOnUiThread(runnable)
        return ""
    }

    /**
     * Create a new plugin result and send it back to JavaScript
     *
     * @param obj a JSONObject contain event payload information
     * @param keepCallback whether keep callback
     * @param status the status code to return to the JavaScript environment
     */
    private fun sendUpdate(obj: JSONObject, keepCallback: Boolean, status: PluginResult.Status = PluginResult.Status.OK) {
        if (callbackContext != null) {
            val result = PluginResult(status, obj)
            result.keepCallback = keepCallback
            callbackContext!!.sendPluginResult(result)
            if (!keepCallback) {
                callbackContext = null
            }
        }
    }

    /**
     * Receive File Data from File Chooser
     *
     * @param requestCode the requested code from chromeclient
     * @param resultCode the result code returned from android system
     * @param intent the data from android file chooser
     */
    override fun onActivityResult(requestCode: Int, resultCode: Int, intent: Intent?) {
        // For Android >= 5.0
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            LOG.d(LOG_TAG, "onActivityResult (For Android >= 5.0)")
            // If RequestCode or Callback is Invalid
            if (requestCode != FILECHOOSER_REQUESTCODE_LOLLIPOP || mUploadCallbackLollipop == null) {
                super.onActivityResult(requestCode, resultCode, intent)
                return
            }
            mUploadCallbackLollipop!!.onReceiveValue(
                WebChromeClient.FileChooserParams.parseResult(
                    resultCode,
                    intent
                )
            )
            mUploadCallbackLollipop = null
        } else {
            LOG.d(LOG_TAG, "onActivityResult (For Android < 5.0)")
            // If RequestCode or Callback is Invalid
            if (requestCode != FILECHOOSER_REQUESTCODE || mUploadCallback == null) {
                super.onActivityResult(requestCode, resultCode, intent)
                return
            }

            if (null == mUploadCallback) return
            val result =
                if (intent == null || resultCode != Activity.RESULT_OK) null else intent.data

            mUploadCallback!!.onReceiveValue(result)
            mUploadCallback = null
        }// For Android < 5.0
    }

    /**
     * The webview client receives notifications about appView
     */
    inner class DappBrowserClient
    /**
     * Constructor.
     *
     * @param webView
     * @param mEditText
     */
        (private var webView: CordovaWebView, private var edittext: EditText) : WebViewClient() {

        /**
         * Override the URL that should be loaded
         *
         * This handles a small subset of all the URIs that would be encountered.
         *
         * @param webView
         * @param url
         */
        override fun shouldOverrideUrlLoading(webView: WebView, url: String): Boolean {
            if (url.startsWith(WebView.SCHEME_TEL)) {
                try {
                    val intent = Intent(Intent.ACTION_DIAL)
                    intent.data = Uri.parse(url)
                    cordova.activity.startActivity(intent)
                    return true
                } catch (e: android.content.ActivityNotFoundException) {
                    LOG.e(LOG_TAG, "Error dialing " + url + ": " + e.toString())
                }

            } else if (url.startsWith("geo:") ||
                       url.startsWith(WebView.SCHEME_MAILTO) ||
                       url.startsWith("market:") ||
                       url.startsWith("intent:")
            ) {
                try {
                    val intent = Intent(Intent.ACTION_VIEW)
                    intent.data = Uri.parse(url)
                    cordova.activity.startActivity(intent)
                    return true
                } catch (e: android.content.ActivityNotFoundException) {
                    LOG.e(LOG_TAG, "Error with " + url + ": " + e.toString())
                }

            } else if (url.startsWith("sms:")) {
                try {
                    val intent = Intent(Intent.ACTION_VIEW)

                    // Get address
                    val parmIndex = url.indexOf('?')
                    val address = if (parmIndex == -1) {
                        url.substring(4)
                    } else {
                        // If body, then set sms body
                        val uri = Uri.parse(url)
                        val query = uri.query
                        if (query != null) {
                            if (query.startsWith("body=")) {
                                intent.putExtra("sms_body", query.substring(5))
                            }
                        }

                        url.substring(4, parmIndex)
                    }
                    intent.data = Uri.parse("sms:$address")
                    intent.putExtra("address", address)
                    intent.type = "vnd.android-dir/mms-sms"
                    cordova.activity.startActivity(intent)
                    return true
                } catch (e: android.content.ActivityNotFoundException) {
                    LOG.e(LOG_TAG, "Error sending sms " + url + ":" + e.toString())
                }

            } else if (!url.startsWith("http:") &&
                       !url.startsWith("https:") &&
                       url.matches("^[a-z]*://.*?$".toRegex())) {
                if (allowedSchemes == null) {
                    val allowed = preferences.getString("AllowedSchemes", "")
                    allowedSchemes = allowed.split(",".toRegex()).dropLastWhile { it.isEmpty() }.toTypedArray()
                }
                if (allowedSchemes != null) {
                    for (scheme in allowedSchemes!!) {
                        if (url.startsWith(scheme)) {
                            try {
                                val obj = JSONObject()
                                obj.put("type", "customscheme")
                                obj.put("url", url)
                                sendUpdate(obj, true)
                                return true
                            } catch (ex: JSONException) {
                                LOG.e(LOG_TAG, "Custom Scheme URI passed in has caused a JSON error.")
                            }

                        }
                    }
                }
            }// Test for whitelisted custom scheme names like mycoolapp:// or twitteroauthresponse:// (Twitter Oauth Response)
            // If sms:5551212?body=This is the message

            return false
        }


        /*
         * onPageStarted fires the LOAD_START_EVENT
         *
         * @param view
         * @param url
         * @param favicon
         */
        override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
            super.onPageStarted(view, url, favicon)
            val newloc = if (url.startsWith("http:") || url.startsWith("https:") || url.startsWith("file:")) {
                url
            } else {
                // Assume that everything is HTTP at this point, because if we don't specify,
                // it really should be.  Complain loudly about this!!!
                LOG.e(LOG_TAG, "Possible Uncaught/Unknown URI")
                "http://$url"
            }

            // Update the UI if we haven't already
            if (newloc != edittext.text.toString()) { // TODO
                edittext.setText(newloc)
            }

            try {
                val obj = JSONObject()
                obj.put("type", LOAD_START_EVENT)
                obj.put("url", newloc)
                sendUpdate(obj, true)
            } catch (ex: JSONException) {
                LOG.e(LOG_TAG, "URI passed in has caused a JSON error.")
            }
        }


        override fun onPageFinished(view: WebView, url: String) {
            super.onPageFinished(view, url)

            // CB-10395 DappBrowser's WebView not storing cookies reliable to local device storage
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
                CookieManager.getInstance().flush()
            } else {
                CookieSyncManager.getInstance().sync()
            }

            // https://issues.apache.org/jira/browse/CB-11248
            view.clearFocus()
            view.requestFocus()

            try {
                val obj = JSONObject()
                obj.put("type", LOAD_STOP_EVENT)
                obj.put("url", url)

                sendUpdate(obj, true)
            } catch (ex: JSONException) {
                LOG.d(LOG_TAG, "Should never happen")
            }

        }

        override fun onReceivedError(view: WebView, errorCode: Int, description: String, failingUrl: String) {
            super.onReceivedError(view, errorCode, description, failingUrl)

            try {
                val obj = JSONObject()
                obj.put("type", LOAD_ERROR_EVENT)
                obj.put("url", failingUrl)
                obj.put("code", errorCode)
                obj.put("message", description)

                sendUpdate(obj, true, PluginResult.Status.ERROR)
            } catch (ex: JSONException) {
                LOG.d(LOG_TAG, "Should never happen")
            }

        }

        /**
         * On received http auth request.
         */
        override fun onReceivedHttpAuthRequest(view: WebView, handler: HttpAuthHandler, host: String, realm: String) {
            // Check if there is some plugin which can resolve this auth challenge
            val pluginManager = webView.pluginManager
            if (pluginManager.onReceivedHttpAuthRequest(webView, CordovaHttpAuthHandler(handler), host, realm)) {
                return
            }

            // By default handle 401 like we'd normally do!
            super.onReceivedHttpAuthRequest(view, handler, host, realm)
        }
    }

    companion object {

        private val LOG_TAG = "DappBrowser"

        private val NULL = "null"
        private val SELF = "_self"
        private val SYSTEM = "_system"

        private val LOCATION = "location"
        private val ZOOM = "zoom"
        private val HIDDEN = "hidden"

        private val EXIT_EVENT = "exit"
        private val LOAD_START_EVENT = "loadstart"
        private val LOAD_STOP_EVENT = "loadstop"
        private val LOAD_ERROR_EVENT = "loaderror"

        private val CLEAR_ALL_CACHE = "clearcache"
        private val CLEAR_SESSION_CACHE = "clearsessioncache"
        private val HARDWARE_BACK_BUTTON = "hardwareback"
        private val MEDIA_PLAYBACK_REQUIRES_USER_ACTION = "mediaPlaybackRequiresUserAction"
        private val SHOULD_PAUSE = "shouldPauseOnSuspend"
        private val USER_WIDE_VIEW_PORT = "useWideViewPort"

        private val TOOLBAR_COLOR = "toolbarcolor"
        private val CLOSE_BUTTON_CAPTION = "closebuttoncaption"
        private val CLOSE_BUTTON_COLOR = "closebuttoncolor"
        private val HIDE_NAVIGATION = "hidenavigationbuttons"
        private val NAVIGATION_COLOR = "navigationbuttoncolor"
        private val HIDE_URL = "hideurlbar"
        private val FOOTER = "footer"
        private val FOOTER_COLOR = "footercolor"

        private val customizableOptions = Arrays.asList(
            CLOSE_BUTTON_CAPTION,
            TOOLBAR_COLOR,
            NAVIGATION_COLOR,
            CLOSE_BUTTON_COLOR,
            FOOTER_COLOR
        )

        private val FILECHOOSER_REQUESTCODE = 1
        private val FILECHOOSER_REQUESTCODE_LOLLIPOP = 2
    }
}
