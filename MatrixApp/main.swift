import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Accessory: no Dock icon (LSUIElement=true in Info.plist already does this,
// but setting policy here too is belt-and-suspenders).
app.setActivationPolicy(.accessory)
app.run()
