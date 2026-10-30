# R47 正常导出过程收据

基线97709f8。新作者工具`tools/authoring/export_playtest_receipt.py`固定执行正常Windows release导出、来源雷达包、来源layout描述、实际新主PCK下生成统一雷达/layout附包四步。源HEAD和生产文件清单在前后必须完全相同；拒绝源码工作树/索引WIP（复用R46门闸）。三件成品逐文件大小/SHA写入export-receipt.json；初始源快照/命令先写export-start.json，失败日志留存，不覆盖已有目录、不激活入口、不清理旧包。

仅`--dry-run`实际执行过，无大包导出。证据`D:/AgentGamePipeline/evidence/r47-20261030/release/dry-run.json`（PowerShell UTF-8 BOM）；包含当前已提交生产源摘要和精确四步命令。6项focused测试、Ruff F/格式、Pyright通过。此工具尚无真实新导出实测，不把模拟/定向测试声称为新包验收。

冻结生产提交后运行（路径应保持尚不存在）：

```powershell
C:/Python314/python.exe tools/authoring/export_playtest_receipt.py D:/AgentGamePipeline/repos/VectorBreach-godot D:/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe D:/AgentGamePipeline/evidence/r47-20261030/release/normal-export
```

预计三件新artifact约3.73GB；旧完整support约1.81GB，完整候选约5.54GB。若另复制候选目录会额外消耗一份，宜在新标准candidate原地加入已核验support。本次D盘快照约27.95GiB可用，非未来导出空间承诺。原Dust视觉GLB属于支持载荷，不能当垃圾清理。

后续流程：新三件普通EXE开局与可选入口先验；沿旧完整build-info清单逐文件复核并只复制support（排除三件旧runtime/build-info），按新export receipt重建外部plan和build-info；用R46verify_playtest_candidate门闸检查，再做正常EXE双入口/GPU验收。旧R43plan工具的provenance文字固定R42，不能直接当本轮新导出收据。新包装工具只负责导出收据，不复制support或自动生成看似已验收的metadata。

限制：source_manifest不含全部原始资产/导入缓存，三件artifact及support另由文件哈希绑定；不声称源码摘要证明PCK语义等价。activation_allowed始终false，不能取代18场、人工三图、70%FPS或CI。
