import SwiftUI
import SwiftData
import CampusLensCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @State private var clearHistory = false
    @State private var clearCalibration = false
    var body: some View {
        ScrollView {
          VStack(spacing:16) {
            GlassPanel("固定设备") {
                ForEach(LensCamera.allCases) { camera in
                    VStack(alignment:.leading) { Text(camera.title); Text(camera.lens).font(.caption).foregroundStyle(.secondary) }
                }
                Text("iPhone 16 Pro 后置物理主摄 · 1× · 传统 Bayer RAW\n最低 iOS 26；iOS 27 支持状态见项目验证记录。")
            }
            GlassPanel("设备校准") {
                NavigationLink("开始三次灰卡校准") { CalibrationView() }
                ForEach(model.calibrations) { c in
                    VStack(alignment:.leading) {
                        Text("\(c.camera.title) · \(Int(c.focalMM))mm · v\(c.version)")
                        Text("修正 \(c.deltaEV,specifier:"%+.2f") EV · 标准差 \(c.standardDeviation,specifier:"%.2f") EV").font(.caption)
                        Text(c.createdAt.formatted()).font(.caption)
                    }
                }
                Button("清除全部校准",role:.destructive) { clearCalibration = true }
            }
            GlassPanel("可选联网视觉 AI") {
                NavigationLink("配置接口、模型和密钥") { AISettingsView() }
                Text(model.aiEnabled ? "已开启：先给出离线结果，补充建议需手动采纳。" : "默认关闭，测光和求解可完全离线使用。")
                Text("开启后仅向你设置的接口发送去除元数据的 1280 像素 JPEG 预览。校内人物照片的发送请遵循学校要求。API Key 仅保存在本机 Keychain。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            GlassPanel("记录管理") {
                Button("清除当前结果与临时 RAW",role:.destructive) {
                    do { try model.clearCurrent() } catch { model.error = error.localizedDescription }
                }
                Button("清除所有历史",role:.destructive) { clearHistory = true }
                Text("本机保留最近 100 条历史预览和参数。临时 RAW 只保留当前结果期间，新拍摄、清除或下次启动时删除；手动导出副本由你管理。")
                    .font(.caption)
            }
            GlassPanel("验收提醒") {
                Text("所有推荐均为起始参数。云端编译和模拟器测试不能证明真机 RAW、实际曝光或人物清晰度通过。请按 README 的实测表验证三种学校新闻场景。")
            }
          }.padding(16)
        }.background(GlassBackdrop(jpeg:model.sample?.previewJPEG)).navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("清除全部历史？",isPresented:$clearHistory,titleVisibility:.visible) {
                Button("清除历史",role:.destructive) {
                    do { try context.delete(model:HistoryRecord.self); try context.save() } catch { model.error = error.localizedDescription }
                }
            }
            .confirmationDialog("清除全部设备校准？",isPresented:$clearCalibration,titleVisibility:.visible) {
                Button("清除校准",role:.destructive) { do { try model.removeCalibrations() } catch { model.error = error.localizedDescription } }
            }
    }
}
struct AISettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var enabled = false
    @State private var endpoint = ""
    @State private var name = ""
    @State private var key = ""
    @State private var saved = false
    var body: some View {
        ScrollView {
          GlassPanel("可选联网辅助") {
            Toggle("启用联网辅助",isOn:$enabled)
            TextField("完整 HTTPS /chat/completions 地址",text:$endpoint).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            TextField("模型名称",text:$name).textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("API Key（Keychain）",text:$key).textInputAutocapitalization(.never).autocorrectionDisabled()
            Text("请填写完整接口地址，App 不自动拼接路径。不接受 HTTP 或重定向。只有场景、主要主体和说明会被校验采纳；曝光数字始终由本机计算。")
                .font(.caption).foregroundStyle(.secondary)
            Button("保存配置") {
                do { try model.saveAI(enabled:enabled,endpoint:endpoint,model:name,key:key); saved = true }
                catch { model.error = error.localizedDescription }
            }.buttonStyle(.glassProminent)
            if saved { Text("配置已保存").foregroundStyle(.teal) }
          }.padding(16)
        }.background(GlassBackdrop(jpeg:model.sample?.previewJPEG)).navigationTitle("联网 AI").navigationBarTitleDisplayMode(.inline)
            .onAppear {
                enabled = model.aiEnabled; endpoint = model.endpoint; name = model.modelName
                do { key = try KeychainStore.read() } catch { model.error = error.localizedDescription }
            }
            .onDisappear { key = "" }
    }
}
struct CalibrationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @State private var aperture = 5.6
    @State private var denominator = 125.0
    @State private var iso = 800.0
    @State private var complete = false
    var body: some View {
        @Bindable var model = model
        ScrollView {
          VStack(spacing:16) {
            GlassPanel("1 · 准备同一灰卡区域") {
                Picker("校准相机",selection:$model.calibrationCamera) { ForEach(LensCamera.allCases) { Text($0.title).tag($0) } }
                    .onChange(of:model.calibrationCamera) { _,_ in model.calibrationMeasurements = []; complete = false }
                Text("在稳定持续光下，使同一灰卡区域填满手机测光重要区域和相机取景。关闭闪光、自动 ISO；相机 M 档。手机与相机保持同一光线和灰卡角度，不能遮挡光线。")
                Text("当前校准焦距：\(model.intent.focal(for:model.calibrationCamera),specifier:"%.0f")mm。三轮保持同一焦距；每轮回到拍摄页拍摄新 RAW。")
                Button("去拍摄新的灰卡 RAW") { model.selectedTab = 0 }
            }
            GlassPanel("2 · 输入你认可的相机曝光") {
                Text("根据灰卡／直方图／样片调整相机，输入认可的参数。不能直接复制 App 推荐作为校准参考。")
                HStack { Text("光圈 f/"); TextField("5.6",value:$aperture,format:.number).keyboardType(.decimalPad) }
                HStack { Text("快门 1/"); TextField("125",value:$denominator,format:.number).keyboardType(.decimalPad) }
                Picker("ISO",selection:$iso) {
                    ForEach(CameraProfile.standard(model.calibrationCamera).isos,id:\.self) { Text(String(Int($0))).tag($0) }
                }
                if let sample = model.sample {
                    Text("手机本次 ID：\(sample.id.uuidString.prefix(8))；\(sample.timestamp.formatted())").font(.caption)
                    if sample.isTestData { Text("测试数据不能校准").foregroundStyle(.orange) }
                }
                Button("记录第 \(min(3,model.calibrationMeasurements.count+1)) 次") {
                    do {
                        guard denominator.isFinite,denominator > 0 else { throw SolverError.invalid("快门分母无效") }
                        try model.addCalibration(aperture:aperture,seconds:1/denominator,iso:iso)
                    } catch { model.error = error.localizedDescription }
                }.disabled(model.calibrationMeasurements.count >= 3)
                Text("已记录 \(model.calibrationMeasurements.count)/3 次独立拍摄")
            }
            GlassPanel("3 · 保存与验证") {
                Button("保存校准版本") { do { try model.finishCalibration(); model.recompute(context:context); complete = true } catch { model.error = error.localizedDescription } }
                    .disabled(model.calibrationMeasurements.count != 3)
                if complete { Text("校准已保存。请在不同光线中验证，校准不等同于验收通过。").foregroundStyle(.teal) }
                Button("重置本轮记录") { model.calibrationMeasurements = []; complete = false }
                Text("修正量为手机 EV 减认可的相机 EV。每个机身、镜头、焦距单独存版本；焦距不匹配时修正为零并标为未校准。")
                    .font(.caption)
            }
          }.padding(16)
        }.background(GlassBackdrop(jpeg:model.sample?.previewJPEG)).navigationTitle("灰卡校准").navigationBarTitleDisplayMode(.inline)
    }
}
