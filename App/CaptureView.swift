import SwiftUI
import CampusLensCore

enum CaptureLayout {
    static func previewSize(in size: CGSize,reservedHeight: CGFloat) -> CGSize {
        let width = max(1,min(size.width,max(1,size.height-reservedHeight)*3/4))
        return CGSize(width:width,height:width*4/3)
    }
}

struct CaptureView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var focus: UnitRect?
    @State private var showConditions = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                if typeSize.isAccessibilitySize {
                    ScrollView {
                        VStack(spacing:12) {
                            captureHeader
                            finder.frame(width:geometry.size.width,height:geometry.size.width*4/3)
                            captureControls
                        }.padding(.bottom,12)
                    }
                } else {
                    let preview = CaptureLayout.previewSize(in:geometry.size,reservedHeight:240)
                    VStack(spacing:0) {
                        captureHeader.frame(height:44)
                        finder.frame(width:preview.width,height:preview.height)
                        captureControls.padding(.top,8)
                        Spacer(minLength:0)
                    }
                }
            }.foregroundStyle(.white)
        }
        .toolbar(.hidden,for:.navigationBar)
        .sheet(isPresented:$showConditions) {
            NavigationStack { ConditionsSheet(intent:model.intent) { model.intent = $0 } }
                .presentationBackground(.clear).presentationDragIndicator(.visible)
        }
    }
    private var captureHeader: some View {
        HStack {
            Text(model.isSimulator ? "测试" : "RAW").font(.caption.weight(.semibold))
                .padding(.horizontal,9).padding(.vertical,5).glassEffect(in:Capsule())
            Spacer()
            Text("1× · 4:3").font(.caption).foregroundStyle(.white.opacity(0.85))
            Spacer()
            Button { showConditions = true } label: { Image(systemName:"slider.horizontal.3").frame(width:36,height:36) }
                .buttonStyle(.glass).accessibilityLabel("拍摄条件").accessibilityIdentifier("capture-conditions")
        }.padding(.horizontal,16)
    }
    private var finder: some View {
        GeometryReader { geometry in
            ZStack {
                if model.isSimulator {
                    Color(white:0.12)
                    Text("模拟器测试取景\n没有真实 RAW／现场测光").multilineTextAlignment(.center).font(.callout).padding()
                } else { CameraPreview(service:model.captureService) { focus = $0 } }
                if let focus {
                    RoundedRectangle(cornerRadius:4).stroke(.yellow,lineWidth:1.5)
                        .frame(width:geometry.size.width*focus.width,height:geometry.size.height*focus.height)
                        .position(x:geometry.size.width*(focus.x+focus.width/2),y:geometry.size.height*(focus.y+focus.height/2))
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }.clipped()
        }.accessibilityIdentifier("capture-viewfinder")
    }
    private var captureControls: some View {
        @Bindable var model = model
        return VStack(spacing:8) {
            SceneSelector(intent:$model.intent,label:"新闻场景").pickerStyle(.segmented)
                .padding(4).glassEffect(in:Capsule())
            Button { showConditions = true } label: {
                Text("D850 \(model.intent.nikonFocal,specifier:"%.0f")mm · 200D \(model.intent.canonFocal,specifier:"%.0f")mm")
                    .font(.caption).foregroundStyle(.white.opacity(0.8))
            }.accessibilityLabel("修改两支镜头的实际焦距")
            HStack {
                Button { model.selectedTab = 1 } label: {
                    if let sample = model.sample,let image = UIImage(data:sample.previewJPEG) {
                        Image(uiImage:image).resizable().scaledToFill().frame(width:42,height:50).clipped().clipShape(RoundedRectangle(cornerRadius:9))
                    } else { Image(systemName:"photo").frame(width:44,height:50) }
                }.accessibilityLabel("查看当前结果").frame(maxWidth:.infinity)
                if model.state == .ready {
                    Button { focus = nil; model.shoot() } label: {
                        Circle().fill(.white).frame(width:60,height:60).padding(5).overlay(Circle().stroke(.white.opacity(0.9),lineWidth:3))
                    }.accessibilityLabel("拍摄并分析").accessibilityIdentifier("shoot")
                } else {
                    Button { model.prepareCamera() } label: {
                        if model.state.busy { ProgressView().tint(.white).padding(12) }
                        else { Text(model.state == .failed ? "重试" : "准备相机").font(.subheadline).padding(12) }
                    }.buttonStyle(.glassProminent).disabled(model.state.busy).accessibilityIdentifier("prepare")
                }
                Button { showConditions = true } label: { Image(systemName:"slider.horizontal.3").frame(width:42,height:42) }
                    .buttonStyle(.glass).accessibilityLabel("拍摄条件").frame(maxWidth:.infinity)
            }
            Text(model.state == .ready ? "拍摄并分析" : model.state.title).font(.caption).accessibilityIdentifier("capture-state")
            Text(model.state == .ready && !model.isSimulator ? "轻点画面选择测光关注区域" : model.message)
                .font(.caption2).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.8)).accessibilityIdentifier("capture-message")
        }.padding(.horizontal,18)
    }
}

