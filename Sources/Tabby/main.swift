import AppKit

let app = NSApplication.shared

// Hidden developer flag: render README images offscreen and exit. Starts nothing else.
let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--render-demo") {
    let dir = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : "docs/images"
    app.setActivationPolicy(.prohibited)
    DemoRenderer.run(outputDir: dir)
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
