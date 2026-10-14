import SwiftUI
@preconcurrency import AVFoundation
import CampusLensCore

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onFocus: ((CGPoint,UnitRect) -> Void)?
    override init(frame: CGRect) {
        super.init(frame:frame)
        addGestureRecognizer(UITapGestureRecognizer(target:self,action:#selector(tapped(_:))))
        isAccessibilityElement = true
        accessibilityTraits = .image
        accessibilityLabel = "后置主摄取景。轻点画面选择测光主体"
        accessibilityHint = "可使用辅助操作选择测光区域；拍摄后在主体列表中确认"
        accessibilityCustomActions = ["左上测光","右上测光","中央测光","左下测光","右下测光"].map {
            UIAccessibilityCustomAction(name:$0,target:self,selector:#selector(accessibilityFocus(_:)))
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override func layoutSubviews() {
        super.layoutSubviews()
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
    }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        setFocus(gesture.location(in:self))
    }
    @objc private func accessibilityFocus(_ action: UIAccessibilityCustomAction) -> Bool {
        let points: [String:CGPoint] = ["左上测光":CGPoint(x:0.25,y:0.25),"右上测光":CGPoint(x:0.75,y:0.25),
                                        "中央测光":CGPoint(x:0.5,y:0.5),"左下测光":CGPoint(x:0.25,y:0.75),"右下测光":CGPoint(x:0.75,y:0.75)]
        guard let p = points[action.name] else { return false }
        setFocus(CGPoint(x:p.x*bounds.width,y:p.y*bounds.height)); return true
    }
    private func setFocus(_ p: CGPoint) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let x = min(0.9,max(0.1,p.x/bounds.width)), y = min(0.9,max(0.1,p.y/bounds.height))
        onFocus?(previewLayer.captureDevicePointConverted(fromLayerPoint:p),UnitRect(x:x-0.1,y:y-0.1,width:0.2,height:0.2))
    }
}
struct CameraPreview: UIViewRepresentable {
    let service: CaptureService
    var focused: (UnitRect) -> Void
    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.videoGravity = .resizeAspect
        view.previewLayer.session = service.session
        return view
    }
    func updateUIView(_ view: PreviewUIView,context: Context) {
        view.onFocus = { point,region in service.focus(at:point,region:region); focused(region) }
    }
}