struct SceneSelector: View {
    @Binding var intent: SceneIntent
    var label = "场景"
    private var selection: Binding<NewsScene> {
        Binding(get:{ intent.scene },set:{ intent.scene = $0; intent.motion = $0.defaultMotion })
    }
    var body: some View {
        Picker(label,selection:selection) {
            Text("会议课堂").tag(NewsScene.classroom)
            Text("颁奖抓拍").tag(NewsScene.award)
            Text("多排合影").tag(NewsScene.group)
        }
    }
}

struct ConditionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SceneIntent
    let save: (SceneIntent) -> Void
    init(intent: SceneIntent,save: @escaping (SceneIntent) -> Void) { _draft = State(initialValue:intent); self.save = save }
    var body: some View {
        ScrollView {
            VStack(spacing:16) {
                ConditionsEditor(intent:$draft)
                Button("保存条件") { save(draft); dismiss() }.buttonStyle(.glassProminent).controlSize(.large).accessibilityIdentifier("save-conditions")
            }.padding(16)
        }.background(GlassBackdrop()).navigationTitle("拍摄条件").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() } } }
    }
}

struct ConditionsEditor: View {
    @Binding var intent: SceneIntent
    var body: some View {
        GlassPanel("现场") {
            SceneSelector(intent:$intent)
            Picker("人物运动",selection:$intent.motion) { ForEach(Motion.allCases) { Text($0.title).tag($0) } }
            Toggle("手持拍摄",isOn:$intent.handheld)
            Toggle("使用闪光灯",isOn:$intent.flash)
            if intent.flash { Text("本推荐只计算持续光，不包含闪光曝光。").font(.caption).foregroundStyle(.secondary) }
        }
        GlassPanel("单反镜头的当前焦距") {
            focalControls(.nikon)
            Divider()
            focalControls(.canon)
            Picker("佳能最大光圈",selection:$intent.canonOpenAperture) {
                Text("自动／保守 f/5.6").tag(Optional<Double>.none)
                ForEach([4.0,4.5,5,5.6],id:\.self) { Text("f/\($0,specifier:"%.1f")").tag(Optional($0)) }
            }
            Text("18mm 为 f/4，55mm 为 f/5.6。中间焦段可填写相机显示的最大光圈；留空时保守使用 f/5.6。").font(.caption).foregroundStyle(.secondary)
        }
        if intent.scene == .group {
            GlassPanel("合影景深") {
                Stepper("\(intent.rows) 排",value:$intent.rows,in:1...10)
                HStack { Text("最近人物 m"); TextField("可选",value:$intent.nearestMeters,format:.number).keyboardType(.decimalPad) }
                HStack { Text("最远人物 m"); TextField("可选",value:$intent.farthestMeters,format:.number).keyboardType(.decimalPad) }
                Text("距离从相机量到人物，两项同时填写。留空采用保守预设，仍需试拍检查前后排。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func focalControls(_ camera: LensCamera) -> some View {
        let values = camera == .nikon ? [24,35,50,70] : [18,24,35,55]
        return VStack(alignment:.leading,spacing:10) {
            Text(camera.title).font(.subheadline.weight(.medium))
            ViewThatFits(in:.horizontal) {
                HStack { ForEach(values,id:\.self) { value in focalButton(value,camera) } }
                VStack(alignment:.leading) { ForEach(values,id:\.self) { value in focalButton(value,camera) } }
            }
            HStack {
                Text("自定义 mm").font(.caption)
                if camera == .nikon { TextField("24–70",value:$intent.nikonFocal,format:.number).keyboardType(.decimalPad) }
                else { TextField("18–55",value:$intent.canonFocal,format:.number).keyboardType(.decimalPad) }
            }
        }
    }
    private func focalButton(_ value: Int,_ camera: LensCamera) -> some View {
        Button { if camera == .nikon { intent.nikonFocal = Double(value) } else { intent.canonFocal = Double(value) } } label: {
            Text("\(value)mm").font(.caption).padding(.vertical,5).fontWeight(intent.focal(for:camera) == Double(value) ? .semibold : .regular)
        }.buttonStyle(.glass).accessibilityAddTraits(intent.focal(for:camera) == Double(value) ? .isSelected : [])
    }
}
