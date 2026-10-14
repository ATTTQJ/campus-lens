# 校园取景 CampusLens

原生 iPhone 校园新闻摄影助手：在 App 内拍摄 **传统 Bayer RAW**，本机读取同次曝光元数据，为以下两套设备分别计算可手动设置的起始参数：

- 尼康 D850＋24–70mm f/2.8G。
- 佳能 EOS 200D＋EF-S 18–55mm f/4–5.6 IS STM。

目标手机是 iPhone 16 Pro 后置物理主摄，1×取景；最低 iOS 26。首版实现会议课堂、颁奖抓拍、多排合影，离线计算、灰卡校准、试拍调整、100 条本机历史和可选视觉 AI。没有相机遥控、照片自动传输、修图、账号或 TestFlight。拍摄不依赖任何其他摄影软件。

**当前交付状态：首个完整测试版 0.1.0（build 6）已生成未签名设备 IPA。** 同一源码提交 `4039e2d` 已通过 [iOS 26 主构建](https://github.com/ATTTQJ/campus-lens/actions/runs/38569117473)和 [iOS 27 兼容验证](https://github.com/ATTTQJ/campus-lens/actions/runs/38569117504)：两套系统各 22 项单元／图像／网络测试与 4 项 UI 测试通过；纯 Swift 包另有 11 项测试通过。手机 Bayer RAW、灰卡校准、两台相机实际效果和外部视觉服务仍待实测，结果均为“起始参数”。

在 [已验证构建产物](https://github.com/ATTTQJ/campus-lens/actions/runs/38569117473/artifacts/11898460697)下载 ZIP，解压获得 `CampusLens-unsigned.ipa`。产物七天有效；完整状态见 [验证记录](docs/VALIDATION.md)。源码位于 [公开仓库](https://github.com/ATTTQJ/campus-lens)。

## 使用流程

1. 拍摄页点击“准备相机”，首次申请相机权限。只选择后置 `.builtInWideAngleCamera`，固定 1×，明确关闭 ProRAW。配置完成并开始会话后检查 Bayer RAW 格式；不可用时明确失败。
2. 点选取景中的重要主体，等待曝光和对焦稳定，点击“拍摄并分析”。同一次请求捕获 RAW 和 JPEG，按 AVFoundation `uniqueID` 配对。曝光数据来自本次 RAW 的 EXIF，缺失时失败，不使用取景时的实时参数代替。
3. 确认场景、运动、手持状态、两个实际焦距和主要主体。合影可填写最近和最远人物距离。缺少距离时采用保守预设并提醒检查景深。
4. 两张相机卡片显示光圈、快门、ISO。相机使用 M 档、关闭自动 ISO，曝光步长设置为 1/3 档；200D 静态手动 ISO 使用整档。先试拍，检查曝光、人物运动和前后排清晰度。
5. 每台相机独立调整曝光补偿、“人物模糊”或“景深不足”。算法重新枚举档位，不悄悄改变运动约束。无解时标明冲突，显示最接近的组合和显式调整建议。
6. 只有焦距／场景变化且取景、主体、光线没变时，才可复用本次测光。更换主体会使推荐失效并要求重拍；换取景或灯光也必须重拍。

所有结果称为“起始参数”。没有匹配设备校准时显示“起始参数 · 未校准”，设备修正为零。校准按机身、镜头、焦距和算法版本匹配；焦距不匹配时不会静默使用其他焦段的修正。

## 工程与算法

Swift 6、SwiftUI、AVFoundation、Vision、ImageIO、SwiftData、Keychain；原生 `CampusLens.xcodeproj`，共享 `CampusLens` Scheme，无第三方 iOS 依赖。导航和控件使用系统 Liquid Glass；参数卡片使用稳定背景、等宽数字和动态字体。

目录：

| 路径 | 用途 |
|---|---|
| `Sources/CampusLensCore` | 纯 Swift 数据模型、曝光／景深求解、RAW 数学、AI JSON 校验 |
| `App` | 真实拍摄、Vision、RAW 区域分析、界面、存储、联网 |
| `Tests/CampusLensCoreTests` | 曝光公式、档位、无解、非法输入、校准、坐标和 JSON 测试 |
| `AppTests` | 合成图像、JPEG 去元数据、RAW 黑白电平／旋转、历史和生命周期、网络测试 |
| `UITests` | 模拟器正常流程、权限拒绝、拍摄失败、后台、超时、大字体和辅助显示环境 |
| `.github/workflows` | 源码检查、iOS 26 主构建、iOS 27 兼容验证 |
| `scripts` | 确定性工程生成、选择模拟器、无签名 IPA 打包和发布脚本 |

曝光参考值与求解：

```text
Ep = log2(Np² / tp) − log2(Sp / 100)
Ei = Ep − 设备校准修正 − 当次曝光补偿
ISO连续值 = 100 × Ni² / (ti × 2^Ei)
```

设备校准和当次补偿分开保存。正补偿使目标 EV 降低、推荐更亮。枚举真实的光圈、快门和 ISO 档位，先满足运动快门和必要景深；在曝光误差不超过 1/3 档的组合中优先较低 ISO，再比较曝光误差、光圈和快门。超出容差或景深／运动无法满足时报告冲突，不独立截断 ISO。稳定光线下 90% 样本与认可参考曝光相差不超过 2/3 档是**待实测的项目目标**。

佳能 18mm 自动最大光圈 f/4，55mm f/5.6；中间焦距默认 f/5.6，可填写相机显示的实际最大光圈。中间焦距最小光圈保守限制在 f/22，55mm 允许到 f/32。尼康 f/2.8–22。两机均仅使用原生 ISO 范围，不启用扩展 ISO。档位表仍需在两台实物上核对。

合影有距离时用薄透镜景深公式和谐均对焦距离估算；弥散圈默认全画幅 0.03mm、APS-C 0.019mm。此估算不能保证刊发尺寸下的清晰度，还需检查对焦、姿态、镜头像差及纵深。防抖不替代人物运动快门。闪光灯开启时明确提示结果不包含闪光曝光。

RAW 高光检查读取 DNG 的黑电平重复模式和白电平，对实际 Bayer 像素归一化，按朝向转换重要区域坐标；采样包括 Bayer 2×2 的四个位置。归一化值达到 0.98 作为接近饱和，重要区域比例超过 1% 时提醒。它不把肤色拉到统一亮度，也不自动改曝光。若黑白电平、空间变化电平或像素布局不受支持，结果诊断明确标注“高光检查未完成”，曝光求解仍基于 EXIF；必须先在 iPhone 16 Pro 实测确认电平和坐标对应。

## 灰卡校准

设置 → 三次灰卡校准。稳定持续光，同一灰卡区域在手机与相机中受同样光线；手机点选测光，相机 M 档、手动 ISO、关闭闪光。每轮用手机拍摄新的真实 RAW，用户根据灰卡／直方图／认可的样片确定相机曝光，并输入可设置档位。禁止把本 App 推荐直接作为校准参考。

每个焦距三次独立拍摄后计算 `Δ = 手机 EV − 认可相机 EV` 的均值和样本标准差，记录测量、机身、镜头、焦距、时间和版本。焦距变化必须重置本轮；标准差超过 1/3 档提醒重复校准。后续更换光线验证，不把校准完成当作曝光验收通过。模拟器数据不能校准。

## 隐私、保存和联网

默认关闭联网。设置完整 HTTPS Chat Completions URL（包含 `/chat/completions` 路径）、模型和 API Key 后启用。使用 [OpenAI 兼容视觉格式](https://developers.openai.com/api/docs/guides/images-vision)，只发送转换为 sRGB、重新编码、清除 APP／COM 元数据段、最长边 1280px 的 JPEG。用户自行决定照片是否可以发送至所配置服务。

请求／资源超时 15 秒，不接受 HTTP 或重定向；无日志输出密钥、图片或接口响应。密钥仅存在本机 `WhenUnlockedThisDeviceOnly` Keychain。JSON 必须且只能包含允许的 `scene`、本机候选 `subjectID`、不超过 1200 字的 `explanation`，额外曝光字段会被拒绝。AI 不参与曝光数值求解。先显示离线结果，联网返回后显示“有补充建议”；用户采纳才变更场景／说明，建议变更主体时要求重拍。失败保留离线参数，支持主动重试。

历史只保留最近 100 条缩略预览、参数、条件、独立调整、使用的校准版本和说明。RAW 不进入历史，只在当前结果期间保留；新拍摄／清除／下次启动时删除临时文件，手动导出副本由用户管理。图库权限仅在主动点击保存预览时请求。仓库和构建产物不包含实际新闻照片或密钥。

## Windows → GitHub → 未签名 IPA

Windows 不能运行 Xcode。源码在 Windows 编写，iOS 编译、模拟器测试和设备 archive 由 GitHub 托管的 macOS runner 完成。

如通过本机 GitHub CLI 发布：安装官方 [GitHub CLI](https://cli.github.com/)，运行 `gh auth login` 完成浏览器授权；在项目目录运行 `powershell -ExecutionPolicy Bypass -File scripts/publish.ps1`。脚本创建当前登录账号的公开 `campus-lens` 仓库并推送 `main`；发现同名仓库会停止，防止覆盖。若本地已有提交，按普通 Git 流程提交和推送，不能重复使用首次发布脚本。密钥无需输入聊天或源码。

| 工作流 | 环境 | 行为 |
|---|---|---|
| Source integrity | Ubuntu | 工程生成一致性、输入／权限打包测试、源码检查 |
| iOS 26 main build | `macos-26`，显式 Xcode 26.6 | Swift 核心测试、iOS 26 模拟器 App／UI 测试；main、标签和手动运行再 archive 设备包 |
| iOS 27 compatibility | `xcode-27`，显式 Xcode 27.0 | Swift 核心测试、iOS 27 编译和模拟器测试，独立于主构建 |

两套环境都从已安装 runtime 中选择指定系统主版本，并创建 iPhone 16 Pro 模拟器；缺少工具链或指定系统会明确失败，不回退到其他版本。Xcode 26.6 的 iOS runtime 小版本未必是 26.6，工作流记录实际 SDK 和模拟器信息。Xcode 27 runner 目前是公共预览，状态以 [官方 26 镜像](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md) 和 [27 镜像](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md) 为准。

进入仓库 Actions，等待 iOS 26 主任务成功。在本次运行底部下载 `CampusLens-iOS26-编号` 产物 ZIP，解压得到：

- `CampusLens-unsigned.ipa`：设备版，**未签名**。
- `SHA256SUMS.txt`、`version.json`：校验值、提交和实际工具链信息。
- `iOS-tests.xcresult`、核心测试日志、模拟器和 archive 日志。

PR 只测试、不生成设备包。主分支和手动触发生成包；Artifacts 保留七天。推送 `v*` 标签时主构建成功后把 IPA 和版本信息附加到 GitHub Release。正式声明支持 iOS 27 前，必须确认**同一提交**的两套系统测试都通过，并完成对应真机验收。

IPA 打包只接受 `iPhoneOS` archive，检查主可执行文件及 POSIX 执行权限，拒绝意外签名材料；按 `Payload/CampusLens.app` 保留文件权限和符号链接。关闭云端签名，不需 Apple 证书。源码公开且使用标准 GitHub 托管 runner 的运行时间免费，产物存储受账号额度影响，详见 [GitHub 计费说明](https://docs.github.com/en/billing/concepts/product-billing/github-actions)。本项目没有启用付费 larger runner。

模拟器测试使用无需 Apple 证书的本地临时 ad-hoc 签名和独立测试 Keychain 权限，用于验证真实 Keychain 调用。`App/Simulator.entitlements` 仅通过模拟器命令行参数使用，不用于设备 archive；交付的设备 IPA 仍关闭签名。自行签名侧载后，由签名工具提供你的应用标识和默认 Keychain 权限。

## Windows 使用 Sideloadly 安装与续签

1. 从 [Sideloadly 官网](https://sideloadly.io/) 安装 Windows 版本，并按官网准备其要求的 Apple 设备驱动／iTunes、iCloud。不要从不明下载站安装。
2. USB 连接 iPhone 16 Pro，解锁并信任这台电脑。手机需启用开发者模式（系统可能要求重启）。
3. 打开 Sideloadly，选择手机，把 `CampusLens-unsigned.ipa` 拖入 IPA 区域。使用自己的 Apple ID 完成签名安装；Apple ID 和密码不放入源码或聊天。
4. 如系统提示未受信任开发者，在“设置 → 通用 → VPN 与设备管理”中信任对应开发者，然后打开“校园取景”，首次准备拍摄时允许相机权限。
5. 免费 Apple ID 的签名通常七天有效；按 Sideloadly 支持的刷新方式定期续签，或在到期前连接电脑重新安装同一 Bundle ID 的包。安装新版尽量沿用同一 ID 和签名账号；卸载会删除 App 数据。Sideloadly、Apple 账号限制和 iOS 的行为以当前官网与手机提示为准。
6. 首次先确认诊断中的 Bayer RAW 格式、EXIF 和拍摄 ID，再按 [真机验收表](docs/FIELD_TEST.md) 测试两台相机。不要求购买其他 RAW 拍摄软件。

## 本地开发与测试

有 Mac 时：

```bash
swift test
xcodebuild test -project CampusLens.xcodeproj -scheme CampusLens \
  -destination 'platform=iOS Simulator,id=实际模拟器UUID' CODE_SIGNING_ALLOWED=NO
bash scripts/build_ios.sh 26 archive
```

Windows 可运行 Python 结构检查：

```powershell
python scripts/generate_project.py
python -m unittest discover -s scripts/tests -v
python scripts/check_source.py
```

可选语法检查需 `pip install tree-sitter tree-sitter-swift` 后执行 `python scripts/parse_swift.py`，它不检查 Swift 类型、系统 API 或并发隔离，不替代 Xcode。添加 Swift 文件后运行工程生成脚本并提交生成的工程和 Scheme。重新生成图标需要 Pillow，正常构建不需要。

模拟器始终标注测试数据，不伪造 RAW；故障注入仅在 Debug 生效。辅助显示 UI 测试通过模拟器系统设置开启降低透明度和减少动态，Debug 修饰器仅提供大字体和深色。VoiceOver 的实际朗读顺序和手机上的显示设置仍需人工验证。

## 官方依据

[Apple RAW 拍摄](https://developer.apple.com/documentation/avfoundation/capturing-photos-in-raw-and-apple-proraw-formats) · [Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) · [尼康 ISO](https://onlinemanual.nikonimglib.com/d850/en/10_iso_sensitivity_01.html) · [佳能规格](https://www.canon-europe.com/media/EOS_200D_PR_Spec_Sheet_EM_Final_tcm13-1581106.pdf)
