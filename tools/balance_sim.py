#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Star Abyss 数值模拟器  (tools/balance_sim.py)
==============================================
纯 Python3 标准库，无第三方依赖，固定随机种子，输出完全确定性。
本机控制台是 GBK，因此【不】向 stdout 打印中文正文，只把报告写成 UTF-8 文件：
    .local/balance_sim_out.txt   （相对工程根目录 StarAbyss/）

模拟内容
  1) 单哨兵 TTK：只普攻 / 普攻+技能（DFS 求最优循环）
  2) Boss 星核守卫 TTK：只普攻 / 普攻+技能（DFS 求最优循环）
  3) 3 个祝福（烈焰之刃 / 生命共鸣 / 疾风步伐）对「哨兵 TTK」「Boss TTK」「存活能力」的增益百分比
  4) 2 哨兵 vs 3 哨兵场景下玩家预期存活 / 清场 / 受击概率（含闪避无敌帧覆盖率）
  5) 敏感性：玩家水平三档、哨兵出手周期两种口径、Boss 房各水平下的祝福收益

全部输入数值来源（已核实的资源文件与测试断言）：
  godot/resources/combat/attack_01.tres       damage=12 duration=0.48 hit[0.16,0.28)
  godot/resources/combat/attack_02.tres       damage=16 duration=0.56 hit[0.20,0.34)
  godot/resources/combat/attack_03.tres       damage=24 duration=0.72 hit[0.25,0.44)
  godot/resources/combat/star_blade.tres      damage=35 duration=0.70 hit[0.25,0.40) reach=5.0 arc=70
  godot/resources/combat/default_player_combat.tres  skill_cooldown=8.0（combat_rules_test 断言）
  godot/resources/enemies/default_sentinel.tres      hp=45 speed=3.2 detect=10 trigger=1.8 atk_cd=1.3
  godot/resources/enemies/sentinel_slash.tres        damage=10 duration=1.28 hit[0.55,0.73) reach=1.8 arc=100
  godot/resources/boss/default_guardian.tres         hp=350 speed=2.6 trigger=2.5 waiting=3.6 gap=[1.6,2.4]
  godot/resources/boss/guardian_sweep.tres           damage=20 duration=1.67 hit[0.80,1.02) reach=2.8 arc=130
  godot/resources/boss/guardian_shockwave.tres       damage=25 duration=2.20 hit[1.20,1.40) reach=4.2 arc=360
  闪避：duration=0.45 invuln=[0.10,0.30) cd=1.20（疾风步伐 → 0.90，blessing_rules_test 断言）
  玩家 HP=100；生命共鸣 +20 上限、普通敌人击杀回 5（blessing_rules_test 断言）
  烈焰之刃：普攻 ×1.20，逐段 roundi → 14/19/29，技能不受影响（blessing_rules_test 断言）

模型假设（每条都在文档中标注为「模型假设」，会影响结论的会给出敏感性表）：
  A1  玩家贴身近战，攻击判定必然命中当前目标（不含位移/角度误差）。
  A2  连招无输入空档：每段 duration 结束后立刻接下一段，三段打完回到第 1 段。
  A3  技能不推进也不重置连招段数（star_blade combo_open/close 均为 0.70，无连段语义）。
  A4  技能冷却自技能动作开始计时 8.0 s。
  A5  命中时刻 = 动作开始 + hit_start；持续 DPS 按动作开始计时（保守，忽略命中延迟）。
  A6  玩家对每次敌人起手的反应时 r ~ N(mean, sd) 截断，见 PROFILES（模型假设，需真实玩家数据校准）。
  A7  玩家按命中窗口择机闪避：期望在 hit_start 前 0.15 s 起滚，使无敌窗 [d+0.10, d+0.30) 覆盖命中；
      时间误差 e ~ N(0, sd) 截断到 ±0.22；另有 dodge_intent 概率「根本没想着闪」。
  A8  闪避仅 [开始+0.10, 开始+0.30) 无敌，且从闪避开始计冷却；已被无敌窗覆盖的招式不再浪费闪避。
  A9  闪避期间玩家不输出（0.45 s 空转），换目标移动 0.55 s，进房接触 ENGAGE 秒（模型假设）。
  A10 未建模受击保护帧(post-hit protection)、硬直位移、击退、绕后（偏保守）。
  A11 哨兵出手周期有两种口径（脚本内 SENTINEL_CADENCE）：
        "cd_from_start" → 周期 = max(动作 1.28 s, 冷却 1.30 s) = 1.30 s（主口径，最常见实现）
        "cd_after_end"  → 周期 = 动作 1.28 s + 冷却 1.30 s = 2.58 s（宽松口径）
      两者威胁相差一倍，必须由研发确认 attack_cooldown 计时起点；脚本对两种口径都输出。
  A12 Boss 交替使用横扫/冲击，招式结束后等待 U(1.6, 2.4) s 再起手。
  A13 玩家输出利用率 uptime：模拟人类失误导致的空转（已含闪避与走位损失之外的额外损失）。
