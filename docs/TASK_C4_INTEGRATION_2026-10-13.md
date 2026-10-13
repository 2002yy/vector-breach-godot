# C4 历史 PR 集成记录

用户于 2026-10-13 明确要求整理所有 PR 并合并到 main。本次授权用于集成已审查的 C4 变化，取代旧文档中的待合并授权；不等同于 G2 人工比赛或完整人工音频验收。

- 基线：PR #27，`8d195df`；更新到 main `d8901e1` 后候选 `68d714e`。
- 全部原生测试：`D:\AgentGamePipeline\evidence\pr27-native-current.log`，`RUN_ALL_OK`。
- RTX 5060 Laptop / Vulkan Forward+：`pr27-c4-vulkan.log`；`reports/step16-c4-evidence.json` 和 dropped / planted / urgent 三张截图已逐张检查。模型可见、接地，紧迫阶段灯光与音调发生变化。
- 60 帧采样：隐藏 / 掉落 / 安装平稳 / 紧迫平均 4.1673 / 4.1649 / 4.1605 / 4.1673 ms，p95 4.677 / 4.763 / 5.016 / 4.861 ms。此为短采样，不代表整场性能。
- 本机引擎输入及音频混音器：`pr27-c4-input-audio-third.log`，拾取 / 安装 / 拆除全部 true，音频峰值 0.27116。输入通过引擎动作与实际 Main 交互路径注入；捕获时仅在进程内临时解除主总线静音，不修改用户保存的音量。此项不冒充真人键鼠或听感验收。
- Windows Export 两次任务在运行器分配前失败。发现工作流和子任务占用同一 concurrency group；删除冗余的子任务锁，保留整个工作流的取消机制。修复提交 `00dabe4`。
- 资产 sidecar 保持 `draft`，完整人工美术 / 听感确认仍是独立后续事项，不由 CI 自动晋级。

合并条件：当前提交 Tests 与 Windows Export / smoke 全绿，审查无未解决问题。具体合并 SHA 和 CI 以 GitHub PR #27 为准。
