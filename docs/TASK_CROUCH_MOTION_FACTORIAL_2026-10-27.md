# Movement-4 R24：共时刻状态与步长交叉查询

基线 `3bc2c2d7c6c0edffc39e79d3e62c282837a58411`（#120），分支 `audit/crouch-motion-factorial`。仅作者Python/GDScript、测试和证据文档；不改正式玩家、Current/候选参数、原图/资产/UI，不合并、不发包、不等CI。

## 八组合拆开状态与步长

在R22同一物理结束时刻 **7/60s** 冻结两档碰前状态：60Hz取tick6、120Hz取tick13，而非相同起始时间标签。两档位置差 **0.014320m**，竖直速度差 **0.169333m/s**，均已离地并保持1.2m蹲姿。

先冻结位置来源60/120 ×速度来源60/120 ×运动安排单个1/60或两个1/120，共8项；同一原碰撞、0.4m半径/1.2m高度、胶囊局部Y=-0.3m和实际默认safe_margin约0.001m。每步先按20.32m/s²扣重力，再做`body_test_motion`，无命中才推进自由飞行状态，有命中立即停止。初始重叠均为空，查询没有移动测试body，也没有修改几何。

| 碰前位置来源 | 速度来源 | 单个1/60 | 两个1/120 |
| --- | --- | --- | --- |
| 60Hz | 60Hz | 命中 | 第二半步命中 |
| 60Hz | 120Hz | 命中 | 第二半步命中 |
| 120Hz | 60Hz | 未命中 | 两步均未命中 |
| 120Hz | 120Hz | 未命中 | 两步均未命中 |

**在这段冻结窗口中，碰前位置决定了是否命中；替换速度或只细分这一步均不消除原接触。** 这不证明所有位置/速度或完整比赛都如此，也不把只读查询算作新的路线首落通过。完整move_and_slide响应、floor状态、多个接触及后续移动没有在查询器中重建。

## 接触法线不等于斜面法线

原接触及查询都绑定同一原npcclip/playerclip `RuntimeCollision`、collider shape **0**。实际ConcavePolygonShape3D数组共 **19242** 个三角形；`var_to_bytes(PackedVector3Array)` SHA256为 `bee276aa31b280252ffa8dcd81e45fa846aa7811df6a9f161d2a82f51621f19b`，原碰撞文件/导入/布局/引擎身份也核对。

原接触点0.002m邻域有 **18737、18741** 两个候选，法线分别接近(-1,0,0)与(0,-1,0)，相互垂直；接触点距两候选边缘约 **0.0000268m**。保留两面歧义，不声称唯一命中其中一面。

因此R23把斜向接触法线简写成“近竖直斜面”应当收窄：**已知的是斜向接触法线，本次候选几何是竖直/水平面边缘邻域，并未证明有一张对应斜面。** 这是进一步查询后的几何澄清，不回写旧原始报告。

API核对：[运动结果返回collider/shape](https://docs.godotengine.org/en/4.7/classes/class_physicstestmotionresult3d.html)，[射线才提供face_index](https://docs.godotengine.org/en/4.7/classes/class_physicsdirectspacestate3d.html)。本机Jolt射线实际返回-1，符合[官方Jolt说明](https://github.com/godotengine/godot-docs/blob/master/tutorials/physics/using_jolt_physics.rst)的默认行为。未为取编号启用额外内存设置；改为读取真实shape的三角形数组，候选编号是该数组索引，**不是Jolt直接报告的face ID**。接触点射线旁证仍标matched=false。

## 验证、保持与交付

最终8组合在`v3/`，原生一个进程完成并有`CROUCH_MOTION_WRITTEN`，无脚本/引擎错误。之前`v2/`先跑同8项，但没有三角邻域证据；补只读shape观测后再跑一次，命中/安全比例逐项相同，故本批共 **16项查询执行、8个独立设计格、0场玩法回放**。未执行的最初矩阵与旧输出保留；没有覆盖原证据。

普通Python完整套件 **385项通过**（新增11）；Ruff F/格式/编译、Pyright **0错误**；GDScript通过缓存`uvx --offline --from gdtoolkit`格式/lint及实际运行。初始异构测试字典的类型诊断用JSON边界注解修正。完整Python套件只跑一次。回归覆盖共结束时刻取样、正交因子完整性、初始重叠/body位移、缺格/截断分步、改变路径/余量、错来源及伪造唯一面/越界索引/超出接触邻域。

入口：`python tools/crouch_motion_factorial.py freeze|verify <R22 Inferno清单> <新证据目录>`，拒绝改写冻结矩阵。原坐标/状态/查询原件在 `D:/AgentGamePipeline/evidence/crouch-motion-factorial-20261027/`，仓库仅存 [无绝对坐标摘要](evidence/crouch-motion-factorial-20261027/summary.json)；提交/PR/精确头CI首查在本机`delivery.json`。

R22/R23原来源、四个既有脏导入、玩家设置和试玩EXE/PCK哈希保持。未改产品行为，不重复正式原生全套/渲染/实包验收。动作13/15、通路7/15、人工pending保持；碰撞未修复，精度未放行，Movement-4未验收，Movement-5冻结。

**下一片**：把碰前位置的水平/高度分量交叉，并回算起跑到起跳阶段在共同物理时刻的位置差，定位约14mm差的触发分量与积累来源；然后评估独立Modern离散步进候选。Current和原图不改，不靠改起点/目标让原路线通过。边缘控制/两图通道、Mirage/Inferno助跑、原机/人工/完整路线、AI/18场/三图/70%FPS仍待完成。
