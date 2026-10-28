# R35 雷达重载缓存与切层测量

基线 `eda13b6`；正式地图几何、派生PNG与生成器保持。Main提供实际level_loaded序号 `radar_load_identity`，RadarDisplay据此重置脚底层采样并交给RadarAtlas。相同地图ID重新加载也清空两层纹理缓存、当前层与旧manifest，重新校验资源身份；工作线程证明绑定单调generation，快速连续重载不会把旧线程结果误认作新图证明。每次HUD更新仍只轮询，未增加大文件同步哈希。无identity调用保持旧接口兼容。

原生定向133检查通过：原116检查，加三图缓存清空/两次快速同ID重载/最终就绪，以及HUD空中保持与同ID重载脚底层重置。新/改RadarAtlas及夹具gdformat/gdlint通过；旧RadarDisplay局部编辑不整文件格式化。完整原生与Vulkan整合结果由根交付记录给出。

本机证据 `D:/AgentGamePipeline/evidence/radar-ai-transition-20261028/radar/`，`focused-final.log`和`timings.json`含26张真实1536²切片的同步SHA+PNG解码+ImageTexture创建耗时。headless单次最大：Dust II 48.426 ms，Mirage 14.713 ms，Inferno 19.109 ms；紧接着缓存命中最大分别38/17/17 us。两张RGBA8解码内容约18 MiB，不包含驱动开销。

这是暖文件系统、headless下的单次微测量，无分位稳定性、实际GPU上传帧时间或整图性能结论。首次切层仍在主线程同步完成，Dust II样本超过16.7ms，需后续有界预取/异步解码和真实渲染帧预算。Image.load_from_file发出既有export警告：当前本地atlas不代表已进入发布包，后续必须明确携带原PNG并完成实际PCK测试。未修改打包规则。用户运行中不重新加载地图而热替换文件仍不会主动刷新。

仍待：三图真实路线/楼层边界实走、敌情与观战规则、冷加载和切层GPU预算、包内atlas回退；不能认定70%FPS或小地图全部验收。
