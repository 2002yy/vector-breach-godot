# Inferno / Mirage 官方原始资源接入

用户授权：下载官方原包并接入当前游戏；延续提交、推送及 PR 合入 main 的交付要求。

## 当前执行契约

- 基线 main：`bfdef836d3abfee6c4e380a1ad594df27cc365b6`。
- 工作分支：`feature/official-classic-map-materials-20261016`；开始时工作区干净。
- 原包固定 app `730`、depot `2347770`、manifest `2520908610273941189`。
- 保留现有重建版及其关卡/冻结清单备份；原始视觉与物理在私有 staging 验证后再切换。
- 两张地图原 VPK 已续传完成，SHA-1 与 Steam 清单一致。Source 2 Viewer 20.1 ZIP 的大小、SHA-256 与 ZIP 校验均通过，CLI 已运行。
- 发现固定 CLI 20.1 需要 `--game` 指向 `gameinfo.gi` 文件、显式 `-d`；地图导出中出现异常也可能退出 0，须同时检查输出和异常日志。
- 公共依赖散布在大量分卷。三轮按所需 Steam chunk 取得并提取 3408 个独立编译资源，缺失 0；部分 VPK 缓存明确标记为非完整 depot，资源另经 VPK CRC 校验，保存 SHA-256 和请求 chunk 清单。

## 接入与验收要求

保留原始材质、UV、模型与依赖，不使用已有的混凝土统一覆盖。按固定导出版本验证坐标变换与尺度；碰撞独立处理，不能由原视觉自动覆盖冻结路网。界面按实际安装资源显示原始材质或重建材质。

先验证一张地图的贴图依赖、原生物理分组、出生/台阶/通道/双爆点，再验证第二张。改动后执行相关原生回归、完整原生测试、Vulkan 实际截图及操作；导出新可玩包并验证入口、原始碰撞字节与冻结哈希。

原始地图、贴图、坐标、转换中间产物和第三方工具保留于私有目录，不提交公开仓库。公共提交保留通用转换/加载、必要测试与复现说明。

私有执行根：`D:/AgentGamePipeline/reference-assets/cs2-official-maps-20261016`。以下覆盖开始时的下载断点；远端/可玩包最终状态以外部交付收据为准。

## 2026-10-17 本机接入结果

- 两张原 VPK 均与固定 Steam 清单 SHA-1 匹配。Source2Viewer 20.1 原始导出保留；运行视觉用根变换复制原网格、UV 和 PNG，未经过 Blender 减面/重绘。Mirage 379 材质/627 图像，Inferno 923 材质/602 图像。
- 最终 113 张透明贴图从原 VTEX 恢复非恒定 alpha，RGB 逐像素一致，修复 A/B 喷漆红块。1229 张贴图使用 BC7/mipmaps；源 PNG 原始字节不受 GPU 导入压缩影响。
- 原生物理独立适配，运行构建真实 Shape3D 后释放仅碰撞的渲染 mesh，解决 Inferno 原加载 OOM。完整视觉始终保留。Mirage 132107、Inferno 2707934 碰撞三角形；排除 sky/仅手雷 clip。
- 同名经典关卡切换到原始材质，保留旧重建版和 JSON/冻结清单备份，没有增加混乱的重复菜单项。Mirage 路网 6082 点/6654 边，Inferno 7619 点/8392 边；每队五出生、双爆点，运行时仍验证关卡/碰撞哈希。
- 实际点击选图、换肤、购买、就绪均通过，两图各有九 AI 加真人。Mirage 60 秒加速观察安装 C4/24 次射击，Inferno 107 秒加速观察回合结束/27 次射击；不把这两项当正常速度 FPS 或全图长局平衡验收。

## Inferno 性能切片

用户明确要求继续优化 34 FPS。相同机器 RTX 5060 Laptop、Vulkan Forward+、1600×900，原正常速度 CT 5v5 20 秒稳定段中位数 34、最低 29 FPS。

隔离 AI 后，原出生点仍约 13200 draw calls / 9557405 primitives；关闭太阳阴影约 5234 次绘制，分辨率减半几乎无 FPS 收益。判断主要瓶颈为 CPU 提交，非像素填充。诊断关闭阴影仅用于定位，正式配置保留阴影。

实现：从不透明原视觉的大三角面建立 59305 面保守遮挡资源，不填孔、不用碰撞或透明叶片作遮挡；关卡专用 60 米/两级太阳级联，换图/卸载恢复设置。重新冻结后 layout 与此前逐字段完全相等，碰撞字节未变。独立视觉配置不会削减 AI 或更改战斗规则。

