import Foundation
import UIKit
import WebKit

let TARGET_SELF = "_self"
let TARGET_SYSTEM = "_system"
let TARGET_BLANK = "_blank"

let TOOLBAR_POSITION_TOP = "top"
let TOOLBAR_POSITION_BOTTOM = "bottom"

let IAB_BRIDGE_NAME = "cordova_iab"

let TOOLBAR_HEIGHT = 44.0
let STATUSBAR_HEIGHT = 20.0
let LOCATIONBAR_HEIGHT = 21.0
let FOOTER_HEIGHT = TOOLBAR_HEIGHT + LOCATIONBAR_HEIGHT

@objc(DappBrowser)
class DappBrowser: CDVPlugin {
    private var useBeforeload = false
    private var waitForBeforeload = false
    var previousStatusBarStyle = -1

    var callbackId = ""
    // var callbackIdPattern: NSRegularExpression? = nil

    var dappBrowserViewController: DappBrowserViewController? = nil

    var nextMethodID = 0

    override func pluginInitialize() {
        super.pluginInitialize()
        useBeforeload = false
        waitForBeforeload = false
        previousStatusBarStyle = -1
        callbackId = ""
        dappBrowserViewController = nil
        nextMethodID = 0
    }

    func setting(forKey key: String) -> Any? {
        return commandDelegate.settings[key.lowercased()]
    }

    override func onReset() {
        if (dappBrowserViewController == nil) {
            print("IAB.close() called but it was already closed.")
            return
        }
        // Things are cleaned up in browserExit.
        dappBrowserViewController!.close()
    }

    func isSystemUrl(_ url: URL?) -> Bool {
        if (url?.host == "itunes.apple.com") {
            return true
        }

        return false
    }

    @objc(open:)
    func open(_ command: CDVInvokedUrlCommand) {
        let url = command.argument(at: 0, withDefault: "") as! String
        var target = command.argument(at: 1, withDefault: "") as! String
        let options = command.argument(at: 2, withDefault: "") as! String
        let browserOptions = DappBrowserOptions()
        browserOptions.parseOptions(options)

        callbackId = command.callbackId


        var pluginResult: CDVPluginResult?

        if (!url.isEmpty) {
            let baseUrl = webViewEngine.url()
            let absoluteUrl = URL(string: url, relativeTo: baseUrl)?.absoluteURL

            if (isSystemUrl(absoluteUrl)) {
                target = TARGET_SYSTEM
            }

            if target == TARGET_SELF {
                openInCordovaWebView(absoluteUrl!)
            } else if target == TARGET_SYSTEM {
                openInSystem(absoluteUrl!)
            } else {
                openInDappBrowser(absoluteUrl!, withOptions: browserOptions)
            }

            pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
        } else {
            pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "incorrect number of arguments")
        }

