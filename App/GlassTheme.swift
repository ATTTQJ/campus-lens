import SwiftUI
import CampusLensCore

/// Material is supplied by iOS, including refraction and accessibility behavior.
struct GlassPanel<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    let title: String?
    let content: Content
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.content = content()
    }
    var body: some View {
        GlassEffectContainer(spacing:8) {
            VStack(alignment:.leading, spacing:14) {
                if let title { Text(title).font(.headline).accessibilityAddTraits(.isHeader) }
                content
            }
        }
        .padding(18).frame(maxWidth:.infinity, alignment:.leading)
        .modifier(PanelMaterial(reduceTransparency:reduceTransparency, dark:colorScheme == .dark))
    }
}

private struct PanelMaterial: ViewModifier {
    let reduceTransparency: Bool
    let dark: Bool
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(uiColor:dark ? .secondarySystemBackground : .systemBackground),
                               in:RoundedRectangle(cornerRadius:24))
        } else {
            content.glassEffect(.regular, in:RoundedRectangle(cornerRadius:24))
        }
    }
}

struct GlassBackdrop: View {
    var jpeg: Data? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(uiColor:.systemGroupedBackground)
                if !reduceTransparency, let jpeg, let image = UIImage(data:jpeg) {
                    Image(uiImage:image).resizable().scaledToFill()
                        .frame(width:geometry.size.width,height:geometry.size.height)
                        .blur(radius:40).opacity(scheme == .dark ? 0.20 : 0.24)
                }
            }.clipped()
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct ExposureNumbers: View {
    let exposure: Exposure
    var body: some View {
        ViewThatFits(in:.horizontal) {
            HStack(alignment:.top,spacing:14) { values }
            VStack(alignment:.leading,spacing:12) { values }
        }.accessibilityElement(children:.contain)
    }
    @ViewBuilder private var values: some View {
        value("光圈",String(format:"f/%.1f",exposure.aperture))
        value("快门",exposure.shutterLabel)
        value("ISO",String(Int(exposure.iso)))
    }
    private func value(_ label: String,_ number: String) -> some View {
        VStack(alignment:.leading,spacing:5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(number).font(.system(.title,weight:.semibold)).monospacedDigit()
                .fixedSize(horizontal:true,vertical:false)
        }.frame(maxWidth:.infinity,alignment:.leading).accessibilityElement(children:.combine)
    }
}
