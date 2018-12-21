class DappBrowserOptions {
    
    
    var location = true
    var toolbar = true
    var closebuttoncaption = ""
    var closebuttoncolor = ""
    var toolbarposition = "bottom"
    var toolbarcolor = ""
    var toolbartranslucent = true
    var hidenavigationbuttons = false
    var navigationbuttoncolor = ""
    var cleardata = false
    var clearcache = false
    var clearsessioncache = false
    var hidespinner = false
    
    var presentationstyle = ""
    var transitionstyle = ""
    
    var enableviewportscale = false
    var mediaplaybackrequiresuseraction = false
    var allowinlinemediaplayback = false
    var keyboarddisplayrequiresuseraction = true
    var suppressesincrementalrendering = false
    var hidden = false
    var disallowoverscroll = false
    var beforeload = false
    
    func parseOptions(_ options: String) {
        if options.isEmpty {
            return
        }

        let pairs = options.split(separator: ",")
        
        // parse keys and values, set the properties
        for pair in pairs {
            let keyvalue = pair.split(separator: "=")
            let key = keyvalue[0].lowercased()
            let value = keyvalue[1]
            let value_lc = value.lowercased()
            
            let strValue = String(value)
            let boolValue = value_lc == "no" ? false : true
            
            switch key {
            case "location":
                location = boolValue
            case "toolbar":
                toolbar = boolValue
            case "closebuttoncaption":
                closebuttoncaption = strValue
            case "closebuttoncolor":
                closebuttoncolor = strValue
            case "toolbarposition":
                toolbarposition = strValue
            case "toolbarcolor":
                toolbarcolor = strValue
            case "toolbartranslucent":
                toolbartranslucent = boolValue
            case "hidenavigationbuttons":
                hidenavigationbuttons = boolValue
            case "navigationbuttoncolor":
                navigationbuttoncolor = strValue
            case "cleardata":
                cleardata = boolValue
            case "clearcache":
                clearcache = boolValue
            case "clearsessioncache":
                clearsessioncache = boolValue
            case "hidespinner":
                hidespinner = boolValue
            case "presentationstyle":
                presentationstyle = strValue
            case "transitionstyle":
                transitionstyle = strValue
            case "enableviewportscale":
                enableviewportscale = boolValue
            case "mediaplaybackrequiresuseraction":
                mediaplaybackrequiresuseraction = boolValue
            case "allowinlinemediaplayback":
                allowinlinemediaplayback = boolValue
            case "keyboarddisplayrequiresuseraction":
                keyboarddisplayrequiresuseraction = boolValue
            case "suppressesincrementalrendering":
                suppressesincrementalrendering = boolValue
            case "hidden":
                hidden = boolValue
            case "disallowoverscroll":
                disallowoverscroll = boolValue
            case "beforeload":
                beforeload = boolValue
            default:
                print("invalid option")
            }
        }
    }
}
