// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "WebBenchStorage",
  platforms: [.macOS("15.0")],
  targets: [
    .target(
      name: "BenchStorage", path: "Sources",
      exclude: [
        "PhotoEditor.swift", "FaviconEditor.swift", "StudioControls.swift", "PaletteTile.swift", "App.swift", "Canvas.swift", "CodeEditor.swift", "Engine.swift", "Session.swift",
        "DesignInspector.swift", "WorkspaceView.swift", "SampleChecks.swift",
      ], sources: ["LayerOrder.swift","IconBitmap.swift","PhotoRecipe.swift","Project.swift"]),
    .testTarget(name: "StorageTests", dependencies: ["BenchStorage"], path: "Tests/Storage"),
  ]
)
