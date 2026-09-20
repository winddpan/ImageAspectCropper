# Image Aspect Cropper

macOS 图片裁剪工具，基于现有 Xcode 工程，使用 SwiftUI、MVVM 和 `@Observable`。保留工程原有的 macOS 27 部署目标，使用 Swift 6，无第三方依赖。

## 数据来源

- `SourceImage.pixels`：经 EXIF 方向校正的完整原图，编辑过程中不修改。
- `EditorViewModel.selection`：相对于原图左上角的像素选区，与画布缩放和平移无关。
- `confirmedCrop`：确认后的选区。预览图片是派生数据，导出始终从原图取样。
- `EditorSettings`：比例、最后编辑的尺寸轴及其数值、格式、质量、网格和目录书签的唯一来源。每次修改写入 UserDefaults；另一条尺寸轴实时推导，不重复保存。
- 画布的缩放和平移仅影响显示。新图重置选区、确认状态、视图位置和撤销历史，保留设置。

SwiftUI 负责窗口、工具栏、参数面板和菜单；`NSViewRepresentable` 中的原生画布处理鼠标、触控板、光标和像素绘制。图片解码、重采样、编码和文件写入通过 `@concurrent` 离开主线程。连续导入会取消过期任务；导出捕获独立快照，因此期间可以打开下一张图片。

## 操作

1. 拖入图片或使用 `⌘O` 打开。
2. 选择 1:1、16:9、4:3、3:2、4:5，或输入自定义宽高比；交换按钮切换横竖比例。
3. 拖动选区移动，拖动四角或边缘调整大小，在选区外拖动重画。选区始终锁定比例并限制在图片内。
4. 设置输出宽或高，另一边自动计算并四舍五入至整数像素。
5. 点击确认或按 `⌘K` 查看裁剪结果，再导出。可以重新编辑或撤销。

触控板捏合和 `⌘` + 滚动缩放；滚动、平移工具或按住空格拖动平移。双指智能缩放切换实际大小和适合窗口。方向键移动选区 1 像素，Shift + 方向键移动 10 像素。

| 快捷键 | 操作 |
| --- | --- |
| `⌘K` | 确认选区 |
| `⇧⌘E` | 导出 |
| `⌘Z` / `⇧⌘Z` | 撤销 / 重做 |
| `⌘+` / `⌘-` | 放大 / 缩小 |
| `⌘0` / `⌘1` | 适合窗口 / 实际大小 |
| Escape | 从裁剪预览返回选区 |

## 导出

支持 JPEG、PNG、AVIF、HEIC、TIFF。编码器以本机 ImageIO 能力为准；不支持的格式禁用。JPEG、AVIF、HEIC 显示质量滑块。JPEG 的透明区域填充白色；PNG 保留透明通道。导出使用 sRGB，移除原图 EXIF / GPS 等元数据。

AVIF 选择 100% 时，编码层将质量参数限制为 0.99，以兼容系统编码器对 1.0 的拒绝；界面及保存的质量设置保持不变，此选项不保证无损编码。JPEG、HEIC 的 100% 仍使用 1.0。

首次导出选择目录，此后直接写入已授权目录。目录使用 security-scoped bookmark 持久化。文件名保留源文件名主体，扩展名随格式变化；同名输出需确认替换，原图所在路径禁止覆盖。写入采用原子替换。

导入限制为 1 亿像素和单边 32,768 像素；导出限制为 1 亿像素和单边 16,384 像素。多帧图片导入第一帧，导出静态图。自定义比例分量为 1 至 1,000，支持小数。

## 构建与验证

在 Xcode 中打开 `ImageAspectCropper.xcodeproj`，选择 `ImageAspectCropper` scheme 运行。工程包含 Swift Testing 测试目标，覆盖选区几何、双向尺寸联动、设置恢复、更换图片、撤销重做、EXIF 方向、透明度以及五种格式的实际编码与解码。

```sh
xcodebuild -project ImageAspectCropper.xcodeproj -scheme ImageAspectCropper -destination 'platform=macOS' build
xcodebuild -project ImageAspectCropper.xcodeproj -scheme ImageAspectCropper -destination 'platform=macOS' test
```

布局参考 [Lightroom 的裁剪工具](https://helpx.adobe.com/ie/lightroom/desktop/edit-photos/crop-rotate-geometry.html)与 [Photomator 的裁剪交互](https://support.pixelmator.com/photomator-user-guide/crop-tool/crop-flip-and-rotate-photos)：中央画布、右侧参数、顶部常用工具，以及固定比例选框和构图网格。