优化 CT 正常速度 30 秒：稳定段中位 69、最低 59 FPS；按同前 20 秒取样，中位 70。T 正常速度 60 秒中位 112、最低 96 FPS，九 AI 自然离开出生。A/B 路线共十处开/关遮挡截图已人工对照，未见墙体/门窗/场景误隐藏；世界区域平均绝对像素差均小于 0.16/255，差值大于 24 的像素比例最高约 0.18%。这些是抽样，不能替代全图所有角度。

证据：`D:/AgentGamePipeline/evidence/inferno-performance-20261017/`，含 baseline、occlusion-candidate、shadow-candidates、optimized-ct、optimized-t、occlusion-tour；渲染隔离探针会暂停 AI，实际性能结论使用正常速度 UI 探针。

## 验证、失败与交付

性能修改完成后原生 178 项 `RUN_ALL_OK`、GdUnit 2/2、GDScript lint、新工具格式检查、Python Ruff、资产分层/元数据/九个公开 GLB 合约与运行检查全部通过。Graybox 17 项含碰撞释放真实射线与换图渲染配置恢复。完整日志为 `native-performance-all.log`；MainStateFlow 退出仍有基线已有的 2 resources in use 提示，断言/退出码通过，不宣称日志零诊断。

有意义的失败均留证：下载 CDN 超时/SSL → 固定 manifest 续传及工具分段；分卷过度分配 → 稀疏 chunk 原地验证；Inferno Blender 视觉导出 OOM → 根变换复制；原 PNG 缺 alpha → 原 VTEX 原生解码；运行原碰撞构建 OOM → 先构建物理并释放无用渲染 mesh；作者工具提前 preload 缺 autoload → deferred 动态加载。

复查安装工具发现关卡与冻结清单同 basename 导致备份目标冲突，已改为 `levels/`、`match-local/` 两目录，并用临时仓库重现/回归。旧关卡 JSON 已从保留的 16 日可玩包恢复；两图 SHA-256 均与原冻结清单完全一致，`backup-recovery.log` 与 `check_install_backup.py` 留证。旧重建素材、完整旧包保持保留。

自动审阅在 `9c30015` 发现 alpha 恢复工具两个边界：恒定非 255 通道误用、同名纹理暂存覆盖。现跳过所有恒定 alpha，暂存/解码/备份保留资源相对路径。新增 unittest 覆盖 0/127/255 恒定通道、变化通道和同 basename 的五目录资源；实际 VRF 20.1 两纹理解码通过。已安装素材审计发现 Mirage 一张花材 alpha 恒为 0，已从原 RGB 备份恢复，最终 Mirage 91 + Inferno 22；其余素材哈希验证不变。Inferno 性能结果不受此修正影响，Mirage 重新导入与导出包截图验证。此增量为离线工具、文档与一张私有视觉贴图，不改生产玩法/碰撞/脚本，复用已验证的 178 项原生结果；新增工具测试命令为 `python -m unittest discover -s tools/tests -p test_restore_source_texture_alpha.py`。

`d6f2213` 复审进一步指出导入配置备份的同 basename 冲突；现保留相对目录并在第一处写入前验证全部输入及备份目标。新增同名备份和后续输入失败不产生部分修改的两项回归，`python -m unittest discover -s tools/tests` 合计三项通过。本机新图 URI basename 均唯一，此问题未影响既有 1229 张配置；运行代码/关卡/图像不再改变，导出最终包的两图 UI 验证通过。

公开 Git 仅提交加载、转换、验证和文档，不提交 Valve 模型/贴图/坐标。完整来源与复现次序见 [取得手册](CS_OFFICIAL_MAP_ACQUISITION.md)。分支基线在本文件开头，精确提交/PR/CI run ID、event、head、最终工作区及包 SHA 记录于 `D:/AgentGamePipeline/evidence/official-classic-maps-20261017/delivery.json`。

目标本机包：`D:/AgentGamePipeline/builds/VectorBreach-official-classic-maps-20261017/VectorBreach.exe`，必须保留整个目录、PCK 和原始碰撞字节旁件。导出后需重新验证两图实际 UI/5v5，不能只检查生成了 EXE。

## 剩余边界与下一片

Source 2 着色器、烘焙灯光、粒子和完整实体逻辑没有整体迁移；目前是官方原网格/UV/贴图及原生物理在 Godot 的适配。60 米外太阳阴影的距离与级联精度是本次性能取舍，非声称画面完全不变。独立的子弹穿透/手雷 clip 查询层、G2 十场人工比赛、全图全部路径/视角、最终用户美术批准均仍开放。

下一执行片：按正常速度从双方各完成多回合人工对局，记录爆点/香蕉道/公寓的低帧与 AI 接触，而非继续盲目降低画质。
