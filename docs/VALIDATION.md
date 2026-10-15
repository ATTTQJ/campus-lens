# 验证记录

最后更新：2026-10-15（Asia/Shanghai）。**源码实现、自动测试、云构建、手机 RAW 和实际相机效果分开记录。**

当前代码提交：`f19e9c44294ca2e20bdadca8f8cbe1e3144a8b42`，版本 **0.2.0，build 12**。iOS 26 自动测试与未签名设备包已验证；同一提交的 iOS 27 本轮验证待完成。后续文档提交不改变被测试的 App 代码。

| 项目 | 状态 | 证据或下一步 |
|---|---|---|
| 原生工程、共享 Scheme、Swift 模块 | 当前 iOS 26 编译通过，iOS 27 本轮待完成 | Xcode 26.6；工程生成按文件名显式排序，Windows／macOS 一致 |
| 源码／plist／Scheme／隐私／密钥模式检查 | Windows 和 Linux CI 通过 | [源码检查](https://github.com/ATTTQJ/campus-lens/actions/runs/38694639963) |
| IPA 打包输入、执行权限、符号链接测试 | Linux CI 三项通过 | Windows 两项通过、POSIX 一项跳过；Linux 全部执行 |
| 曝光公式、补偿、档位、无解、非法输入、校准、坐标、JPEG 元数据和 AI JSON | 纯 Swift 包 11 项通过 | 当前 Xcode 26.6 通过，0 failures；27 本轮待完成 |
| iOS 单元／图像／生命周期／网络／回退测试 | 当前 iOS 26 共 32 项通过 | 核心 11 项、图像／历史 9 项、网络 2 项、回退与竞态 10 项；0 failures |
| UI：权限拒绝、失败、后台、离线、超时、大字体、辅助显示、调整／撤销 | 当前 iOS 26 共 5 项通过 | 新增 3:4 取景、画幅外快门、首次结果回顶、预览／应用／撤销／恢复。降低透明度／减少动态使用真实模拟器系统设置 |
| JPEG 隐私处理 | 自动测试通过 | 转换 sRGB、最长边限制、物理朝向、清除 APP／COM、无 GPS／EXIF |
| Keychain 调用和迟到网络响应 | 自动测试通过 | 模拟器临时 ad-hoc 签名测试宿主；真实 Keychain 保存／恢复，URLProtocol 请求无外部联网 |
| 公开 GitHub 仓库 | 已创建并提交源码 | [ATTTQJ/campus-lens](https://github.com/ATTTQJ/campus-lens) |
| iOS 26 主构建 | 成功 | [run 38694640099](https://github.com/ATTTQJ/campus-lens/actions/runs/38694640099)，Xcode 26.6（17F113），iOS 26.5 模拟器 |
| iOS 27 兼容验证 | 当前提交本轮待完成 | [run 38694639992](https://github.com/ATTTQJ/campus-lens/actions/runs/38694639992)；旧版本通过不能替代本次结果，真机兼容性未实测 |
| 设备 archive／未签名 IPA | 已生成并下载核对 | ARM64 iPhoneOS，可执行权限保留，最低 iOS 26.0，无签名目录、描述文件和 Mach-O LC_CODE_SIGNATURE，包含隐私清单 |
| iPhone 16 Pro Bayer RAW、同次 EXIF、实际区域对应 | 未实测 | 侧载后验证 RAW 格式码、ID、EXIF、DNG、电平、主体框和朝向；不能用模拟器代替 |
| D850／200D 可设置档位 | 官方资料建表，未实物逐项核对 | 相机设置 1/3 曝光步长和手动 ISO；中间焦段最大光圈由相机显示确认 |
| 两机三场景曝光／运动／景深／失焦／灯光 | 未实测 | 按 [FIELD_TEST.md](FIELD_TEST.md) 逐样本记录 |
| 90% 样本误差 ≤2/3 EV | 待验证目标 | 稳定光线、认可参考曝光、分机身统计；不是当前保证 |
| 校准准确度和跨光线稳定性 | 未实测 | 各机、各焦段三次灰卡及异光验证 |
| 实际可配置视觉服务 | 未外部联网实测 | 协议、超时和数据校验已自动测试；用户提供接口／模型／Key 后验证 |
| VoiceOver、手机系统辅助显示、刊发清晰度 | 未人工验收 | 手机和学校实际刊发尺寸验证 |

## 交付产物

设备包：`CampusLens-unsigned.ipa`，402,771 bytes。

```text
SHA256 b41501d531035728a1d84d0432bfb11958ba9eecdea396a9572df845835b0e89
Bundle ID org.campuslens.CampusLens
Version 0.2.0
Build 12
Minimum OS 26.0
SDK 26.5
Architecture ARM64
Executable permissions 0755
```

[iOS 26 产物 ZIP](https://github.com/ATTTQJ/campus-lens/actions/runs/38694640099/artifacts/11954390037)包含 IPA、SHA256、版本信息、测试报告和构建日志，保留至 2026-10-22。ZIP SHA256 为 `d4942586d4a25eab5ae8a1a6b217560b6e0a02b7885101282227dd4f7d45b9e0`，已下载核对。

[原生 UI 截图与摘要](https://github.com/ATTTQJ/campus-lens/actions/runs/38696197706/artifacts/11954390114)直接导出本次 XCTest 附件，包含拍摄、结果、调整预览、撤销和辅助显示截图。摘要记录 iPhone 16 Pro、iOS 26.5 模拟器，37 tests passed、0 failed、0 skipped。ZIP SHA256 为 `e786ec35978e24adeace1127e5fea3fdd7c04f3de7bd3cea4d9d4c68d1a216ca`。界面中的灰色取景与缩略图是明确标记的测试数据，无现场 RAW；不能把这些截图视为真机拍摄证明。

设备包关闭云端签名，用户自行签名安装。模拟器仅为测试 Keychain 使用无需证书的临时本地签名；测试权限文件未用于设备 archive。

## 四阶段状态

1. 工程、四页面、权限、云构建：iOS 26 自动验收通过，当前为 build 12。
2. 真实 RAW、元数据、Vision、离线求解：源码和编译／离线自动测试通过；实际手机 RAW 待验证。
3. 校准、历史、试拍调整：校准记录／算法和历史更新自动测试通过；相机校准与试拍待验证。
4. 联网、异常响应、iOS 26/27：当前 iOS 26 自动验收通过，27 本轮待完成；外部视觉接口与真机兼容待验证。

四阶段实现最初整合为完整 IPA build 6，未分别发布四个阶段的历史 IPA。当前 build 12 完成原生玻璃界面和独立回退改进，详情见 [UI-0.2.md](UI-0.2.md)。后续修复通过主分支或手动构建生成新包，版本标签可触发 Release 交付。
