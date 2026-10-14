# 验证记录

最后更新：2026-10-14（Asia/Shanghai）。**源码实现、自动测试、云构建、手机 RAW 和实际相机效果分开记录。**

| 项目 | 状态 | 证据或下一步 |
|---|---|---|
| 原生工程、共享 Scheme、Swift 模块 | 已生成；未被 Xcode 加载验证 | `scripts/generate_project.py` 在 Windows 运行成功 |
| Swift 源码语法 | 语法解析通过 | `scripts/parse_swift.py`；不是 Swift 编译器，不检查 API／类型／并发 |
| 源码／plist／Scheme／隐私／密钥模式检查 | Windows 通过 | `scripts/check_source.py` |
| IPA 缺失 archive 和模拟器包拒绝测试 | Windows 两项通过 | Python unittest |
| IPA 执行权限与符号链接测试 | 未执行，Windows 跳过 | Linux／macOS CI 执行 |
| 曝光公式、档位、无解、校准、非法输入单元测试 | 已编写，未运行 | `swift test`，等待云端 |
| JPEG 去元数据、旋转、合成 RAW 电平／ROI测试 | 已编写，未运行 | AppTests，等待 iOS 模拟器 |
| 超时、迟到响应、本机历史、生命周期测试 | 已编写，未运行 | AppTests，等待 iOS 模拟器 |
| 权限拒绝、拍摄失败、后台、离线、超时、辅助显示 UI | 已编写，未运行 | UITests，等待 iOS 模拟器 |
| 公开 GitHub 仓库 | 已创建 | https://github.com/ATTTQJ/campus-lens；公开，账号 ATTTQJ |
| Xcode 26.6／iOS 26 主构建 | 源码发布后首次触发 | 检查 Actions，保留提交和 run URL |
| Xcode 27.0／iOS 27 兼容测试 | 源码发布后首次触发，不声明支持 | 同一提交两套系统测试通过后更新 |
| 设备 archive／未签名 IPA | 尚未生成 | 主构建必须全部通过后生成；没有可安装包 |
| iPhone 16 Pro Bayer RAW 及同次 EXIF | 未实测 | 手机侧载后验证 RAW format、ID、EXIF、DNG 和区域朝向 |
| D850／200D 可设置档位 | 官方资料建表，未实物逐项核对 | 相机设置 1/3 曝光步长和手动 ISO |
| 两机三场景曝光／运动／景深／失焦／灯光 | 未实测 | 按 FIELD_TEST.md 逐样本记录 |
| 90% 样本误差 ≤2/3 EV | 待验证目标 | 稳定光线、认可参考曝光、分机身统计 |
| 校准准确度和跨光线稳定性 | 未实测 | 各机、各焦段三次灰卡及异光验证 |
| VoiceOver、真实系统辅助显示、刊发清晰度 | 未人工验收 | 手机和学校实际刊发尺寸验证 |

自动构建通过后请填写：

| 提交 SHA | 主构建 URL／结果 | iOS 27 URL／结果 | IPA SHA256 | 日期 |
|---|---|---|---|---|
| 待填写 | 待运行 | 待运行 | 待生成 | 待填写 |

四阶段交付里程碑：

1. 工程、四页面、权限、云构建：源码齐备，IPA 待云构建。
2. 真实 RAW、元数据、Vision、离线求解：源码齐备，真实拍摄待手机验证。
3. 校准、历史、试拍调整：源码齐备，自动测试和实测待运行。
4. 联网、异常响应、iOS 26/27：源码齐备，模拟器和实际接口待验证。

当前没有声称任何阶段已交付可侧载 IPA。每阶段成功构建并记录对应提交／标签后，才可填写为“IPA 已交付”。
