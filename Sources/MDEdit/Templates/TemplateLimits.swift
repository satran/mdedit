import Foundation

/// Every limit of the template engine in one place. A test builds a copy with one value changed to exceed it by one.
/// KB and MB are 1,024 and 1,048,576 bytes. The values are starting points that the performance tests check.
struct TemplateLimits: Equatable {
    var templateBytes = 64 * 1024
    var nodes = 2_000
    var forDepth = 2
    var blockDepth = 10
    var digits = 9
    var listItems = 100
    var sectionBytes = 64 * 1024
    var readBytes = 8 * 1024 * 1024
    var titleBytes = 4 * 1024
    var metaBytes = 16 * 1024
    var entries = 10_000
    var steps = 200_000
    var outputBytes = 2 * 1024 * 1024
    var clock: TimeInterval = 2

    static let standard = TemplateLimits()
}
