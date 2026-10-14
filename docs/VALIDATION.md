# 验证记录

最后更新：2026-10-15（Asia/Shanghai）。**源码实现、自动测试、云构建、手机 RAW 和实际相机效果分开记录。**

已验证的代码提交：`4039e2d317cb549887f55352fc2bdae65f9600f6`。首个完整测试版为 **0.1.0，build 6**；此记录后续仅作文档更新，不改变被测试的代码。

| 项目 | 状态 | 证据或下一步 |
|---|---|---|
| 原生工程、共享 Scheme、Swift 模块 | 两套 Xcode 已编译通过 | Xcode 26.6／27.0；原生工程生成一致性检查通过 |
| 源码／plist／Scheme／隐私／密钥模式检查 | Windows 和 Linux CI 通过 | [源码检查](https://github.com/ATTTQJ/campus-lens/actions/runs/38569117466) |
| IPA 打包输入、执行权限、符号链接测试 | Linux CI 三项通过 | Windows 两项通过、POSIX 一项跳过；Linux 全部执行 |
| 曝光公式、补偿、档位、无解、非法输入、校准、坐标、JPEG 元数据和 AI JSON | 纯 Swift 包 11 项通过 | 两套工具链均通过，0 failures |
| iOS 单元／图像／生命周期／网络测试 | 两套系统各 22 项通过 | 核心 11 项、图像／历史 9 项、网络 2 项；0 failures |
| UI：权限拒绝、拍摄失败、后台、离线、超时、大字体、辅助显示 | 两套系统各 4 项通过 | 摄影故障使用明确的 Debug 注入；降低透明度／减少动态使用真实模拟器系统设置 |
| JPEG 隐私处理 | 自动测试通过 | 转换 sRGB、最长边限制、物理朝向、清除 APP／COM、无 GPS／EXIF |
| Keychain 调用和迟到网络响应 | 自动测试通过 | 模拟器临时 ad-hoc 签名测试宿主；真实 Keychain 保存／恢复，URLProtocol 请求无外部联网 |
| 公开 GitHub 仓库 | 已创建并提交源码 | [ATTTQJ/campus-lens](https://github.com/ATTTQJ/campus-lens) |
| iOS 26 主构建 | 成功 | [run 38569117473](https://github.com/ATTTQJ/campus-lens/actions/runs/38569117473)，Xcode 26.6（17F113），iOS 26.5 模拟器 |
| iOS 27 兼容验证 | 编译与模拟器测试成功 | [run 38569117504](https://github.com/ATTTQJ/campus-lens/actions/runs/38569117504)，Xcode 27.0（27A266a），iOS 27.0 模拟器；真机兼容性未实测 |
| 设备 archive／未签名 IPA | 已生成并下载核对 | ARM64 iPhoneOS，可执行权限保留，最低 iOS 26.0，无签名目录和描述文件，包含隐私清单 |
| iPhone 16 Pro Bayer RAW、同次 EXIF、实际区域对应 | 未实测 | 侧载后验证 RAW 格式码、ID、EXIF、DNG、电平、主体框和朝向；不能用模拟器代替 |
| D850／200D 可设置档位 | 官方资料建表，未实物逐项核对 | 相机设置 1/3 曝光步长和手动 ISO；中间焦段最大光圈由相机显示确认 |
| 两机三场景曝光／运动／景深／失焦／灯光 | 未实测 | 按 [FIELD_TEST.md](FIELD_TEST.md) 逐样本记录 |
| 90% 样本误差 ≤2/3 EV | 待验证目标 | 稳定光线、认可参考曝光、分机身统计；不是当前保证 |
| 校准准确度和跨光线稳定性 | 未实测 | 各机、各焦段三次灰卡及异光验证 |
| 实际可配置视觉服务 | 未外部联网实测 | 协议、超时和数据校验已自动测试；用户提供接口／模型／Key 后验证 |
| VoiceOver、手机系统辅助显示、刊发清晰度 | 未人工验收 | 手机和学校实际刊发尺寸验证 |

## 交付产物

设备包：`CampusLens-unsigned.ipa`，315,018 bytes。

```text
SHA256 bfd12ca64ec00f04daeed98d8c18ff338299728b0e8ac0d8f0e736b49150252a
Bundle ID org.campuslens.CampusLens
Version 0.1.0
Build 6
Minimum OS 26.0
SDK 26.5
Architecture ARM64
```

[iOS 26 产物 ZIP](https://github.com/ATTTQJ/campus-lens/actions/runs/38569117473/artifacts/11898460697)包含 IPA、SHA256、版本信息、测试报告和构建日志，保留至 2026-10-21。ZIP SHA256 为 `142f4de250126710af1229f4166ca2a7f0606f515702f3dcc6c774f781522b07`。

[iOS 27 兼容产物 ZIP](https://github.com/ATTTQJ/campus-lens/actions/runs/38569117504/artifacts/11897077625)包含兼容报告和日志，保留至 2026-10-21。ZIP SHA256 为 `3c1be8677e15ebf0436368bb70febb0673397d2c242a2af23403a606d70a3ee1`。

设备包关闭云端签名，用户自行签名安装。模拟器仅为测试 Keychain 使用无需证书的临时本地签名；测试权限文件未用于设备 archive。

## 四阶段状态

1. 工程、四页面、权限、云构建：自动验收通过，已包含在 build 6。
2. 真实 RAW、元数据、Vision、离线求解：源码和编译／离线自动测试通过；实际手机 RAW 待验证。
3. 校准、历史、试拍调整：校准记录／算法和历史更新自动测试通过；相机校准与试拍待验证。
4. 联网、异常响应、iOS 26/27：两系统自动验收通过；外部视觉接口与真机兼容待验证。

四阶段实现整合为首个完整 IPA build 6，未分别发布四个阶段的历史 IPA。后续修复通过主分支或手动构建生成新包，版本标签可触发 Release 交付。
