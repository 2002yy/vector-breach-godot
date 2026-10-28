# R36 雷达后台切片解码

基线 `a1d090d`，分支 `perf/radar-layer-streaming`。上批真实三图26张切片的同步冷加载最高48.426ms，包含文件读取、哈希与PNG解码。本批把这三项移到单独线程；线程只生成Image，ImageTexture创建仍在HUD主线程，未改原图、派生底图或生成器。

`select_layer()` 在未缓存时提交请求并返回空结果，由现有旧线框底图回退承接；之后轮询已结束线程才上传纹理，不在每帧等待线程。最多两份已上传纹理和一份待处理解码Image。地图generation和切片request_serial共同绑定结果；换层或同ID重载时旧结果被丢弃，不向新地图或错误楼层发布。PREDELETE等待两个线程收尾，因而销毁时仍可能等待正在进行的磁盘/CPU任务；并非完全异步关闭。

后台读取同一份字节进行SHA256和PNG解码，避免哈希与解码重新读文件之间的差异；缺失/哈希错继续texture_identity_mismatch，解码错误继续texture_unreadable。直接解码原PNG字节也避开Image.load_from_file的导出路径警告，但原始PNG仍须显式打包，并在实际PCK验证。

定向原生171项通过，涵盖三图全部切片、首次请求空结果、缓存上限、切片请求被新请求替代、解码中同ID重载、旧身份校验结果隔离和错误哈希回退。输出无SCRIPT ERROR/ERROR。gdformat检查与gdlint零问题。证据：`D:/AgentGamePipeline/evidence/radar-layer-streaming-20261028/radar/focused.log`、`timings.json`、`summary.json`。不运行全套，整合全套由根任务执行。

本机headless微测量，单位µs，单次跑26张切片最大值：

|地图|首次请求|主线程轮询含纹理创建|缓存命中|
|---|---:|---:|---:|
|Dust II|237|452|46|
|Mirage|96|489|16|
|Inferno|83|476|11|

后台解码耗时仍存在；加载期间回退显示，首次可见底图延迟未消除。上表不是GPU上传成本或三图70%帧率证明；Vulkan真实上传/切层帧时间、低内存与慢盘、快速反复换层、三图实走楼层边界和实际包完整性仍待验。旧层不会被错误展示为当前层。该片不发布新包、不改变正式Current。

Mirage Vulkan探针初次因仅等待source-ready而早退，作者探针已改为同时等待atlas_layer>=0；重跑EXIT0、REAL_RADAR_VULKAN_OK，截图mirage-stream.png已亲自查看，底图/标记正常。该测试入口修复不改变运行时行为。详细记录radar/vulkan-result.json。
