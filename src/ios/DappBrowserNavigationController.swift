class DappBrowserNavigationController: UINavigationController {
    static let STATUSBAR_HEIGHT = 20.0
    
    var orientationDelegate: CDVScreenOrientationDelegate?
    
    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        if presentedViewController != nil {
            super.dismiss(animated: flag, completion: completion)
        }
    }
    
    override func viewDidLoad() {
        
        var statusBarFrame: CGRect = invertFrameIfNeeded(UIApplication.shared.statusBarFrame)
        statusBarFrame.size.height = CGFloat(DappBrowserNavigationController.STATUSBAR_HEIGHT)
        // simplified from: http://stackoverflow.com/a/25669695/219684
        
        let bgToolbar = UIToolbar(frame: statusBarFrame)
        bgToolbar.barStyle = .default
        bgToolbar.autoresizingMask = .flexibleWidth
        view.addSubview(bgToolbar)
        
        super.viewDidLoad()
    }
    
    func invertFrameIfNeeded(_ rect: CGRect) -> CGRect {
        var rect = rect
        if UIApplication.shared.statusBarOrientation.isLandscape {
            let temp: CGFloat = rect.size.width
            rect.size.width = rect.size.height
            rect.size.height = temp
        }
        rect.origin = CGPoint.zero
        return rect
    }


    override var shouldAutorotate: Bool {
        if (orientationDelegate != nil) && orientationDelegate!.responds(to: #selector(getter: self.shouldAutorotate)) {
            return orientationDelegate!.shouldAutorotate()
        }
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if (orientationDelegate != nil) && orientationDelegate!.responds(to: #selector(getter: self.supportedInterfaceOrientations)) {
            return orientationDelegate!.supportedInterfaceOrientations()
        }
        
        return UIInterfaceOrientationMask(rawValue: 1 << UIInterfaceOrientation.portrait.rawValue)
    }
    
    /*
    override func shouldAutorotate(to interfaceOrientation: UIInterfaceOrientation) -> Bool {
        if (orientationDelegate != nil) && orientationDelegate!.responds(to: #selector(self.shouldAutorotate(to:))) {
            return orientationDelegate!.shouldAutorotate(to: interfaceOrientation)
        }
        
        return true
    }
    */
}
