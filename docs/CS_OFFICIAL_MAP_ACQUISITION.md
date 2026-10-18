# 官方 CS2 地图取得、转换与复用手册

更新：2026-10-17。适用于当前 Godot 游戏。两张新图已完成本机原始材质接入；最终远端与打包状态见本批任务记录和交付收据。

## 先看结论与执行断点

第一张经典图是 **Dust II / de_dust2（CS2 版）**。本机原始材质入口使用官方资源转换成品；另一个沙线入口为重建外观。两者都叠加了本作的 B 点高架，碰撞、路网和爆破规则也由本作维护，不能把当前关卡称为完全未修改的官方关卡。

Inferno、Mirage 早期包来自第三方整理的几何和重建材质；本机现已升级为“Steam 官方 depot → 地图 VPK 与依赖 → Source 2 Viewer 导出 → Godot 适配”。旧重建素材与冻结清单保留备份。

本次实际进度：

| 步骤 | 结果与边界 |
| --- | --- |
| 回查 Dust II 来源 | 本机关卡 JSON、生成脚本和审计记录相互吻合；旧下载命令及原始导出日志未找回 |
| Steam 匿名访问 | 成功登录，取得 app 730 / depot 2347770 的 depot key 和当前完整 manifest |
| 固定当前版本 | `2520908610273941189`；Steam 清单显示 2026-10-15 17:23:21，不把其未标时区的时间另作转换 |
| 定向原包下载 | 16 日超时后保留断点；17 日以相同 manifest、`-validate -max-downloads 32` 续传，两张 VPK 的大小与 SHA-1 均匹配 |
| 导出工具取得 | 20.1 官方 ZIP 分段下载后大小、SHA-256、ZIP CRC 均通过，CLI 实际导出成功 |
| 公共依赖 | Steam chunk 定向缓存，提取 3408 个资源；VPK CRC 校验通过，逐文件 SHA-256 已留档，缺失 0 |
| 新两图原材质导出与导入 | 均已完成本机接入、独立原生物理与冻结路网、Vulkan 5v5 和购买/就绪验证 |

当前下一片为 Inferno 性能优化及最终包验收；原始着色器、Source 2 灯光和全部碰撞查询语义仍需单独适配。

## 1. Dust II 历史证据

旧参考根目录：`D:/3Dgame-reference/cs2-current`，本次检查已不存在。游戏运行所用的转换成品仍在，不需要重新取得才能继续玩现有版本。

| 字段 | 已找回的记录 |
| --- | --- |
| Steam app / depot | `730` / `2347770` |
| 历史 manifest | `118363704811264052` |
| 地图原包 | `game/csgo/maps/de_dust2.vpk` |
| 原包 SHA-256 | `51d6bb432b6553bfae6c38219a527c5de2464a2b107080f2b8be7d8427ebb885` |
| 原始视觉转换来源 | `analysis/dust2/de_dust2-reference.glb` |
| 原始物理转换来源 | `analysis/dust2/de_dust2-world-physics_physics.glb` |
| 导航参考来源 | `analysis/dust2/de_dust2-nav-reference.glb` |
| 当前原始视觉成品 | `assets/local_reference/dustline/de_dust2_original.glb` |
| 当前碰撞成品 | `assets/models/dustline/dustline_depths.glb` |
| 独立高架 | `assets/models/dustline/dustline_skywalk.glb` |

本机证据入口：`data/levels/dustline-depths-original-local.json`、`docs/map-data/dustline-depths-audit.json`、`tools/blender/build_dustline_assets.py`。这些文件部分按资产边界被 Git 忽略，不能依赖公开 checkout 一定有它们。

历史脚本明确读取原包、物理及导航参考，并记录官方 depot 和原包哈希；这足以恢复取得路线，但不能证明今天使用的 DepotDownloader 版本或以下命令就是当年的原命令。本次用等效的定向取得方式实测。

