# Inferno 原碰撞 mesh 原子耗时

基线 `1730994`，仅新增作者探针 `profile_collision_meshes.gd`，不改原三角形、缓存、地图或运行时。headless 实例化实际原碰撞场景，按 Graybox 相同顺序赋值缓存 shape、添加 StaticBody、添加 CollisionShape、释放视觉 mesh；每个 mesh 后让一个物理帧。探针逐段计时，不把帧等待计入原子段。

最终缓存命中49个shape，来源GLB、原.import和缓存文件SHA绑定于结果。验证710.101ms、缓存读取189.369ms。49个mesh的同步挂接段合计3037.099ms；这是隔离CPU墙钟样本，不是完整Main或GPU帧预算。

下表路径均位于 `OfficialSourceAlignment/`，时间单位ms。

|mesh|三角数|shape赋值|添加body|添加shape（含树通知/物理登记）|总同步段|
|---|---:|---:|---:|---:|---:|
|COLLISION_ONLY_physics_group_wood_001|1,438,118|29.220|0.023|2039.727|2068.989|
|COLLISION_ONLY_physics_group_concrete_002|714,175|14.541|0.023|602.995|617.578|
|COLLISION_ONLY_physics_passbullets_vrf_unknown_key_2838185980|144,408|3.470|0.003|91.140|94.633|
|COLLISION_ONLY_physics_group_rock|135,695|2.757|0.017|88.798|91.699|
|COLLISION_ONLY_physics_group_rock_001|100,050|2.017|0.012|64.477|66.526|

前两项约占总同步挂接88.5%。初轮wood节点注册段2171.469ms，最终2039.727ms；R40完整Main曾见约1.60s，环境/负载不同，不能混为严格同机配对提升。最大mesh另单独执行一次未缓存 `create_trimesh_shape()` 为1586.928ms，新shape faces与缓存faces逐项完全相等。该未缓存创建是额外诊断，实际命中路径没有执行它，故不能把这1.59秒再计入实际缓存开局。

结论：缓存命中已经免去了重新创建三角shape，但仍有超过2秒的单次live-tree shape挂接。每mesh之后await无法切开这段原子调用；本探针不能证明引擎内部哪一个物理后端函数占用，需原生CPU采样才能继续细分。

下一步可在独立作者候选中，将wood与concrete的三角集合做确定性空间分块，验证每个原三角及变换精确保留，再比较注册峰值、总时间、内存和接缝接触。相同三角集合不自动证明不同body划分下的接触/台阶/射线语义等价，必须复核既有通路、边缘与支撑门闸后才讨论进入运行时。另一候选是shape资源准备与视觉加载重叠，但必须先确定物理后端线程限制；本轮未启用任何候选。

证据：`D:/AgentGamePipeline/evidence/exported-layout-20261029/mesh/result.json`（初轮）与`result-final.json`（含未缓存创建对照）。最终Godot退出0/`COLLISION_MESH_PROFILE_OK meshes=49`；格式和lint通过。本片不重复全套测试，不认定三图人工、18场或70%FPS通过。
