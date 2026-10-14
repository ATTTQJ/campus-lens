import SwiftUI
import SwiftData
import CampusLensCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase
    var body: some View {
        @Bindable var model = model
        TabView(selection:$model.selectedTab) {
            Tab("拍摄",systemImage:"camera",value:0) { NavigationStack { CaptureView() } }
            Tab("结果",systemImage:"slider.horizontal.3",value:1) { NavigationStack { ResultView() } }
            Tab("历史",systemImage:"clock",value:2) { NavigationStack { HistoryView() } }
            Tab("设置",systemImage:"gearshape",value:3) { NavigationStack { SettingsView() } }
        }
        .tint(.teal)
        .alert("提示",isPresented:Binding(get:{ model.error != nil },set:{ if !$0 { model.error = nil } })) {
            Button("知道了") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .onChange(of:phase) { _,new in if new == .background { model.backgrounded() } }
    }
}
struct CaptureView: View {
    @Environment(AppModel.self) private var model
    @State private var focus: UnitRect?
    @State private var showConditions = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        @Bindable var model = model
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing:0) {
                    ZStack {
                        if model.isSimulator {
                            Color(white:0.12)
                            Text("模拟器测试取景\n不提供 RAW／真实测光").multilineTextAlignment(.center).foregroundStyle(.white)
                        } else {
                            CameraPreview(service:model.captureService) { focus = $0 }
                        }
                        if let focus {
                            Rectangle().stroke(.yellow,lineWidth:2)
                                .frame(width:geometry.size.width*focus.width,height:geometry.size.width*4/3*focus.height)
                                .position(x:geometry.size.width*(focus.x+focus.width/2),y:geometry.size.width*4/3*(focus.y+focus.height/2))
                                .allowsHitTesting(false)
                        }
                    }
                    .aspectRatio(3/4,contentMode:.fit)
                    Spacer(minLength:0)
                }
                VStack {
                    HStack {
                        Text(model.isSimulator ? "测试数据" : "1× · 物理主摄").font(.caption.bold())
                        Spacer()
                        Button("条件",systemImage:"slider.horizontal.3") { showConditions = true }
                            .buttonStyle(.glass)
                    }
                    .padding().background(reduceTransparency ? Color.black : Color.black.opacity(0.7))
                    Spacer()
                    ScrollView {
                      VStack(spacing:12) {
                        SceneSelector(intent:$model.intent,label:"新闻场景").pickerStyle(.segmented)
                        HStack {
                            focalMenu(.nikon)
                            focalMenu(.canon)
                        }
                        Text(model.state.title).font(.headline).accessibilityIdentifier("capture-state")
                        Text(model.message).font(.caption).multilineTextAlignment(.center)
                            .accessibilityIdentifier("capture-message")
                        if model.state == .ready {
                            Button { focus = nil; model.shoot() } label: {
                                Label("拍摄并分析",systemImage:"camera.aperture").frame(maxWidth:.infinity)
                            }.buttonStyle(.glassProminent).controlSize(.large).accessibilityIdentifier("shoot")
                        } else {
                            Button { model.prepareCamera() } label: {
                                Label(model.state == .failed ? "重新准备相机" : "准备相机",systemImage:"camera").frame(maxWidth:.infinity)
                            }.buttonStyle(.glassProminent).controlSize(.large).disabled(model.state.busy).accessibilityIdentifier("prepare")
                        }
                        if model.state.busy { ProgressView().tint(.white) }
                      }.padding()
                    }
                    .frame(maxHeight:geometry.size.height*(typeSize.isAccessibilitySize ? 0.72 : 0.43))
                    .background(reduceTransparency ? Color.black : Color.black.opacity(0.85))
                }.foregroundStyle(.white)
            }
        }
        .navigationTitle("校园取景").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented:$showConditions) { NavigationStack {
            Form { ConditionsEditor(intent:$model.intent) }
                .navigationTitle("拍摄条件").toolbar { ToolbarItem(placement:.confirmationAction) { Button("完成") { showConditions = false } } }
        } }
    }
    @ViewBuilder func focalMenu(_ camera: LensCamera) -> some View {
        let focal = model.intent.focal(for:camera)
        Menu("\(camera.title) · \(focal,specifier:"%.0f")mm") {
            ForEach(camera == .nikon ? [24,35,50,70] : [18,24,35,55],id:\.self) { value in
                Button("\(value)mm") { if camera == .nikon { model.intent.nikonFocal = Double(value) } else { model.intent.canonFocal = Double(value) } }
            }
        }.buttonStyle(.glass).font(.caption)
    }
}
struct SceneSelector: View {
    @Binding var intent: SceneIntent
    var label = "场景"
    private var selection: Binding<NewsScene> {
        Binding<NewsScene>(get:{ intent.scene },set:{ scene in
            intent.scene = scene
            intent.motion = scene.defaultMotion
        })
    }
    var body: some View {
        Picker(label,selection:selection) {
            Text("会议课堂").tag(NewsScene.classroom)
            Text("颁奖抓拍").tag(NewsScene.award)
            Text("多排合影").tag(NewsScene.group)
        }
    }
}
struct ConditionsEditor: View {
    @Binding var intent: SceneIntent
    var body: some View {
        Section("现场确认") {
            SceneSelector(intent:$intent)
            Picker("人物运动",selection:$intent.motion) { ForEach(Motion.allCases) { Text($0.title).tag($0) } }
            Toggle("手持拍摄",isOn:$intent.handheld)
            Toggle("将使用闪光灯（推荐不含闪光曝光）",isOn:$intent.flash)
        }
        Section("镜头当前实际焦距") {
            HStack { Text("尼康 mm"); TextField("24–70",value:$intent.nikonFocal,format:.number).keyboardType(.decimalPad) }
            HStack { Text("佳能 mm"); TextField("18–55",value:$intent.canonFocal,format:.number).keyboardType(.decimalPad) }
            Picker("佳能相机显示的最大光圈",selection:$intent.canonOpenAperture) {
                Text("自动／保守 f/5.6").tag(Optional<Double>.none)
                ForEach([4.0,4.5,5,5.6],id:\.self) { Text("f/\($0, specifier:"%.1f")").tag(Optional($0)) }
            }
            Text("18mm 自动使用 f/4，55mm 为 f/5.6。中间焦段可输入相机显示档位；未输入时保守使用 f/5.6。")
                .font(.caption).foregroundStyle(.secondary)
        }
        if intent.scene == .group {
            Section("合影景深") {
                Stepper("\(intent.rows) 排",value:$intent.rows,in:1...10)
                HStack { Text("最近人物 m"); TextField("可选",value:$intent.nearestMeters,format:.number).keyboardType(.decimalPad) }
                HStack { Text("最远人物 m"); TextField("可选",value:$intent.farthestMeters,format:.number).keyboardType(.decimalPad) }
                Text("两项距离同时填写，均从相机量到人物。留空时使用保守预设，仍需检查前后排清晰度。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
struct ResultView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing:16) {
                if let sample = model.sample {
                    SubjectImage(sample:sample,selectedID:model.intent.subjectID) { model.changeSubject($0) }
                    Text(sample.timestamp.formatted(date:.abbreviated,time:.standard)).font(.caption).foregroundStyle(.secondary)
                    if sample.isTestData { Label("模拟器测试数据，不能用于现场曝光",systemImage:"exclamationmark.triangle").foregroundStyle(.orange) }
                    if model.needsReshoot {
                        Text("主体已变化，点选取景中的新主体后重拍。当前推荐已失效。").foregroundStyle(.orange)
                        Button("返回拍摄") { model.selectedTab = 0 }
                    } else if !model.confirmed {
                        VStack(alignment:.leading,spacing:12) {
                            Text("确认现场条件与主要主体").font(.title3.bold())
                            Picker("主要主体",selection:Binding(get:{ model.intent.subjectID },set:{ model.changeSubject($0) })) {
                                ForEach(sample.subjects) { Text($0.label).tag($0.id) }
                            }
                            Text("在图片中点选检测框，或选择拍摄时点选的重要区域。初次确认后，更换主体必须重拍。")
                                .font(.caption).foregroundStyle(.secondary)
                            ConditionsEditor(intent:$model.intent)
                            Button("确认并计算两台相机参数") { model.confirm(context:context) }
                                .buttonStyle(.glassProminent).accessibilityIdentifier("confirm")
                        }.padding().background(.background,in:RoundedRectangle(cornerRadius:20))
                    } else {
                        if model.solvedIntent != model.intent {
                            Text("拍摄条件已变化，当前卡片仍是上一次计算。取景和光线不变时请重新计算；其他变化请重拍。")
                                .foregroundStyle(.orange)
                            Button("按当前条件重新计算") { model.recompute(context:context) }
                        }
                        ForEach(model.recommendations) { recommendation in
                            RecommendationCard(recommendation:recommendation,adjustment:model.adjustments[recommendation.camera.rawValue] ?? CameraAdjustment()) { compensation,faster,depth,reset in
                                model.adjust(recommendation.camera,compensation:compensation,faster:faster,depth:depth,reset:reset,context:context)
                            }
                        }
                        if model.recommendations.isEmpty { ProgressView("求解中") }
                        DisclosureGroup("焦距／场景变化后重新计算") {
                            ConditionsEditor(intent:$model.intent)
                            Button("取景和光线未变，重新计算") { model.recompute(context:context) }
                            Text("取景、主体或灯光变化时必须重拍。失焦需检查相机对焦；灯光条纹需试拍排查，参数算法不能自动修正。").font(.caption)
                        }.padding()
                        aiSection
                    }
                    HStack {
                        if let rawURL = model.rawURL { ShareLink(item:rawURL) { Label("导出 RAW",systemImage:"square.and.arrow.up") } }
                        Button("保存预览") { Task { await model.savePreviewToPhotos() } }
                    }.buttonStyle(.glass)
                    DisclosureGroup("本次测量诊断") {
                        Text("拍摄 ID：\(sample.id.uuidString)")
                        Text("RAW 格式：\(sample.rawFormat)；旋转：\(sample.orientation)")
                        Text("同次 EXIF：f/\(sample.exposure.aperture, specifier:"%.2f")，\(sample.exposure.shutterLabel)，ISO \(sample.exposure.iso, specifier:"%.0f")")
                        ForEach(sample.diagnostics,id:\.self) { Text($0) }
                        if let subject = sample.subjects.first(where: { $0.id == model.intent.subjectID }), let stats = subject.highlights {
                            Text("重要区域采样 \(stats.sampledPixels) 像素；饱和 \(stats.clippedFraction*100, specifier:"%.2f")%")
                        }
                    }.font(.caption).padding()
                } else {
                    ContentUnavailableView("还没有当前测光",systemImage:"camera",description:Text("先在拍摄页拍摄 RAW，然后确认现场条件。"))
                }
            }.padding()
        }.background(Color(uiColor:.systemGroupedBackground))
        .navigationTitle("本次结果")
        .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("清除当前") { do { try model.clearCurrent() } catch { model.error = error.localizedDescription } } } }
    }
    @ViewBuilder var aiSection: some View {
        VStack(alignment:.leading,spacing:12) {
            if !model.aiStatus.isEmpty { Text(model.aiStatus).font(.headline).accessibilityIdentifier("ai-status") }
            if let suggestion = model.suggestion {
                Text("建议场景：\(suggestion.scene.title)；主体 \(suggestion.subjectID)")
                Text(suggestion.explanation)
                Button("采纳补充建议") { model.applyAI(context:context) }.buttonStyle(.glass)
            }
            if let text = model.aiExplanation { DisclosureGroup("已采纳的联网说明") { Text(text) } }
            if model.aiEnabled { Button(model.aiBusy ? "请求中" : "重试联网建议") { model.requestAI() }.disabled(model.aiBusy) }
        }.padding()
    }
}
struct SubjectImage: View {
    let sample: CaptureSample
    let selectedID: Int
    var select: ((Int) -> Void)? = nil
    var body: some View {
        if let image = UIImage(data:sample.previewJPEG) {
            Image(uiImage:image).resizable().aspectRatio(contentMode:.fit)
                .overlay { GeometryReader { g in
                    ForEach(sample.subjects) { subject in
                        Button { select?(subject.id) } label: {
                            Rectangle().stroke(subject.id == selectedID ? Color.yellow : Color.teal,lineWidth:subject.id == selectedID ? 3 : 1)
                        }
                        .frame(width:g.size.width*subject.rect.width,height:g.size.height*subject.rect.height)
                        .position(x:g.size.width*(subject.rect.x+subject.rect.width/2),y:g.size.height*(subject.rect.y+subject.rect.height/2))
                        .accessibilityLabel("选择\(subject.label)").disabled(select == nil)
                    }
                } }.clipShape(RoundedRectangle(cornerRadius:16))
        }
    }
}
struct RecommendationCard: View {
    let recommendation: Recommendation
    var adjustment = CameraAdjustment()
    var adjust: ((Double?,Bool,Bool,Bool) -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text(recommendation.camera.title).font(.title2.bold())
            Text(recommendation.camera.lens).font(.caption).foregroundStyle(.secondary)
            Text(recommendation.status).font(.subheadline).foregroundStyle(.teal)
            if !recommendation.isFeasible, recommendation.exposure != nil {
                Text("最接近的可设置组合，尚未满足曝光要求").font(.headline).foregroundStyle(.orange)
            }
            if let e = recommendation.exposure {
                ViewThatFits(in:.horizontal) {
                    HStack(alignment:.top,spacing:16) { numbers(e) }
                    VStack(alignment:.leading,spacing:12) { numbers(e) }
                }.accessibilityElement(children:.contain).accessibilityIdentifier("parameters-\(recommendation.camera.rawValue)")
            } else { Text("没有满足约束的可用参数").font(.headline).foregroundStyle(.orange) }
            if !recommendation.conflicts.isEmpty {
                Label("约束冲突 · 请先调整",systemImage:"exclamationmark.triangle").foregroundStyle(.orange).font(.headline)
                ForEach(recommendation.conflicts,id:\.self) { Text($0) }
                ForEach(recommendation.alternatives,id:\.self) { Text("• "+$0) }
            }
            DisclosureGroup("推荐理由与试拍注意事项") {
                VStack(alignment:.leading,spacing:8) {
                    Text("运动／手持快门不慢于 \(Exposure(aperture:1,seconds:recommendation.maxSeconds,iso:100).shutterLabel)；必要景深 f/\(recommendation.minAperture,specifier:"%.1f")")
                    if let focus = recommendation.focusMeters { Text("景深计算对焦距离约 \(focus,specifier:"%.2f")m，试拍确认") }
                    if let error = recommendation.errorEV { Text("档位曝光误差 \(error,specifier:"%+.2f") EV，正值偏暗") }
                    Text("当前补偿 \(recommendation.compensationEV,specifier:"%+.2f") EV（正值使推荐更亮）")
                    ForEach(recommendation.warnings,id:\.self) { Text($0) }
                }.font(.subheadline).padding(.top,8)
            }
            if let adjust {
                HStack {
                    Text("曝光补偿").font(.subheadline)
                    Spacer()
                    Button("− 1/3") { adjust(adjustment.compensation-1.0/3,false,false,false) }
                    Text(adjustment.compensation,format:.number.precision(.fractionLength(2))).monospacedDigit()
                    Button("+ 1/3") { adjust(adjustment.compensation+1.0/3,false,false,false) }
                }
                ViewThatFits(in:.horizontal) {
                    HStack { feedback(adjust) }
                    VStack(alignment:.leading) { feedback(adjust) }
                }.buttonStyle(.glass)
                Button("重置本机试拍调整") { adjust(nil,false,false,true) }.font(.caption)
            }
        }.padding(20).frame(maxWidth:.infinity,alignment:.leading)
            .background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:24))
    }
    @ViewBuilder func numbers(_ e: Exposure) -> some View {
        number("光圈",String(format:"f/%.1f",e.aperture))
        number("快门",e.shutterLabel)
        number("ISO",String(Int(e.iso)))
    }
    func number(_ label: String,_ value: String) -> some View {
        VStack(alignment:.leading,spacing:6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title,design:.rounded,weight:.bold)).monospacedDigit().fixedSize(horizontal:true,vertical:false)
        }.frame(maxWidth:.infinity,alignment:.leading).accessibilityElement(children:.combine)
    }
    @ViewBuilder func feedback(_ action: @escaping (Double?,Bool,Bool,Bool) -> Void) -> some View {
        Button("人物模糊") { action(nil,true,false,false) }
        Button("景深不足") { action(nil,false,true,false) }
    }
}
struct HistoryView: View {
    @Query(sort:\HistoryRecord.timestamp,order:.reverse) private var records: [HistoryRecord]
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            if records.isEmpty { ContentUnavailableView("暂无历史",systemImage:"clock",description:Text("确认后自动保存最近 100 条参数和预览；不保存 RAW。")) }
            ForEach(records) { record in
                NavigationLink { HistoryDetail(record:record) } label: {
                    HStack {
                        if let image = UIImage(data:record.thumbnail) { Image(uiImage:image).resizable().scaledToFill().frame(width:64,height:80).clipped().clipShape(RoundedRectangle(cornerRadius:8)) }
                        VStack(alignment:.leading) {
                            Text(record.timestamp.formatted(date:.abbreviated,time:.shortened))
                            Text("历史记录").font(.caption).foregroundStyle(.secondary)
                            if let result = try? record.decoded() {
                                Text(result.intent.scene.title).font(.subheadline)
                                ForEach(result.recommendations) { r in
                                    if let e = r.exposure { Text("\(r.camera.title)：f/\(e.aperture,specifier:"%.1f") · \(e.shutterLabel) · ISO \(Int(e.iso))").font(.caption).monospacedDigit() }
                                }
                            }
                        }
                    }
                }
            }.onDelete { indices in
                for index in indices { context.delete(records[index]) }
                do { try context.save() } catch { model.error = error.localizedDescription }
            }
        }.navigationTitle("历史 · 最近 100 条")
    }
}
struct HistoryDetail: View {
    let record: HistoryRecord
    var body: some View {
        ScrollView {
            if let result = try? record.decoded() {
                VStack(alignment:.leading,spacing:16) {
                    Label("历史参数，不能代表当前现场光线",systemImage:"clock").foregroundStyle(.orange)
                    SubjectImage(sample:result.sample,selectedID:result.intent.subjectID)
                    Text(result.sample.timestamp.formatted())
                    Text("\(result.intent.scene.title) · \(result.intent.motion.title) · \(result.intent.handheld ? "手持" : "有支撑")")
                    Text("尼康 \(result.intent.nikonFocal,specifier:"%.0f")mm · 佳能 \(result.intent.canonFocal,specifier:"%.0f")mm")
                    ForEach(result.recommendations) { RecommendationCard(recommendation:$0) }
                    if let text = result.aiExplanation { Text(text) }
                }.padding()
            } else { ContentUnavailableView("历史数据无法读取",systemImage:"exclamationmark.triangle") }
        }.background(Color(uiColor:.systemGroupedBackground)).navigationTitle("历史记录")
    }
}
