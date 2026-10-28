# 实际导出碰撞依赖验证

基线98d170c。本批只新增`check_exported_collision.gd`作者工具，不改运行时、地图或资产。使用本批标准Windows导出的实际`product.pck`（3,620,438,302字节），不是前批诊断资源包。

把探针复制到无资产、无autoload的空项目后运行；挂载前断言三图资源不可用，挂载后断言原GLB字节缺失，以原GLB逻辑路径经实际导出remap加载PackedScene并实例化。匹配Graybox的`COLLISION_`筛选与`create_trimesh_shape()`后备构建规则生成真实静态碰撞；等待物理帧后，对最多32个实际网格中心作垂直射线，确认命中当前实例后代。

|地图|实例网格|生成碰撞形状|射线|命中|
|---|---:|---:|---:|---:|
|Dust II|50|35|32|32|
|Mirage|39|39|32|32|
|Inferno|49|49|32|30|

三图通过，最终日志没有SCRIPT ERROR或ERROR，未出现缺外部依赖诊断。初轮GDS类型推断解析失败保存为`parse-failure.log`，声明Array后成功；不是游戏资源缺陷。最终结果与日志：`D:/AgentGamePipeline/evidence/radar-final-pack-20261029/dependencies/final-result.json`、`final-run.log`。新脚本格式/lint通过。

执行方式：空项目内`Godot --headless --path <empty> --script res://check.gd -- <actual-product.pck> <fresh-result.json>`。不在原工程运行该隔离探针。

边界：证明实际导出碰撞PackedScene的资源依赖可解析/实例化，并且其网格可构建可命中的物理形状；没有实例化完整Main/地图视觉与全部角色音效，也不替代Graybox碰撞缓存命中、全图几何等价、完整比赛或人工三图验收。Inferno两条射线未命中不作为缺失几何结论，采样中心不是逐面覆盖。最终EXE与主包雷达附包整合由对应通道继续验证。
