import Foundation

/// Every limit of the template engine in one place. A test builds a copy with one value changed to exceed it by one.
/// KB and MB are 1,024 and 1,048,576 bytes. The values are starting points that the performance tests check.
struct TemplateLimits: Equatable {
    var templateBytes = 64 * 1024
    var nodes = 4_000
    var forDepth = 3
    var blockDepth = 10
    var digits = 9
    var listItems = 500
    var sectionBytes = 64 * 1024
    var readBytes = 8 * 1024 * 1024
    var titleBytes = 4 * 1024
    var metaBytes = 16 * 1024
    /// A note read for its task lines, and a JSON or YAML file read as data.
    var taskBytes = 256 * 1024
    var dataBytes = 256 * 1024
    var taskItems = 500
    /// Values in a data file (every number, text, list and record counts) and how deep they nest.
    var dataValues = 50_000
    var dataDepth = 12
    /// Includes: how deep they nest and how many are run in one render.
    var includeDepth = 3
    var includes = 50
    /// The longest pattern for `match`, and how deep `recursive` goes.
    var patternLength = 100
    var recursiveDepth = 12
    /// What a query parameter can hold (a link on a rendered page sets them).
    var queryKeys = 20
    var queryValueLength = 256
    var entries = 10_000
    var steps = 200_000
    var outputBytes = 2 * 1024 * 1024
    var clock: TimeInterval = 2

    static let standard = TemplateLimits()
}
