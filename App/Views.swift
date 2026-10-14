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
        }.tint(.blue)
        .alert("提示",isPresented:Binding(get:{ model.error != nil },set:{ if !$0 { model.error = nil } })) {
            Button("知道了") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .onChange(of:phase) { _,new in if new == .background { model.backgrounded() } }
    }
}

struct ResultView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @State private var adjusting: LensCamera?
    @State private var showConditions = false
    @State private var showSubjects = false
    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing:16) {
                if let sample = model.sample {
                    if model.confirmed { resultHeader(sample) }
                    else {
                        GlassPanel("确认测光关注区域") {
                            SubjectImage(sample:sample,selectedID:model.intent.subjectID,showRegions:true) { model.changeSubject($0) }
                            Picker("主要主体",selection:Binding(get:{ model.intent.subjectID },set:{ model.changeSubject($0) })) {
                                ForEach(sample.subjects) { Text($0.label).tag($0.id) }
                            }
                            Text("框表示测光关注区域，不代表单反已经合焦。确认后隐藏；换主体时需重拍。").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if sample.isTestData { GlassPanel { Label("模拟器测试数据，不能用于现场曝光",systemImage:"exclamationmark.triangle").font(.subheadline) } }
                    if model.needsReshoot {
                        GlassPanel("主体已变化，需要重拍") {
                            Text("当前参数已失效。返回拍摄页，点选新主体后重新拍摄 RAW。")
                            Button("返回拍摄") { model.selectedTab = 0 }.buttonStyle(.glassProminent)
                        }
                    } else if !model.confirmed {
                        ConditionsEditor(intent:$model.intent)
                        Button("确认并计算两台相机参数") { model.confirm(context:context) }
                            .buttonStyle(.glassProminent).controlSize(.large).accessibilityIdentifier("confirm")
                    } else { solvedResults }
                    diagnostics(sample)
                } else { ContentUnavailableView("还没有当前测光",systemImage:"camera",description:Text("先拍摄 RAW，再确认现场条件。")) }
            }.padding(16)
        }.background(GlassBackdrop(jpeg:model.sample?.previewJPEG))
        .navigationTitle("本次参数").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement:.topBarTrailing) {
                Menu {
                    if let rawURL = model.rawURL { ShareLink(item:rawURL) { Label("导出 RAW",systemImage:"square.and.arrow.up") } }
                    Button("保存预览") { Task { await model.savePreviewToPhotos() } }
                    Button("清除当前",role:.destructive) { do { try model.clearCurrent() } catch { model.error = error.localizedDescription } }
                } label: { Image(systemName:"ellipsis") }.accessibilityLabel("结果操作")
            }
        }
        .sheet(item:$adjusting) { camera in
            NavigationStack { AdjustmentSheet(camera:camera) }.presentationBackground(.clear).presentationDragIndicator(.visible)
        }
        .sheet(isPresented:$showConditions) {
            NavigationStack { ConditionsSheet(intent:model.intent) { model.intent = $0; model.recompute(context:context) } }
                .presentationBackground(.clear).presentationDragIndicator(.visible)
        }
        .sheet(isPresented:$showSubjects) { subjectSelection }
    }
    @ViewBuilder private var solvedResults: some View {
        if model.solvedIntent != model.intent {
            GlassPanel("条件已修改") {
                Text("当前卡片仍是上次结果。取景与光线不变时可重新计算，其他变化请重拍。").font(.subheadline)
                Button("按当前条件重新计算") { model.recompute(context:context) }.buttonStyle(.glass)
            }
        }
        ForEach(model.recommendations) { recommendation in
            RecommendationCard(recommendation:recommendation) { adjusting = recommendation.camera }
        }
        if model.isSolving { ProgressView("正在计算参数") }
        GlassPanel {
            Button("修改焦距与拍摄条件",systemImage:"slider.horizontal.3") { showConditions = true }.buttonStyle(.glass)
            Button("重新选择测光主体",systemImage:"person.crop.rectangle") { showSubjects = true }.buttonStyle(.glass)
            Text("取景、主体或灯光变化时需要重拍。失焦请检查单反对焦，灯光条纹需试拍排查。").font(.caption).foregroundStyle(.secondary)
        }
        aiSection
    }
    private var subjectSelection: some View {
        NavigationStack {
            ScrollView {
                if let sample = model.sample {
                    GlassPanel("测光关注区域") {
                        SubjectImage(sample:sample,selectedID:model.intent.subjectID,showRegions:true) { model.changeSubject($0); showSubjects = false }
                        Text("更换主体后需要重新拍摄，旧参数不会继续使用。").font(.caption)
                    }.padding()
                }
            }.background(GlassBackdrop(jpeg:model.sample?.previewJPEG)).navigationTitle("选择主体")
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("取消") { showSubjects = false } } }
        }.presentationBackground(.clear)
    }
    private func resultHeader(_ sample: CaptureSample) -> some View {
        GlassPanel {
            HStack(alignment:.top,spacing:14) {
                SubjectImage(sample:sample,selectedID:model.intent.subjectID).frame(width:70)
                VStack(alignment:.leading,spacing:5) {
                    Text(model.intent.scene.title).font(.headline)
                    Text(sample.timestamp.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)
                    Text("主体："+(sample.subjects.first { $0.id == model.intent.subjectID }?.label ?? "关注区域")).font(.caption)
                }
            }
        }
    }
    private var aiSection: some View {
        GlassPanel {
            if !model.aiStatus.isEmpty { Text(model.aiStatus).font(.subheadline).accessibilityIdentifier("ai-status") }
            if let suggestion = model.suggestion {
                DisclosureGroup("有补充建议") {
                    Text("建议场景：\(suggestion.scene.title)")
                    Text(suggestion.explanation)
                    Button("采纳补充建议") { model.applyAI(context:context) }.buttonStyle(.glass)
                }
            }
            if let text = model.aiExplanation { DisclosureGroup("已采纳的联网说明") { Text(text) } }
            if model.aiEnabled { Button(model.aiBusy ? "请求中" : "重试联网建议") { model.requestAI() }.disabled(model.aiBusy).buttonStyle(.glass) }
            else { Text("离线计算 · 联网辅助未开启").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func diagnostics(_ sample: CaptureSample) -> some View {
        GlassPanel {
            DisclosureGroup("测量详情") {
                VStack(alignment:.leading,spacing:8) {
                    Text("拍摄 ID：\(sample.id.uuidString)")
                    Text("RAW 格式：\(sample.rawFormat)；旋转：\(sample.orientation)")
                    Text("同次 EXIF：f/\(sample.exposure.aperture,specifier:"%.2f") · \(sample.exposure.shutterLabel) · ISO \(sample.exposure.iso,specifier:"%.0f")")
                    ForEach(sample.diagnostics,id:\.self) { Text($0) }
                    if let stats = sample.subjects.first(where:{ $0.id == model.intent.subjectID })?.highlights {
                        Text("重要区域采样 \(stats.sampledPixels) 像素；饱和 \(stats.clippedFraction*100,specifier:"%.2f")%")
                    }
                }.font(.caption).padding(.top,8)
            }
        }
    }
}

struct SubjectImage: View {
    let sample: CaptureSample
    let selectedID: Int
    var showRegions = false
    var select: ((Int) -> Void)? = nil
    var body: some View {
        if let image = UIImage(data:sample.previewJPEG) {
            Image(uiImage:image).resizable().aspectRatio(contentMode:.fit)
                .overlay {
                    if showRegions {
                        GeometryReader { geometry in
                            ForEach(sample.subjects) { subject in
                                Button { select?(subject.id) } label: {
                                    RoundedRectangle(cornerRadius:3).stroke(subject.id == selectedID ? Color.yellow : Color.white.opacity(0.75),lineWidth:subject.id == selectedID ? 2 : 1)
                                }
                                .frame(width:geometry.size.width*subject.rect.width,height:geometry.size.height*subject.rect.height)
                                .position(x:geometry.size.width*(subject.rect.x+subject.rect.width/2),y:geometry.size.height*(subject.rect.y+subject.rect.height/2))
                                .accessibilityLabel("选择\(subject.label)").disabled(select == nil)
                            }
                        }.accessibilityIdentifier("subject-regions")
                    }
                }.clipShape(RoundedRectangle(cornerRadius:12))
        }
    }
}

struct RecommendationCard: View {
    let recommendation: Recommendation
    var adjust: (() -> Void)? = nil
    var body: some View {
        GlassPanel {
            Text(recommendation.camera.title).font(.headline)
            Text(recommendation.status).font(.caption).foregroundStyle(.secondary)
            if let exposure = recommendation.exposure {
                ExposureNumbers(exposure:exposure).accessibilityIdentifier("parameters-\(recommendation.camera.rawValue)")
                if !recommendation.isFeasible { Text("可设置的参考组合 · 仍需调整现场条件").font(.subheadline).foregroundStyle(.orange) }
                if exposure.iso >= 6400 {
                    Text("ISO 较高：当前光线下，为保留 \(exposure.shutterLabel) 秒和 f/\(exposure.aperture,specifier:"%.1f")，需要 ISO \(Int(exposure.iso))。")
                        .font(.caption).accessibilityIdentifier("high-iso-\(recommendation.camera.rawValue)")
                }
            } else { Text("当前条件下没有可用组合").font(.headline).foregroundStyle(.orange) }
            if !recommendation.conflicts.isEmpty {
                Text("需要调整拍摄条件").font(.subheadline.weight(.semibold))
                ForEach(recommendation.conflicts,id:\.self) { Text($0).font(.caption) }
                ForEach(recommendation.alternatives,id:\.self) { Text($0).font(.caption) }
            }
            if let adjust {
                Button { adjust() } label: { HStack { Text("试拍调整"); Spacer(); Image(systemName:"chevron.right").font(.caption) } }
                    .buttonStyle(.glass).accessibilityIdentifier("adjust-\(recommendation.camera.rawValue)")
            }
            DisclosureGroup("为什么这样设置") {
                VStack(alignment:.leading,spacing:8) {
                    Text("人物运动／手持需要不慢于 \(Exposure(aperture:1,seconds:recommendation.maxSeconds,iso:100).shutterLabel) 秒；景深要求至少 f/\(recommendation.minAperture,specifier:"%.1f")。")
                    if let focus = recommendation.focusMeters { Text("建议景深对焦距离约 \(focus,specifier:"%.2f")m，请试拍确认。") }
                    if let error = recommendation.errorEV { Text("档位误差 \(error,specifier:"%+.2f") 档，正值偏暗。") }
                    Text("曝光补偿 \(recommendation.compensationEV,specifier:"%+.2f") 档，正值更亮。")
                    ForEach(recommendation.warnings,id:\.self) { Text($0) }
                    Text("快门加快一档或光圈收小一档，匹配同样曝光通常需要 ISO 翻倍。请根据试拍和噪点接受程度明确修改条件。")
                }.font(.caption).padding(.top,8)
            }
        }
    }
}

struct HistoryView: View {
    @Query(sort:\HistoryRecord.timestamp,order:.reverse) private var records: [HistoryRecord]
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            if records.isEmpty { ContentUnavailableView("暂无历史",systemImage:"clock",description:Text("确认后保存最近 100 条参数和预览，不保留 RAW。")) }
            ForEach(records) { record in
                NavigationLink { HistoryDetail(record:record) } label: {
                    GlassPanel {
                        HStack(alignment:.top,spacing:12) {
                            if let image = UIImage(data:record.thumbnail) { Image(uiImage:image).resizable().scaledToFill().frame(width:56,height:74).clipped().clipShape(RoundedRectangle(cornerRadius:9)) }
                            VStack(alignment:.leading,spacing:4) {
                                Text(record.timestamp.formatted(date:.abbreviated,time:.shortened)).font(.subheadline)
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
                }.listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top:6,leading:16,bottom:6,trailing:16))
            }.onDelete { indices in
                for index in indices { context.delete(records[index]) }
                do { try context.save() } catch { model.error = error.localizedDescription }
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).background(GlassBackdrop(jpeg:records.first?.thumbnail))
            .navigationTitle("历史").navigationBarTitleDisplayMode(.inline)
    }
}

struct HistoryDetail: View {
    let record: HistoryRecord
    var body: some View {
        ScrollView {
            if let result = try? record.decoded() {
                VStack(spacing:16) {
                    GlassPanel {
                        Label("历史参数，不能代表当前光线",systemImage:"clock").font(.subheadline)
                        SubjectImage(sample:result.sample,selectedID:result.intent.subjectID)
                        Text(result.sample.timestamp.formatted()).font(.caption)
                        Text("\(result.intent.scene.title) · \(result.intent.motion.title) · \(result.intent.handheld ? "手持" : "有支撑")").font(.subheadline)
                        Text("D850 \(result.intent.nikonFocal,specifier:"%.0f")mm · 200D \(result.intent.canonFocal,specifier:"%.0f")mm").font(.caption)
                    }
                    ForEach(result.recommendations) { RecommendationCard(recommendation:$0) }
                    if let text = result.aiExplanation { GlassPanel { Text(text) } }
                }.padding(16)
            } else { ContentUnavailableView("历史数据无法读取",systemImage:"exclamationmark.triangle") }
        }.background(GlassBackdrop(jpeg:record.thumbnail)).navigationTitle("历史记录").navigationBarTitleDisplayMode(.inline)
    }
}
