//
//  DotquadLiteHarness.swift
//  DotquadLiteHarness
//
//  Opens Dotquad Lite in DroppyKit's harness:
//
//      swift run DotquadLiteHarness
//
//  Not main.swift: that name is top-level code and can't hold @main.
//

import DroppyKit
import DroppyKitHarness
import DotquadLite

@main
struct DotquadLiteHarness: DropletHarnessApp {
    static func makeDroplet() -> any Droplet { DotquadLiteDroplet() }
}
