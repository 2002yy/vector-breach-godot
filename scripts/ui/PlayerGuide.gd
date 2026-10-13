extends RefCounted

const CONTROLS := "WASD 移动 · 鼠标瞄准 / 左键射击\nShift 静步 · Ctrl 蹲伏 · 空格跳跃\n1 步枪 · 2 手枪 · 3 刀 · 4 切换投掷物\nR 换弹 · G 丢弃 · E 拾取 / 按住安装或拆弹\nB 购买（出生区准备阶段）· Tab 计分板\nEsc 暂停菜单 · F 全屏 · F1 操作帮助"
const MATCH_RULES := "门厅区：你 + 两名队友，对抗三名敌人。\n首局 / 换边后：双方均为手枪 + $800。\n步枪 $2700，攒钱后在准备阶段按 B，再按 1。\n进攻方带炸弹前往 A / B 区，按住 E 安装；\n防守方阻止安装，或到炸弹旁按住 E 拆除。"
const PRACTICE_RULES := "练习地图开局配有步枪和手枪，按 1 / 2 切换。\n铸造厂·重构用于练习与画面展示，\n其余历史 / 测试地图不代表完整平衡比赛。"
const RESEARCH_RULES := "经典 CS 研究图：自由探索、练枪与碰撞研究。\n开局配有步枪和手枪，按 1 / 2 切换。\n有可受击练习靶；尚未配置完整爆破 AI。\n原始材质版保留本机参考资源。"


static func weapon_name(weapon_id: String) -> String:
	return String(
		(
			{
				"rifle": "步枪",
				"pistol": "手枪",
				"knife": "战术刀",
				"he_grenade": "高爆手雷",
				"flash_grenade": "闪光弹",
				"smoke_grenade": "烟雾弹"
			}
			. get(weapon_id, weapon_id)
		)
	)
