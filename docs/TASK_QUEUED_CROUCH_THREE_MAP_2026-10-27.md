# Movement-4 R22：三图预排队蹲跳与站立静步对照

基线 `22f63cadb50f4a7b14f374d07542a31f34034f08`（#118），分支 `audit/queued-crouch-three-map`。仅作者Python、测试与证据文档；Current/候选参数、玩家代码、原地图/资产/UI不改，不合并、不发包、不等CI。

## 冻结与回放

沿用R4原起点/目标/容差/时长及三方案有效输入：Dust II/Inferno用original，Mirage用back150_run200。三图27条时间线全部冻结并写matrix-lock后，才执行三方案 × jump/no_jump/站立walk ×60/120Hz **54次新实图回放**。没有重选成功样本、调整起跳时刻或回写旧记录。

jump逐事件保持原输入，改为预排队生产者并观测实际process/physics步进；no_jump只删除Space，保留Ctrl；walk删除Space和Ctrl、逐事件加Shift，其余时刻/方向/鼠标保持配对。检查完整InputMap事件、单次受支持起跳、正向离地、实际帧计数、原碰撞/布局/引擎/运行时代码身份，没有inline fallback或漏样本。

结果：**18/18实际起跳、空中蹲伏与首落通过**；**36次配对控制均未到**，站立walk全程保持1.8m且没有蹲伏输入。逐样本校验crouching与1.2/1.8m胶囊一致，不能只靠Ctrl标签算蹲跳。回接同几何R1的1.2m胶囊四弧分段通道，各档保留自身证明，9组三方案脚本通路按现有门槛qualified_jump。

不证明必须蹲伏才能通过，也不证明完整站姿到蹲姿转换的连续扫掠包络：原资格通道是固定1.2m身体，实际回放碰撞另由正式玩家执行。不宣布原版CS蹲跳等价。

## 覆盖与频率差异

合并R21已有11点/33组后，共14点/42组：24 qualified_jump、9 walk_only、9 route_unproven。动作类别 **10/15→13/15**，必须跳跃脚本通路 **4/15→7/15**。剩余动作类别为Mirage/Inferno的run_up，不把其他点改名充数。

| 地图 | Current首落位置差 | Legacy首落位置差 | Modern首落位置差 |
| --- | --- | --- | --- |
| Dust II | 0.0718m | 0.0811m | 0.0760m |
| Mirage | 0.2979m | 0.2411m | 0.1733m |
| Inferno | 0.0288m | 0.0182m | **0.5115m** |

表为60/120Hz三维首落差，时间差8.3–50ms。原始接触/支撑/阶段/位置保留。落点都在原目标范围内，**不等于精确首落、稳定停住或频率等价通过**；没有临时设宽松阈值放行0.5115m，precision_equivalence_accepted仍false。

## 验证和交付

工具：`python tools/queued_crouch_audit.py freeze|verify <R21源配置> <新证据目录>`，verify支持`--out`另存冻结汇总，拒绝覆盖不同内容。matrix-lock绑定三图清单及全部上游输入SHA，校验时重建输入并回算R21的576条旧试验/身体凭据。

普通Python完整套件 **363项通过**（新增12），Ruff F/格式/编译、Pyright **0错误**。回归覆盖保留原几何/输入、两种不同姿态控制、错方案/错几何/相机源、只有蹲跳标签、胶囊不符/非有限值、错控制时刻及只起跳没空蹲不能拿类别信用。六次原生回放均有完成标记且无脚本/引擎错误。完整Python套件最终只跑一次；未改产品行为，不重复正式原生全套/渲染/实包验收。

本机证据：`D:/AgentGamePipeline/evidence/queued-crouch-three-map-20261027/`，含先冻结的三图清单/matrix-lock、六份原始报告/日志与`validated-summary-v2.json`。首版汇总保留，v2只增加同轨迹的频率差，未重跑物理。无绝对地图坐标摘要见 [R22结果](evidence/queued-crouch-three-map-20261027/summary.json)，提交/PR/CI首查见本机`delivery.json`。

上游原文件、四个既有脏导入、玩家设置和10月26日试玩EXE/PCK哈希保持，人工入口仍可用、评分pending，无新包。

**Movement-4未验收，Movement-5冻结。** 下一片先定位Inferno Modern这组约0.512m首落差：复用原轨迹/接触/支撑/移动阶段，检查碰撞面、台阶、贴地与离散时序，不调Current或原目标。随后补边缘配对制动控制/两图新通道、Mirage/Inferno助跑；原机/人工、精度/完整出生路线、AI难度/18场/连续三图/70%FPS仍待完成。
