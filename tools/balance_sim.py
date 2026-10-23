#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Star Abyss 数值模拟器  (tools/balance_sim.py)
==============================================
纯 Python3 标准库，无第三方依赖，固定随机种子，输出完全确定性。
本机控制台是 GBK，因此【不】向 stdout 打印中文正文，只把报告写成 UTF-8 文件：
    .local/balance_sim_out.txt   (相对工程根目录 StarAbyss/)

模拟内容
  1) 单哨兵 TTK：只普攻 / 普攻+技能(最优循环)
  2) Boss 星核守卫 TTK：只普攻 / 普攻+技能(最优循环)
  3) 3 个祝福（烈焰之刃 / 生命共鸣 / 疾风步伐）对「哨兵 TTK」「Boss TTK」「存活能力」的增益百分比
  4) 2 哨兵 vs 3 哨兵场景下玩家预期存活/清场情况（含闪避无敌帧覆盖率与受击概率）

全部输入的数值来源（均为已核实资源文件，不在此重复猜测）：
  godot/resources/combat/attack_01.tres       damage=12 duration=0.48 hit[0.16,0.28)
  godot/resources/combat/attack_02.tres       damage=16 duration=0.56 hit[0.20,0.34)
  godot/resources/combat/attack_03.tres       damage=24 duration=0.72 hit[0.25,0.44)
  godot/resources/combat/star_blade.tres      damage=35 duration=0.70 hit[0.25,0.40) reach=5.0 arc=70
  godot/resources/combat/default_player_combat.tres  skill_cooldown=8.0 (经 combat_rules_test 断言)
  godot/resources/enemies/default_sentinel.tres      hp=45 speed=3.2 detect=10 trigger=1.8 atk_cd=1.3
  godot/resources/enemies/sentinel_slash.tres        damage=10 duration=1.28 hit[0.55,0.73) reach=1.8 arc=100
  godot/resources/boss/default_guardian.tres         hp=350 speed=2.6 trigger=2.5 waiting=3.6 gap=[1.6,2.4]
  godot/resources/boss/guardian_sweep.tres           damage=20 duration=1.67 hit[0.80,1.02) reach=2.8 arc=130
  godot/resources/boss/guardian_shockwave.tres       damage=25 duration=2.20 hit[1.20,1.40) reach=4.2 arc=360
  闪避：duration=0.45 invuln=[0.10,0.30) cd=1.20（疾风步伐 → 0.90，blessing_rules_test 断言）
  玩家 HP=100；生命共鸣 +20 上限、普通敌人击杀回 5（blessing_rules_test 断言）
  烈焰之刃：普攻 ×1.20，逐段 roundi → 14/19/29，技能不受影响（blessing_rules_test 断言）

模型假设（脚本内可调，文档中逐条标注为「模型假设」）：
  A1 玩家为贴身近战，攻击判定必然命中当前目标（不含未命中的位移误差）。
  A2 连招无输入空档：每段 duration 结束后立刻接下一段；三段打完回到第 1 段。
  A3 技能不推进也不重置连招段数（star_blade 的 combo_open/close 均为 0.70，无连段语义）。
  A4 技能的冷却自「技能动作开始」起算 8.0 s。
  A5 命中时刻 = 动作开始 + hit_start；DPS 统计按动作开始计时（保守，忽略命中延迟）。
  A6 玩家对每次敌人攻击的反应时 r ~ N(0.32, 0.10) 截断到 [0.10, 0.65]（模型假设，需真实玩家数据校准）。
  A7 闪避只有 [开始+0.10, 开始+0.30) 期间无敌，且从闪避开始计冷却。
  A8 闪避期间玩家不输出（0.45 s 空转），换目标移动耗时 0.55 s（模型假设）。
  A9 未建模受击保护帧(post-hit protection)、硬直位移与击退（偏保守，见文档「需要真实玩家数据」）。
  A10 哨兵彼此独立按 攻击1.28 s + 冷却1.30 s = 2.58 s 周期循环出手，初始相位错开 0.35 s。
  A11 Boss 交替使用横扫/冲击，招式结束后等待 U(1.6, 2.4) s 再起手。