## 2. 工具与私有目录

本次私有根目录：`D:/AgentGamePipeline/reference-assets/cs2-official-maps-20261016`，下文记作 `$refRoot`。换机器只需更换路径，版本与校验仍必须一致。

工具：

- 本机 DepotDownloader：`D:/AgentGamePipeline/reference-assets/csgo-original-20261015/tools/DepotDownloader/DepotDownloader.exe`。
- 实测版本：`3.4.0+c553ef4d60c00a4f5fd16c9fe017f569001589ff`，.NET 9.0.4。
- 新机器从 [DepotDownloader 官方仓库](https://github.com/SteamRE/DepotDownloader)的 releases 取得，记录实际版本，禁止把未验证的新版本冒充本次版本。
- Source 2 Viewer 固定 release `20.1`，资产 `cli-windows-x64.zip`，官方地址：`https://github.com/ValveResourceFormat/ValveResourceFormat/releases/download/20.1/cli-windows-x64.zip`。
- 该 ZIP 应为 **52,773,073 字节**，官方 release API 的 digest：`sha256:67aaf8a67a85ca60fd09ff343e62103a4cdf3a2d177fc656231d7d734c5b3aa3`。

建议分层保存 `game/` 原包、`tools/` 固定工具、`analysis/<map>/` 原始导出、`staging/<map>/` Godot 适配成品、`logs/` 和 `receipt.json`。保留原包与未修改导出，适配操作在 staging 进行。

## 3. 先获取清单，再选文件

以下为 PowerShell；不需提供 Steam 密码。本次匿名访问该 depot 已成功；未来若返回权限或 manifest 错误，应按实际错误处理，不假设永远可用。

```powershell
$refRoot = 'D:/AgentGamePipeline/reference-assets/cs2-official-maps-20261016'
$depotExe = 'D:/AgentGamePipeline/reference-assets/csgo-original-20261015/tools/DepotDownloader/DepotDownloader.exe'
New-Item -ItemType Directory -Path $refRoot -Force | Out-Null
& $depotExe --version
& $depotExe -app 730 -depot 2347770 -manifest-only -dir $refRoot
if ($LASTEXITCODE -ne 0) { throw 'Steam manifest acquisition failed' }
```

清单文件为 `manifest_2347770_<manifest>.txt`。先核对日志中的 manifest ID、日期、目标文件和大小，再固定版本下载；清单查询成功不等于原包下载成功。

本次官方清单记录：

| 文件 | 字节数 | Steam 清单 SHA-1 |
| --- | ---: | --- |
| `game/csgo/maps/de_inferno.vpk` | 453401552 | `ffba75060715b1f315209c28df94646781fe3365` |
| `game/csgo/maps/de_mirage.vpk` | 176187297 | `0def8c7402b1ecf6d387f6e559d210b5a1856b32` |
| `game/csgo/pak01_dir.vpk` | 7706697 | `ebbf0fec064024563cfd0523c8161cb5c39dc919` |

整个 depot 清单为 **65,024,032,313 字节**；本次 D 盘剩余约 37.5 GB，因此不下载整个 depot，也不默认下载所有公共分卷。两张地图原包约 630 MB，尚不包括后续发现的公共依赖和转换空间。

必须选正式地图名，排除 `_vanity` 菜单背景截断版。

## 4. 定向下载、断点续传与校验

生成 UTF-8 无 BOM 的清单。保留 game 目录结构和 gameinfo，供工具解析公共依赖。

```powershell
$selectedFiles = @(
    'game/csgo/maps/de_inferno.vpk',
    'game/csgo/maps/de_mirage.vpk',
    'game/csgo/pak01_dir.vpk',
    'game/csgo/gameinfo.gi',
    'game/core/pak01_dir.vpk',
    'game/core/gameinfo.gi'
)
$fileList = Join-Path $refRoot 'files.txt'
[IO.File]::WriteAllLines($fileList, $selectedFiles, [Text.UTF8Encoding]::new($false))
& $depotExe -app 730 -depot 2347770 -manifest 2520908610273941189 -filelist $fileList -dir $refRoot -validate
if ($LASTEXITCODE -ne 0) { throw 'Steam content download failed; retain partials' }
```

断点恢复：重跑同一 manifest、同一 `$refRoot`、同一清单并保留 `-validate` 和 `.DepotDownloader/`。不删除下载状态，不在旧目录混入另一 manifest 的公共包。若升级版本，创建新根目录并重新记录所有哈希。

**预分配会提前产生完整长度文件。文件存在、大小正确、进度百分比或命令退出码均不能单独证明成功。** 至少对以下两张图核对 Steam 清单 SHA-1，再为存档计算 SHA-256：

```powershell
$mapChecks = @(
    @{ Name='de_inferno'; Bytes=453401552; Sha1='ffba75060715b1f315209c28df94646781fe3365' },
    @{ Name='de_mirage'; Bytes=176187297; Sha1='0def8c7402b1ecf6d387f6e559d210b5a1856b32' }
)
foreach ($check in $mapChecks) {
    $mapFile = Join-Path $refRoot ('game/csgo/maps/' + $check.Name + '.vpk')
    if ((Get-Item -LiteralPath $mapFile).Length -ne $check.Bytes) { throw 'Wrong map size' }
    if ((Get-FileHash -LiteralPath $mapFile -Algorithm SHA1).Hash.ToLowerInvariant() -ne $check.Sha1) {
        throw ('Incomplete or mismatched map: ' + $check.Name)
    }
    Get-FileHash -LiteralPath $mapFile -Algorithm SHA256
}
```

这组期望值仅对应 manifest `2520908610273941189`。公共索引、gameinfo 和后续分卷也应按该 manifest 的对应行校验。所有选择文件校验成功才进入下一步。

## 5. 取得并校验导出工具

最初 GitHub CLI/urllib 单连接下载未完成，残缺文件保留。最终使用私有 `tools/download_tool_ranges.py`：16 路、每段 2 MB，验证 Content-Range、段长，合并后校验完整 SHA-256 与 ZIP CRC。下面是网络正常时的普通下载示例；已验证成品为 `tools/cli-windows-x64-20.1-verified.zip`：

```powershell
$toolRoot = Join-Path $refRoot 'tools'
New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null
$toolZip = Join-Path $toolRoot 'cli-windows-x64-20.1.retry.zip'
if (Test-Path -LiteralPath $toolZip) { throw 'Choose a fresh retry filename; retain earlier partials' }
Invoke-WebRequest -Uri 'https://github.com/ValveResourceFormat/ValveResourceFormat/releases/download/20.1/cli-windows-x64.zip' -OutFile $toolZip -TimeoutSec 120
if ((Get-Item -LiteralPath $toolZip).Length -ne 52773073) { throw 'Incomplete tool archive' }
if ((Get-FileHash -LiteralPath $toolZip -Algorithm SHA256).Hash.ToLowerInvariant() -ne '67aaf8a67a85ca60fd09ff343e62103a4cdf3a2d177fc656231d7d734c5b3aa3') {
    throw 'Tool archive hash mismatch'
}
$toolDir = Join-Path $toolRoot 'source2viewer-20.1'
if (Test-Path -LiteralPath $toolDir) { throw 'Inspect existing tool folder before extraction' }
Expand-Archive -LiteralPath $toolZip -DestinationPath $toolDir
$s2vExe = Join-Path $toolDir 'Source2Viewer-CLI.exe'
& $s2vExe --version
& $s2vExe --help
```

版本升级前查 `--help`；工具明确提示 CLI 参数可能变化，不直接套用最新在线文档替代固定版本实际帮助。

## 6. 导出原视觉、物理与导航参考

依据 [Source 2 Viewer 地图导出说明](https://s2v.app/ValveResourceFormat/guides/exporting-maps.html)及 [CLI 参数说明](https://s2v.app/ValveResourceFormat/guides/command-line.html)编写。以下是待验证流程，须保存 stdout、stderr、退出码及 `exceptions.txt`。

先列目录与完整性检查，不直接对整个包盲目反编译：

```powershell
$gameDir = Join-Path $refRoot 'game/csgo'
$mapName = 'de_inferno' # Second pass: de_mirage
$mapVpk = Join-Path $gameDir ('maps/' + $mapName + '.vpk')
& $s2vExe -i $mapVpk --vpk_verify
if ($LASTEXITCODE -ne 0) { throw 'VPK integrity check failed' }
& $s2vExe -i $mapVpk --vpk_list
```

在目录中确认正式 `maps/<map>.vmap_c`、world、`world_physics.vmdl_c`、导航和内嵌 skybox 的**实际路径**。不要根据猜测路径把空导出当作成功。

视觉导出例子，先确认目录中确有这个 vmap 路径：

```powershell
$exportDir = Join-Path $refRoot ('analysis/' + $mapName + '/visual')
if (Test-Path -LiteralPath $exportDir) { throw 'Use a fresh export directory' }
New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
& $s2vExe -i $mapVpk --game (Join-Path $gameDir 'gameinfo.gi') -f ('maps/' + $mapName + '.vmap_c') -o $exportDir -d --gltf_export_format gltf --gltf_export_materials --gltf_textures_adapt
if ($LASTEXITCODE -ne 0) { throw 'Map export failed; inspect missing dependencies' }
```

首次导出优先独立 glTF / bin / 图片，便于检查贴图引用和大小；不强行把大型场景塞进单个 GLB。核对实际存在的模型、道具、UV、基础色/法线/粗糙度/透明贴图；退出 0 仍需检查缺失依赖警告和图片是否实际齐全。

物理导出用目录中确认的 `world_physics.vmdl_c`，传同样的 `--game`、`--gltf_export_format gltf` 和 `--gltf_export_materials`，另存 `analysis/<map>/physics/`。保留原始物理组名称与未简化网格，再区分实体碰撞、playerclip、NPC clip 和非碰撞装饰。导出可能另写 `_physics` 文件，应清点实际输出；不把包含 render mesh 的单个输出自动视为完整物理。

导航文件单独保留原始编译资源及其校验，作为出生点、区域、连接的参考。glTF 视觉导出不等于取得可用导航；Godot 仍需显式编制并冻结本作路网。

## 7. 缺公共依赖时如何补齐

地图包不保证包含全部外部资源。`pak01_dir.vpk` 是公共包索引，不包含各个分卷的全部数据；只拿索引不能宣布依赖齐全。

1. 保持 `game/csgo/gameinfo.gi` 与 `game/core/` 结构，20.1 的 `--game` 必须指向 `gameinfo.gi` 文件，同时显式 `-d`；新版在线文档的默认值不能直接套用。收集缺失资源路径。
2. 用 Source 2 Viewer 打开公共 `pak01_dir.vpk`，或用 CLI `--vpk_dir` 查资源所在 archive index。索引输出若不足，使用 GUI 文件属性或 VPK 索引解析取得分卷号，不猜分卷。
3. 把实际所需 `game/csgo/pak01_NNN.vpk` / `game/core/pak01_NNN.vpk` 完整路径追加到 `files.txt`，仍从同一 depot、同一 manifest 下载并校验。
4. 对新出现的纹理、模型、材质间接依赖继续补齐；每次记录新增文件与原因，避免一开始下载全体几十 GB 分卷。
5. 内嵌 VPK（例如 3D skybox）需要先提取内包，再对内包列目录和导出；首次导出没显示天空不等于原图没有天空。
6. 缺失列表归零后，仍要检查材质采样和模型实例，保存逐区对比图。只有这一阶段完成，才可标记“目标图依赖取得完成”。

## 8. Godot 适配：必须复用的经验

- 保留未修改的原始导出，另存可编辑 Blender 源与 Godot 成品；保留原 UV 和贴图，不默认覆盖成 `ClassicResearchMaterials.gd` 的混凝土/金属。
- Dust II 的旧源坐标记录为米系数 `0.0254`，映射 `x=source_y, y=source_z, z=source_x` 后乘系数；这是旧生成脚本约定。新导出 glTF 可能已经转换坐标和单位，必须用可测距离及轴向确认，禁止再盲乘一次。当前第三方 Inferno/Mirage 的 scale/offset 也不能直接套到官方原包导出。
- 植物、布篷等 Source 2 资源会把动画权重放在 `COLOR_0`。已有修正位于 `scripts/level/GrayboxLevel.gd::_repair_reference_vertex_channels`，按已知材质处理；不要全图删除顶点色。保留 alpha-cutout、双面和贴图规则，并检查树干与枝叶。
- 灰尘卡片、光束、blocklight 等源引擎辅助资源与普通可见墙体分开处理。优先记录隐藏规则与截图，不随意删模型。
- 2026-10-18 实际修复：`csgo_effects.vfx` 的灰尘/蒸汽 glTF 可能没有 `alphaMode`，基础色还会丢原生 alpha，显示为悬空灰面。使用 `prepare_source_effect_materials.py` 解码原 VMAT 的颜色/三个遮罩，旁置私有清单，由 `SourceEffectMaterials.gd` 做透明/加色与遮罩滚动适配；不能只把整张白图设透明混合或直接删面。重建遮挡时也排除该源特效着色器。完整命令、限制及证据见 `TASK_CLASSIC_EFFECT_SURFACES_2026-10-18.md`。
- 视觉和碰撞独立；地图原生 physics 应保留分组后适配，不能把所有装饰三角面一起当玩家碰撞。旧简化 AWMH 物理也不能冒充未经简化的原版碰撞。
- 新资源不能静默覆盖现行关卡和 `data/levels/match-local/` 冻结清单。先使用新 staging/新关卡 ID 验证；确认出生、双爆点、台阶/门洞/斜坡/clip 后，显式重编路网并校验新的 level/collision 哈希。
- Source 2 的灯光、复杂着色、烟雾、实体逻辑不会因为导出 glTF 自动移入 Godot。要完整保留 Source 2 运行效果，应在 CS2/Workshop Tools 中使用源资源；当前 Godot 版本需要单独适配这些功能。

## 9. 验收与交付记录

每次 `receipt.json` 至少记录 app/depot/manifest、工具版本及 SHA-256、选择文件清单、官方期望 SHA-1、实测 SHA-1/SHA-256、下载/导出退出码和日志、缺失依赖、转换参数、输出哈希、截图及测试结果。失败或中断明确记 `complete:false`。

依次通过：原包校验 → 工具校验 → VPK 结构/依赖 → 视觉贴图实际导出 → 未简化物理清点 → Godot 逐区视觉/接触验证 → 冻结路网与 5v5 回合 → 原生全套和相关 Vulkan 探针 → 导出包实际入口。不能用前一步替代后一步。

材质/碰撞接入后按 `AGENTS.md` 跑全套原生测试和 Vulkan 截图检查。17 日接入阶段全套已出现 `RUN_ALL_OK`，GdUnit 2/2；后续性能修改应重新验证。原始 Valve 资源继续放私有目录及已忽略的本机资源目录，不提交二进制和地图坐标到公开仓库。

本次私有证据：`D:/AgentGamePipeline/reference-assets/cs2-official-maps-20261016/`，含 `manifest-probe.log`、`manifest_2347770_2520908610273941189.txt`、`files.txt`、`maps-download.log`、下载断点和 `receipt.json`。工具及地图下载的预分配/残缺文件只用于恢复，不是有效交付件。

## 10. 2026-10-17 实际成功路线：定向公共资源

完整下载所需公共分卷会达到十余 GB，随后还会增长。本次没有把局部分卷冒充完整原包，采用以下可重放流程：

1. 完整校验两张地图、csgo/core 的 `pak01_dir.vpk` 和 `gameinfo.gi`。清单 SHA-256 为 `6ceff0bf74218fe69091641ffee87c57b8dad91caea13ac1b0a365567553e53f`。
2. 私有 `dependency_inventory.py` 读取 VPK v1/v2 目录和资源引用；`prepare_resource_ranges.py` 递归规划模型、材质、纹理等所需分卷字节区间。
3. 固定 DepotDownloader 上游提交 `c553ef4d60c00a4f5fd16c9fe017f569001589ff`，应用 `tools/depot-range.patch`。CLI-only 私有构建适配 .NET SDK 8.0.423，仅请求与资源区间相交的 Steam chunk，仍由 SteamKit 验证 chunk 内容。构建信息在 `tools/range-tool-build-info.json`。
4. 缓存放 `PARTIAL-cache-NOT-full-depot`；Windows 使用 sparse 文件保存原偏移。设置本进程 `VB_STEAM_RANGE_PLAN` 为不可变 JSON，再执行 `dotnet tools/depot-range-v2/DepotDownloader.dll -app 730 -depot 2347770 -manifest 2520908610273941189 -filelist resource-range-files.txt -dir PARTIAL-cache-NOT-full-depot -validate -max-downloads 32`。不同轮次 chunk 审计先归档。
5. 按 VPK 条目解压并校验 CRC，再写入 `game_loose/csgo` / `game_loose/core`。只把完整校验后的独立资源用于导出；不把局部缓存挂载成完整 pak。新引用产生下一轮计划，直至缺失为零。
6. 三轮最终提取 3408 个独立资源；`loose-resource-receipt.json` 保存全部 SHA-256、缺失 0 和来源。`game_loose` 放原 `gameinfo.gi`、地图 VPK 硬链接与独立编译资源，不放共享 pak 索引，避免 CLI 再尝试挂载不完整分卷。

私有源码与辅助脚本保留在上述根目录；方法包 `tools/acquisition-method-only.zip` 仅含脚本、补丁、构建信息和说明，不含 Valve 资源。换机器重放时仍须取得可访问的同一 manifest；不要仅复制缓存文件名就宣称通过。

重要失败与修正：普通 Python truncate 曾实际分配整个分卷；后改为 Windows sparse API。常规 DepotDownloader 更新分支会重建分卷、丢失 sparse 属性；v2 改为只验证请求 chunk 的原地缓存。稀疏回收工具仅对已证明为零的未请求区间打洞，不触碰验证内容。NuGet CRL 不可达时使用进程级 `DOTNET_SYSTEM_NET_HTTP_SOCKETSHTTPHANDLER_HTTP2SUPPORT=false`、`NUGET_CERT_REVOCATION_MODE=offline` 完成工具恢复，没有修改全局网络配置。

## 11. 已验证的转换与修复次序

视觉实际命令：`Source2Viewer-CLI.exe -i game_loose/csgo/maps/de_inferno.vpk --game game_loose/csgo/gameinfo.gi -f maps/de_inferno.vmap_c -o analysis/de_inferno/visual-raw -d --gltf_export_format gltf --gltf_export_materials --gltf_textures_adapt`。Mirage 替换地图名。完整原导出保留，日志仍有缺失 Source 2 着色器的提示，但没有缺模型/材质/纹理文件异常。CLI 可能异常后退出 0，必须检查实际 glTF、bin、PNG 和日志。

物理使用 `-f maps/de_inferno/world_physics.vmdl_c`，真正物理在额外生成的 `world_physics_physics.gltf`，主 glTF 可能为空。Mirage 41 组中运行 39 组、132107 三角形；Inferno 52 组中运行 49 组、2707934 三角形。排除 sky 和仅手雷 clip，保留原玩家实体/clip；当前统一物理层不等同 Source 2 的所有子弹/手雷查询层。

公共工具顺序：

1. `tools/align_official_classic_gltf.py --source <原视觉gltf> --metadata <旧对齐metadata> --output <新私有目录/map.gltf>`：逐依赖复制、校验 SHA，只加根变换、移除源太阳，不简化视觉或重建 UV。20.1 已将 Source 英寸转换为米，轴为 `(source_y, source_z, source_x)`；根 Y 旋转 +90°，偏移使用既有元数据的 `.0254/sourceToWebScale`。禁止重复缩放。Inferno 经 Blender 视觉导出曾 OOM，所以改用此方式；失败日志保留。
2. Blender CLI 运行 `tools/blender/convert_official_classic_map.py --help`，使用 `--kind collision` 转换 `_physics.gltf`。保留原三角面与分组，生成 `COLLISION_ONLY_` 前缀，否则运行时不会建立形状。对齐由该工具的 Blender 坐标转换完成。
3. `tools/restore_source_texture_alpha.py --source-gltf <原gltf> --target-gltf <适配gltf> --resources <game_loose/csgo> --decoder <CLI> --work <新审计目录>`：对 MASK/BLEND 材质找回原 VTEX alpha；仅当 RGB 逐像素完全相同、alpha 非恒定时替换原生解码 PNG。Mirage 最终 91 张、Inferno 22 张，修复原来 A/B 喷漆红矩形、污渍卡片等异常。全 0/127/255 等恒定通道均跳过；暂存、解码匹配和备份保留相对资源目录，避免同名覆盖。保留之前的 PNG 和收据，不绘制新纹理。
4. 按 `tools/prepare_official_classic_level.py --help` 校验原包 SHA-1 和所有 glTF 依赖，归档旧 JSON/冻结清单，经显式 `--replace-frozen-baseline` 切换关卡，再用 `tools/author_classic_match.gd` 离线生成新路网。运行时继续拒绝哈希不符，不自动烘焙。
5. `tools/configure_official_texture_imports.py --visual <适配gltf> --backup-dir <新备份目录>`：只配置新贴图的 BC7 高质量 VRAM 压缩和 mipmaps；先校验全部源/备份目标，再修改导入配置，备份保留纹理相对目录以避免同名冲突。工程开启 `textures/vram_compression/import_s3tc_bptc`，再 Godot import。1229 张原 PNG 字节保持不变。
6. 独立原生碰撞先建立 Shape3D，再释放仅碰撞源的 GPU mesh 引用，避免 Inferno 加载时 OOM；离线作者工具保留这些 mesh 用于烘焙。真实射线回归证明释放后仍阻挡，不移除碰撞。
7. 性能：`tools/build_classic_occluder.py` 从大于等于 0.25 平方米的原始不透明视觉三角面生成二进制，`tools/authoring/save_classic_occluder.gd` 保存 `.res`。不填门洞、不用碰撞模型作遮挡、不采用透明植被。Inferno 得到 59305 面。关卡 `render_profile` 指定 `occluder_resource`、`sun_shadow_distance:60`、`sun_shadow_cascades:2`；备份现行冻结清单后显式重编，确认布局没有变化。换图和卸载时恢复原视口/太阳设置。

实际截图入口：`tools/authoring/capture_classic_materials.gd -- <level-id> <证据目录> --compare-occlusion`，A/B 两路十视角逐帧对比开关遮挡；它会测试瞬移，不能算自然行走通过。性能隔离用 `profile_classic_rendering.gd`，实战帧率用 `ClassicMapsUIProbe.tscn -- --map <id> --observe --observe-seconds 30 --real-time-observe --evidence-dir <目录>`。加速模拟模式的 FPS 不能与正常速度比较。
