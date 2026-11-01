import SwiftUI

struct RootView: View {
    @EnvironmentObject var ws: Workspace
    @AppStorage("binderWidth") private var binderWidth = 272.0
    @State private var dragStart: Double?

    var body: some View {
        Group {
            if ws.focus {
                FocusView(document: ws.document)
            } else {
                HStack(spacing: 0) {
                    if ws.binderVisible {
                        BinderView().frame(width: binderWidth)
                        divider
                    }
                    DetailView(document: ws.document)
                }
            }
        }
        .ignoresSafeArea()
        .onOpenURL { ws.openExternal($0) }
        .background(Color(Palette.paneBg))
        .background(TrafficLights())
        .overlay {
            if ws.paletteVisible {
                ZStack(alignment: .top) {
                    Color.clear.contentShape(Rectangle()).onTapGesture { ws.paletteVisible = false }
                    PaletteView().padding(.top, 70)
                }
            }
        }
        .overlay {
            if ws.shellBarVisible {
                ZStack(alignment: .top) {
                    Color.clear.contentShape(Rectangle()).onTapGesture { if ws.shellJob == nil { ws.shellBarVisible = false } }
                    ShellBarView().padding(.top, 70)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let log = ws.shellLog { ShellLogView(log: log) { ws.shellLog = nil }.padding(16) }
        }
        .alert("Something went wrong", isPresented: Binding(get: { ws.message != nil }, set: { if !$0 { ws.message = nil } })) {
            Button("OK") { ws.message = nil }
        } message: { Text(ws.message ?? "") }
    }

    /// A 1pt line with a wider strip to grab.
    private var divider: some View {
        Rectangle().fill(Color(Palette.binderBorder)).frame(width: 1)
            .overlay {
                Color.clear.frame(width: 9).contentShape(Rectangle())
                    .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { v in
                            if dragStart == nil { dragStart = binderWidth }
                            binderWidth = min(420, max(200, (dragStart ?? 272) + v.translation.width))
                        }
                        .onEnded { _ in dragStart = nil })
            }
    }
}
