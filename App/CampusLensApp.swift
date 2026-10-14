import SwiftUI
import SwiftData

@main
struct CampusLensApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup { RootView().environment(model).modifier(TestAccessibilitySettings()) }
            .modelContainer(for: HistoryRecord.self, inMemory: ProcessInfo.processInfo.arguments.contains("--ui-test"))
    }
}

struct TestAccessibilitySettings: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--accessibility-test") {
            content.dynamicTypeSize(.accessibility5)
                .preferredColorScheme(.dark)
        } else { content }
        #else
        content
        #endif
    }
}
