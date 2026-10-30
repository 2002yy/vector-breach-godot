# R46 完整试玩候选的只读门闸

基线5887573。新增`tools/authoring/verify_playtest_candidate.py`，不改旧计划工具，不复制/导出大包，不替换桌面入口。

输入：完整候选目录、源码仓库、外部冻结delivery plan、实际导出过程的export receipt、期望完整HEAD。新的export receipt必须记录`runtime_source_head`、`runtime_sources`、`runtime_source_sha256`和`artifacts`（三件新EXE/main PCK/radar PCK的bytes及SHA256）。源码字典由`source_manifest(repo)`生成，摘要由`manifest_hash`生成；须在真实导出前后核对一致后形成收据，不能事后给旧PCK补一个当前源码标签。

source_manifest覆盖git跟踪的scripts（排除scripts/tests）、scenes、shaders、data、project.godot、export_presets.cfg实际工作字节；未跟踪生产文件、工作树或索引相对HEAD的生产改动均拒绝；新增模块必须先提交，不能仅加入索引就把WIP标为该HEAD。测试目录仍排除。原资产由文件载荷收据绑定；此摘要不声称涵盖全部资产或Godot导入缓存。

门闸拒绝：源码/HEAD变化、旧build-info、导出三件身份不符、候选清单与外部计划不等、缺support、内容被改、额外旧文件、bundle依赖或input未绑定、候选reparse成员。新build-info必须包含相同`runtime_source_head`/`runtime_source_sha256`，files为计划全部文件的bytes/SHA256，不能继承旧build-info。

成功只说明收据和实际文件一致，固定`activation_allowed=false`。独立输入收据仍是信任边界：手工伪造整套一致收据不能被此工具识别；它不检查PCK内部源码，不代替实际导出记录、普通EXE双入口、三图比赛/人工/性能或CI。外部plan也必须保留已验证完整support（包括Dust原视觉GLB）；工具不会凭空发现任意被plan和bundle同时遗漏的隐性运行时依赖。

本轮10项定向测试，包括完整一致fixture、旧metadata、旧export、导出后源码变更、未跟踪新模块、真实临时Git库中生产WIP/仅索引差异/新staged模块拒绝而测试WIP允许、缺support、PCK篡改、额外旧包、缺bundle依赖。Python Ruff F/格式与Pyright通过。尚无新标准导出收据，不能对桌面旧包给出新版本放行结论。父批完整Python回归记录在PROJECT_STATUS；这里无生产行为变化。

下一步：冻结生产源码，实际正常导出前后采集源码摘要，保留完整support形成新计划/metadata，再运行门闸与普通EXE双入口验收。
