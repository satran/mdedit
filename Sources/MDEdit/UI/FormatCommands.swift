import SwiftUI

/// The Format menu and its palette entries. Keys: ⌘B ⌘I ⌘K, ⇧⌘X strike, ⇧⌘H highlight, ⇧⌘C inline code, ⌃1…6 headings,
/// ⌘0 body, ⇧⌘L bullets, ⇧⌘N numbers, ⇧⌘T tasks, ⇧⌘. quote, ⌥⌘C code block, ⌥⌘- rule.
@MainActor
func formatCommands(ws: Workspace?) -> [Cmd] {
    let on = ws?.document.url != nil && ws?.mode == .write
    func f(_ id: String, _ title: String, _ action: FormatAction, _ key: KeyEquivalent, _ mods: EventModifiers = .command, divider: Bool = false) -> Cmd {
        Cmd(id: "format-" + id, title: title, place: .format, key: key, modifiers: mods, enabled: on, dividerBefore: divider) { ws?.editor.apply(action) }
    }
    let opt: EventModifiers = [.command, .option], shift: EventModifiers = [.command, .shift]
    return [
        f("bold", "Bold", .bold, "b"),
        f("italic", "Italic", .italic, "i"),
        f("strike", "Strikethrough", .strike, "x", shift),
        f("highlight", "Highlight", .highlight, "h", shift),
        f("code", "Inline Code", .code, "c", shift),
        f("link", "Link", .link, "k"),
        f("h1", "Heading 1", .heading(1), "1", .control, divider: true),
        f("h2", "Heading 2", .heading(2), "2", .control),
        f("h3", "Heading 3", .heading(3), "3", .control),
        f("h4", "Heading 4", .heading(4), "4", .control),
        f("h5", "Heading 5", .heading(5), "5", .control),
        f("h6", "Heading 6", .heading(6), "6", .control),
        f("body", "Body Text", .body, "0", .command),
        f("bullet", "Bulleted List", .bullet, "l", shift, divider: true),
        f("numbered", "Numbered List", .numbered, "n", shift),
        f("task", "Task List", .task, "t", shift),
        f("quote", "Quote", .quote, ".", shift),
        f("codeblock", "Code Block", .codeBlock, "c", opt),
        f("rule", "Horizontal Rule", .rule, "-", opt),
    ]
}
