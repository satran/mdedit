import AppKit
import CoreText

/// The fonts that ship in the app (IBM Plex Mono, Source Serif 4; see the OFL files next to them), and a
/// lookup by family that works for those and for anything installed on the Mac.
enum Fonts {
    private static let registered: Void = {
        let dir = Bundle.main.resourceURL
        let urls = [dir?.appendingPathComponent("Fonts"), dir].compactMap { $0 }.flatMap {
            (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? []
        }.filter { $0.pathExtension == "ttf" }
        for u in urls { CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil) }
    }()

    static func installed(_ family: String) -> Bool {
        _ = registered
        return NSFontManager.shared.availableFontFamilies.contains(family)
    }

    static func nsFont(family: String, size: CGFloat) -> NSFont? {
        guard installed(family) else { return nil }
        return NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: family]), size: size)
    }
}
