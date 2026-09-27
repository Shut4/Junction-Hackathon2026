import Foundation

/// Resolves text through the app bundle so iOS's per-app language preference is used.
func localized(_ key:String,_ arguments:Any...) -> String {
    var text=Bundle.main.localizedString(forKey:key,value:key,table:nil)
    for (index,argument) in arguments.enumerated() {
        text=text.replacingOccurrences(of:"{\(index)}",with:String(describing:argument))
    }
    return text
}
