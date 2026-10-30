# R49 雷达原文件与导出资源共存

R48发现实际新包import字节与旧收据不一致；此外，保留raw支持文件时，RadarAtlas原逻辑直接要求原作者import SHA，无法接受合法导出remap。此次只修改RadarAtlas身份判断，不删除raw，不弱化原内容检查。

作者模式（raw存在且无export_identity）继续要求原作者import摘要，并异步验证原raw SHA。有export_identity或缺raw时，必须通过既有严格export合同：source、source SHA、作者import SHA、level SHA与atlas字段匹配，atlas字节SHA、实际shipped-import SHA、实际remap路径和compiled路径/摘要由收据绑定。load_level仍先核对真实level JSON及runtime_collision_scene，不接受任意目标替换。

raw与合法导出remap共存时，异步同时哈希raw及compiled；任一内容不符均拒绝。不能因为raw篡改而退到compiled，也不能因raw正确而忽略compiled篡改。验证结束再次检查当前import摘要与开始时严格验证过的摘要相同。原图切换level/generation线程隔离保持。

新增独立作者测试`tools/authoring/test_radar_raw_export_contract.gd`，14项真实临时文件合同检查：作者raw、raw+导出共存、raw篡改、compiled篡改、八个收据绑定字段篡改、compiled-only成功/篡改拒绝。相同fixture加载旧HEAD脚本红退出1（raw+导出共存失败），候选绿退出0；生产源码从未临时还原成旧版。临时文件仅用于内容/绑定检查，不声称是有效可加载场景或GPU显示证据。

证据：`D:/AgentGamePipeline/evidence/r49-20261031/runtime/{red.log,green.log,baseline_RadarAtlas.gd,run_contract.py}`。新/改GDS格式及lint通过。原生完整套件、实际导出及Vulkan雷达可见性由父批统一执行；此处不把身份fixture声称为实际新包显示验收。未改原版资源、地图几何、Current参数或旧冻结作者工具。
