import SwiftUI

/// A slim bar under the header: a line of text and a few small buttons.
struct InfoBar: View {
    struct Action { var title: String; var enabled = true; var run: () -> Void }
    var text: String
    var spinner = false
    var actions: [Action] = []

    var body: some View {
        HStack(spacing: 12) {
            if spinner { ProgressView().controlSize(.small) }
            Text(text).font(.system(size: 12.5)).lineLimit(2)
            Spacer()
            ForEach(Array(actions.enumerated()), id: \.offset) { _, a in Button(a.title, action: a.run).controlSize(.small).disabled(!a.enabled) }
        }
        .padding(.horizontal, 28).frame(height: 34)
        .background(Color(Palette.chip))
    }
}
