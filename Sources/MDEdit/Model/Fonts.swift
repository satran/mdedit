import AppKit
import CoreText

/// The fonts that ship in the app (IBM Plex Mono, Source Serif 4, and Literata and Inter when they are in the bundle; see the OFL files next to them), and a
/// lookup by family that works for those and for anything installed on the Mac.
enum Fonts {
    private static let registered: Void = {
        let dir = Bundle.main.resourceURL
        let urls = [dir?.appendingPathComponent("Fonts"), dir].compactMap { $0 }.flatMap {
            (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? []
        }.filter { $0.pathExtension == "ttf" }
        for u in urls { CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil) }
    }()

    /// Every installed family, split once per launch: fixed-pitch ones for the editor, and the others that are meant for reading
    /// (sans, serif, rounded...) for the viewer. Script, ornament and symbol faces are left out of both.
    private static let classified: (mono: [String], text: [String]) = {
        _ = registered
        let fm = NSFontManager.shared
        let skipped: Set<UInt32> = [0x9000_0000, 0xA000_0000, 0xC000_0000]      // CoreText style classes: ornamentals, scripts, symbolic
        let latin = CharacterSet(charactersIn: "AaZz09")
        var mono: [String] = [], text: [String] = []
        for family in fm.availableFontFamilies where !family.hasPrefix(".") {
            guard let name = fm.availableMembers(ofFontFamily: family)?.first?.first as? String, let font = NSFont(name: name, size: 12) else { continue }
            if font.isFixedPitch { mono.append(family) }
            else if !skipped.contains(font.fontDescriptor.symbolicTraits.rawValue & 0xF000_0000), font.coveredCharacterSet.isSuperset(of: latin) { text.append(family) }
        }
        let order: (String, String) -> Bool = { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return (mono.sorted(by: order), text.sorted(by: order))
    }()
    static var monospacedFamilies: [String] { classified.mono }
    /// Families the viewer can use; a name the stylesheet could not carry safely (`Preferences.cleanFamily`) is left out.
    static var readingFamilies: [String] { classified.text.filter { Preferences.cleanFamily($0) == $0 } }

    static func installed(_ family: String) -> Bool {
        _ = registered
        return NSFontManager.shared.availableFontFamilies.contains(family)
    }

    static func nsFont(family: String, size: CGFloat) -> NSFont? {
        guard installed(family) else { return nil }
        return NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: family]), size: size)
    }
}
