import SwiftUI
import SwiftData
import CampusLensCore

struct AdjustmentSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let camera: LensCamera
    @State private var preview: AdjustmentPreview?
    @State private var preparing = false
    private var adjustment: CameraAdjustment { model.adjustments[camera.rawValue] ?? CameraAdjustment() }
    private var enabled: Bool { !preparing && !model.isSolving && !model.needsReshoot && model.solvedIntent == model.intent }
    var body: some View {
        ScrollView {
            VStack(spacing:16) {
                GlassPanel {
                    HStack {
                        Text(camera.title).font(.headline)
                        Spacer()
                        Text("已调整 \(model.adjustmentCount(camera)) 次").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("adjustment-count")
                    }
                    if let result = model.recommendations.first(where:{ $0.camera == camera }),let exposure = result.exposure {
                        ExposureNumbers(exposure:exposure).accessibilityIdentifier("adjusted-parameters")
                    }
                    if let change = model.adjustmentChanges[camera.rawValue] {
                        Text(change.title).font(.caption.weight(.medium))
                        if let before = change.before,let after = change.after {
                            Text("快门 \(before.shutterLabel) → \(after.shutterLabel) · 光圈 f/\(before.aperture,specifier:"%.1f") → f/\(after.aperture,specifier:"%.1f")\nISO \(Int(before.iso)) → \(Int(after.iso))")
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                GlassPanel {
                    ViewThatFits(in:.horizontal) { HStack { feedbackButtons }; VStack { feedbackButtons } }
                    Text("选择问题后先预览，再确认应用。失焦请检查单反对焦；手机测光不能确认单反合焦。").font(.caption).foregroundStyle(.secondary)
                }
                GlassPanel("曝光补偿") {
                    HStack {
                        Button("− 1/3") { propose(.compensation(adjustment.compensation-1/3)) }.disabled(!enabled || adjustment.compensation <= -5)
                        Spacer()
                        Text(adjustment.compensation,format:.number.precision(.fractionLength(2))).monospacedDigit()
                        Spacer()
                        Button("+ 1/3") { propose(.compensation(adjustment.compensation+1/3)) }.disabled(!enabled || adjustment.compensation >= 5)
                    }.buttonStyle(.glass)
                    Text("正值使推荐曝光更亮。撤销会同时恢复光圈、快门要求和补偿。").font(.caption).foregroundStyle(.secondary)
                }
                GlassPanel {
                    ViewThatFits(in:.horizontal) { HStack { rollbackButtons }; VStack(alignment:.leading) { rollbackButtons } }
                    Text("仅调整 \(camera.title)，另一台相机保持独立。恢复初始会清除本次该机的调整和补偿。").font(.caption).foregroundStyle(.secondary)
                }
                if preparing || model.isSolving { ProgressView("正在计算") }
            }.padding(16)
        }.background(GlassBackdrop(jpeg:model.sample?.previewJPEG))
        .navigationTitle("试拍调整").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement:.confirmationAction) { Button("完成") { dismiss() } } }
        .sheet(item:$preview) { value in
            NavigationStack { AdjustmentPreviewView(preview:value) {
                do { try model.applyAdjustment(value,context:context); preview = nil }
                catch { preview = nil; model.error = error.localizedDescription }
            } }.presentationBackground(.clear).presentationDragIndicator(.visible)
        }
    }
    @ViewBuilder private var feedbackButtons: some View {
        Button("人物模糊") { propose(.faster) }.buttonStyle(.glass).disabled(!enabled).accessibilityIdentifier("feedback-faster")
        Button("景深不足") { propose(.depth) }.buttonStyle(.glass).disabled(!enabled).accessibilityIdentifier("feedback-depth")
    }
    @ViewBuilder private var rollbackButtons: some View {
        Button("撤销上一步",systemImage:"arrow.uturn.backward") {
            do { try model.undoAdjustment(camera,context:context) } catch { model.error = error.localizedDescription }
        }.buttonStyle(.glass).disabled(!enabled || !model.canUndo(camera)).accessibilityIdentifier("undo-adjustment")
        Button("恢复初始",systemImage:"arrow.counterclockwise") { propose(.restore) }
            .buttonStyle(.glass).disabled(!enabled || adjustment.isInitial).accessibilityIdentifier("restore-adjustment")
    }
    private func propose(_ action: AdjustmentAction) {
        guard enabled else { return }
        preparing = true
        Task {
            defer { preparing = false }
            do { preview = try await model.previewAdjustment(camera,action:action) }
            catch { model.error = error.localizedDescription }
        }
    }
}

struct AdjustmentPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let preview: AdjustmentPreview
    let apply: () -> Void
    var body: some View {
        ScrollView {
            VStack(spacing:16) {
                GlassPanel("\(preview.camera.title) · \(preview.action.title)") {
                    Text("应用前").font(.subheadline)
                    if let before = preview.before.exposure { ExposureNumbers(exposure:before) }
                    Divider()
                    Text("应用后").font(.subheadline)
                    if let after = preview.after.exposure { ExposureNumbers(exposure:after) }
                    else { Text("调整后没有可设置的组合").foregroundStyle(.orange) }
                    if let before = preview.before.exposure,let after = preview.after.exposure,after.iso > before.iso {
                        Text("为保持曝光，ISO 将从 \(Int(before.iso)) 增至 \(Int(after.iso))，噪点可能增加。").font(.subheadline)
                    }
                    if !preview.after.isFeasible {
                        Text(preview.action == .restore ? "恢复初始后仍需调整现场条件，下面是具体原因。" : "这次调整无法同时满足曝光与清晰要求，请取消并修改现场条件。")
                            .font(.subheadline).foregroundStyle(.orange)
                        ForEach(preview.after.conflicts,id:\.self) { Text($0).font(.caption) }
                        ForEach(preview.after.alternatives,id:\.self) { Text($0).font(.caption) }
                    }
                }
                Button("应用这次调整",action:apply).buttonStyle(.glassProminent).controlSize(.large)
                    .disabled(!preview.after.isFeasible && preview.action != .restore).accessibilityIdentifier("apply-adjustment")
                Button("取消") { dismiss() }.buttonStyle(.glass)
            }.padding(16)
        }.background(GlassBackdrop()).navigationTitle("预览参数变化").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() } } }
    }
}
