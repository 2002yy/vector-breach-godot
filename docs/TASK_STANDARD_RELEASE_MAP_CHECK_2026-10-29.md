# R42 最新标准导出与统一雷达附包

基线`0b98bc9`，只新增作者构建包装器，不修改生产脚本、project或export preset。实际执行一次Windows Desktop标准`--export-release`，输出`D:/AgentGamePipeline/evidence/standard-release-20261029/candidate/VectorBreach.exe`及同名PCK；未使用旧主包代码覆盖层、诊断主项目或原GLB附包。

新增`tools/authoring/build_standard_release_radar.py`可一次导出并串行完成：来源原字节核验、隔离目录对实际新PCK构建雷达身份、生成三图冻结布局收据、合并固定命名资产附包、以产品自己的导出RadarAtlas检查三图26切片。所有子进程用显式参数、超时和错误门闸；产物/工作目录要求新路径，拒绝覆盖已有附包。`--existing-export`仅用于接续一次已完成的标准导出，避免重复大包。

本次标准EXE109,071,360字节，主PCK3,620,471,578字节，固定`VectorBreach-radar.pck`1,634,192字节。附包不重复产品脚本、原GLB或compiled collision。实际新PCK隔离验证`RADAR_FINAL_READY maps=3 slices=26`通过，导出与检查日志无SCRIPT ERROR或ERROR。SHA256见本机`radar-build/artifacts.json`。

执行示例：`python tools/authoring/build_standard_release_radar.py <新的候选目录> --godot <编辑器版Godot控制台路径>`。不能传release模板：此作者工具依赖编辑器的导出和脚本执行能力。复用最新工程时默认定位仓库根目录；对已导出的一次性候选补附包时增加`--existing-export`，但目录中不能已存在固定附包或构建工作目录。该接续选项只核验资产身份，不证明任意已有主包的运行时代码等于当前HEAD；本次代码来源由独立标准导出日志与未变的生产树共同确认。

包装器Ruff F、格式和Pyright零错误，未重复原生全套：生产行为与R41验证版本相同。本机`export.log`及`radar-build/`保留实际导出、来源准备、隔离构建与正测日志。导出发生在新增包装器落盘前，但生产代码/配置未变，后续格式化也仅影响作者包装器。

候选已交给独立图形开局通道，实际EXE正常菜单三图开局结果由该通道记录。此文件不把隔离切片通过写成完整开局、比赛或70%FPS验收，也未更新桌面试玩入口。旧基线清理由根代理在新候选验收后按单独清单处理。
