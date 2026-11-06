import SwiftUI
import AppKit

extension View {
    /// The pointing hand over something clickable. The note under an overlay asks for an I-beam, so it is asked for twice.
    func pointerCursor() -> some View {
        onContinuousHover { phase in
            if case .active = phase {
                NSCursor.pointingHand.set()
                DispatchQueue.main.async { NSCursor.pointingHand.set() }
            }
        }
    }
}
