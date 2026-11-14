import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

if let index = CommandLine.arguments.firstIndex(of: "--snapshot") {
    let output = CommandLine.arguments.count > index + 1
        ? CommandLine.arguments[index + 1]
        : "/tmp/island-preview.png"
    MainActor.assumeIsolated {
        SnapshotMode.run(outputPath: output)
    }
    print("snapshot written to \(output)")
    exit(0)
}

if CommandLine.arguments.contains("--probe") {
    MainActor.assumeIsolated {
        let probe = AppDelegate()
        probe.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        print(probe.probeDescription)
    }
    exit(0)
}

let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