"""

import math
import random
from pathlib import Path

# ----------------------------------------------------------------------------
# 全局模拟配置
# ----------------------------------------------------------------------------
SEED = 20261023
TRIALS = 600
DT = 0.02
TIME_CAP = 40.0          # 单个房间模拟的最长时长（秒）
OUT_PATH = Path(__file__).resolve().parent.parent / ".local" / "balance_sim_out.txt"

# ----------------------------------------------------------------------------
# 输入数值（全部来自 .tres，见文件头注释）
# ----------------------------------------------------------------------------
PLAYER_HP = 100.0
GRAVITY = 18.0

ATTACKS = [
    {"name": "attack_01", "damage": 12.0, "duration": 0.48, "hit_start": 0.16, "hit_end": 0.28},
    {"name": "attack_02", "damage": 16.0, "duration": 0.56, "hit_start": 0.20, "hit_end": 0.34},
    {"name": "attack_03", "damage": 24.0, "duration": 0.72, "hit_start": 0.25, "hit_end": 0.44},
]
COMBO_CYCLE = sum(a["duration"] for a in ATTACKS)          # 1.76 s
COMBO_DAMAGE = sum(a["damage"] for a in ATTACKS)           # 52

SKILL = {"damage": 35.0, "duration": 0.70, "hit_start": 0.25, "hit_end": 0.40,
         "cd": 8.0, "reach": 5.0, "arc": 70.0}

DODGE = {"duration": 0.45, "inv_start": 0.10, "inv_end": 0.30, "cd": 1.2}
DODGE_CD_WIND = 0.9

SENTINEL = {"hp": 45.0, "speed": 3.2, "detect": 10.0, "trigger": 1.8, "atk_cd": 1.3,
            "attack": {"damage": 10.0, "duration": 1.28, "hit_start": 0.55, "hit_end": 0.73,
                       "reach": 1.8, "arc": 100.0}}

GUARDIAN = {"hp": 350.0, "speed": 2.6, "detect": 30.0, "trigger": 2.5, "waiting": 3.6,
            "gap_min": 1.6, "gap_max": 2.4,
            "sweep": {"damage": 20.0, "duration": 1.67, "hit_start": 0.80, "hit_end": 1.02,
                      "reach": 2.8, "arc": 130.0},
            "shockwave": {"damage": 25.0, "duration": 2.20, "hit_start": 1.20, "hit_end": 1.40,
                          "reach": 4.2, "arc": 360.0}}

# 祝福
FLAME_MULT = 1.20
VITALITY_MAX_HP_BONUS = 20.0
VITALITY_KILL_HEAL = 5.0
BLESSINGS = ["none", "flame", "vitality", "wind"]
BLESSING_LABEL = {"none": "无祝福(基线)", "flame": "烈焰之刃", "vitality": "生命共鸣", "wind": "疾风步伐"}

# 模型假设参数（A6-A10）
REACTION_MEAN = 0.32
REACTION_SD = 0.10
REACTION_MIN = 0.10
REACTION_MAX = 0.65
TARGET_SWITCH_TIME = 0.55
SENTINEL_PHASE_STEP = 0.35
BOSS_FIRST_ATTACK_AT = 1.2


def roundi(value: float) -> int:
    """与 Godot roundi() 一致的「四舍五入，远离零」行为（仅用于正数）。"""
    return int(math.floor(value + 0.5))


# ----------------------------------------------------------------------------
# 1) 伤害时间轴 / TTK
# ----------------------------------------------------------------------------
def optimal_ttk(target_hp: float, normal_mult: float, allow_skill: bool):
    """在 A1-A5 假设下用深度优先搜索求「最短击杀时刻」的最优动作序列。

    返回 (ttk, actions) —— actions 是 (开始时刻, 动作名, 命中时刻, 伤害) 列表。
    """
    best = {"ttk": float("inf"), "plan": None}
    node_budget = [200000]

    def dfs(t: float, idx: int, skill_ready: float, dealt: float, plan: list):
        if node_budget[0] <= 0 or t >= best["ttk"] or t > 200.0:
            return
        node_budget[0] -= 1
        # 分支一：打下一段普攻
        atk = ATTACKS[idx]
        dmg = roundi(atk["damage"] * normal_mult)
        hit = t + atk["hit_start"]
        nd = dealt + dmg
        plan.append((t, atk["name"], hit, dmg))
        if nd >= target_hp:
            if hit < best["ttk"]:
                best["ttk"] = hit
                best["plan"] = list(plan)
        else:
            dfs(t + atk["duration"], (idx + 1) % 3, skill_ready, nd, plan)
        plan.pop()
        # 分支二：放技能（若冷却好）
        if allow_skill and t + 1e-9 >= skill_ready:
            hit = t + SKILL["hit_start"]
            nd2 = dealt + SKILL["damage"]
            plan.append((t, "skill", hit, SKILL["damage"]))
            if nd2 >= target_hp:
                if hit < best["ttk"]:
                    best["ttk"] = hit
                    best["plan"] = list(plan)
            else:
                dfs(t + SKILL["duration"], idx, t + SKILL["cd"], nd2, plan)
            plan.pop()

    dfs(0.0, 0, 0.0, 0.0, [])
    if best["plan"] is None:
        return None, []
    # 只保留到击杀为止的动作
    plan = []
    dealt = 0.0
    for start, name, hit, dmg in best["plan"]:
        plan.append((start, name, hit, dmg))
        dealt += dmg
        if dealt >= target_hp:
            break
    return best["ttk"], plan


def greedy_hit_count(target_hp: float, normal_mult: float) -> int:
    """只普攻时击杀需要的命中次数。"""
    dealt = 0.0
    for i in range(60):
        dealt += roundi(ATTACKS[i % 3]["damage"] * normal_mult)
        if dealt >= target_hp:
            return i + 1
    return -1


def sustained_dps(horizon: float, normal_mult: float, use_skill: bool = True) -> float:
    """持续输出 DPS：技能好了就放，否则连招（A2/A4，动作开始计时）。"""
    t, idx, skill_ready, dmg = 0.0, 0, 0.0, 0.0
    while t < horizon:
        if use_skill and t + 1e-9 >= skill_ready:
            dmg += SKILL["damage"]
            t += SKILL["duration"]
            skill_ready = t - SKILL["duration"] + SKILL["cd"]
        else:
            atk = ATTACKS[idx]
            dmg += roundi(atk["damage"] * normal_mult)
            t += atk["duration"]
            idx = (idx + 1) % 3
    return dmg / horizon


def dodge_uptime(cd: float) -> float:
    """无敌帧理论覆盖率 = 无敌时长 / 闪避冷却。"""
    return (DODGE["inv_end"] - DODGE["inv_start"]) / cd


# ----------------------------------------------------------------------------
# 2) 房间级存活模拟（离散时间步，蒙特卡洛，共用随机数）
# ----------------------------------------------------------------------------
def _draw_reaction(rng: random.Random) -> float:
    """A6：反应时截断正态。"""
    while True:
        r = rng.gauss(REACTION_MEAN, REACTION_SD)
        if REACTION_MIN <= r <= REACTION_MAX:
            return r


def simulate_room(kind: str, count: int, blessing: str, trials: int = TRIALS,
                  seed: int = SEED, dodge_enabled: bool = True, time_cap: float = TIME_CAP):
    """模拟一个房间，返回指标字典。

    kind: "sentinel" | "boss"
    blessing: "none" | "flame" | "vitality" | "wind"
    """
    normal_mult = FLAME_MULT if blessing == "flame" else 1.0
    max_hp = PLAYER_HP + (VITALITY_MAX_HP_BONUS if blessing == "vitality" else 0.0)
    dodge_cd = DODGE_CD_WIND if blessing == "wind" else DODGE["cd"]
    dps = sustained_dps(60.0, normal_mult, use_skill=True)

    total_enemy_hp = (SENTINEL["hp"] * count) if kind == "sentinel" else GUARDIAN["hp"]

    deaths = 0
    death_times = []
    clear_times = []
    hp_left_on_clear = []
    hp_lost_all = []
    hits_taken = 0
    hits_total = 0
    dodges_committed = 0

    for trial in range(trials):
        rng = random.Random(seed * 7919 + trial)   # 共用随机数：不同祝福变体同一 trial 序列
        hp = max_hp
        t = 0.0
        invuln = []            # [(start, end)]
        dodging = []           # [(start, end)] 闪避动作占用
        dodge_ready = 0.0
        travel_left = 0.0
        t_hits_taken = 0
        t_hits_total = 0

        if kind == "sentinel":
            enemies = []
            for i in range(count):
                enemies.append({
                    "hp": SENTINEL["hp"],
                    "next_start": SENTINEL_PHASE_STEP * i,
                    "pending": None,     # (hit_start, hit_end, damage)
                })
            period = SENTINEL["attack"]["duration"] + SENTINEL["atk_cd"]
        else:
            enemies = [{"hp": GUARDIAN["hp"], "next_start": BOSS_FIRST_ATTACK_AT,
                        "pending": None, "cycle": 0}]

        def alive(enemy_list):
            return [e for e in enemy_list if e["hp"] > 0.0]

        def current_target(enemy_list):
            for e in enemy_list:
                if e["hp"] > 0.0:
                    return e
            return None

        outcome = None  # "death" | "clear"
        while t < time_cap:
            t += DT
            # ---- 敌人出手排程 ----
            for e in enemies:
                if e["hp"] <= 0.0:
                    continue
                if e["next_start"] is not None and t >= e["next_start"] and e["pending"] is None:
                    if kind == "sentinel":
                        atk = SENTINEL["attack"]
                        nxt = e["next_start"] + period
                        gap = 0.0
                    else:
                        if e["cycle"] % 2 == 0:
                            atk = GUARDIAN["sweep"]
                        else:
                            atk = GUARDIAN["shockwave"]
                        e["cycle"] += 1
                        gap = rng.uniform(GUARDIAN["gap_min"], GUARDIAN["gap_max"])
                        nxt = e["next_start"] + atk["duration"] + gap
                    start = t
                    hs = start + atk["hit_start"]
                    he = start + atk["hit_end"]
                    e["pending"] = (hs, he, atk["damage"])
                    e["next_start"] = nxt
                    # 玩家对本次起手的反应（在起手瞬间就规划一次闪避）
                    if dodge_enabled:
                        plan = max(start + _draw_reaction(rng), dodge_ready)
                        if plan < he:
                            invuln.append((plan + DODGE["inv_start"], plan + DODGE["inv_end"]))
                            dodging.append((plan, plan + DODGE["duration"]))
                            dodge_ready = plan + dodge_cd
                            if blessing == "wind":
                                pass
                # ---- 命中结算 ----
                if e["pending"] is not None and t >= e["pending"][1]:
                    hs, he, dmg = e["pending"]
                    e["pending"] = None
                    t_hits_total += 1
                    dodged = any(a < he and b > hs for a, b in invuln)
                    if dodged:
                        pass
                    else:
                        t_hits_taken += 1
                        hp -= dmg
                        if hp <= 0.0:
                            hp = 0.0
                            outcome = "death"
                            break
            if outcome == "death":
                break
            # ---- 玩家输出 ----
            busy_dodge = any(a <= t < b for a, b in dodging)
            if travel_left > 1e-9:
                travel_left -= DT
            elif not busy_dodge:
                tgt = current_target(enemies)
                if tgt is None:
                    outcome = "clear"
                    break
                tgt["hp"] -= dps * DT
                if tgt["hp"] <= 0.0:
                    tgt["hp"] = 0.0
                    if blessing == "vitality" and kind == "sentinel":
                        hp = min(max_hp, hp + VITALITY_KILL_HEAL)
                    if current_target(enemies) is None:
                        outcome = "clear"
                        break
                    travel_left = TARGET_SWITCH_TIME
            if not alive(enemies):
                outcome = "clear"
                break
        # ---- 记录 ----
        hits_taken += t_hits_taken
        hits_total += t_hits_total
        hp_lost_all.append(max_hp - hp)
        if outcome == "death":
            deaths += 1
            death_times.append(t)
        elif outcome == "clear":
            clear_times.append(t)
            hp_left_on_clear.append(hp)
        else:
            # 超时未分胜负：按存活到上限处理
            clear_times.append(time_cap)
            hp_left_on_clear.append(hp)

    def mean(xs):
        return sum(xs) / len(xs) if xs else 0.0

    return {
        "kind": kind,
        "count": count,
        "blessing": blessing,
        "dodge_enabled": dodge_enabled,
        "max_hp": max_hp,
        "dps": dps,
        "sustained_dps_60s": sustained_dps(60.0, normal_mult, use_skill=True),
        "dps_no_skill": sustained_dps(60.0, normal_mult, use_skill=False),
        "dodge_cd": dodge_cd,
        "invuln_uptime": dodge_uptime(dodge_cd),
        "death_rate": deaths / trials,
        "mean_death_time": mean(death_times),
        "mean_room_time": mean(clear_times + death_times),
        "mean_clear_time": mean(clear_times),
        "mean_hp_left_on_clear": mean(hp_left_on_clear),
        "mean_hp_lost": mean(hp_lost_all),
        "hit_rate": (hits_taken / hits_total) if hits_total else 0.0,
        "dodge_success_rate": (1.0 - hits_taken / hits_total) if hits_total else 0.0,
        "hits_taken_per_trial": hits_taken / trials,
        "total_enemy_hp": total_enemy_hp,
    }


# ----------------------------------------------------------------------------
# 3) 报告生成
# ----------------------------------------------------------------------------
def fmt(x, nd=3):
    if isinstance(x, float):
        return f"{x:.{nd}f}"
    return str(x)


def pct(new: float, base: float) -> float:
    if abs(base) < 1e-12:
        return 0.0
    return (new - base) / base * 100.0


def main() -> int:
    lines = []

    def w(s=""):
        lines.append(s)

    w("=" * 78)
    w("Star Abyss 数值模拟报告 —— tools/balance_sim.py")
    w("=" * 78)
    w(f"确定性参数: SEED={SEED}  TRIALS={TRIALS}  DT={DT}s  TIME_CAP={TIME_CAP}s")
    w("本文件由脚本生成，文档中所有模拟数字均须引用本文件真实输出。")
    w("")
    w("[0] 输入数值（来源 .tres / 测试断言）")
    w("-" * 78)
    for i, a in enumerate(ATTACKS):
        w(f"  普攻{i+1} {a['name']:<9} 伤害={a['damage']:>5.1f} 时长={a['duration']:.2f}s "
          f"命中窗口=[{a['hit_start']:.2f},{a['hit_end']:.2f})")
    w(f"  连招一轮: 时长={COMBO_CYCLE:.2f}s 总伤害={COMBO_DAMAGE:.0f} "
      f"→ 连招循环 DPS={COMBO_DAMAGE/COMBO_CYCLE:.3f}")
    w(f"  技能 星刃斩: 伤害={SKILL['damage']:.0f} 时长={SKILL['duration']:.2f}s "
      f"命中=[{SKILL['hit_start']:.2f},{SKILL['hit_end']:.2f}) CD={SKILL['cd']:.1f}s "
      f"射程={SKILL['reach']:.0f}m 扇形={SKILL['arc']:.0f}°")
    w(f"  闪避: 时长={DODGE['duration']:.2f}s 无敌=[{DODGE['inv_start']:.2f},{DODGE['inv_end']:.2f}) "
      f"CD={DODGE['cd']:.1f}s → 无敌覆盖率={dodge_uptime(DODGE['cd'])*100:.2f}%")
    w(f"        疾风步伐 CD={DODGE_CD_WIND:.1f}s → 无敌覆盖率={dodge_uptime(DODGE_CD_WIND)*100:.2f}%")
    w(f"  哨兵: HP={SENTINEL['hp']:.0f} 攻击伤害={SENTINEL['attack']['damage']:.0f} "
      f"时长={SENTINEL['attack']['duration']:.2f}s 命中=[{SENTINEL['attack']['hit_start']:.2f},"
      f"{SENTINEL['attack']['hit_end']:.2f}) CD={SENTINEL['atk_cd']:.1f}s "
      f"出手周期={SENTINEL['attack']['duration']+SENTINEL['atk_cd']:.2f}s")
    w(f"  Boss: HP={GUARDIAN['hp']:.0f} 横扫={GUARDIAN['sweep']['damage']:.0f}伤/"
      f"{GUARDIAN['sweep']['duration']:.2f}s(命中[{GUARDIAN['sweep']['hit_start']:.2f},"
      f"{GUARDIAN['sweep']['hit_end']:.2f})) 冲击={GUARDIAN['shockwave']['damage']:.0f}伤/"
      f"{GUARDIAN['shockwave']['duration']:.2f}s(命中[{GUARDIAN['shockwave']['hit_start']:.2f},"
      f"{GUARDIAN['shockwave']['hit_end']:.2f})) 间隔=[{GUARDIAN['gap_min']:.1f},"
      f"{GUARDIAN['gap_max']:.1f}]s")
    w("")

    # ---------------- [1] 单哨兵 TTK ----------------
    w("[1] 单哨兵 TTK（HP=45，无闪避空转的理想循环）")
    w("-" * 78)
    sent_hp = SENTINEL["hp"]
    rows_sent = {}
    for b in BLESSINGS:
        mult = FLAME_MULT if b == "flame" else 1.0
        ttk_atk, plan_atk = optimal_ttk(sent_hp, mult, allow_skill=False)
        ttk_both, plan_both = optimal_ttk(sent_hp, mult, allow_skill=True)
        hits = greedy_hit_count(sent_hp, mult)
        rows_sent[b] = {"ttk_atk": ttk_atk, "ttk_both": ttk_both, "hits": hits,
                        "plan_atk": plan_atk, "plan_both": plan_both,
                        "mult": mult}
        skill_cnt = sum(1 for p in plan_both if p[1] == "skill")
        w(f"  {BLESSING_LABEL[b]:<10} 只普攻 TTK={ttk_atk:.3f}s (命中{hits}次，普攻倍率×{mult:.2f})"
          f"   |   普攻+技能 TTK={ttk_both:.3f}s (技能{skill_cnt}次)")
        seq = " → ".join(f"{n}@{h:.2f}s({d:g})" for _, n, h, d in plan_both)
        w(f"      最优序列: {seq}")
    w("")

    # ---------------- [2] Boss TTK ----------------
    w("[2] Boss 星核守卫 TTK（HP=350）")
    w("-" * 78)
    boss_hp = GUARDIAN["hp"]
    rows_boss = {}
    for b in BLESSINGS:
        mult = FLAME_MULT if b == "flame" else 1.0
        ttk_atk, plan_atk = optimal_ttk(boss_hp, mult, allow_skill=False)
        ttk_both, plan_both = optimal_ttk(boss_hp, mult, allow_skill=True)
        skill_cnt = sum(1 for p in plan_both if p[1] == "skill")
        rows_boss[b] = {"ttk_atk": ttk_atk, "ttk_both": ttk_both, "skill_cnt": skill_cnt,
                        "mult": mult}
        w(f"  {BLESSING_LABEL[b]:<10} 只普攻 TTK={ttk_atk:.3f}s   |   普攻+技能 TTK={ttk_both:.3f}s"
          f" (技能{skill_cnt}次，循环耗时{len(plan_both)}个动作)")
    w("")
    w("  持续 DPS（60s 窗口，技能好了即放；不含闪避空转与走位）")
    for b in BLESSINGS:
        mult = FLAME_MULT if b == "flame" else 1.0
        w(f"    {BLESSING_LABEL[b]:<10} 含技能 DPS={sustained_dps(60.0, mult, True):.3f}   "
          f"只普攻 DPS={sustained_dps(60.0, mult, False):.3f}")
    w("")

    # ---------------- [3] 房间存活模拟 ----------------
    scenarios = [("sentinel", 2), ("sentinel", 3), ("boss", 1)]
    results = {}
    for kind, count in scenarios:
        for b in BLESSINGS:
            results[(kind, count, b)] = simulate_room(kind, count, b)
    # 不闪避对照组
    nodge = {
        ("sentinel", 2): simulate_room("sentinel", 2, "none", dodge_enabled=False),
        ("sentinel", 3): simulate_room("sentinel", 3, "none", dodge_enabled=False),
        ("boss", 1): simulate_room("boss", 1, "none", dodge_enabled=False),
    }

    def scenario_title(kind, count):
        if kind == "sentinel":
            return f"{count} 哨兵房（{int(SENTINEL['hp'])*count} 点敌方总血量）"
        return "Boss 房（晶核守卫 350 HP）"

    for kind, count in scenarios:
        w(f"[3] {scenario_title(kind, count)} —— 存活模拟（{TRIALS} 次试验，共用随机数）")
        w("-" * 78)
        w("  祝福          玩家HP  闪避CD  无敌覆盖   阵亡率    平均阵亡时刻  平均清场耗时  "
          "清场剩余HP  平均损失HP  受击概率  闪避成功率")
        for b in BLESSINGS:
            r = results[(kind, count, b)]
            w(f"  {BLESSING_LABEL[b]:<10}  {r['max_hp']:>6.0f}  {r['dodge_cd']:>6.2f}  "
              f"{r['invuln_uptime']*100:>7.2f}%  {r['death_rate']*100:>6.1f}%  "
              f"{r['mean_death_time']:>11.2f}s  {r['mean_clear_time']:>10.2f}s  "
              f"{r['mean_hp_left_on_clear']:>9.1f}  {r['mean_hp_lost']:>9.1f}  "
              f"{r['hit_rate']*100:>7.1f}%  {r['dodge_success_rate']*100:>8.1f}%")
        rn = nodge[(kind, count)]
        w(f"  {'完全不用闪避':<10}  {rn['max_hp']:>6.0f}  {'--':>6}  {'0.00%':>7}  "
          f"{rn['death_rate']*100:>6.1f}%  {rn['mean_death_time']:>11.2f}s  "
          f"{rn['mean_clear_time']:>10.2f}s  {rn['mean_hp_left_on_clear']:>9.1f}  "
          f"{rn['mean_hp_lost']:>9.1f}  {rn['hit_rate']*100:>7.1f}%  {'0.0%':>8}")
        w("")

    # ---------------- [4] 祝福增益对比 ----------------
    w("[4] 三个祝福的量化对比（增益百分比，基线 = 无祝福）")
    w("-" * 78)
    w("  说明: TTK 增益 = (基线TTK - 祝福TTK)/基线TTK；为负表示变慢。")
    w("        生存增益 = (基线平均损失HP - 祝福平均损失HP)/基线平均损失HP。")
    w("")
    base_sent_ttk = rows_sent["none"]["ttk_both"]
    base_sent_ttk_atk = rows_sent["none"]["ttk_atk"]
    base_boss_ttk = rows_boss["none"]["ttk_both"]
    base_boss_ttk_atk = rows_boss["none"]["ttk_atk"]
    w("  (a) TTK 层面")
    w("  祝福        哨兵TTK(只普攻) 增益%   哨兵TTK(含技能) 增益%   "
      "BossTTK(只普攻) 增益%  BossTTK(含技能) 增益%")
    gain_table = {}
    for b in BLESSINGS:
        rs, rb = rows_sent[b], rows_boss[b]
        g_atk = pct(rs["ttk_atk"], base_sent_ttk_atk)
        g_both = pct(rs["ttk_both"], base_sent_ttk)
        gb_atk = pct(rb["ttk_atk"], base_boss_ttk_atk)
        gb_both = pct(rb["ttk_both"], base_boss_ttk)
        gain_table[b] = {"sent_atk": g_atk, "sent_both": g_both,
                         "boss_atk": gb_atk, "boss_both": gb_both}
        w(f"  {BLESSING_LABEL[b]:<10} {rs['ttk_atk']:>9.3f}s {g_atk:>9.2f}%  "
          f"{rs['ttk_both']:>9.3f}s {g_both:>9.2f}%   "
          f"{rb['ttk_atk']:>9.3f}s {gb_atk:>9.2f}%  {rb['ttk_both']:>9.3f}s {gb_both:>9.2f}%")
    w("")
    w("  (b) 生存层面（平均损失 HP 与阵亡率）")
    w("  祝福        2哨兵损失HP  生存增益%   3哨兵损失HP  生存增益%   Boss损失HP  生存增益%   "
      "2哨兵阵亡率  3哨兵阵亡率  Boss阵亡率")
    surv_gain = {}
    for b in BLESSINGS:
        r2 = results[("sentinel", 2, b)]
        r3 = results[("sentinel", 3, b)]
        rb = results[("boss", 1, b)]
        b2 = results[("sentinel", 2, "none")]["mean_hp_lost"]
        b3 = results[("sentinel", 3, "none")]["mean_hp_lost"]
        bb = results[("boss", 1, "none")]["mean_hp_lost"]
        surv_gain[b] = {"s2": pct(b2, r2["mean_hp_lost"]),   # 注意方向：损失变小 = 正增益
                        "s3": pct(b3, r3["mean_hp_lost"]),
                        "boss": pct(bb, rb["mean_hp_lost"])}
        # pct 方向修正：损失越小越好
        surv_gain[b]["s2"] = -surv_gain[b]["s2"]
        surv_gain[b]["s3"] = -surv_gain[b]["s3"]
        surv_gain[b]["boss"] = -surv_gain[b]["boss"]
        w(f"  {BLESSING_LABEL[b]:<10} {r2['mean_hp_lost']:>10.1f} {surv_gain[b]['s2']:>9.2f}%  "
          f"{r3['mean_hp_lost']:>10.1f} {surv_gain[b]['s3']:>9.2f}%  "
          f"{rb['mean_hp_lost']:>9.1f} {surv_gain[b]['boss']:>9.2f}%   "
          f"{r2['death_rate']*100:>9.1f}%  {r3['death_rate']*100:>9.1f}%  {rb['death_rate']*100:>8.1f}%")
    w("")

    # ---------------- [5] 2 vs 3 哨兵 ----------------
    w("[5] 2 哨兵 vs 3 哨兵：预期存活 / 清场曲线")
    w("-" * 78)
    w("  指标                2哨兵(基线)   3哨兵(基线)   3/2 倍数")
    r2 = results[("sentinel", 2, "none")]
    r3 = results[("sentinel", 3, "none")]
    def ratio(a, b):
        return (a / b) if abs(b) > 1e-12 else 0.0
    w(f"  平均房间耗时        {r2['mean_clear_time']:>10.2f}s  {r3['mean_clear_time']:>10.2f}s  "
      f"{ratio(r3['mean_clear_time'], r2['mean_clear_time']):>8.2f}x")
    w(f"  平均受击次数/局     {r2['hits_taken_per_trial']:>10.2f}   {r3['hits_taken_per_trial']:>10.2f}   "
      f"{ratio(r3['hits_taken_per_trial'], r2['hits_taken_per_trial']):>8.2f}x")
    w(f"  平均损失 HP         {r2['mean_hp_lost']:>10.1f}   {r3['mean_hp_lost']:>10.1f}   "
      f"{ratio(r3['mean_hp_lost'], r2['mean_hp_lost']):>8.2f}x")
    w(f"  受击概率(单次攻击)  {r2['hit_rate']*100:>9.1f}%   {r3['hit_rate']*100:>9.1f}%   "
      f"{ratio(r3['hit_rate'], r2['hit_rate']):>8.2f}x")
    w(f"  闪避成功率          {r2['dodge_success_rate']*100:>9.1f}%   {r3['dodge_success_rate']*100:>9.1f}%   "
      f"{ratio(r3['dodge_success_rate'], r2['dodge_success_rate']):>8.2f}x")
    w(f"  阵亡率              {r2['death_rate']*100:>9.1f}%   {r3['death_rate']*100:>9.1f}%")
    w(f"  不用闪避·3哨兵损失HP {nodge[('sentinel',3)]['mean_hp_lost']:>10.1f}   "
      f"阵亡率 {nodge[('sentinel',3)]['death_rate']*100:.1f}%   "
      f"（对比用闪避：{r3['mean_hp_lost']:.1f} / {r3['death_rate']*100:.1f}%）")
    w("")

    # ---------------- [6] 关键数字摘要 ----------------
    w("[6] 关键数字摘要（供文档引用）")
    w("-" * 78)
    k1 = rows_sent["none"]["ttk_atk"]
    k2 = rows_sent["none"]["ttk_both"]
    k3 = rows_boss["none"]["ttk_both"]
    key = {
        "sentinel_ttk_attack_only": k1,
        "sentinel_ttk_with_skill": k2,
        "boss_ttk_attack_only": rows_boss["none"]["ttk_atk"],
        "boss_ttk_with_skill": k3,
        "combo_cycle_dps": COMBO_DAMAGE / COMBO_CYCLE,
        "dps_with_skill_60s": sustained_dps(60.0, 1.0, True),
        "flame_sentinel_ttk_gain_pct": gain_table["flame"]["sent_atk"],
        "flame_boss_ttk_gain_pct": gain_table["flame"]["boss_both"],
        "wind_sentinel_ttk_gain_pct": gain_table["wind"]["sent_atk"],
        "vitality_boss_ttk_gain_pct": gain_table["vitality"]["boss_both"],
        "dodge_uptime_base_pct": dodge_uptime(DODGE["cd"]) * 100.0,
        "dodge_uptime_wind_pct": dodge_uptime(DODGE_CD_WIND) * 100.0,
        "s2_hp_lost_base": results[("sentinel", 2, "none")]["mean_hp_lost"],
        "s3_hp_lost_base": results[("sentinel", 3, "none")]["mean_hp_lost"],
        "boss_hp_lost_base": results[("boss", 1, "none")]["mean_hp_lost"],
        "boss_death_rate_base_pct": results[("boss", 1, "none")]["death_rate"] * 100.0,
        "s3_death_rate_base_pct": results[("sentinel", 3, "none")]["death_rate"] * 100.0,
        "sentinel_room_clear_time_s3": results[("sentinel", 3, "none")]["mean_clear_time"],
        "boss_room_clear_time": results[("boss", 1, "none")]["mean_clear_time"],
    }
    for k, v in key.items():
        if isinstance(v, float) and abs(v) >= 10:
            w(f"  {k:<32} = {v:.2f}")
        else:
            w(f"  {k:<32} = {v:.4f}")
    w("")
    w("[7] 结论性观察（由上面数字直接得出）")
    w("-" * 78)
    flame_sent = gain_table["flame"]["sent_atk"]
    flame_boss = gain_table["flame"]["boss_both"]
    wind_sent = gain_table["wind"]["sent_atk"]
    vit_boss = gain_table["vitality"]["boss_both"]
    w(f"  - 烈焰之刃对哨兵 TTK 增益 = {flame_sent:.2f}%，对 Boss TTK 增益 = {flame_boss:.2f}%。")
    w(f"    哨兵 45HP 在两种倍率下都需 {rows_sent['none']['hits']} 段命中才能击杀，"
      f"因此首房/第二房几乎拿不到收益。")
    w(f"  - 疾风步伐与生命共鸣对 TTK 增益 = {wind_sent:.2f}% / {vit_boss:.2f}%"
      f"（两者都不影响输出，只影响生存）。")
    w(f"  - 3 哨兵房平均损失 HP {results[('sentinel',3,'none')]['mean_hp_lost']:.1f}，"
      f"Boss 房平均损失 HP {results[('boss',1,'none')]['mean_hp_lost']:.1f}："
      f"威胁高度集中在 Boss 房。")
    w("")

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")

    # stdout 只打印 ASCII 摘要，避免 GBK 控制台编码问题
    print("balance_sim.py OK")
    print(f"report written: {OUT_PATH}")
    print(f"sentinel ttk (attack only / with skill) = {k1:.3f}s / {k2:.3f}s")
    print(f"boss ttk (attack only / with skill)     = {rows_boss['none']['ttk_atk']:.3f}s / {k3:.3f}s")
    print(f"flame gain: sentinel {flame_sent:.2f}%  boss {flame_boss:.2f}%")
    print(f"wind gain : sentinel ttk {wind_sent:.2f}%  (dodge uptime "
          f"{dodge_uptime(DODGE['cd'])*100:.1f}% -> {dodge_uptime(DODGE_CD_WIND)*100:.1f}%)")
    print(f"vitality gain: boss ttk {vit_boss:.2f}%")
    print(f"hp lost: 2 sentinels {results[('sentinel',2,'none')]['mean_hp_lost']:.1f}  "
          f"3 sentinels {results[('sentinel',3,'none')]['mean_hp_lost']:.1f}  "
          f"boss {results[('boss',1,'none')]['mean_hp_lost']:.1f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