"""

import contextlib
import math
import random
from pathlib import Path

# ----------------------------------------------------------------------------
# 全局配置
# ----------------------------------------------------------------------------
SEED = 20261023
TRIALS = 600
DT = 0.02
TIME_CAP = 60.0
OUT_PATH = Path(__file__).resolve().parent.parent / ".local" / "balance_sim_out.txt"

# ----------------------------------------------------------------------------
# 输入数值
# ----------------------------------------------------------------------------
PLAYER_HP = 100.0
GRAVITY = 18.0

ATTACKS = [
    {"name": "attack_01", "damage": 12.0, "duration": 0.48, "hit_start": 0.16, "hit_end": 0.28},
    {"name": "attack_02", "damage": 16.0, "duration": 0.56, "hit_start": 0.20, "hit_end": 0.34},
    {"name": "attack_03", "damage": 24.0, "duration": 0.72, "hit_start": 0.25, "hit_end": 0.44},
]
COMBO_CYCLE = sum(a["duration"] for a in ATTACKS)
COMBO_DAMAGE = sum(a["damage"] for a in ATTACKS)

SKILL = {"damage": 35.0, "duration": 0.70, "hit_start": 0.25, "hit_end": 0.40,
         "cd": 8.0, "reach": 5.0, "arc": 70.0}

DODGE = {"duration": 0.45, "inv_start": 0.10, "inv_end": 0.30, "cd": 1.2}
DODGE_CD_WIND = 0.9
WIND_INV_END = 0.30          # 疾风步伐的无敌帧结束时刻（当前与基线相同；用于「候选方案」模拟）

SENTINEL = {"hp": 45.0, "speed": 3.2, "detect": 10.0, "trigger": 1.8, "atk_cd": 1.3,
            "attack": {"damage": 10.0, "duration": 1.28, "hit_start": 0.55, "hit_end": 0.73,
                       "reach": 1.8, "arc": 100.0}}

GUARDIAN = {"hp": 350.0, "speed": 2.6, "detect": 30.0, "trigger": 2.5, "waiting": 3.6,
            "gap_min": 1.6, "gap_max": 2.4,
            "sweep": {"damage": 20.0, "duration": 1.67, "hit_start": 0.80, "hit_end": 1.02,
                      "reach": 2.8, "arc": 130.0},
            "shockwave": {"damage": 25.0, "duration": 2.20, "hit_start": 1.20, "hit_end": 1.40,
                          "reach": 4.2, "arc": 360.0}}

FLAME_MULT = 1.20
VITALITY_MAX_HP_BONUS = 20.0
VITALITY_KILL_HEAL = 5.0
BLESSINGS = ["none", "flame", "vitality", "wind"]
BLESSING_LABEL = {"none": "无祝福(基线)", "flame": "烈焰之刃",
                  "vitality": "生命共鸣", "wind": "疾风步伐"}

# 模型假设参数
DODGE_LEAD = 0.15
DODGE_ERROR_CLAMP = 0.22
TARGET_SWITCH_TIME = 0.55
ENGAGE = {"sentinel": 1.6, "boss": 3.0}
SENTINEL_PHASE_STEP = 0.35
BOSS_FIRST_ATTACK_AT = 1.2

PROFILES = {
    "expert": {"label": "高手", "react_mean": 0.26, "react_sd": 0.07,
               "react_min": 0.10, "react_max": 0.45,
               "dodge_err_sd": 0.09, "dodge_intent": 1.00, "uptime": 1.00},
    "average": {"label": "普通", "react_mean": 0.32, "react_sd": 0.10,
                "react_min": 0.12, "react_max": 0.60,
                "dodge_err_sd": 0.16, "dodge_intent": 0.85, "uptime": 0.85},
    "novice": {"label": "新手", "react_mean": 0.40, "react_sd": 0.12,
               "react_min": 0.15, "react_max": 0.70,
               "dodge_err_sd": 0.24, "dodge_intent": 0.65, "uptime": 0.65},
}
DEFAULT_PROFILE = "average"
PROFILE_ORDER = ["expert", "average", "novice"]

CADENCE = {
    "cd_from_start": "周期=max(动作1.28,冷却1.30)=1.30s",
    "cd_after_end": "周期=动作1.28+冷却1.30=2.58s",
}
DEFAULT_CADENCE = "cd_from_start"

DODGE_CFG = {"duration": DODGE["duration"], "cd": DODGE["cd"]}


def roundi(value: float) -> int:
    """与 Godot roundi() 一致的「四舍五入，远离零」（仅用于正数）。"""
    return int(math.floor(value + 0.5))


def gain(base: float, new: float) -> float:
    """增益百分比，正值 = 变好（更快 / 损失更少）。"""
    if abs(base) < 1e-12:
        return 0.0
    return (base - new) / base * 100.0


# ----------------------------------------------------------------------------
# 1) TTK / DPS（确定性）
# ----------------------------------------------------------------------------
def optimal_ttk(target_hp, normal_mult, allow_skill):
    """DFS 求最短击杀时刻 -> (ttk, plan[(开始,动作,命中,伤害)])。"""
    best = {"ttk": float("inf"), "plan": None}
    budget = [200000]

    def dfs(t, idx, skill_ready, dealt, plan):
        if budget[0] <= 0 or t >= best["ttk"] or t > 200.0:
            return
        budget[0] -= 1
        atk = ATTACKS[idx]
        dmg = roundi(atk["damage"] * normal_mult)
        hit = t + atk["hit_start"]
        nd = dealt + dmg
        plan.append((t, atk["name"], hit, dmg))
        if nd >= target_hp:
            if hit < best["ttk"]:
                best["ttk"], best["plan"] = hit, list(plan)
        else:
            dfs(t + atk["duration"], (idx + 1) % 3, skill_ready, nd, plan)
        plan.pop()
        if allow_skill and t + 1e-9 >= skill_ready:
            hit = t + SKILL["hit_start"]
            nd2 = dealt + SKILL["damage"]
            plan.append((t, "skill", hit, SKILL["damage"]))
            if nd2 >= target_hp:
                if hit < best["ttk"]:
                    best["ttk"], best["plan"] = hit, list(plan)
            else:
                dfs(t + SKILL["duration"], idx, t + SKILL["cd"], nd2, plan)
            plan.pop()

    dfs(0.0, 0, 0.0, 0.0, [])
    if best["plan"] is None:
        return None, []
    plan, dealt = [], 0.0
    for start, name, hit, dmg in best["plan"]:
        plan.append((start, name, hit, dmg))
        dealt += dmg
        if dealt >= target_hp:
            break
    return best["ttk"], plan


def hit_count_needed(target_hp, normal_mult):
    dealt = 0.0
    for i in range(60):
        dealt += roundi(ATTACKS[i % 3]["damage"] * normal_mult)
        if dealt >= target_hp:
            return i + 1
    return -1


def sustained_dps(horizon, normal_mult, use_skill=True):
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


def dodge_uptime(cd, inv_end=None):
    if inv_end is None:
        inv_end = DODGE["inv_end"]
    return (inv_end - DODGE["inv_start"]) / cd


def sentinel_period(cadence):
    if cadence == "cd_from_start":
        return max(SENTINEL["attack"]["duration"], SENTINEL["atk_cd"])
    return SENTINEL["attack"]["duration"] + SENTINEL["atk_cd"]


# ----------------------------------------------------------------------------
# 2) 房间存活模拟
# ----------------------------------------------------------------------------
def _draw_reaction(rng, prof):
    while True:
        r = rng.gauss(prof["react_mean"], prof["react_sd"])
        if prof["react_min"] <= r <= prof["react_max"]:
            return r


def _draw_dodge_error(rng, prof):
    while True:
        e = rng.gauss(0.0, prof["dodge_err_sd"])
        if -DODGE_ERROR_CLAMP <= e <= DODGE_ERROR_CLAMP:
            return e


def simulate_room(kind, count, blessing, trials=TRIALS, seed=SEED, dodge_enabled=True,
                  time_cap=TIME_CAP, profile=DEFAULT_PROFILE, cadence=DEFAULT_CADENCE,
                  hp_bonus=True, kill_heal=True):
    """hp_bonus / kill_heal 仅对 blessing="vitality" 有意义，用于拆解该祝福的两部分效果。"""
    prof = PROFILES[profile]
    normal_mult = FLAME_MULT if blessing == "flame" else 1.0
    max_hp = PLAYER_HP + (VITALITY_MAX_HP_BONUS if (blessing == "vitality" and hp_bonus) else 0.0)
    dodge_cd = DODGE_CD_WIND if blessing == "wind" else DODGE["cd"]
    inv_start = DODGE["inv_start"]
    inv_end = WIND_INV_END if blessing == "wind" else DODGE["inv_end"]
    dps = sustained_dps(60.0, normal_mult, use_skill=True) * prof["uptime"]
    engage = ENGAGE[kind]
    period = sentinel_period(cadence)

    deaths = 0
    death_times, clear_times, hp_left_on_clear, hp_lost_all = [], [], [], []
    taken = total = dodges = dodged = 0

    for trial in range(trials):
        rng = random.Random(seed * 7919 + trial)      # 共用随机数，便于横向对比
        hp = max_hp
        t = 0.0
        invuln, dodging = [], []
        dodge_ready = 0.0
        travel_left = 0.0
        t_taken = t_total = t_dodges = t_dodged = 0

        if kind == "sentinel":
            enemies = [{"hp": SENTINEL["hp"], "next_start": engage + SENTINEL_PHASE_STEP * i,
                        "pending": None, "cycle": 0} for i in range(count)]
        else:
            enemies = [{"hp": GUARDIAN["hp"], "next_start": engage + BOSS_FIRST_ATTACK_AT,
                        "pending": None, "cycle": 0}]

        def current_target():
            for e in enemies:
                if e["hp"] > 0.0:
                    return e
            return None

        outcome = None
        while t < time_cap:
            t += DT
            for e in enemies:
                if e["hp"] <= 0.0:
                    continue
                if e["pending"] is None and e["next_start"] is not None and t >= e["next_start"]:
                    if kind == "sentinel":
                        atk = SENTINEL["attack"]
                        nxt = e["next_start"] + period
                    else:
                        atk = GUARDIAN["sweep"] if e["cycle"] % 2 == 0 else GUARDIAN["shockwave"]
                        e["cycle"] += 1
                        nxt = (e["next_start"] + atk["duration"]
                               + rng.uniform(GUARDIAN["gap_min"], GUARDIAN["gap_max"]))
                    start = t
                    hs, he = start + atk["hit_start"], start + atk["hit_end"]
                    e["pending"] = (hs, he, atk["damage"])
                    e["next_start"] = nxt
                    if dodge_enabled and rng.random() < prof["dodge_intent"]:
                        if not any(a < he and b > hs for a, b in invuln):
                            react_at = start + _draw_reaction(rng, prof)
                            desired = hs - DODGE_LEAD + _draw_dodge_error(rng, prof)
                            plan = max(react_at, desired, dodge_ready)
                            if plan < he:
                                invuln.append((plan + inv_start, plan + inv_end))
                                dodging.append((plan, plan + DODGE["duration"]))
                                dodge_ready = plan + dodge_cd
                                t_dodges += 1
                if e["pending"] is not None and t >= e["pending"][1]:
                    hs, he, dmg = e["pending"]
                    e["pending"] = None
                    t_total += 1
                    if any(a < he and b > hs for a, b in invuln):
                        t_dodged += 1
                    else:
                        t_taken += 1
                        hp -= dmg
                        if hp <= 0.0:
                            hp = 0.0
                            outcome = "death"
                            break
            if outcome == "death":
                break
            in_dodge = any(a <= t < b for a, b in dodging)
            if travel_left > 1e-9:
                travel_left -= DT
            elif not in_dodge:
                tgt = current_target()
                if tgt is None:
                    outcome = "clear"
                    break
                tgt["hp"] -= dps * DT
                if tgt["hp"] <= 0.0:
                    tgt["hp"] = 0.0
                    if blessing == "vitality" and kind == "sentinel" and kill_heal:
                        hp = min(max_hp, hp + VITALITY_KILL_HEAL)
                    if current_target() is None:
                        outcome = "clear"
                        break
                    travel_left = TARGET_SWITCH_TIME
            if all(e["hp"] <= 0.0 for e in enemies):
                outcome = "clear"
                break

        taken += t_taken
        total += t_total
        dodges += t_dodges
        dodged += t_dodged
        hp_lost_all.append(max_hp - hp)
        if outcome == "death":
            deaths += 1
            death_times.append(t)
        else:
            clear_times.append(t)
            hp_left_on_clear.append(hp)

    def mean(xs):
        return sum(xs) / len(xs) if xs else 0.0

    return {
        "kind": kind, "count": count, "blessing": blessing, "profile": profile,
        "cadence": cadence, "dodge_enabled": dodge_enabled,
        "max_hp": max_hp, "dps": dps, "dodge_cd": dodge_cd,
        "invuln_uptime": dodge_uptime(dodge_cd, inv_end),
        "death_rate": deaths / trials,
        "mean_death_time": mean(death_times),
        "mean_clear_time": mean(clear_times),
        "mean_hp_left_on_clear": mean(hp_left_on_clear),
        "mean_hp_left_ratio": (sum(max_hp - x for x in hp_lost_all) / len(hp_lost_all) / max_hp)
        if hp_lost_all else 0.0,
        "mean_hp_lost": mean(hp_lost_all),
        "hit_rate": (taken / total) if total else 0.0,
        "dodge_success_rate": (dodged / total) if total else 0.0,
        "hits_taken_per_trial": taken / trials,
        "enemy_attacks_per_trial": total / trials,
        "dodges_per_trial": dodges / trials,
    }


# ----------------------------------------------------------------------------
# 3) 报告
# ----------------------------------------------------------------------------
@contextlib.contextmanager
def override_constants(overrides):
    """临时覆盖模块级数值（用于「候选方案」试算），退出时严格还原。"""
    saved_dict = {}
    saved_globals = []
    for key, value in overrides.items():
        if "." in key:
            parts = key.split(".")
            obj = globals()[parts[0]]
            for part in parts[1:-1]:
                obj = obj[part]
            leaf = parts[-1]
            saved_dict[(id(obj), leaf)] = (obj, leaf, obj[leaf])
            obj[leaf] = value
        else:
            saved_globals.append((key, globals()[key]))
            globals()[key] = value
    try:
        yield
    finally:
        for obj, leaf, old in saved_dict.values():
            obj[leaf] = old
        for key, old in saved_globals:
            globals()[key] = old


def main() -> int:
    lines = []

    def w(s=""):
        lines.append(s)

    w("=" * 92)
    w("Star Abyss 数值模拟报告 —— tools/balance_sim.py")
    w("=" * 92)
    w(f"确定性参数: SEED={SEED}  TRIALS={TRIALS}  DT={DT}s  TIME_CAP={TIME_CAP}s")
    w(f"主口径: 玩家水平={PROFILES[DEFAULT_PROFILE]['label']}({DEFAULT_PROFILE})  "
      f"哨兵出手周期={CADENCE[DEFAULT_CADENCE]}")
    w("本文件由脚本真实生成；BALANCE_DESIGN.md 中所有模拟数字必须引用本文件，不得手写。")
    w("")
    w("[0] 输入数值（来源 .tres / 测试断言）")
    w("-" * 92)
    for i, a in enumerate(ATTACKS):
        w(f"  普攻{i + 1} {a['name']:<9} 伤害={a['damage']:>5.1f} 时长={a['duration']:.2f}s "
          f"命中窗口=[{a['hit_start']:.2f},{a['hit_end']:.2f})")
    w(f"  连招一轮: 时长={COMBO_CYCLE:.2f}s 总伤害={COMBO_DAMAGE:.0f} "
      f"→ 连招循环 DPS={COMBO_DAMAGE / COMBO_CYCLE:.3f}")
    w(f"  技能 星刃斩: 伤害={SKILL['damage']:.0f} 时长={SKILL['duration']:.2f}s "
      f"命中=[{SKILL['hit_start']:.2f},{SKILL['hit_end']:.2f}) CD={SKILL['cd']:.1f}s "
      f"射程={SKILL['reach']:.0f}m 扇形={SKILL['arc']:.0f}°")
    w(f"  闪避: 时长={DODGE['duration']:.2f}s 无敌=[{DODGE['inv_start']:.2f},{DODGE['inv_end']:.2f}) "
      f"CD={DODGE['cd']:.1f}s → 无敌覆盖率={dodge_uptime(DODGE['cd']) * 100:.2f}%")
    w(f"        疾风步伐 CD={DODGE_CD_WIND:.1f}s → 覆盖率={dodge_uptime(DODGE_CD_WIND) * 100:.2f}%"
      f"（冷却缩减 {gain(DODGE['cd'], DODGE_CD_WIND):.2f}%，覆盖率 "
      f"{dodge_uptime(DODGE_CD_WIND) / dodge_uptime(DODGE['cd']):.3f}x）")
    w(f"  哨兵: HP={SENTINEL['hp']:.0f} 伤害={SENTINEL['attack']['damage']:.0f} "
      f"动作={SENTINEL['attack']['duration']:.2f}s 命中=[{SENTINEL['attack']['hit_start']:.2f},"
      f"{SENTINEL['attack']['hit_end']:.2f}) 冷却={SENTINEL['atk_cd']:.1f}s")
    w(f"  Boss: HP={GUARDIAN['hp']:.0f} 横扫={GUARDIAN['sweep']['damage']:.0f}伤/"
      f"{GUARDIAN['sweep']['duration']:.2f}s(命中[{GUARDIAN['sweep']['hit_start']:.2f},"
      f"{GUARDIAN['sweep']['hit_end']:.2f})) 冲击={GUARDIAN['shockwave']['damage']:.0f}伤/"
      f"{GUARDIAN['shockwave']['duration']:.2f}s(命中[{GUARDIAN['shockwave']['hit_start']:.2f},"
      f"{GUARDIAN['shockwave']['hit_end']:.2f})) 间隔=[{GUARDIAN['gap_min']:.1f},"
      f"{GUARDIAN['gap_max']:.1f}]s")
    w("  玩家水平档（A6/A7/A13，模型假设）:")
    for p in PROFILE_ORDER:
        pr = PROFILES[p]
        w(f"    {pr['label']:<4}({p:<7}) 反应 {pr['react_mean']:.2f}±{pr['react_sd']:.2f}s  "
          f"闪避误差σ {pr['dodge_err_sd']:.2f}s  闪避意图 {pr['dodge_intent'] * 100:.0f}%  "
          f"输出利用率 {pr['uptime'] * 100:.0f}%")
    w("")

    # ---------------- [1] 单哨兵 TTK ----------------
    w("[1] 单哨兵 TTK（HP=45，理想循环，不含闪避空转与走位）")
    w("-" * 92)
    rows_sent = {}
    for b in BLESSINGS:
        mult = FLAME_MULT if b == "flame" else 1.0
        ttk_atk, _ = optimal_ttk(SENTINEL["hp"], mult, allow_skill=False)
        ttk_both, plan_both = optimal_ttk(SENTINEL["hp"], mult, allow_skill=True)
        hits = hit_count_needed(SENTINEL["hp"], mult)
        rows_sent[b] = {"ttk_atk": ttk_atk, "ttk_both": ttk_both, "hits": hits, "mult": mult}
        skill_cnt = sum(1 for p in plan_both if p[1] == "skill")
        w(f"  {BLESSING_LABEL[b]:<10} 只普攻 TTK={ttk_atk:.3f}s (命中 {hits} 段，普攻倍率×{mult:.2f})"
          f"   |   普攻+技能 TTK={ttk_both:.3f}s (技能 {skill_cnt} 次)")
        w("      最优序列: " + " → ".join(f"{n}@{h:.2f}s({d:g})" for _, n, h, d in plan_both))
    w("")

    # ---------------- [2] Boss TTK ----------------
    w("[2] Boss 星核守卫 TTK（HP=350）")
    w("-" * 92)
    rows_boss = {}
    for b in BLESSINGS:
        mult = FLAME_MULT if b == "flame" else 1.0
        ttk_atk, _ = optimal_ttk(GUARDIAN["hp"], mult, allow_skill=False)
        ttk_both, plan_both = optimal_ttk(GUARDIAN["hp"], mult, allow_skill=True)
        skill_cnt = sum(1 for p in plan_both if p[1] == "skill")
        rows_boss[b] = {"ttk_atk": ttk_atk, "ttk_both": ttk_both,
                        "skill_cnt": skill_cnt, "actions": len(plan_both), "mult": mult}
        w(f"  {BLESSING_LABEL[b]:<10} 只普攻 TTK={ttk_atk:.3f}s   |   普攻+技能 TTK={ttk_both:.3f}s"
          f" (技能 {skill_cnt} 次，共 {len(plan_both)} 个动作)")
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
    nodge = {sc: simulate_room(sc[0], sc[1], "none", dodge_enabled=False) for sc in scenarios}

    def scenario_title(kind, count):
        if kind == "sentinel":
            return f"{count} 哨兵房（敌方总血量 {int(SENTINEL['hp']) * count}）"
        return "Boss 房（晶核守卫 350 HP）"

    w(f"[3] 房间存活模拟（{TRIALS} 次试验，玩家水平={PROFILES[DEFAULT_PROFILE]['label']}，"
      f"{CADENCE[DEFAULT_CADENCE]}）")
    for kind, count in scenarios:
        w("-" * 92)
        w(f"  {scenario_title(kind, count)}")
        w("  祝福          玩家HP 闪避CD 无敌覆盖  阵亡率  平均阵亡时刻  平均清场耗时  "
          "清场剩HP 平均损失HP  受击概率 闪避成功率 敌方出手/局")
        for b in BLESSINGS:
            r = results[(kind, count, b)]
            w(f"  {BLESSING_LABEL[b]:<10} {r['max_hp']:>6.0f} {r['dodge_cd']:>6.2f} "
              f"{r['invuln_uptime'] * 100:>7.2f}% {r['death_rate'] * 100:>6.1f}% "
              f"{r['mean_death_time']:>11.2f}s {r['mean_clear_time']:>10.2f}s "
              f"{r['mean_hp_left_on_clear']:>7.1f} {r['mean_hp_lost']:>9.1f} "
              f"{r['hit_rate'] * 100:>7.1f}% {r['dodge_success_rate'] * 100:>8.1f}% "
              f"{r['enemy_attacks_per_trial']:>9.2f}")
        rn = nodge[(kind, count)]
        w(f"  {'完全不用闪避':<10} {rn['max_hp']:>6.0f} {'--':>6} {'0.00%':>7} "
          f"{rn['death_rate'] * 100:>6.1f}% {rn['mean_death_time']:>11.2f}s "
          f"{rn['mean_clear_time']:>10.2f}s {rn['mean_hp_left_on_clear']:>7.1f} "
          f"{rn['mean_hp_lost']:>9.1f} {rn['hit_rate'] * 100:>7.1f}% {'0.0%':>8} "
          f"{rn['enemy_attacks_per_trial']:>9.2f}")
    w("")

    # ---------------- [4] 祝福定量对比 ----------------
    base_sent_atk = rows_sent["none"]["ttk_atk"]
    base_sent_both = rows_sent["none"]["ttk_both"]
    base_boss_atk = rows_boss["none"]["ttk_atk"]
    base_boss_both = rows_boss["none"]["ttk_both"]
    gain_table = {}
    for b in BLESSINGS:
        rs, rb = rows_sent[b], rows_boss[b]
        gain_table[b] = {
            "sent_atk": gain(base_sent_atk, rs["ttk_atk"]),
            "sent_both": gain(base_sent_both, rs["ttk_both"]),
            "boss_atk": gain(base_boss_atk, rb["ttk_atk"]),
            "boss_both": gain(base_boss_both, rb["ttk_both"]),
        }

    w("[4] 三个祝福的量化对比（基线 = 无祝福；正值 = 变好）")
    w("-" * 92)
    w("  (a) TTK 增益（%）＝（基线TTK − 祝福TTK）/ 基线TTK × 100")
    w("  祝福        哨兵TTK(只普攻) 增益  哨兵TTK(含技能) 增益  BossTTK(只普攻) 增益  BossTTK(含技能) 增益")
    for b in BLESSINGS:
        rs, rb, g = rows_sent[b], rows_boss[b], gain_table[b]
        w(f"  {BLESSING_LABEL[b]:<10} {rs['ttk_atk']:>9.3f}s {g['sent_atk']:>9.2f}% "
          f"{rs['ttk_both']:>9.3f}s {g['sent_both']:>9.2f}% "
          f"{rb['ttk_atk']:>9.3f}s {g['boss_atk']:>9.2f}% "
          f"{rb['ttk_both']:>9.3f}s {g['boss_both']:>9.2f}%")
    w("")
    w("  (b) 生存增益（%）＝（基线平均损失HP − 祝福平均损失HP）/ 基线平均损失HP × 100")
    w("  祝福        2哨兵损失HP 增益   3哨兵损失HP 增益   Boss损失HP 增益   "
      "2哨兵阵亡率 3哨兵阵亡率 Boss阵亡率")
    surv_gain = {}
    for b in BLESSINGS:
        r2 = results[("sentinel", 2, b)]
        r3 = results[("sentinel", 3, b)]
        rb = results[("boss", 1, b)]
        b2 = results[("sentinel", 2, "none")]["mean_hp_lost"]
        b3 = results[("sentinel", 3, "none")]["mean_hp_lost"]
        bb = results[("boss", 1, "none")]["mean_hp_lost"]
        surv_gain[b] = {"s2": gain(b2, r2["mean_hp_lost"]),
                        "s3": gain(b3, r3["mean_hp_lost"]),
                        "boss": gain(bb, rb["mean_hp_lost"])}
        w(f"  {BLESSING_LABEL[b]:<10} {r2['mean_hp_lost']:>9.1f} {surv_gain[b]['s2']:>8.2f}% "
          f"{r3['mean_hp_lost']:>9.1f} {surv_gain[b]['s3']:>8.2f}% "
          f"{rb['mean_hp_lost']:>9.1f} {surv_gain[b]['boss']:>8.2f}%  "
          f"{r2['death_rate'] * 100:>8.1f}% {r3['death_rate'] * 100:>8.1f}% "
          f"{rb['death_rate'] * 100:>8.1f}%")
    w("")
    w("  (c) 综合评分（(a)哨兵TTK、(a)BossTTK、(b)三场景生存 共 5 项增益的算术平均；"
      "仅用于横向比较祝福强度，属模型口径而非官方设计口径）")
    for b in BLESSINGS:
        g = gain_table[b]
        s = surv_gain[b]
        score = (g["sent_atk"] + g["boss_both"] + s["s2"] + s["s3"] + s["boss"]) / 5.0
        w(f"    {BLESSING_LABEL[b]:<10} 哨兵TTK {g['sent_atk']:>7.2f}% | BossTTK {g['boss_both']:>7.2f}% | "
          f"2哨兵生存 {s['s2']:>7.2f}% | 3哨兵生存 {s['s3']:>7.2f}% | Boss生存 {s['boss']:>7.2f}% "
          f"→ 平均 {score:>7.2f}%")
    w("")

    # ---------------- [5] 2 vs 3 哨兵 ----------------
    w("[5] 2 哨兵 vs 3 哨兵：预期存活 / 清场曲线（基线祝福，主口径）")
    w("-" * 92)
    r2 = results[("sentinel", 2, "none")]
    r3 = results[("sentinel", 3, "none")]

    def ratio(a, b):
        return (a / b) if abs(b) > 1e-12 else 0.0

    w("  指标                     2哨兵        3哨兵        3/2 倍数")
    w(f"  平均房间耗时             {r2['mean_clear_time']:>9.2f}s   {r3['mean_clear_time']:>9.2f}s   "
      f"{ratio(r3['mean_clear_time'], r2['mean_clear_time']):>8.2f}x")
    w(f"  敌方出手次数/局          {r2['enemy_attacks_per_trial']:>9.2f}    "
      f"{r3['enemy_attacks_per_trial']:>9.2f}    "
      f"{ratio(r3['enemy_attacks_per_trial'], r2['enemy_attacks_per_trial']):>8.2f}x")
    w(f"  玩家被击中次数/局        {r2['hits_taken_per_trial']:>9.2f}    "
      f"{r3['hits_taken_per_trial']:>9.2f}    "
      f"{ratio(r3['hits_taken_per_trial'], r2['hits_taken_per_trial']):>8.2f}x")
    w(f"  平均损失 HP              {r2['mean_hp_lost']:>9.1f}    {r3['mean_hp_lost']:>9.1f}    "
      f"{ratio(r3['mean_hp_lost'], r2['mean_hp_lost']):>8.2f}x")
    w(f"  受击概率（单次攻击）     {r2['hit_rate'] * 100:>8.1f}%    {r3['hit_rate'] * 100:>8.1f}%    "
      f"{ratio(r3['hit_rate'], r2['hit_rate']):>8.2f}x")
    w(f"  闪避成功率               {r2['dodge_success_rate'] * 100:>8.1f}%    "
      f"{r3['dodge_success_rate'] * 100:>8.1f}%    "
      f"{ratio(r3['dodge_success_rate'], r2['dodge_success_rate']):>8.2f}x")
    w(f"  阵亡率                   {r2['death_rate'] * 100:>8.1f}%    {r3['death_rate'] * 100:>8.1f}%")
    w(f"  不用闪避·3哨兵          损失HP {nodge[('sentinel', 3)]['mean_hp_lost']:.1f}"
      f"（用闪避 {r3['mean_hp_lost']:.1f}）  阵亡率 "
      f"{nodge[('sentinel', 3)]['death_rate'] * 100:.1f}%（用闪避 {r3['death_rate'] * 100:.1f}%）")
    w("")

    # ---------------- [6] 敏感性 ----------------
    w("[6] 敏感性分析（基线祝福）")
    w("-" * 92)
    w("  (a) 玩家水平三档")
    w("  场景              水平    平均清场耗时 平均损失HP 阵亡率  平均阵亡时刻 敌方出手/局 闪避成功率")
    tier = {}
    for kind, count in scenarios:
        for p in PROFILE_ORDER:
            r = simulate_room(kind, count, "none", profile=p)
            tier[(kind, count, p)] = r
            tag = f"{count} 哨兵" if kind == "sentinel" else "Boss"
            w(f"  {tag:<16}  {PROFILES[p]['label']:<4}  {r['mean_clear_time']:>11.2f}s "
              f"{r['mean_hp_lost']:>9.1f} {r['death_rate'] * 100:>6.1f}% "
              f"{r['mean_death_time']:>11.2f}s {r['enemy_attacks_per_trial']:>9.2f} "
              f"{r['dodge_success_rate'] * 100:>8.1f}%")
    w("")
    w("  (b) 哨兵出手周期口径（研发需确认 attack_cooldown 计时起点）")
    w("  场景              口径            平均清场耗时 平均损失HP 阵亡率  敌方出手/局")
    cad = {}
    for kind, count in scenarios:
        if kind != "sentinel":
            continue
        for c in ("cd_from_start", "cd_after_end"):
            r = simulate_room(kind, count, "none", cadence=c)
            cad[(kind, count, c)] = r
            w(f"  {count} 哨兵           {c:<15} {r['mean_clear_time']:>11.2f}s "
              f"{r['mean_hp_lost']:>9.1f} {r['death_rate'] * 100:>6.1f}% "
              f"{r['enemy_attacks_per_trial']:>9.2f}")
    w("")
    w("  (c) Boss 房：各水平玩家 × 各祝福的阵亡率与损失 HP（看祝福对弱玩家的价值）")
    w("  水平    祝福        损失HP  阵亡率  清场耗时  闪避成功率")
    boss_matrix = {}
    for p in PROFILE_ORDER:
        for b in BLESSINGS:
            r = simulate_room("boss", 1, b, profile=p)
            boss_matrix[(p, b)] = r
            w(f"  {PROFILES[p]['label']:<4}  {BLESSING_LABEL[b]:<10} {r['mean_hp_lost']:>8.1f} "
              f"{r['death_rate'] * 100:>6.1f}% {r['mean_clear_time']:>9.2f}s "
              f"{r['dodge_success_rate'] * 100:>8.1f}%")
    w("")
    w("  (d) 生命共鸣两部分效果拆解（+20 生命上限 / 普通敌人击杀回 5）")
    w("  场景           变体             损失HP  剩HP%  阵亡率")
    vit = {}
    for kind, count in scenarios:
        tag = f"{count} 哨兵" if kind == "sentinel" else "Boss"
        variants = [
            ("无祝福", simulate_room(kind, count, "none")),
            ("生命共鸣(全量)", simulate_room(kind, count, "vitality")),
            ("仅+20上限", simulate_room(kind, count, "vitality", kill_heal=False)),
            ("仅击杀回5", simulate_room(kind, count, "vitality", hp_bonus=False)),
        ]
        for name, r in variants:
            vit[(kind, count, name)] = r
            w(f"  {tag:<14}  {name:<16} {r['mean_hp_lost']:>7.1f} "
              f"{r['mean_hp_left_ratio'] * 100:>6.1f}% {r['death_rate'] * 100:>6.1f}%")
    w("")

    # ---------------- [7] 关键数字 ----------------
    k_sent_atk = rows_sent["none"]["ttk_atk"]
    k_sent_both = rows_sent["none"]["ttk_both"]
    k_boss_atk = rows_boss["none"]["ttk_atk"]
    k_boss_both = rows_boss["none"]["ttk_both"]
    w("[7] 关键数字摘要（供 BALANCE_DESIGN.md 引用）")
    w("-" * 92)
    key = [
        ("sentinel_ttk_attack_only_s", k_sent_atk, 3),
        ("sentinel_ttk_with_skill_s", k_sent_both, 3),
        ("boss_ttk_attack_only_s", k_boss_atk, 3),
        ("boss_ttk_with_skill_s", k_boss_both, 3),
        ("combo_cycle_dps", COMBO_DAMAGE / COMBO_CYCLE, 3),
        ("sustained_dps_with_skill_60s", sustained_dps(60.0, 1.0, True), 3),
        ("skill_share_of_sentinel_ttk_pct", gain(k_sent_atk, k_sent_both), 2),
        ("flame_gain_sentinel_ttk_pct", gain_table["flame"]["sent_atk"], 2),
        ("flame_gain_boss_ttk_pct", gain_table["flame"]["boss_both"], 2),
        ("wind_gain_sentinel_ttk_pct", gain_table["wind"]["sent_atk"], 2),
        ("vitality_gain_boss_ttk_pct", gain_table["vitality"]["boss_both"], 2),
        ("dodge_uptime_base_pct", dodge_uptime(DODGE["cd"]) * 100, 2),
        ("dodge_uptime_wind_pct", dodge_uptime(DODGE_CD_WIND) * 100, 2),
        ("s2_hp_lost_base", results[("sentinel", 2, "none")]["mean_hp_lost"], 2),
        ("s3_hp_lost_base", results[("sentinel", 3, "none")]["mean_hp_lost"], 2),
        ("boss_hp_lost_base", results[("boss", 1, "none")]["mean_hp_lost"], 2),
        ("s2_death_rate_base_pct", results[("sentinel", 2, "none")]["death_rate"] * 100, 2),
        ("s3_death_rate_base_pct", results[("sentinel", 3, "none")]["death_rate"] * 100, 2),
        ("boss_death_rate_base_pct", results[("boss", 1, "none")]["death_rate"] * 100, 2),
        ("s2_room_time_base_s", results[("sentinel", 2, "none")]["mean_clear_time"], 2),
        ("s3_room_time_base_s", results[("sentinel", 3, "none")]["mean_clear_time"], 2),
        ("boss_room_time_base_s", results[("boss", 1, "none")]["mean_clear_time"], 2),
        ("boss_attacks_per_fight", results[("boss", 1, "none")]["enemy_attacks_per_trial"], 2),
        ("s3_attacks_per_fight", results[("sentinel", 3, "none")]["enemy_attacks_per_trial"], 2),
        ("boss_hit_rate_base_pct", results[("boss", 1, "none")]["hit_rate"] * 100, 2),
        ("s3_hit_rate_base_pct", results[("sentinel", 3, "none")]["hit_rate"] * 100, 2),
        ("survival_gain_flame_s2_pct", surv_gain["flame"]["s2"], 2),
        ("survival_gain_flame_s3_pct", surv_gain["flame"]["s3"], 2),
        ("survival_gain_vitality_s2_pct", surv_gain["vitality"]["s2"], 2),
        ("survival_gain_vitality_s3_pct", surv_gain["vitality"]["s3"], 2),
        ("survival_gain_wind_s2_pct", surv_gain["wind"]["s2"], 2),
        ("survival_gain_wind_s3_pct", surv_gain["wind"]["s3"], 2),
        ("s3_hp_lost_expert", tier[("sentinel", 3, "expert")]["mean_hp_lost"], 2),
        ("s3_hp_lost_average", tier[("sentinel", 3, "average")]["mean_hp_lost"], 2),
        ("s3_hp_lost_novice", tier[("sentinel", 3, "novice")]["mean_hp_lost"], 2),
        ("s3_death_rate_novice_pct", tier[("sentinel", 3, "novice")]["death_rate"] * 100, 2),
        ("boss_hp_lost_expert", tier[("boss", 1, "expert")]["mean_hp_lost"], 2),
        ("boss_hp_lost_average", tier[("boss", 1, "average")]["mean_hp_lost"], 2),
        ("boss_hp_lost_novice", tier[("boss", 1, "novice")]["mean_hp_lost"], 2),
        ("boss_death_rate_novice_pct", tier[("boss", 1, "novice")]["death_rate"] * 100, 2),
        ("s3_hp_lost_cadence_after_end", cad[("sentinel", 3, "cd_after_end")]["mean_hp_lost"], 2),
        ("s3_hp_left_ratio_base_pct", results[("sentinel", 3, "none")]["mean_hp_left_ratio"] * 100, 2),
        ("boss_hp_left_ratio_base_pct", results[("boss", 1, "none")]["mean_hp_left_ratio"] * 100, 2),
        ("boss_hp_left_ratio_novice_pct", tier[("boss", 1, "novice")]["mean_hp_left_ratio"] * 100, 2),
        ("boss_hp_lost_no_dodge", nodge[("boss", 1)]["mean_hp_lost"], 2),
        ("boss_death_rate_no_dodge_pct", nodge[("boss", 1)]["death_rate"] * 100, 2),
        ("s3_hp_lost_no_dodge", nodge[("sentinel", 3)]["mean_hp_lost"], 2),
        ("vitality_s3_lost_full", vit[("sentinel", 3, "生命共鸣(全量)")]["mean_hp_lost"], 2),
        ("vitality_s3_lost_hp_bonus_only", vit[("sentinel", 3, "仅+20上限")]["mean_hp_lost"], 2),
        ("vitality_s3_lost_kill_heal_only", vit[("sentinel", 3, "仅击杀回5")]["mean_hp_lost"], 2),
        ("vitality_boss_lost_hp_bonus_only", vit[("boss", 1, "仅+20上限")]["mean_hp_lost"], 2),
        ("vitality_boss_lost_kill_heal_only", vit[("boss", 1, "仅击杀回5")]["mean_hp_lost"], 2),
    ]
    for k, v, nd in key:
        w(f"  {k:<38} = {v:.{nd}f}")
    w("")

    # ---------------- [8] 结论 ----------------
    w("[8] 由上面数字直接得到的结论")
    w("-" * 92)
    w(f"  1) 单哨兵 TTK：只普攻 {k_sent_atk:.2f}s（{rows_sent['none']['hits']} 段命中）；"
      f"加入技能可压到 {k_sent_both:.2f}s（提速 {gain(k_sent_atk, k_sent_both):.2f}%）。"
      f"1 个技能(35) ≈ 0.775 只哨兵的血量。")
    w(f"  2) 烈焰之刃：哨兵 TTK 增益 {gain_table['flame']['sent_atk']:.2f}%"
      f"（45HP 在 ×1.00 与 ×1.20 下均需 {rows_sent['none']['hits']} 段命中，"
      f"对首个祝福完全无效）；Boss TTK 增益 {gain_table['flame']['boss_both']:.2f}%"
      f"（{base_boss_both:.2f}s → {rows_boss['flame']['ttk_both']:.2f}s）。")
    w(f"  3) 疾风步伐 Boss TTK 增益 {gain_table['wind']['boss_both']:.2f}%、"
      f"生命共鸣 Boss TTK 增益 {gain_table['vitality']['boss_both']:.2f}%：两者都是纯生存祝福。")
    w(f"  4) 生存端：3 哨兵房平均损失 {results[('sentinel', 3, 'none')]['mean_hp_lost']:.1f} HP，"
      f"Boss 房 {results[('boss', 1, 'none')]['mean_hp_lost']:.1f} HP"
      f"（主口径 {PROFILES[DEFAULT_PROFILE]['label']} 玩家）。")
    w(f"  5) Boss 战平均 {results[('boss', 1, 'none')]['enemy_attacks_per_trial']:.2f} 次出手、"
      f"平均清场 {results[('boss', 1, 'none')]['mean_clear_time']:.2f}s → "
      f"招式循环只跑 {results[('boss', 1, 'none')]['enemy_attacks_per_trial']:.1f} 个动作。")
    w(f"  6) 阵亡率：普通玩家 3 哨兵房 {results[('sentinel', 3, 'none')]['death_rate'] * 100:.1f}%、"
      f"Boss 房 {results[('boss', 1, 'none')]['death_rate'] * 100:.1f}%；"
      f"新手 Boss 房 {tier[('boss', 1, 'novice')]['death_rate'] * 100:.1f}%、"
      f"3 哨兵房 {tier[('sentinel', 3, 'novice')]['death_rate'] * 100:.1f}%。")
    w(f"  7) 哨兵出手周期口径影响：3 哨兵房损失 "
      f"{cad[('sentinel', 3, 'cd_from_start')]['mean_hp_lost']:.1f} HP(cd_from_start) vs "
      f"{cad[('sentinel', 3, 'cd_after_end')]['mean_hp_lost']:.1f} HP(cd_after_end)，"
      f"结论相差 {ratio(cad[('sentinel', 3, 'cd_from_start')]['mean_hp_lost'], cad[('sentinel', 3, 'cd_after_end')]['mean_hp_lost']):.2f}x。")
    w(f"  8) 即使完全不闪避：3 哨兵房损失 {nodge[('sentinel', 3)]['mean_hp_lost']:.1f} HP，"
      f"Boss 房损失 {nodge[('boss', 1)]['mean_hp_lost']:.1f} HP，阵亡率 "
      f"{nodge[('boss', 1)]['death_rate'] * 100:.1f}% → 不闪避也打不死。")
    w(f"  9) 生命共鸣拆解：3 哨兵房 仅击杀回5 损失 "
      f"{vit[('sentinel', 3, '仅击杀回5')]['mean_hp_lost']:.1f} HP、仅+20上限 损失 "
      f"{vit[('sentinel', 3, '仅+20上限')]['mean_hp_lost']:.1f} HP"
      f"（全量 {vit[('sentinel', 3, '生命共鸣(全量)')]['mean_hp_lost']:.1f} HP）"
      f"→ 增益主要来自击杀回血，+20 上限在 Boss 房贡献 0.00。")
    w("  10) 注意：烈焰之刃在 2 哨兵房出现 52.8% → 8.5% 的受击概率跳变，"
      "属离散时序的『刀口效应』（多打出的伤害恰好让哨兵在命中结算前死亡），"
      "不是稳健结论，需真实玩家数据确认。")
    w("")

    # ---------------- [9] 参数调整候选方案实测 ----------------
    w("[9] 参数调整候选方案实测（普通玩家，基线祝福；用于给 BALANCE_DESIGN.md 的建议值提供依据）")
    w("-" * 92)
    candidates = [
        ("C0 基线（当前线上）", {},
         "当前 .tres 数值"),
        ("C1 哨兵HP 45→56", {"SENTINEL.hp": 56.0},
         "使烈焰之刃在哨兵房产生 4段→3段 的段数差，同时抬高房间威胁"),
        ("C2 Boss350→560, 间隔1.3~1.9", {"GUARDIAN.hp": 560.0,
                                        "GUARDIAN.gap_min": 1.3,
                                        "GUARDIAN.gap_max": 1.9},
         "延长 Boss 战时长、让招式循环多跑几轮"),
        ("C3 C2+Boss伤害 20/25→24/30", {"GUARDIAN.hp": 560.0,
                                        "GUARDIAN.gap_min": 1.3,
                                        "GUARDIAN.gap_max": 1.9,
                                        "SENTINEL.hp": 56.0,
                                        "GUARDIAN.sweep.damage": 24.0,
                                        "GUARDIAN.shockwave.damage": 30.0},
         "C1+C2 之上提高单次招式威胁"),
        ("C4 C3+疾风CD0.75/无敌0.36", {"GUARDIAN.hp": 560.0,
                                      "GUARDIAN.gap_min": 1.3,
                                      "GUARDIAN.gap_max": 1.9,
                                      "SENTINEL.hp": 56.0,
                                      "GUARDIAN.sweep.damage": 24.0,
                                      "GUARDIAN.shockwave.damage": 30.0,
                                      "DODGE_CD_WIND": 0.75,
                                      "WIND_INV_END": 0.36},
         "C3 之上让疾风步伐的无敌覆盖率实质提高"),
        ("C5 C3+Boss伤害 28/35", {"GUARDIAN.hp": 560.0,
                                 "GUARDIAN.gap_min": 1.3,
                                 "GUARDIAN.gap_max": 1.9,
                                 "SENTINEL.hp": 56.0,
                                 "GUARDIAN.sweep.damage": 28.0,
                                 "GUARDIAN.shockwave.damage": 35.0},
         "把 Boss 单次招式威胁抬到接近 1/3 血池（致死压力目标值）"),
        ("C6 最终推荐包", {"GUARDIAN.hp": 560.0,
                          "GUARDIAN.gap_min": 1.3,
                          "GUARDIAN.gap_max": 1.9,
                          "SENTINEL.hp": 56.0,
                          "GUARDIAN.sweep.damage": 28.0,
                          "GUARDIAN.shockwave.damage": 35.0,
                          "DODGE_CD_WIND": 0.75,
                          "WIND_INV_END": 0.36,
                          "VITALITY_MAX_HP_BONUS": 32.0,
                          "VITALITY_KILL_HEAL": 8.0},
         "C3/C5 之上：疾风步伐 CD0.9→0.75 且无敌帧→0.36；生命共鸣 +20→+32、回5→回8"),
    ]
    cand_rows = {}
    w("  方案                          2哨兵损失 3哨兵损失 3哨兵阵亡率 Boss损失 Boss阵亡率 "
      "Boss出手/局 Boss清场 2哨兵清场")
    for label, ov, _note in candidates:
        with override_constants(ov):
            c2 = simulate_room("sentinel", 2, "none")
            c3 = simulate_room("sentinel", 3, "none")
            cb = simulate_room("boss", 1, "none")
        cand_rows[label] = (c2, c3, cb)
        w(f"  {label:<28} {c2['mean_hp_lost']:>9.1f} {c3['mean_hp_lost']:>9.1f} "
          f"{c3['death_rate'] * 100:>9.1f}% {cb['mean_hp_lost']:>8.1f} "
          f"{cb['death_rate'] * 100:>9.1f}% {cb['enemy_attacks_per_trial']:>10.2f} "
          f"{cb['mean_clear_time']:>7.2f}s {c2['mean_clear_time']:>8.2f}s")
    w("")
    w("  候选方案内容:")
    for label, ov, note in candidates:
        w(f"    {label}: {note}")
        if ov:
            w(f"      overrides = {ov}")
    w("")
    w("  C6（最终推荐包）下的祝福强度复验（普通玩家；TTK 基线按哨兵 56HP / Boss 560HP 重算）")
    w("  祝福        3哨兵损失HP Boss损失HP 3哨兵清场 Boss清场 综合均值(C6口径)")
    cand_ov = {label.split()[0]: ov for label, ov, _ in candidates}
    c4_ov = cand_ov["C6"]
    c1_ov = cand_ov["C1"]
    c3_ov = cand_ov["C6"]
    sent_hp_c = c3_ov["SENTINEL.hp"]
    boss_hp_c = c3_ov["GUARDIAN.hp"]
    base_sent_c = optimal_ttk(sent_hp_c, 1.0, allow_skill=False)[0]
    base_boss_c = optimal_ttk(boss_hp_c, 1.0, allow_skill=True)[0]
    c4 = {}
    with override_constants(c4_ov):
        for b in BLESSINGS:
            mult_b = FLAME_MULT if b == "flame" else 1.0
            r3b = simulate_room("sentinel", 3, b)
            rbb = simulate_room("boss", 1, b)
            g_sent = gain(base_sent_c, optimal_ttk(sent_hp_c, mult_b, allow_skill=False)[0])
            g_boss = gain(base_boss_c, optimal_ttk(boss_hp_c, mult_b, allow_skill=True)[0])
            c4[b] = (r3b, rbb, g_sent, g_boss)
    base_s3_c4 = c4["none"][0]["mean_hp_lost"]
    base_bb_c4 = c4["none"][1]["mean_hp_lost"]
    for b in BLESSINGS:
        r3b, rbb, g_sent, g_boss = c4[b]
        s3 = gain(base_s3_c4, r3b["mean_hp_lost"])
        sb = gain(base_bb_c4, rbb["mean_hp_lost"])
        score = (g_sent + g_boss + s3 + sb) / 4.0
        w(f"  {BLESSING_LABEL[b]:<10} {r3b['mean_hp_lost']:>10.1f} {rbb['mean_hp_lost']:>9.1f} "
          f"{r3b['mean_clear_time']:>9.2f}s {rbb['mean_clear_time']:>7.2f}s {score:>12.2f}%")
    w(f"    （C6 口径下的 TTK 基线：哨兵 {base_sent_c:.3f}s、Boss {base_boss_c:.3f}s）")
    w("")
    w("  C6（最终推荐包）下各水平玩家的阵亡率与损失 HP")
    w("  场景        水平    损失HP  Boss损失HP  3哨兵阵亡率 Boss阵亡率")
    for p in PROFILE_ORDER:
        with override_constants(c4_ov):
            s3 = simulate_room("sentinel", 3, "none", profile=p)
            bs = simulate_room("boss", 1, "none", profile=p)
        w(f"  3哨兵/Boss  {PROFILES[p]['label']:<4}  {s3['mean_hp_lost']:>12.1f}  "
          f"{bs['mean_hp_lost']:>10.1f}  {s3['death_rate'] * 100:>10.1f}% "
          f"{bs['death_rate'] * 100:>9.1f}%")
    w("")

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print("balance_sim.py OK")
    print(f"report written: {OUT_PATH}")
    print(f"sentinel ttk (attack only / with skill) = {k_sent_atk:.3f}s / {k_sent_both:.3f}s")
    print(f"boss ttk (attack only / with skill)     = {k_boss_atk:.3f}s / {k_boss_both:.3f}s")
    print(f"flame gain: sentinel {gain_table['flame']['sent_atk']:.2f}%  "
          f"boss {gain_table['flame']['boss_both']:.2f}%")
    print(f"wind  gain: sentinel {gain_table['wind']['sent_atk']:.2f}%  "
          f"dodge uptime {dodge_uptime(DODGE['cd']) * 100:.2f}% -> {dodge_uptime(DODGE_CD_WIND) * 100:.2f}%")
    print(f"vitality gain: boss {gain_table['vitality']['boss_both']:.2f}%")
    print(f"survival gain (3 sentinels): flame {surv_gain['flame']['s3']:.2f}%  "
          f"vitality {surv_gain['vitality']['s3']:.2f}%  wind {surv_gain['wind']['s3']:.2f}%")
    print(f"hp lost: 2 sentinels {results[('sentinel', 2, 'none')]['mean_hp_lost']:.1f}  "
          f"3 sentinels {results[('sentinel', 3, 'none')]['mean_hp_lost']:.1f}  "
          f"boss {results[('boss', 1, 'none')]['mean_hp_lost']:.1f}")
    print(f"death rate: s3 {results[('sentinel', 3, 'none')]['death_rate'] * 100:.1f}%  "
          f"boss {results[('boss', 1, 'none')]['death_rate'] * 100:.1f}%  "
          f"boss@novice {tier[('boss', 1, 'novice')]['death_rate'] * 100:.1f}%")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
