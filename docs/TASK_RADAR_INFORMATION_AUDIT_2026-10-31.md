# R50 雷达实战信息审计

冻结基线 `09592b70e33b452684d58f0559960698a6adc249`。本片只读生产源码、现有测试与数据合同，不改变生产树，避免让并行18场矩阵混用行为版本。证据 `D:/AgentGamePipeline/evidence/r50-20261031/radar/source-audit.json` 绑定7份源码SHA；没有启动Godot/GPU，也未将静态审计写成运行时或人工验收。

## 已定位的规则缺口

| 编号 | 优先级 | 源码依据 | 下一项定向复现 |
| --- | --- | --- | --- |
| R50-R1 | P1 | `Main._build_radar_players` 仅保存敌人可见到期时间；失去视野后的2.5秒内，每次仍发布敌人的当前位置和朝向。`RadarDisplay._draw_player` 接受spotted记录 | 先看见敌人，再用墙/烟阻断并移动敌人；确认标记是否继续追踪。应冻结最后合法可见位置，超时移除；不能只测试spotted布尔值 |
| R50-R2 | P2 | `Main._build_radar_snapshot` 的位置、脚底、落地与朝向始终取Player；`MatchSpectator.tick` 则使用所选队友的独立相机 | 玩家死亡后切换另一楼层队友，验证中心/脚底/楼层/自身标记使用同一观战对象；无队友场景应单独定义 |
| R50-R3 | P2 | 北向固定设置使snapshot.player_yaw为0；`RadarDisplay._draw` 的中心箭头始终向上，没有独立真实朝向字段 | 关闭地图旋转，转身90度：底图和北向保持，中心箭头需反映实际方向 |
| R50-R4 | P2待规则确认 | `_is_target_legally_spotted` 有距离、视锥、烟雾、射线，未检查玩家闪光强度 | 全闪期间射线可见的新敌人是否仍被雷达揭示。先明确与共享失明规则的关系，再定门槛；不直接把渐进闪光等同完全不可见 |

以上前三项数据流在源码中成立，但尚缺运行时失败复现、修复及回归；第四项还需规则确认。敌情只来自本地玩家视野，不包含队友共享观察；这是当前实现范围，未研究原版客户端前不宣称经典一致或断言必须改成共享。

## 已有覆盖与边界

`MainStateFlowTestRunner` 已检查旋转模式玩家heading、范围/地图比例、目标和队友spotted；`test_real_radar.gd` 已检查脚底采样、空中保持、切图复位、层间0.25m滞回及2.5m最大偏差。它们不覆盖上表四项。未新增只复述源码的Python镜像测试；后续应通过真实GDScript调用与场景输入复现，再修生产行为。

C4记录由`C4Device.get_radar_record`无条件发布state和XZ；显示端仅绘制dropped/planted，超范围固定到圆边，没有高度字段，也没有按阵营/已知状态过滤。是否应对CT隐藏未知掉弹、安装后如何获知位置，需要独立经典规则核对；本片不凭直觉改变信息公平性。

朝向变换的底图逆旋转与标记正旋转互为逆运算，未发现该处确定缺陷。空中维持原楼层、落地才采样是既有明确策略，不能把跳起不切片当bug。连续楼梯/落地、三图多楼层与实战可读性仍须实际运动验证。

下一片优先R50-R1最后可见位置反证，其后统一玩家/观战雷达参考姿态与北向模式真实朝向；新行为提交必须明确使冻结比赛矩阵失效的范围，不可追写为旧矩阵已验证。

## 并行比赛资格复核

只读审查发现旧`run_bounded_full_match.fingerprint`用`git ls-files`，漏掉未追踪的三图local JSON及实际manifest/navigation/碰撞依赖。新增独立`snapshot_match_dependencies.py`，不改运行中的旧wrapper或原frozen收据；按实际加载路径绑定每图level、manifest、raw、import、compiled、缓存res及json，当前合计21文件。manifest内含导航、出生点、目标点，无外部导航文件；Dust没有match_manifest字段，使用产品默认dustline.json。缓存严格绑定raw/import/engine/cache SHA，属派生数据但实际影响碰撞形状，因此也记录。视觉纹理不在此玩法闭包。

8项定向反例检查、Ruff格式/lint通过；真实21文件快照已写`radar/dependencies-observed.json`。首次观察UTC为2026-10-31T06:49:56.948751Z，不能追写为首场启动前证据。R49 `normal-export/layout-source.json`的三图level/manifest/raw共9个旧SHA与当前一致，属于历史旁证，不证明此前比赛中途没有瞬时变更。只读结论在`radar/review.json`。

整场种子在场景建立后每回合首次FREEZE检测时施加到各AI RNG，基于seed、serial与display_name；setup早先使用instance_id，未证明所有随机来源/时序确定，因此固定种子属于采样配置，不是确定回放。玩家始终静止，每回合自动就绪且当T时通过真实丢弃输入放C4；首次Live做两物理帧暂停检查。结论只覆盖9AI加静止玩家整场，不代替10AI对称平衡、真人手感、人工三图或GPU帧率验收。执行环境首次记录晚于首场，console是小启动器，后补真实引擎exe字节身份需保留时间边界。