        pluginResult?.keepCallback = (1)
        commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }

    @objc(close:)
    func close(_ command: CDVInvokedUrlCommand) {
        onReset()
    }

    func show(_ command: CDVInvokedUrlCommand?, withNoAnimate noAnimate: Bool) {
        var initHidden = false
        if command == nil && noAnimate == true {
            initHidden = true
        }

        if dappBrowserViewController == nil {
            print("Tried to show IAB after it was closed.")
            return
        }
        if previousStatusBarStyle != -1 {
            print("Tried to show IAB while already shown")
            return
        }

        if !initHidden {
            previousStatusBarStyle = UIApplication.shared.statusBarStyle.rawValue
        }

        let nav = DappBrowserNavigationController(rootViewController: dappBrowserViewController!)
        nav.orientationDelegate = DappBrowserScreenOrientationDelegate(viewController: dappBrowserViewController)
        nav.isNavigationBarHidden = true
        nav.modalPresentationStyle = dappBrowserViewController!.modalPresentationStyle

        weak var weakSelf: DappBrowser? = self

        // Run later to avoid the "took a long time" log message.
        DispatchQueue.main.async(execute: {
            if weakSelf?.dappBrowserViewController != nil {
                let osVersion = Float(UIDevice.current.systemVersion) ?? 0.0
                var frame: CGRect = UIScreen.main.bounds
                if initHidden && osVersion < 11 {
                    frame.origin.x = -10000
                }

                let tmpWindow = UIWindow(frame: frame)
                let tmpController = UIViewController()

                tmpWindow.rootViewController = tmpController
                tmpWindow.windowLevel = UIWindowLevelNormal

                if !initHidden || osVersion < 11 {
                    tmpWindow.makeKeyAndVisible()
                }
                tmpController.present(nav, animated: !noAnimate)
            }
        })
    }

    @objc(show:)
    func show(_ command: CDVInvokedUrlCommand) {
        show(command, withNoAnimate: false)
    }

    @objc(hide:)
    func hide(_ command: CDVInvokedUrlCommand) {
        if dappBrowserViewController == nil {
            print("Tried to hide IAB after it was closed.")
            return
        }
        if previousStatusBarStyle == -1 {
            print("Tried to hide IAB while already hidden")
            return
        }

        previousStatusBarStyle = UIApplication.shared.statusBarStyle.rawValue

        // Run later to avoid the "took a long time" log message.
        DispatchQueue.main.async(execute: {
            if self.dappBrowserViewController != nil {
                self.previousStatusBarStyle = -1
                self.dappBrowserViewController!.presentingViewController!.dismiss(animated: true)
            }
        })
    }

    @objc(loadAfterBeforeload:)
    func loadAfterBeforeload(_ command: CDVInvokedUrlCommand) {
        let urlStr = command.argument(at: 0, withDefault: "") as! String

        if (!useBeforeload) {
            print("unexpected loadAfterBeforeload called without feature beforeload=yes")
        }
        if (dappBrowserViewController == nil) {
            print("Tried to invoke loadAfterBeforeload on IAB after it was closed.")
        }
        if urlStr.isEmpty {
            print("loadAfterBeforeload called with nil argument, ignoring.")
            return
        }

        let url = URL(string: urlStr)
        waitForBeforeload = false
        dappBrowserViewController!.navigate(to: url)
    }


    func openInCordovaWebView(_ url: URL) {
        let request = URLRequest(url: url)

        // the webview engine itself will filter for this according to <allow-navigation> policy
        // in config.xml
        webViewEngine.load(request)
    }

    func openInSystem(_ url: URL) {
        NotificationCenter.default.post(Notification(name: NSNotification.Name.CDVPluginHandleOpenURL, object: url))
        UIApplication.shared.openURL(url)
    }

    func openInDappBrowser(_ url: URL, withOptions options: DappBrowserOptions) {
        let dataStore = WKWebsiteDataStore.default()
        if options.cleardata {
            let dateFrom = Date(timeIntervalSince1970: 0)
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: dateFrom, completionHandler: {
                print("Removed all WKWebView data")
                self.dappBrowserViewController!.webView?.configuration.processPool = WKProcessPool() // create new process pool to flush all data
            })
        }

        if options.clearcache {
            if #available(iOS 11.0, *) {
                // Deletes all cookies
                let cookieStore = dataStore.httpCookieStore
                cookieStore.getAllCookies({ cookies in
                    for cookie in cookies {
                        cookieStore.delete(cookie, completionHandler: nil)
                    }
                })
            } else {
                // https://stackoverflow.com/a/31803708/777265
                // Only deletes domain cookies (not session cookies)
                dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), completionHandler: { records in
                    for record: WKWebsiteDataRecord in records {
                        let dataTypes = record.dataTypes
                        if dataTypes.contains(WKWebsiteDataTypeCookies) {
                            WKWebsiteDataStore.default().removeData(ofTypes: record.dataTypes, for: [record], completionHandler: {
                            })
                        }
                    }
                })
            }
        }

        if options.clearsessioncache {
            if #available(iOS 11.0, *) {
                // Deletes session cookies
                let cookieStore: WKHTTPCookieStore = dataStore.httpCookieStore
                cookieStore.getAllCookies({ cookies in
                    for cookie in cookies {
                        if cookie.isSessionOnly {
                            cookieStore.delete(cookie, completionHandler: nil)
                        }
                    }
                })
            } else {
                print("clearsessioncache not available below iOS 11.0")
            }
        }

        if dappBrowserViewController == nil {
            var userAgent = CDVUserAgentUtil.originalUserAgent()!
            let overrideUserAgent = setting(forKey: "OverrideUserAgent")
            let appendUserAgent = setting(forKey: "AppendUserAgent")
            if overrideUserAgent != nil {
                userAgent = overrideUserAgent as! String
            }
            if appendUserAgent != nil {
                userAgent = userAgent + (appendUserAgent as! String)
            }
            dappBrowserViewController = DappBrowserViewController(userAgent: userAgent, prevUserAgent: commandDelegate.userAgent(), browserOptions: options)
            dappBrowserViewController!.navigationDelegate = self

            if viewController is CDVScreenOrientationDelegate {
                dappBrowserViewController!.orientationDelegate = viewController as? CDVScreenOrientationDelegate
            }
        }

        dappBrowserViewController!.showLocationBar(options.location)
        dappBrowserViewController!.showToolBar(options.toolbar, toolbarPosition: options.toolbarposition)
        if !options.closebuttoncaption.isEmpty || !options.closebuttoncolor.isEmpty {
            dappBrowserViewController!.setCloseButtonTitle(options.closebuttoncaption, colorString: options.closebuttoncolor)
        }
        // Set Presentation Style
        var presentationStyle: UIModalPresentationStyle = .fullScreen // default
        if !options.presentationstyle.isEmpty {
            if (options.presentationstyle.lowercased() == "pagesheet") {
                presentationStyle = .pageSheet
            } else if (options.presentationstyle.lowercased() == "formsheet") {
                presentationStyle = .formSheet
            }
        }
        dappBrowserViewController!.modalPresentationStyle = presentationStyle

        // Set Transition Style
        var transitionStyle: UIModalTransitionStyle = .coverVertical // default
        if !options.transitionstyle.isEmpty {
            if (options.transitionstyle.lowercased() == "fliphorizontal") {
                transitionStyle = .flipHorizontal
            } else if (options.transitionstyle.lowercased() == "crossdissolve") {
                transitionStyle = .crossDissolve
            }
        }
        dappBrowserViewController!.modalTransitionStyle = transitionStyle

        //prevent webView from bouncing

        if options.disallowoverscroll {
            if dappBrowserViewController!.webView?.responds(to: #selector(getter: WKWebView.scrollView)) ?? false {
                dappBrowserViewController!.webView?.scrollView.bounces = false
            } else {
                for subview in dappBrowserViewController!.webView!.subviews {
                    if subview is UIScrollView {
                        (subview as! UIScrollView).bounces = false
                    }
                }
            }
        }

        // use of beforeload event
        useBeforeload = options.beforeload
        waitForBeforeload = options.beforeload

        dappBrowserViewController!.navigate(to: url)
        show(nil, withNoAnimate: options.hidden)
    }

    // This is a helper method for the inject{Script|Style}{Code|File} API calls, which
    // provides a consistent method for injecting JavaScript code into the document.
    //
    // If a wrapper string is supplied, then the source string will be JSON-encoded (adding
    // quotes) and wrapped using string formatting. (The wrapper string should have a single
    // '%@' marker).
    //
    // If no wrapper is supplied, then the source string is executed directly.
    func injectDeferredObject(_ source: String, withWrapper jsWrapper: String?) {
        // Ensure a message handler bridge is created to communicate with the CDVWKdappBrowserViewController
        evaluateJavaScript("(function(w){if(!w._cdvMessageHandler) {w._cdvMessageHandler = function(id,d){w.webkit.messageHandlers.\(IAB_BRIDGE_NAME).postMessage({d:d, id:id});}}})(window)")

        if jsWrapper != nil {
            let jsonData: Data? = try? JSONSerialization.data(withJSONObject: [source], options: [])
            var sourceArrayString: String? = nil
            if let aData = jsonData {
                sourceArrayString = String(data: aData, encoding: .utf8)
            }
            if sourceArrayString != nil {
                let sourceString = (sourceArrayString as NSString?)?.substring(with: NSRange(location: 1, length: (sourceArrayString?.count ?? 0) - 2))
                let jsToInject = String(format: jsWrapper!, sourceString ?? "")
                evaluateJavaScript(jsToInject)
            }
        } else {
            evaluateJavaScript(source)
        }
    }

    //Synchronus helper for javascript evaluation
    func evaluateJavaScript(_ script: String) {
        dappBrowserViewController!.webView?.evaluateJavaScript(script, completionHandler: { result, error in
            if error == nil {
                if result != nil {
                    if let aResult = result {
                        print("\(aResult)")
                    }
                }
            } else {
                print("evaluateJavaScript error : \(error!.localizedDescription) : \(script)")
            }
        })
    }

    @objc(injectScriptCode:)
    func injectScriptCode(_ command: CDVInvokedUrlCommand) {
        var jsWrapper: String?
        if (command.callbackId != nil && command.callbackId! != "INVALID") {
            jsWrapper = String(format: "_cdvMessageHandler('%@',JSON.stringify([eval(%%@)]));", command.callbackId!)
        }
        injectDeferredObject(command.argument(at: 0) as! String, withWrapper: jsWrapper)
    }

    @objc(injectScriptFile:)
    func injectScriptFile(_ command: CDVInvokedUrlCommand) {
        var jsWrapper: String?
        if command.callbackId != nil && command.callbackId! != "INVALID" {
            jsWrapper = String(format: "(function(d) { var c = d.createElement('script'); c.src = %%@; c.onload = function() { _cdvMessageHandler('%@'); }; d.body.appendChild(c); })(document)", command.callbackId!)
        } else {
            jsWrapper = "(function(d) { var c = d.createElement('script'); c.src = %@; d.body.appendChild(c); })(document)"
        }
        injectDeferredObject(command.argument(at: 0) as! String, withWrapper: jsWrapper)
    }

    @objc(injectStyleCode:)
    func injectStyleCode(_ command: CDVInvokedUrlCommand) {
        var jsWrapper: String?
        if command.callbackId != nil && command.callbackId != "INVALID" {
            jsWrapper = String(format: "(function(d) { var c = d.createElement('style'); c.innerHTML = %%@; c.onload = function() { _cdvMessageHandler('%@'); }; d.body.appendChild(c); })(document)", command.callbackId!)
        } else {
            jsWrapper = "(function(d) { var c = d.createElement('style'); c.innerHTML = %@; d.body.appendChild(c); })(document)"
        }
        injectDeferredObject(command.argument(at: 0) as! String, withWrapper: jsWrapper)
    }

    @objc(injectStyleFile:)
    func injectStyleFile(_ command: CDVInvokedUrlCommand) {
        var jsWrapper: String?
        if command.callbackId != nil && command.callbackId! != "INVALID" {
            jsWrapper = String(format: "(function(d) { var c = d.createElement('link'); c.rel='stylesheet'; c.type='text/css'; c.href = %%@; c.onload = function() { _cdvMessageHandler('%@'); }; d.body.appendChild(c); })(document)", command.callbackId!)
        } else {
            jsWrapper = "(function(d) { var c = d.createElement('link'); c.rel='stylesheet', c.type='text/css'; c.href = %@; d.body.appendChild(c); })(document)"
        }
        injectDeferredObject(command.argument(at: 0) as! String, withWrapper: jsWrapper)
    }

    @objc(reply:)
    func reply(_ command: CDVInvokedUrlCommand) {
        let method = command.argument(at: 0) as! String
        let methodID = command.argument(at: 1) as! Int
        var response = command.argument(at: 2) as! String

        print(method, methodID, response)
        response = response.replacingOccurrences(of: "'", with: "\\'")
        evaluateJavaScript("(function() { cochain.callback('\(method)', \(methodID), '\(response)') })()")
    }

    func webView(_ theWebView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        let mainDocumentURL = navigationAction.request.mainDocumentURL
        let isTopLevelNavigation = url == mainDocumentURL
        var shouldStart = true

        // When beforeload=yes, on first URL change, initiate JS callback. Only after the beforeload event, continue.
        if waitForBeforeload && isTopLevelNavigation {
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: ["type": "beforeload", "url": url?.absoluteString ?? 0])
            pluginResult!.keepCallback = (1)

            commandDelegate.send(pluginResult, callbackId: callbackId)
            decisionHandler(WKNavigationActionPolicy.cancel)
            return
        }

        //if is an app store link, let the system handle it, otherwise it fails to load it
        if url != nil && (url!.scheme == "itms-appss" || url!.scheme == "itms-apps") {
            theWebView.stopLoading()
            openInSystem(url!)
            shouldStart = false
        } else if (!callbackId.isEmpty) && isTopLevelNavigation {
            // Send a loadstart event for each top-level navigation (includes redirects).
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: ["type": "loadstart", "url": url?.absoluteString ?? ""])
            pluginResult!.keepCallback = (1)

            commandDelegate.send(pluginResult, callbackId: callbackId)
        }

        if useBeforeload && isTopLevelNavigation {
            waitForBeforeload = true
        }

        if shouldStart {
            decisionHandler(WKNavigationActionPolicy.allow)
        } else {
            decisionHandler(WKNavigationActionPolicy.cancel)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {

        var pluginResult: CDVPluginResult?

        if let messageContent = message.body as? [String: String] {
            let scriptCallbackId = messageContent["id"]

            if let scriptResult = messageContent["d"] {
                var decodedResult: [Any]? = nil
                if let anEncoding = scriptResult.data(using: .utf8) {
                    decodedResult = (try? JSONSerialization.jsonObject(with: anEncoding, options: [])) as? [Any]
                }
                if decodedResult != nil {
                    pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: decodedResult)
                } else {
                    pluginResult = CDVPluginResult(status: CDVCommandStatus_JSON_EXCEPTION)
                }
            } else {
                pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: [Any]())
            }
            commandDelegate.send(pluginResult, callbackId: scriptCallbackId)
        } else if !callbackId.isEmpty {
            // Send a message event
            let messageContent = message.body as? String
            var decodedResult: Data? = nil
            if let anEncoding = messageContent?.data(using: .utf8) {
                decodedResult = (try? JSONSerialization.jsonObject(with: anEncoding, options: [])) as? Data
            }
            if decodedResult != nil {
                var dResult = [String: Any]()
                dResult["type"] = "message"
                dResult["data"] = decodedResult
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: dResult)
                pluginResult!.keepCallback = (1)
                commandDelegate.send(pluginResult, callbackId: callbackId)
            }
        }
    }

    func userContentControllerForCochain(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if (!callbackId.isEmpty) {
            let req = message.body as! [String: Any]
            let method = req["method"] as! String
            let methodID = req["methodID"] as! Int
            let args = req["args"] as! [String: Any]

            nextMethodID = methodID + 1

            var dResult = [String: Any]()
            dResult["type"] = "exec"
            dResult["method"] = method
            dResult["methodID"] = methodID
            dResult["args"] = args
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: dResult)
            pluginResult!.keepCallback = (1)
            commandDelegate.send(pluginResult, callbackId: callbackId)
        }
    }

    func didStartProvisionalNavigation(_ theWebView: WKWebView?) {
        print("didStartProvisionalNavigation")
    }

    func didFinishNavigation(_ theWebView: WKWebView?) {
        if !callbackId.isEmpty {
            var url = theWebView?.url?.absoluteString
            if url == nil {
                if dappBrowserViewController?.currentURL != nil {
                    url = dappBrowserViewController!.currentURL!.absoluteString
                } else {
                    url = ""
                }
            }
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: ["type": "loadstop", "url": url!])
            pluginResult!.keepCallback = (1)

            commandDelegate.send(pluginResult, callbackId: callbackId)
        }

        evaluateJavaScript("(function() { if (!window.cochain) window.cochain = {}; window.cochain.nextMethodID = \(nextMethodID) })()")
    }

    func webView(_ theWebView: WKWebView?, didFailNavigation: Error) {
        if !callbackId.isEmpty {
            var url = theWebView?.url?.absoluteString
            if url == nil {
                if dappBrowserViewController?.currentURL != nil {
                    url = dappBrowserViewController!.currentURL!.absoluteString
                } else {
                    url = ""
                }
            }
            let error = didFailNavigation as NSError
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: [
                "type": "loaderror",
                "url": url!,
                "code": error.code, "message": error.localizedDescription
            ])
            pluginResult!.keepCallback = (1)

            commandDelegate.send(pluginResult, callbackId: callbackId)
        }
    }

    @objc func browserExit() {
        if !callbackId.isEmpty {
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: ["type": "exit"])
            commandDelegate.send(pluginResult, callbackId: callbackId)
            callbackId = ""
        }

        if dappBrowserViewController != nil {
            dappBrowserViewController!.configuration?.userContentController.removeScriptMessageHandler(forName: IAB_BRIDGE_NAME)
            dappBrowserViewController!.configuration?.userContentController.removeScriptMessageHandler(forName: "cochain")
            dappBrowserViewController!.configuration = nil

            dappBrowserViewController!.webView?.stopLoading()
            dappBrowserViewController!.webView?.removeFromSuperview()
            dappBrowserViewController!.webView?.uiDelegate = nil
            dappBrowserViewController!.webView?.navigationDelegate = nil
            dappBrowserViewController!.webView = nil

            // Set navigationDelegate to nil to ensure no callbacks are received from it.
            dappBrowserViewController!.navigationDelegate = nil
            dappBrowserViewController = nil
        }

        if #available(iOS 7.0, *) {
            if previousStatusBarStyle != -1 {
                // UIApplication.shared.statusBarStyle = UIStatusBarStyle(rawValue: previousStatusBarStyle)!
            }
        }

        previousStatusBarStyle = -1 // this value was reset before reapplying it. caused statusbar to stay black on ios7
    }
}

class DappBrowserViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private var userAgent = ""
    private var prevUserAgent = ""
    private var userAgentLockToken: Int = 0
    private var browserOptions: DappBrowserOptions

    var webView: WKWebView?
    var configuration: WKWebViewConfiguration?
    var closeButton: UIBarButtonItem?
    var addressLabel: UILabel?
    var backButton: UIBarButtonItem?
    var forwardButton: UIBarButtonItem?
    var spinner: UIActivityIndicatorView?
    var toolbar: UIToolbar?
    var webViewUIDelegate: DappBrowserUIDelegate
    weak var orientationDelegate: CDVScreenOrientationDelegate?
    weak var navigationDelegate: DappBrowser?
    var currentURL: URL?

    var viewRenderedAtLeastOnce = false
    var isExiting = false

    init(userAgent: String, prevUserAgent: String, browserOptions: DappBrowserOptions) {
        self.userAgent = userAgent
        self.prevUserAgent = prevUserAgent
        self.browserOptions = browserOptions
        webViewUIDelegate = DappBrowserUIDelegate(title: Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "")

        super.init(nibName: nil, bundle: nil)

        webViewUIDelegate.viewController = self

        createViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        print("deinit")
    }

    func createViews() {
        // We create the views in code for primarily for ease of upgrades and not requiring an external .xib to be included

        var webViewBounds = view.bounds
        let toolbarIsAtBottom = !(browserOptions.toolbarposition == TOOLBAR_POSITION_TOP)
        webViewBounds.size.height -= CGFloat(browserOptions.location ? FOOTER_HEIGHT : TOOLBAR_HEIGHT)
        let userContentController = WKUserContentController()

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        configuration.userContentController.add(self, name: IAB_BRIDGE_NAME)
        configuration.userContentController.add(self, name: "cochain")

        //WKWebView options
        configuration.allowsInlineMediaPlayback = browserOptions.allowinlinemediaplayback
        if #available(iOS 10.0, *) {
            configuration.ignoresViewportScaleLimits = browserOptions.enableviewportscale
            if browserOptions.mediaplaybackrequiresuseraction == true {
                configuration.mediaTypesRequiringUserActionForPlayback = .all
            } else {
                configuration.mediaTypesRequiringUserActionForPlayback = []
            }
        } else {
            // iOS 9
            configuration.mediaPlaybackRequiresUserAction = browserOptions.mediaplaybackrequiresuseraction
        }

        let webView = WKWebView(frame: webViewBounds, configuration: configuration)
        self.webView = webView

        view.addSubview(webView)
        view.sendSubview(toBack: webView)

        webView.navigationDelegate = self
        webView.uiDelegate = webViewUIDelegate
        webView.backgroundColor = UIColor.white

        webView.clearsContextBeforeDrawing = true
        webView.clipsToBounds = true
        webView.contentMode = .scaleToFill
        webView.isMultipleTouchEnabled = true
        webView.isOpaque = true
        webView.isUserInteractionEnabled = true
        automaticallyAdjustsScrollViewInsets = true
        webView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false

        if #available(iOS 11.0, *) {
            webView.scrollView.contentInsetAdjustmentBehavior = .never
        }

        let spinner = UIActivityIndicatorView(activityIndicatorStyle: .gray)
        self.spinner = spinner
        spinner.alpha = 1.000
        spinner.autoresizesSubviews = true
        spinner.autoresizingMask = [.flexibleLeftMargin, .flexibleTopMargin, .flexibleBottomMargin, .flexibleRightMargin]
        spinner.clearsContextBeforeDrawing = false
        spinner.clipsToBounds = false
        spinner.contentMode = .scaleToFill
        spinner.frame = CGRect(x: webView.frame.midX, y: webView.frame.midY, width: 20.0, height: 20.0)
        spinner.isHidden = false
        spinner.hidesWhenStopped = true
        spinner.isMultipleTouchEnabled = false
        spinner.isOpaque = false
        spinner.isUserInteractionEnabled = false
        spinner.stopAnimating()

        closeButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.close))
        closeButton!.isEnabled = true

        let flexibleSpaceButton = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        let fixedSpaceButton = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        fixedSpaceButton.width = 20

        let toolbarY: CGFloat = toolbarIsAtBottom ? view.bounds.size.height - CGFloat(TOOLBAR_HEIGHT) : 0.0
        let toolbarFrame = CGRect(x: 0.0, y: toolbarY, width: view.bounds.size.width, height: CGFloat(TOOLBAR_HEIGHT))

        let toolbar = UIToolbar(frame: toolbarFrame)
        self.toolbar = toolbar
        toolbar.alpha = 1.000
        toolbar.autoresizesSubviews = true
        toolbar.autoresizingMask = toolbarIsAtBottom ? ([.flexibleWidth, .flexibleTopMargin]) : .flexibleWidth
        toolbar.barStyle = .blackOpaque
        toolbar.clearsContextBeforeDrawing = false
        toolbar.clipsToBounds = false
        toolbar.contentMode = .scaleToFill
        toolbar.isHidden = false
        toolbar.isMultipleTouchEnabled = false
        toolbar.isOpaque = false
        toolbar.isUserInteractionEnabled = true
        if !browserOptions.toolbarcolor.isEmpty {
            // Set toolbar color if user sets it in options
            toolbar.barTintColor = colorFromHexString(hexString: browserOptions.toolbarcolor)
        }
        if !browserOptions.toolbartranslucent {
            // Set toolbar translucent to no if user sets it in options
            toolbar.isTranslucent = false
        }

        let labelInset: CGFloat = 5.0
        let locationBarY: CGFloat = toolbarIsAtBottom ? view.bounds.size.height - CGFloat(FOOTER_HEIGHT) : view.bounds.size.height - CGFloat(LOCATIONBAR_HEIGHT)

        let addressLabel = UILabel(frame: CGRect(x: labelInset, y: locationBarY, width: view.bounds.size.width - labelInset, height: CGFloat(LOCATIONBAR_HEIGHT)))
        self.addressLabel = addressLabel
        addressLabel.adjustsFontSizeToFitWidth = false
        addressLabel.alpha = 1.000
        addressLabel.autoresizesSubviews = true
        addressLabel.autoresizingMask = [.flexibleWidth, .flexibleRightMargin, .flexibleTopMargin]
        addressLabel.backgroundColor = UIColor.clear
        addressLabel.baselineAdjustment = .alignCenters
        addressLabel.clearsContextBeforeDrawing = true
        addressLabel.clipsToBounds = true
        addressLabel.contentMode = .scaleToFill
        addressLabel.isEnabled = true
        addressLabel.isHidden = false
        addressLabel.lineBreakMode = .byTruncatingTail

        if addressLabel.responds(to: NSSelectorFromString("setMinimumScaleFactor:")) {
            addressLabel.minimumScaleFactor = 10.0 / UIFont.labelFontSize
        } else if addressLabel.responds(to: NSSelectorFromString("setMinimumFontSize:")) {
            // addressLabel.minimumFontSize = 10.0
        }

        addressLabel.isMultipleTouchEnabled = false
        addressLabel.numberOfLines = 1
        addressLabel.isOpaque = false
        addressLabel.shadowOffset = CGSize(width: 0.0, height: -1.0)
        addressLabel.text = NSLocalizedString("Loading...", comment: "")
        addressLabel.textAlignment = .left
        addressLabel.textColor = UIColor(white: 1.000, alpha: 1.000)
        addressLabel.isUserInteractionEnabled = false

        let frontArrowString = NSLocalizedString("►", comment: "") // create arrow from Unicode char
        forwardButton = UIBarButtonItem(title: frontArrowString, style: .plain, target: self, action: #selector(self.goForward))
        forwardButton!.isEnabled = true
        forwardButton!.imageInsets = .zero
        if !browserOptions.navigationbuttoncolor.isEmpty {
            // Set button color if user sets it in options
            forwardButton!.tintColor = colorFromHexString(hexString: browserOptions.navigationbuttoncolor)
        }

        let backArrowString = NSLocalizedString("◄", comment: "") // create arrow from Unicode char
        backButton = UIBarButtonItem(title: backArrowString, style: .plain, target: self, action: #selector(self.goBack))
        backButton!.isEnabled = true
        backButton!.imageInsets = .zero
        if !browserOptions.navigationbuttoncolor.isEmpty {
            // Set button color if user sets it in options
            backButton!.tintColor = colorFromHexString(hexString: browserOptions.navigationbuttoncolor)
        }

        // Filter out Navigation Buttons if user requests so
        if browserOptions.hidenavigationbuttons {
            toolbar.items = [closeButton!, flexibleSpaceButton]
        } else {
            toolbar.items = [closeButton!, flexibleSpaceButton, backButton!, fixedSpaceButton, forwardButton!]
        }

        view.backgroundColor = UIColor.gray
        view.addSubview(toolbar)
        view.addSubview(addressLabel)
        view.addSubview(spinner)
    }

    func setWebViewFrame(_ frame: CGRect) {
        print("Setting the WebView's frame to \(NSStringFromCGRect(frame))")
        webView?.frame = frame
    }

    func setCloseButtonTitle(_ title: String?, colorString: String?) {
        // the advantage of using UIBarButtonSystemItemDone is the system will localize it for you automatically
        // but, if you want to set this yourself, knock yourself out (we can't set the title for a system Done button, so we have to create a new one)
        closeButton = nil
        // Initialize with title if title is set, otherwise the title will be 'Done' localized
        closeButton = title != nil ? UIBarButtonItem(title: title, style: .bordered, target: self, action: #selector(self.close)) : UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.close))
        closeButton!.isEnabled = true
        // If color on closebutton is requested then initialize with that that color, otherwise use initialize with default
        closeButton!.tintColor = colorString != nil ? colorFromHexString(hexString: colorString) : UIColor(red: 60.0 / 255.0, green: 136.0 / 255.0, blue: 230.0 / 255.0, alpha: 1)

        toolbar?.items?[0] = closeButton!
    }

    func showLocationBar(_ show: Bool) {
        var locationbarFrame: CGRect = addressLabel!.frame

        let toolbarVisible = !toolbar!.isHidden

        // prevent double show/hide
        if show == !(addressLabel!.isHidden) {
            return
        }

        if show {
            addressLabel!.isHidden = false

            if toolbarVisible {
                // toolBar at the bottom, leave as is
                // put locationBar on top of the toolBar

                var webViewBounds: CGRect = view.bounds
                webViewBounds.size.height -= CGFloat(FOOTER_HEIGHT)
                setWebViewFrame(webViewBounds)

                locationbarFrame.origin.y = webViewBounds.size.height
                addressLabel!.frame = locationbarFrame
            } else {
                // no toolBar, so put locationBar at the bottom

                var webViewBounds: CGRect = view.bounds
                webViewBounds.size.height -= CGFloat(LOCATIONBAR_HEIGHT)
                setWebViewFrame(webViewBounds)

                locationbarFrame.origin.y = webViewBounds.size.height
                addressLabel!.frame = locationbarFrame
            }
        } else {
            addressLabel!.isHidden = true

            if toolbarVisible {
                // locationBar is on top of toolBar, hide locationBar

                // webView take up whole height less toolBar height
                var webViewBounds: CGRect = view.bounds
                webViewBounds.size.height -= CGFloat(TOOLBAR_HEIGHT)
                setWebViewFrame(webViewBounds)
            } else {
                // no toolBar, expand webView to screen dimensions
                setWebViewFrame(view.bounds)
            }
        }
    }

    func showToolBar(_ show: Bool, toolbarPosition: String?) {
        var toolbarFrame: CGRect = toolbar!.frame
        var locationbarFrame: CGRect = addressLabel!.frame

        let locationbarVisible = !addressLabel!.isHidden

        // prevent double show/hide
        if show == !(toolbar!.isHidden) {
            return
        }

        if show {
            toolbar!.isHidden = false
            var webViewBounds: CGRect = view.bounds

            if locationbarVisible {
                // locationBar at the bottom, move locationBar up
                // put toolBar at the bottom
                webViewBounds.size.height -= CGFloat(FOOTER_HEIGHT)
                locationbarFrame.origin.y = webViewBounds.size.height
                addressLabel!.frame = locationbarFrame
                toolbar!.frame = toolbarFrame
            } else {
                // no locationBar, so put toolBar at the bottom
                var webViewBounds: CGRect = view.bounds
                webViewBounds.size.height -= CGFloat(TOOLBAR_HEIGHT)
                toolbar!.frame = toolbarFrame
            }

            if (toolbarPosition == TOOLBAR_POSITION_TOP) {
                toolbarFrame.origin.y = 0
                webViewBounds.origin.y += toolbarFrame.size.height
            } else {
                toolbarFrame.origin.y = webViewBounds.size.height + CGFloat(LOCATIONBAR_HEIGHT)
            }
            setWebViewFrame(webViewBounds)
        } else {
            toolbar!.isHidden = true

            if locationbarVisible {
                // locationBar is on top of toolBar, hide toolBar
                // put locationBar at the bottom

                // webView take up whole height less locationBar height
                var webViewBounds: CGRect = view.bounds
                webViewBounds.size.height -= CGFloat(LOCATIONBAR_HEIGHT)
                setWebViewFrame(webViewBounds)

                // move locationBar down
                locationbarFrame.origin.y = webViewBounds.size.height
                addressLabel!.frame = locationbarFrame
            } else {
                // no locationBar, expand webView to screen dimensions
                setWebViewFrame(view.bounds)
            }
        }
    }

    override func viewDidLoad() {
        viewRenderedAtLeastOnce = false
        super.viewDidLoad()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isExiting && (navigationDelegate != nil) && navigationDelegate!.responds(to: #selector(navigationDelegate!.browserExit)) {
            navigationDelegate!.browserExit()
            isExiting = false
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .default
    }

    override var prefersStatusBarHidden: Bool {
        return false
    }

    @objc func close() {
        CDVUserAgentUtil.releaseLock(&userAgentLockToken)
        currentURL = nil

        weak var weakSelf: UIViewController? = self

        // Run later to avoid the "took a long time" log message.
        DispatchQueue.main.async(execute: {
            self.isExiting = true
            if weakSelf?.responds(to: #selector(getter: UIViewController.presentingViewController)) ?? false {
                weakSelf?.presentingViewController?.dismiss(animated: true)
            } else {
                weakSelf?.parent?.dismiss(animated: true)
            }
        })
    }

    func navigate(to url: URL?) {
        let request: URLRequest? = url != nil ? URLRequest(url: url!) : nil

        if userAgentLockToken != 0 {
            if let req = request {
                webView?.load(req)
            }
        } else {
            weak var weakSelf: DappBrowserViewController? = self
            CDVUserAgentUtil.acquireLock({ lockToken in
                self.userAgentLockToken = lockToken
                CDVUserAgentUtil.setUserAgent(self.userAgent, lockToken: lockToken)
                if let req = request {
                    weakSelf?.webView?.load(req)
                }
            })
        }
    }

    @objc func goBack(_ sender: Any?) {
        webView?.goBack()
    }

    @objc func goForward(_ sender: Any?) {
        webView?.goForward()
    }

    override func viewWillAppear(_ animated: Bool) {
        if #available(iOS 7.0, *) {
            if !viewRenderedAtLeastOnce {
                viewRenderedAtLeastOnce = true
                var viewBounds: CGRect? = webView?.bounds
                viewBounds?.origin.y = CGFloat(STATUSBAR_HEIGHT)
                let height = viewBounds?.size.height ?? 0.0
                viewBounds?.size.height = height - CGFloat(STATUSBAR_HEIGHT)
                webView?.frame = viewBounds ?? CGRect.zero
                // UIApplication.shared.statusBarStyle = UIStatusBarStyle(rawValue: preferredStatusBarStyle)!
            }
        }

        rePositionViews()

        super.viewWillAppear(animated)
    }

    // On iOS 7 the status bar is part of the view's dimensions, therefore it's height has to be taken into account.
    // The height of it could be hardcoded as 20 pixels, but that would assume that the upcoming releases of iOS won't
    // change that value.
    func getStatusBarOffset() -> Float {
        let statusBarFrame: CGRect = UIApplication.shared.statusBarFrame
        var statusBarOffset: Float = 0.0
        if #available(iOS 7.0, *) {
            statusBarOffset = Float(min(statusBarFrame.size.width, statusBarFrame.size.height))
        }
        return statusBarOffset
    }

    func rePositionViews() {
        if (browserOptions.toolbarposition == TOOLBAR_POSITION_TOP) {
            webView?.frame = CGRect(x: webView?.frame.origin.x ?? 0.0, y: CGFloat(TOOLBAR_HEIGHT), width: webView?.frame.size.width ?? 0.0, height: webView?.frame.size.height ?? 0.0)
            toolbar?.frame = CGRect(x: toolbar?.frame.origin.x ?? 0.0, y: CGFloat(getStatusBarOffset()), width: toolbar?.frame.size.width ?? 0.0, height: toolbar?.frame.size.height ?? 0.0)
        }
    }

    // Helper function to convert hex color string to UIColor
    // Assumes input like "#00FF00" (#RRGGBB).
    // Taken from https://stackoverflow.com/questions/1560081/how-can-i-create-a-uicolor-from-a-hex-string
    func colorFromHexString(hexString: String?) -> UIColor? {
        var rgbValue: UInt32 = 0
        let scanner = Scanner(string: hexString ?? "")
        scanner.scanLocation = 1 // bypass '#' character
        scanner.scanHexInt32(&rgbValue)
        return UIColor(
            red: CGFloat(Double(Int(rgbValue) & 0xff0000 >> 16) / 255.0),
            green: CGFloat(Double(((Int(rgbValue) & 0xff00) >> 8)) / 255.0),
            blue: CGFloat(Double((Int(rgbValue) & 0xff)) / 255.0),
            alpha: 1.0
        )
    }

    func webView(_ theWebView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        // loading url, start spinner, update back/forward

        addressLabel?.text = NSLocalizedString("Loading...", comment: "")
        backButton?.isEnabled = theWebView.canGoBack
        forwardButton?.isEnabled = theWebView.canGoForward

        print(browserOptions.hidespinner ? "Yes" : "No")
        if !browserOptions.hidespinner {
            spinner?.startAnimating()
        }

        return (navigationDelegate?.didStartProvisionalNavigation(theWebView))!
    }

    func webView(_ theWebView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url: URL? = navigationAction.request.url
        let mainDocumentURL: URL? = navigationAction.request.mainDocumentURL

        let isTopLevelNavigation = url == mainDocumentURL

        if isTopLevelNavigation {
            currentURL = url
        }

        navigationDelegate?.webView(theWebView, decidePolicyFor: navigationAction, decisionHandler: decisionHandler)
    }

    func webView(_ theWebView: WKWebView, didFinish navigation: WKNavigation!) {
        // update url, stop spinner, update back/forward

        addressLabel?.text = currentURL?.absoluteString
        backButton?.isEnabled = theWebView.canGoBack
        forwardButton?.isEnabled = theWebView.canGoForward
        theWebView.scrollView.contentInset = .zero

        spinner?.stopAnimating()

        // Work around a bug where the first time a PDF is opened, all UIWebViews
        // reload their User-Agent from NSUserDefaults.
        // This work-around makes the following assumptions:
        // 1. The app has only a single Cordova Webview. If not, then the app should
        //    take it upon themselves to load a PDF in the background as a part of
        //    their start-up flow.
        // 2. That the PDF does not require any additional network requests. We change
        //    the user-agent here back to that of the CDVViewController, so requests
        //    from it must pass through its white-list. This *does* break PDFs that
        //    contain links to other remote PDF/websites.
        // More info at https://issues.apache.org/jira/browse/CB-2225
        let isPDF = false
        // TODO webview class
        // let isPDF: Bool = "true" == theWebView.evaluateJavaScript("document.body==null")
        if isPDF {
            CDVUserAgentUtil.setUserAgent(prevUserAgent, lockToken: userAgentLockToken)
        }

        navigationDelegate?.didFinishNavigation(theWebView)
    }

    func webView(_ theWebView: WKWebView, failedNavigation delegateName: String?, withError: Error) {
        // log fail message, stop spinner, update back/forward
        let error = withError as NSError
        print(String(format: "webView:%@ - %ld: %@", delegateName ?? "", error.code, error.localizedDescription))

        backButton?.isEnabled = theWebView.canGoBack
        forwardButton?.isEnabled = theWebView.canGoForward
        spinner?.stopAnimating()

        addressLabel?.text = NSLocalizedString("Load Error", comment: "")

        navigationDelegate?.webView(theWebView, didFailNavigation: error)
    }

    func webView(_ theWebView: WKWebView, didFail: WKNavigation!, withError: Error) {
        webView(theWebView, failedNavigation: "didFailNavigation", withError: withError)
    }

    func webView(_ theWebView: WKWebView, didFailProvisionalNavigation: WKNavigation!, withError: Error) {
        webView(theWebView, failedNavigation: "didFailProvisionalNavigation", withError: withError)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if (message.name == IAB_BRIDGE_NAME) {
            navigationDelegate?.userContentController(userContentController, didReceive: message)
        } else if (message.name == "cochain") {
            navigationDelegate?.userContentControllerForCochain(userContentController, didReceive: message)
        }
    }

    @objc override var shouldAutorotate: Bool {
        if (orientationDelegate != nil) && orientationDelegate!.responds(to: #selector(getter: self.shouldAutorotate)) {
            return orientationDelegate!.shouldAutorotate()
        }
        return true
    }

    @objc override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if (orientationDelegate != nil) && orientationDelegate!.responds(to: #selector(getter: self.supportedInterfaceOrientations)) {
            return orientationDelegate!.supportedInterfaceOrientations()
        }

        return UIInterfaceOrientationMask(rawValue: 1 << UIInterfaceOrientation.portrait.rawValue)
    }

    /*
    @objc override func shouldAutorotate(to interfaceOrientation: UIInterfaceOrientation) -> Bool {
        if (orientationDelegate != nil) && orientationDelegate!.responds(to: #selector(self.shouldAutorotate(to:))) {
            return orientationDelegate!.shouldAutorotate(to: interfaceOrientation)
        }

        return true
    }
    */
}

class DappBrowserScreenOrientationDelegate: NSObject, CDVScreenOrientationDelegate {
    func shouldAutorotate(to interfaceOrientation: UIInterfaceOrientation) -> Bool {
        return false // actually deprecated
    }
    
    var dappBrowserViewController: DappBrowserViewController?

    init(viewController: DappBrowserViewController?) {
        dappBrowserViewController = viewController
    }

    func supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
        return dappBrowserViewController!.supportedInterfaceOrientations
    }

    func shouldAutorotate() -> Bool {
        return dappBrowserViewController!.shouldAutorotate
    }
}
