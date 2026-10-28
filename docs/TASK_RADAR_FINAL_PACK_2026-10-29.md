# 实际标准导出 PCK 与雷达附包

基线98d170c。使用现有 Windows Desktop preset执行实际 `--export-pack`，未修改preset、运行时代码或原资产，也未更新桌面试玩目录。导出前D盘约10.95GB可用，选择单份PCK，不另复制EXE/大包。产物仅在本机证据目录。

新增 `tools/authoring/build_final_radar_supplement.gd` 分三阶段：prepare在完整工程核对原GLB、原.import、关卡和atlas哈希；build在空项目挂载实际产品PCK，读取真实导出remap与compiled资源哈希后生成收据；check在空项目挂载产品PCK及附包，加载产品自己的导出RadarAtlas脚本，验证三图全部切片。附包只有atlas.json、PNG和export_identity.json，不含产品脚本、原GLB、compiled collision、关卡或原.import，不覆盖产品程序。已有产品collision直接复用。

实测：标准主PCK **3,620,438,302字节**，SHA256 `97822009b22778ad38bb86ae133f3c7c5d9c2c7321279d29115940e6f2eac920`；资产附包 **1,631,716字节**，SHA256 `ae0c3e39118672bdda91af660286f305faff8b5d342b91aafa6187476c188eb4`。空项目中原GLB缺失且无本地res资源回退，三图26切片校验/异步解码通过，最终格式化后再次check通过。未复制诊断包中135MB collision，也未增加359MB原GLB。

执行顺序：源工程运行工具 `-- prepare <新input.json> reserved`；将作者工具复制至空项目check.gd；空项目运行 `-- build <product.pck> <input.json> <新supplement.pck>`，再运行 `-- check <product.pck> <supplement.pck>`。输出路径需不存在；本工具不是正式产品的自动挂载入口。生成收据必须针对最终导出产物重跑，不能用缓存收据代替。

本机证据 `D:/AgentGamePipeline/evidence/radar-final-pack-20261029/package/`：export.log、prepare/build/check.log、input.json、results.json、isolated及两个PCK。实际导出完成savepack，三图marker `RADAR_FINAL_READY maps=3 slices=26`；格式/lint通过。没有扩大include_filter，因为明确资产附包已解决原字节读取需求，当前正式启动仍需显式先挂载附包。当前证据只证明最终导出资源字节与雷达可匹配，不证明正式EXE已自动加载附包、全部原场景依赖或三图人工可玩/FPS；完整collision依赖实例化由独立通道验证。最终EXE整合、损坏附包负例及成品发包仍待验。
