# R48 完整支持载荷与新版本信息

新增独立作者工具`stage_complete_playtest.py`，核验旧完整build-info的支持文件及本次真实导出三件身份，只复制支持文件，保留新EXE/主PCK/雷达PCK，生成新build-info和外部计划。metadata只记录真实export receipt的runtime提交/生产源摘要，不沿用旧测试成绩或旧版本标记；activation_allowed=false，Movement Current保持，环境候选默认关闭。

实际只读计划：44项，支持文件1,807,919,675字节，保留原Dust视觉GLB、三图bundle及可选入口。证据`D:/AgentGamePipeline/evidence/r48-20261030/support/plan.json`。先发现旧附包builder在candidate留35个中间JSON/PNG；按明确前缀、路径/无reparse检查及SHA/bytes收据移到export-intermediates保存，不删除、不动三件成品，见intermediate-move-receipt.json。

实际复制已在协调窗口完成：41支持文件逐项复制及SHA核验，三件新runtime保持，fresh build-info已生成；SUPPORT_READY。五项定向测试验证复制完整且不覆盖新runtime、旧support篡改拒绝、缺三件拒绝、多余文件拒绝、第二次覆盖拒绝，Ruff/格式/Pyright通过。新工具只做组装/文件身份，不代替产品普通EXE/可选入口/GPU或18场/人工/帧率验收，最终结果以本批delivery.json为准。

R46严格门闸需要源码HEAD等于真实runtime提交756ef174；父代理已建只含runtime roots的稀疏worktree，先逐文件字节核对export runtime_sources，再用原verify_playtest_candidate及计划/receipt检查完整候选。后续作者工具或文档提交不能追写成旧二进制的runtime HEAD。

后续审查发现旧试玩说明含旧版本/测试成绩，已修工具为generate_guidance，不继承旧说明。实际候选只定点替换试玩说明.txt并同步plan/build-info的同一文件SHA；旧说明、原plan/metadata备份和guidance-repair.json保存在support证据目录。三件runtime/assets未改，旧完整包未改。新说明绑定runtime756，说明当前入口、Current/环境候选默认、已实现AI闪光和真实雷达及仍待验事项；5项focused包含排除旧日期/提交/298成绩断言，Ruff/Pyright通过。完整门闸需在这次说明修复后重验。
