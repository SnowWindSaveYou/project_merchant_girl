#!/usr/bin/env python3
"""
《末世行商》主线剧情分支树查看/编辑工具

支持 CLI（给智能体）和 GUI（给人类）两种使用方式。

用法:
  # CLI 模式
  python story_tree.py list-keys <type>                  # 列出某类 key
  python story_tree.py show <type> <id>                  # 查看某条详情
  python story_tree.py tree [chapter_num]                # 查看主线分支树
  python story_tree.py flag-graph [flag]                 # 查看 flag 依赖图
  python story_tree.py search <query>                    # 全文搜索
  python story_tree.py edit <type> <id> <field> <value>  # 编辑字段
  python story_tree.py key-list create <name>            # 创建 key 列表
  python story_tree.py key-list add <name> <key> [<key>...]  # 添加 key
  python story_tree.py key-list remove <name> <key> [<key>...]  # 移除 key
  python story_tree.py key-list show <name>              # 查看列表内容
  python story_tree.py key-list list                     # 列出所有列表名
  python story_tree.py key-list delete <name>            # 删除列表
  python story_tree.py simulate                          # 模拟玩家走剧情 (CLI JSON)

  # GUI 模式
  python story_tree.py gui
"""

import argparse
import json
import os
import sys
import copy
from collections import defaultdict
from pathlib import Path
from typing import Any, Optional

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------

PROJECT_ROOT = Path(__file__).resolve().parent.parent
CONFIGS_DIR = PROJECT_ROOT / "assets" / "configs"
KEY_REGISTRY_PATH = Path(__file__).resolve().parent / "story_tree_keys.json"

DATA_FILES = {
    "chapters": "story_chapters.json",
    "story_dialogues": "story_dialogues.json",
    "tutorial_dialogues": "tutorial_dialogues.json",
    "story_events": "story_events.json",
    "campfire_dialogues": "campfire_dialogues.json",
    "npc_dialogues": "npc_dialogues.json",
    "quests": "quests.json",
    "random_events": "guaji_random_events.json",
}

KEY_TYPE_LABELS = {
    "chapters": "章节 (prologue, ch1, ch2, ...)",
    "dialogues": "主线对话 (SD_*)",
    "tutorial": "教程对话 (SD_TUTORIAL_*)",
    "campfires": "篝火对话 (CF_*)",
    "npc_dialogues": "NPC 对话 (NPC_*)",
    "events": "主线事件 (SEVT_*)",
    "random_events": "随机事件 (EVT_*)",
    "quests": "任务 (Q_*)",
    "flags": "Flag (全文件提取)",
    "choice_sets": "选项集 (CH_*)",
    "result_sets": "结果集 (RS_*)",
    "results": "结果条目 (RES_*)",
    "memories": "回忆碎片 (mem_*)",
    "ops": "操作指令 (add_relation_*, add_goodwill:*, ...)",
}


# ---------------------------------------------------------------------------
# 数据模型
# ---------------------------------------------------------------------------

class StoryData:
    """加载所有剧情 JSON 配置，提供统一查询接口。"""

    def __init__(self, configs_dir: Path = CONFIGS_DIR):
        self.configs_dir = configs_dir
        self.chapters: list[dict] = []
        self.dialogues: list[dict] = []
        self.campfire_dialogues: list[dict] = []
        self.tutorial_dialogues: list[dict] = []
        self.npc_dialogues: list[dict] = []
        self.story_events: list[dict] = []
        self.choice_sets: dict[str, list[dict]] = {}
        self.result_sets: dict[str, list[dict]] = {}
        self.quests: list[dict] = []
        self.random_events: list[dict] = []

        self._dialogue_by_id: dict[str, dict] = {}
        self._campfire_by_id: dict[str, dict] = {}
        self._npc_dialogue_by_id: dict[str, dict] = {}
        self._event_by_id: dict[str, dict] = {}
        self._quest_by_id: dict[str, dict] = {}
        self._random_event_by_id: dict[str, dict] = {}
        self._chapter_by_id: dict[str, dict] = {}

        self.flag_producers: dict[str, list[str]] = defaultdict(list)
        self.flag_consumers: dict[str, list[str]] = defaultdict(list)
        self.all_flags: set[str] = set()

        self._load_all()

    def _load_json(self, filename: str) -> Any:
        path = self.configs_dir / filename
        if not path.exists():
            return None
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)

    def _load_all(self):
        data = self._load_json(DATA_FILES["chapters"])
        if data:
            self.chapters = data
            for ch in self.chapters:
                self._chapter_by_id[ch["id"]] = ch

        data = self._load_json(DATA_FILES["story_dialogues"])
        if data and "dialogues" in data:
            self.dialogues = data["dialogues"]
            for d in self.dialogues:
                self._dialogue_by_id[d["id"]] = d

        data = self._load_json(DATA_FILES["campfire_dialogues"])
        if data and "dialogues" in data:
            self.campfire_dialogues = data["dialogues"]
            for d in self.campfire_dialogues:
                self._campfire_by_id[d["id"]] = d

        data = self._load_json(DATA_FILES["tutorial_dialogues"])
        if data and "dialogues" in data:
            self.tutorial_dialogues = data["dialogues"]
            for d in self.tutorial_dialogues:
                self._dialogue_by_id[d["id"]] = d  # tutorial dialogues also lookupable by ID

        data = self._load_json(DATA_FILES["npc_dialogues"])
        if data and "dialogues" in data:
            self.npc_dialogues = data["dialogues"]
            for d in self.npc_dialogues:
                self._npc_dialogue_by_id[d["id"]] = d

        data = self._load_json(DATA_FILES["story_events"])
        if data:
            self.story_events = data.get("events", [])
            self.choice_sets = data.get("choice_sets", {})
            self.result_sets = data.get("result_sets", {})
            for e in self.story_events:
                self._event_by_id[e["event_id"]] = e

        data = self._load_json(DATA_FILES["quests"])
        if data and "quests" in data:
            self.quests = data["quests"]
            for q in self.quests:
                self._quest_by_id[q["id"]] = q

        data = self._load_json(DATA_FILES["random_events"])
        if data and "events" in data:
            self.random_events = data["events"]
            for e in self.random_events:
                self._random_event_by_id[e.get("event_id", e.get("id", ""))] = e

        self._build_flag_graph()

    def _build_flag_graph(self):
        for ch in self.chapters:
            cond = ch.get("advance_conditions", {})
            if "flag" in cond:
                self.flag_consumers[cond["flag"]].append(ch["id"])
                self.all_flags.add(cond["flag"])
            for f in cond.get("required_flags", []):
                self.flag_consumers[f].append(ch["id"])
                self.all_flags.add(f)
            for f in ch.get("on_advance_flags", []):
                self.flag_producers[f].append(ch["id"])
                self.all_flags.add(f)

        for d in self.dialogues:
            did = d["id"]
            for f in d.get("required_flags", []):
                self.flag_consumers[f].append(did)
                self.all_flags.add(f)
            for f in d.get("forbidden_flags", []):
                self.all_flags.add(f)
            for ch in d.get("choices", []):
                for f in ch.get("set_flags", []):
                    self.flag_producers[f].append(did)
                    self.all_flags.add(f)

        for d in self.campfire_dialogues:
            did = d["id"]
            for f in d.get("required_flags", []):
                self.flag_consumers[f].append(did)
                self.all_flags.add(f)
            for f in d.get("forbidden_flags", []):
                self.all_flags.add(f)
            for ch in d.get("choices", []):
                for f in ch.get("set_flags", []):
                    self.flag_producers[f].append(did)
                    self.all_flags.add(f)

        for d in self.tutorial_dialogues:
            did = d["id"]
            for f in d.get("required_flags", []):
                self.flag_consumers[f].append(did)
                self.all_flags.add(f)
            for f in d.get("forbidden_flags", []):
                self.all_flags.add(f)
            for ch in d.get("choices", []):
                for f in ch.get("set_flags", []):
                    self.flag_producers[f].append(did)
                    self.all_flags.add(f)

        for d in self.npc_dialogues:
            did = d["id"]
            for f in d.get("required_flags", []):
                self.flag_consumers[f].append(did)
                self.all_flags.add(f)
            for f in d.get("forbidden_flags", []):
                self.all_flags.add(f)
            for ch in d.get("choices", []):
                for f in ch.get("set_flags", []):
                    self.flag_producers[f].append(did)
                    self.all_flags.add(f)

        for e in self.story_events:
            eid = e["event_id"]
            for f in e.get("required_flags", []):
                self.flag_consumers[f].append(eid)
                self.all_flags.add(f)
            for f in e.get("forbidden_flags", []):
                self.all_flags.add(f)

        for cs_id, choices in self.choice_sets.items():
            for c in choices:
                for f in c.get("show_condition", []):
                    self.flag_consumers[f].append(f"{cs_id}:{c['choice_id']}")
                    self.all_flags.add(f)
        for rs_id, results in self.result_sets.items():
            for r in results:
                rk = r.get("result_key", "")
                for f in r.get("set_flags", []):
                    self.flag_producers[f].append(rk)
                    self.all_flags.add(f)
                for f in r.get("clear_flags", []):
                    self.all_flags.add(f)

        for q in self.quests:
            qid = q["id"]
            if q.get("trigger_flag"):
                self.flag_consumers[q["trigger_flag"]].append(qid)
                self.all_flags.add(q["trigger_flag"])
            if q.get("complete_flag"):
                self.flag_producers[q["complete_flag"]].append(qid)
                self.all_flags.add(q["complete_flag"])

    def list_keys(self, key_type: str) -> list[str]:
        if key_type == "chapters":
            return [ch["id"] for ch in self.chapters]
        elif key_type == "dialogues":
            return [d["id"] for d in self.dialogues]
        elif key_type == "campfires":
            return [d["id"] for d in self.campfire_dialogues]
        elif key_type == "tutorial":
            return [d["id"] for d in self.tutorial_dialogues]
        elif key_type == "npc_dialogues":
            return [d["id"] for d in self.npc_dialogues]
        elif key_type == "events":
            return [e["event_id"] for e in self.story_events]
        elif key_type == "random_events":
            return [e.get("event_id", e.get("id", "")) for e in self.random_events]
        elif key_type == "quests":
            return [q["id"] for q in self.quests]
        elif key_type == "flags":
            return sorted(self.all_flags)
        elif key_type == "choice_sets":
            return sorted(self.choice_sets.keys())
        elif key_type == "result_sets":
            return sorted(self.result_sets.keys())
        elif key_type == "results":
            keys = []
            for rs_list in self.result_sets.values():
                for r in rs_list:
                    if "result_key" in r:
                        keys.append(r["result_key"])
            return sorted(keys)
        elif key_type == "memories":
            mems = set()
            for d in self.dialogues + self.tutorial_dialogues + self.campfire_dialogues + self.npc_dialogues:
                for ch in d.get("choices", []):
                    mem = ch.get("memory")
                    if mem and "id" in mem:
                        mems.add(mem["id"])
            return sorted(mems)
        elif key_type == "ops":
            ops = set()
            for d in self.dialogues + self.tutorial_dialogues + self.campfire_dialogues + self.npc_dialogues:
                for ch in d.get("choices", []):
                    for op in ch.get("ops", []):
                        ops.add(self._normalize_op(op))
            for rs_list in self.result_sets.values():
                for r in rs_list:
                    for op in r.get("ops", []):
                        ops.add(self._normalize_op(op))
            for q in self.quests:
                for op in q.get("reward_ops", []):
                    ops.add(self._normalize_op(op))
            return sorted(ops)
        else:
            return []

    @staticmethod
    def _normalize_op(op: str) -> str:
        parts = op.split(":")
        if len(parts) >= 2:
            try:
                int(parts[-1])
                return ":".join(parts[:-1]) + ":N"
            except ValueError:
                return op
        return op

    def get_detail(self, key_type: str, key_id: str) -> Optional[dict]:
        if key_type == "chapters":
            return self._chapter_by_id.get(key_id)
        elif key_type == "dialogues":
            return self._dialogue_by_id.get(key_id)
        elif key_type == "campfires":
            return self._campfire_by_id.get(key_id)
        elif key_type == "npc_dialogues":
            return self._npc_dialogue_by_id.get(key_id)
        elif key_type == "events":
            return self._event_by_id.get(key_id)
        elif key_type == "random_events":
            return self._random_event_by_id.get(key_id)
        elif key_type == "quests":
            return self._quest_by_id.get(key_id)
        elif key_type == "choice_sets":
            if key_id in self.choice_sets:
                return {"id": key_id, "choices": self.choice_sets[key_id]}
            return None
        elif key_type == "result_sets":
            if key_id in self.result_sets:
                return {"id": key_id, "results": self.result_sets[key_id]}
            return None
        elif key_type == "flags":
            if key_id in self.all_flags:
                return {
                    "flag": key_id,
                    "produced_by": self.flag_producers.get(key_id, []),
                    "consumed_by": self.flag_consumers.get(key_id, []),
                }
            return None
        elif key_type == "results":
            for rs_list in self.result_sets.values():
                for r in rs_list:
                    if r.get("result_key") == key_id:
                        return r
            return None
        elif key_type == "memories":
            for d in self.dialogues + self.tutorial_dialogues + self.campfire_dialogues + self.npc_dialogues:
                for ch in d.get("choices", []):
                    mem = ch.get("memory")
                    if mem and mem.get("id") == key_id:
                        return {**mem, "source_dialogue": d["id"], "source_choice": ch["text"]}
            return None
        return None

    def get_chapter_tree(self, chapter_num: Optional[int] = None) -> dict:
        chapters_out = []
        for ch in sorted(self.chapters, key=lambda c: c["chapter"]):
            if chapter_num is not None and ch["chapter"] != chapter_num:
                continue
            cnum = ch["chapter"]
            dials = [d for d in self.dialogues if d.get("chapter") == cnum]
            evts = [e for e in self.story_events if e.get("chapter") == cnum]
            flag_gates = {}
            for f in ch.get("on_advance_flags", []):
                flag_gates[f] = self.flag_consumers.get(f, [])
            dial_chains = []
            for d in dials:
                req = d.get("required_flags", [])
                sets = []
                for c in d.get("choices", []):
                    sets.extend(c.get("set_flags", []))
                dial_chains.append({
                    "id": d["id"], "title": d.get("title", ""),
                    "type": d.get("type", ""),
                    "required_flags": req, "sets_flags": list(set(sets)),
                })
            evt_chains = []
            for e in evts:
                req = e.get("required_flags", [])
                sets = []
                rs_id = e.get("result_set_id", "")
                if rs_id in self.result_sets:
                    for r in self.result_sets[rs_id]:
                        sets.extend(r.get("set_flags", []))
                evt_chains.append({
                    "id": e["event_id"], "name": e.get("event_name", ""),
                    "scene": e.get("scene", ""),
                    "required_flags": req, "sets_flags": list(set(sets)),
                    "next_event_id": e.get("next_event_id"),
                })
            chapters_out.append({
                "id": ch["id"], "chapter": ch["chapter"],
                "name": ch.get("name", ""), "subtitle": ch.get("subtitle", ""),
                "summary": ch.get("summary", ""),
                "advance_conditions": ch.get("advance_conditions", {}),
                "on_advance_flags": ch.get("on_advance_flags", []),
                "unlocks": ch.get("unlocks", []),
                "dialogues": dial_chains, "events": evt_chains,
                "flag_gates": flag_gates,
            })
        return {"chapters": chapters_out}

    def get_flag_graph(self, flag_name: Optional[str] = None) -> dict:
        if flag_name:
            if flag_name not in self.all_flags:
                return {"error": f"Flag '{flag_name}' not found"}
            return {
                "flag": flag_name,
                "produced_by": self.flag_producers.get(flag_name, []),
                "consumed_by": self.flag_consumers.get(flag_name, []),
            }
        else:
            result = {}
            for f in sorted(self.all_flags):
                result[f] = {
                    "produced_by": self.flag_producers.get(f, []),
                    "consumed_by": self.flag_consumers.get(f, []),
                }
            return result

    def search(self, query: str) -> dict:
        q = query.lower()
        results = defaultdict(list)
        for ch in self.chapters:
            if q in json.dumps(ch, ensure_ascii=False).lower():
                results["chapters"].append(ch["id"])
        for d in self.dialogues:
            if q in json.dumps(d, ensure_ascii=False).lower():
                results["dialogues"].append(d["id"])
        for d in self.campfire_dialogues:
            if q in json.dumps(d, ensure_ascii=False).lower():
                results["campfires"].append(d["id"])
        for d in self.tutorial_dialogues:
            if q in json.dumps(d, ensure_ascii=False).lower():
                results["tutorial"].append(d["id"])
        for d in self.npc_dialogues:
            if q in json.dumps(d, ensure_ascii=False).lower():
                results["npc_dialogues"].append(d["id"])
        for e in self.story_events:
            if q in json.dumps(e, ensure_ascii=False).lower():
                results["events"].append(e["event_id"])
        for cs_id, choices in self.choice_sets.items():
            if q in json.dumps(choices, ensure_ascii=False).lower():
                results["choice_sets"].append(cs_id)
        for rs_id, results_list in self.result_sets.items():
            if q in json.dumps(results_list, ensure_ascii=False).lower():
                results["result_sets"].append(rs_id)
        for q_item in self.quests:
            if q in json.dumps(q_item, ensure_ascii=False).lower():
                results["quests"].append(q_item["id"])
        return dict(results)

    def edit_field(self, key_type: str, key_id: str, field: str, value: str,
                   dry_run: bool = False) -> dict:
        source_info = self._locate_source(key_type, key_id)
        if not source_info:
            return {"error": f"Key '{key_id}' not found in type '{key_type}'"}
        filename, data_path = source_info
        filepath = self.configs_dir / filename
        with open(filepath, "r", encoding="utf-8") as f:
            root = json.load(f)
        target = self._navigate_path(root, data_path)
        if target is None:
            return {"error": f"Cannot navigate to data path: {data_path}"}
        new_value = self._parse_value(value)
        old_value = target.get(field)
        if old_value is None and field not in target:
            return {"info": f"Field '{field}' does not exist. Will create it.",
                    "old_value": None, "new_value": new_value}
        if dry_run:
            return {"dry_run": True, "old_value": old_value, "new_value": new_value}
        target[field] = new_value
        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(root, f, ensure_ascii=False, indent=2)
            f.write("\n")
        self._load_all()
        return {"success": True, "old_value": old_value, "new_value": new_value}

    def _locate_source(self, key_type: str, key_id: str) -> Optional[tuple[str, str]]:
        if key_type == "chapters":
            for i, ch in enumerate(self.chapters):
                if ch["id"] == key_id:
                    return (DATA_FILES["chapters"], f"[{i}]")
        elif key_type == "dialogues":
            for i, d in enumerate(self.dialogues):
                if d["id"] == key_id:
                    return (DATA_FILES["story_dialogues"], f"dialogues[{i}]")
        elif key_type == "campfires":
            for i, d in enumerate(self.campfire_dialogues):
                if d["id"] == key_id:
                    return (DATA_FILES["campfire_dialogues"], f"dialogues[{i}]")
        elif key_type == "tutorial":
            for i, d in enumerate(self.tutorial_dialogues):
                if d["id"] == key_id:
                    return (DATA_FILES["tutorial_dialogues"], f"dialogues[{i}]")
        elif key_type == "npc_dialogues":
            for i, d in enumerate(self.npc_dialogues):
                if d["id"] == key_id:
                    return (DATA_FILES["npc_dialogues"], f"dialogues[{i}]")
        elif key_type == "events":
            for i, e in enumerate(self.story_events):
                if e["event_id"] == key_id:
                    return (DATA_FILES["story_events"], f"events[{i}]")
        elif key_type == "quests":
            for i, q in enumerate(self.quests):
                if q["id"] == key_id:
                    return (DATA_FILES["quests"], f"quests[{i}]")
        return None

    @staticmethod
    def _navigate_path(root: Any, path: str) -> Any:
        obj = root
        parts = path.replace("]", "").split("[")
        for part in parts:
            if not part:
                continue
            if part.isdigit():
                obj = obj[int(part)]
            else:
                obj = obj[part]
        return obj

    @staticmethod
    def _parse_value(value: str) -> Any:
        try:
            return json.loads(value)
        except (json.JSONDecodeError, ValueError):
            pass
        try:
            return int(value)
        except ValueError:
            pass
        try:
            return float(value)
        except ValueError:
            pass
        if value.lower() == "true":
            return True
        if value.lower() == "false":
            return False
        if value.lower() == "null":
            return None
        return value


# ---------------------------------------------------------------------------
# 剧情模拟器
# ---------------------------------------------------------------------------

class PlayerState:
    """模拟玩家状态，追踪 flag、关系、好感等。"""

    def __init__(self):
        self.flags: set[str] = set()
        self.chapter: int = 0
        self.trips: int = 0
        self.settlements_visited: set[str] = set()
        self.goodwill: dict[str, int] = {}
        self.hidden_nodes_found: int = 0
        self.relation_linli: int = 0
        self.relation_taoxia: int = 0
        self.credits: int = 0
        self.fuel: int = 0

    def apply_ops(self, ops: list[str]):
        for op in ops:
            parts = op.split(":")
            if len(parts) >= 2:
                cmd = parts[0]
                if cmd == "add_relation_linli":
                    self.relation_linli += int(parts[-1])
                elif cmd == "add_relation_taoxia":
                    self.relation_taoxia += int(parts[-1])
                elif cmd == "add_goodwill" and len(parts) >= 3:
                    settlement = parts[1]
                    self.goodwill[settlement] = self.goodwill.get(settlement, 0) + int(parts[-1])
                elif cmd in ("add_credit", "add_credits"):
                    self.credits += int(parts[-1])
                elif cmd == "add_fuel":
                    self.fuel += int(parts[-1])
                elif cmd == "add_time":
                    self.trips += int(parts[-1])
                elif cmd == "set_flag":
                    self.flags.add(parts[1])
                elif cmd == "unlock_route" and len(parts) >= 2:
                    pass  # 解锁路线，暂不模拟

    def set_flags(self, flags: list[str]):
        for f in flags:
            self.flags.add(f)

    def clear_flags(self, flags: list[str]):
        for f in flags:
            self.flags.discard(f)

    def snapshot(self) -> dict:
        return {
            "flags": sorted(self.flags),
            "chapter": self.chapter,
            "trips": self.trips,
            "settlements_visited": sorted(self.settlements_visited),
            "goodwill": dict(self.goodwill),
            "hidden_nodes_found": self.hidden_nodes_found,
            "relation_linli": self.relation_linli,
            "relation_taoxia": self.relation_taoxia,
            "credits": self.credits,
            "fuel": self.fuel,
        }

    def restore(self, snap: dict):
        self.flags = set(snap["flags"])
        self.chapter = snap["chapter"]
        self.trips = snap["trips"]
        self.settlements_visited = set(snap.get("settlements_visited", []))
        self.goodwill = dict(snap.get("goodwill", {}))
        self.hidden_nodes_found = snap.get("hidden_nodes_found", 0)
        self.relation_linli = snap.get("relation_linli", 0)
        self.relation_taoxia = snap.get("relation_taoxia", 0)
        self.credits = snap.get("credits", 0)
        self.fuel = snap.get("fuel", 0)

    @property
    def avg_relation(self) -> float:
        return (self.relation_linli + self.relation_taoxia) / 2


class StorySimulator:
    """剧情模拟器：模拟玩家推进剧情、做选择、查看分支。"""

    def __init__(self, sd: StoryData):
        self.sd = sd
        self.state = PlayerState()
        self.history: list[dict] = []
        self._undo_stack: list[tuple[dict, int]] = []  # (snapshot, history_len)

    # ---- 条件检查 ----

    def _check_dialogue(self, d: dict) -> tuple[bool, list[str]]:
        """检查对话是否可触发，返回 (是否可触发, 缺失条件列表)。"""
        missing = []
        for f in d.get("required_flags", []):
            if f not in self.state.flags:
                missing.append(f"需要 flag: {f}")
        for f in d.get("forbidden_flags", []):
            if f in self.state.flags:
                missing.append(f"已有禁止 flag: {f}")
        if d.get("chapter", -1) > self.state.chapter:
            missing.append(f"需要章节 ≥ {d['chapter']}，当前 {self.state.chapter}")
        if d.get("min_trips", 0) > self.state.trips:
            missing.append(f"需要趟数 ≥ {d['min_trips']}，当前 {self.state.trips}")
        rs = d.get("relation_stage", "any")
        if rs != "any":
            avg = self.state.avg_relation
            if rs == "early" and avg >= 20:
                missing.append(f"关系阶段需 early(<20)，当前 {avg:.0f}")
            elif rs == "mid" and not (20 <= avg < 60):
                missing.append(f"关系阶段需 mid(20-59)，当前 {avg:.0f}")
            elif rs == "late" and avg < 60:
                missing.append(f"关系阶段需 late(≥60)，当前 {avg:.0f}")
        return (len(missing) == 0, missing)

    def _check_event(self, e: dict) -> tuple[bool, list[str]]:
        missing = []
        for f in e.get("required_flags", []):
            if f not in self.state.flags:
                missing.append(f"需要 flag: {f}")
        for f in e.get("forbidden_flags", []):
            if f in self.state.flags:
                missing.append(f"已有禁止 flag: {f}")
        if e.get("chapter", -1) > self.state.chapter:
            missing.append(f"需要章节 ≥ {e['chapter']}，当前 {self.state.chapter}")
        return (len(missing) == 0, missing)

    # ---- 获取可用内容 ----

    def get_available(self) -> dict:
        """获取当前所有可触发的内容，分类返回。"""
        result = {"dialogues": [], "events": [], "campfires": [], "tutorial": [], "npc_dialogues": []}
        for d in self.sd.dialogues:
            ok, _ = self._check_dialogue(d)
            if ok:
                result["dialogues"].append(d)
        for e in self.sd.story_events:
            ok, _ = self._check_event(e)
            if ok:
                result["events"].append(e)
        for d in self.sd.campfire_dialogues:
            ok, _ = self._check_dialogue(d)
            if ok:
                result["campfires"].append(d)
        for d in self.sd.tutorial_dialogues:
            ok, _ = self._check_dialogue(d)
            if ok:
                result["tutorial"].append(d)
        for d in self.sd.npc_dialogues:
            ok, _ = self._check_dialogue(d)
            if ok:
                result["npc_dialogues"].append(d)
        return result

    def get_locked(self) -> list[dict]:
        """获取当前不可触发的内容，附带原因。"""
        locked = []
        for d in self.sd.dialogues:
            ok, missing = self._check_dialogue(d)
            if not ok:
                locked.append({"id": d["id"], "title": d.get("title", ""),
                               "type": "dialogue", "reasons": missing})
        for e in self.sd.story_events:
            ok, missing = self._check_event(e)
            if not ok:
                locked.append({"id": e["event_id"], "name": e.get("event_name", ""),
                               "type": "event", "reasons": missing})
        for d in self.sd.campfire_dialogues:
            ok, missing = self._check_dialogue(d)
            if not ok:
                locked.append({"id": d["id"], "title": d.get("title", ""),
                               "type": "campfire", "reasons": missing})
        for d in self.sd.tutorial_dialogues:
            ok, missing = self._check_dialogue(d)
            if not ok:
                locked.append({"id": d["id"], "title": d.get("title", ""),
                               "type": "tutorial", "reasons": missing})
        for d in self.sd.npc_dialogues:
            ok, missing = self._check_dialogue(d)
            if not ok:
                locked.append({"id": d["id"], "title": d.get("title", ""),
                               "type": "npc_dialogue", "reasons": missing})
        return locked

    # ---- 可用内容快照 & 差异 ----

    def _available_id_set(self) -> set[str]:
        """返回当前所有可触发内容的 ID 集合（用于 diff）。"""
        ids = set()
        for d in self.sd.dialogues:
            ok, _ = self._check_dialogue(d)
            if ok:
                ids.add(d["id"])
        for e in self.sd.story_events:
            ok, _ = self._check_event(e)
            if ok:
                ids.add(e["event_id"])
        for d in self.sd.campfire_dialogues:
            ok, _ = self._check_dialogue(d)
            if ok:
                ids.add(d["id"])
        for d in self.sd.tutorial_dialogues:
            ok, _ = self._check_dialogue(d)
            if ok:
                ids.add(d["id"])
        for d in self.sd.npc_dialogues:
            ok, _ = self._check_dialogue(d)
            if ok:
                ids.add(d["id"])
        return ids

    def _id_to_label(self, item_id: str) -> str:
        """根据 ID 查找标题。"""
        for lookup in (self.sd._dialogue_by_id, self.sd._campfire_by_id,
                       self.sd._npc_dialogue_by_id, self.sd._chapter_by_id):
            if item_id in lookup:
                d = lookup[item_id]
                return d.get("title") or d.get("name") or d.get("event_name", item_id)
        if item_id in self.sd._event_by_id:
            return self.sd._event_by_id[item_id].get("event_name", item_id)
        return item_id

    def _compute_diff(self, before_ids: set[str], after_ids: set[str]) -> dict:
        """计算可用内容变化。"""
        added_ids = after_ids - before_ids
        removed_ids = before_ids - after_ids
        return {
            "added": sorted(added_ids),
            "added_labels": {iid: self._id_to_label(iid) for iid in sorted(added_ids)},
            "removed": sorted(removed_ids),
            "removed_labels": {iid: self._id_to_label(iid) for iid in sorted(removed_ids)},
        }

    # ---- 执行选择 ----

    def trigger_dialogue(self, dialogue_id: str, choice_idx: int) -> Optional[dict]:
        """触发对话并选择某个选项。"""
        d = self.sd._dialogue_by_id.get(dialogue_id)
        if not d:
            return None
        choices = d.get("choices", [])
        if choice_idx < 0 or choice_idx >= len(choices):
            return None

        before_ids = self._available_id_set()

        # 保存状态
        self._undo_stack.append((self.state.snapshot(), len(self.history)))

        choice = choices[choice_idx]
        self.state.apply_ops(choice.get("ops", []))
        self.state.set_flags(choice.get("set_flags", []))

        entry = {
            "action": "dialogue",
            "id": dialogue_id,
            "title": d.get("title", ""),
            "choice_text": choice.get("text", ""),
            "flags_set": choice.get("set_flags", []),
            "ops": choice.get("ops", []),
        }
        if choice.get("memory"):
            entry["memory"] = choice["memory"]
        if choice.get("result_text"):
            entry["result_text"] = choice["result_text"]
        self.history.append(entry)

        self._check_chapter_advance()

        after_ids = self._available_id_set()
        entry["available_diff"] = self._compute_diff(before_ids, after_ids)
        return entry

    def trigger_campfire(self, dialogue_id: str, choice_idx: int) -> Optional[dict]:
        d = self.sd._campfire_by_id.get(dialogue_id)
        if not d:
            return None
        choices = d.get("choices", [])
        if choice_idx < 0 or choice_idx >= len(choices):
            return None

        before_ids = self._available_id_set()

        self._undo_stack.append((self.state.snapshot(), len(self.history)))

        choice = choices[choice_idx]
        self.state.apply_ops(choice.get("ops", []))
        self.state.set_flags(choice.get("set_flags", []))

        entry = {
            "action": "campfire",
            "id": dialogue_id,
            "title": d.get("title", ""),
            "choice_text": choice.get("text", ""),
            "flags_set": choice.get("set_flags", []),
            "ops": choice.get("ops", []),
        }
        if choice.get("result_text"):
            entry["result_text"] = choice["result_text"]
        self.history.append(entry)
        self._check_chapter_advance()

        after_ids = self._available_id_set()
        entry["available_diff"] = self._compute_diff(before_ids, after_ids)
        return entry

    def trigger_npc_dialogue(self, dialogue_id: str, choice_idx: int) -> Optional[dict]:
        d = self.sd._npc_dialogue_by_id.get(dialogue_id)
        if not d:
            return None
        choices = d.get("choices", [])
        if choice_idx < 0 or choice_idx >= len(choices):
            return None

        before_ids = self._available_id_set()

        self._undo_stack.append((self.state.snapshot(), len(self.history)))

        choice = choices[choice_idx]
        self.state.apply_ops(choice.get("ops", []))
        self.state.set_flags(choice.get("set_flags", []))

        entry = {
            "action": "npc_dialogue",
            "id": dialogue_id,
            "title": d.get("title", ""),
            "choice_text": choice.get("text", ""),
            "flags_set": choice.get("set_flags", []),
            "ops": choice.get("ops", []),
        }
        if choice.get("result_text"):
            entry["result_text"] = choice["result_text"]
        self.history.append(entry)
        self._check_chapter_advance()

        after_ids = self._available_id_set()
        entry["available_diff"] = self._compute_diff(before_ids, after_ids)
        return entry

    def trigger_event(self, event_id: str, result_key: str) -> Optional[dict]:
        e = self.sd._event_by_id.get(event_id)
        if not e:
            return None

        before_ids = self._available_id_set()

        self._undo_stack.append((self.state.snapshot(), len(self.history)))

        rs_id = e.get("result_set_id", "")
        result = None
        if rs_id in self.sd.result_sets:
            for r in self.sd.result_sets[rs_id]:
                if r.get("result_key") == result_key:
                    result = r
                    break

        if not result:
            self._undo_stack.pop()
            return None

        self.state.apply_ops(result.get("ops", []))
        self.state.set_flags(result.get("set_flags", []))
        self.state.clear_flags(result.get("clear_flags", []))

        entry = {
            "action": "event",
            "id": event_id,
            "name": e.get("event_name", ""),
            "result_key": result_key,
            "choice_text": "",  # 填入选项文本
            "reward_desc": result.get("reward_desc", ""),
            "risk_desc": result.get("risk_desc", ""),
            "flags_set": result.get("set_flags", []),
            "flags_cleared": result.get("clear_flags", []),
            "ops": result.get("ops", []),
        }
        # 查找选项文本
        cs_id = e.get("choice_set_id", "")
        if cs_id in self.sd.choice_sets:
            for c in self.sd.choice_sets[cs_id]:
                if c.get("result_key") == result_key:
                    entry["choice_text"] = c.get("choice_text", "")
                    break
        self.history.append(entry)
        self._check_chapter_advance()

        after_ids = self._available_id_set()
        entry["available_diff"] = self._compute_diff(before_ids, after_ids)
        return entry

    # ---- 预览选择 ----

    def preview_choice(self, dialogue_id: str, choice_idx: int,
                       source: str = "dialogue") -> Optional[dict]:
        """预览选择某个选项后的效果，不实际修改状态。返回新解锁内容。"""
        if source == "dialogue":
            d = self.sd._dialogue_by_id.get(dialogue_id)
        elif source == "campfire":
            d = self.sd._campfire_by_id.get(dialogue_id)
        elif source == "npc_dialogue":
            d = self.sd._npc_dialogue_by_id.get(dialogue_id)
        else:
            return None

        if not d:
            return None
        choices = d.get("choices", [])
        if choice_idx < 0 or choice_idx >= len(choices):
            return None

        choice = choices[choice_idx]
        # 模拟设置 flag
        temp_flags = set(self.state.flags)
        for f in choice.get("set_flags", []):
            temp_flags.add(f)

        # 找新解锁的内容
        newly_available = []
        all_items = (
            [(dd, "dialogue") for dd in self.sd.dialogues] +
            [(dd, "tutorial") for dd in self.sd.tutorial_dialogues] +
            [(dd, "campfire") for dd in self.sd.campfire_dialogues] +
            [(dd, "npc_dialogue") for dd in self.sd.npc_dialogues] +
            [(ee, "event") for ee in self.sd.story_events]
        )
        for item, item_type in all_items:
            iid = item.get("id") or item.get("event_id", "")
            if iid == dialogue_id:
                continue
            req = set(item.get("required_flags", []))
            forb = set(item.get("forbidden_flags", []))
            # 在 temp 状态下可触发
            temp_ok = req.issubset(temp_flags) and not forb.intersection(temp_flags)
            # 在当前状态下不可触发
            cur_ok = req.issubset(self.state.flags) and not forb.intersection(self.state.flags)
            if temp_ok and not cur_ok:
                newly_available.append({
                    "id": iid,
                    "title": item.get("title") or item.get("event_name", ""),
                    "type": item_type,
                })

        return {
            "choice_text": choice.get("text", ""),
            "flags_set": choice.get("set_flags", []),
            "ops": choice.get("ops", []),
            "result_text": choice.get("result_text", ""),
            "unlocks": newly_available,
        }

    def preview_event_choice(self, event_id: str, result_key: str) -> Optional[dict]:
        """预览事件选项效果。"""
        e = self.sd._event_by_id.get(event_id)
        if not e:
            return None
        rs_id = e.get("result_set_id", "")
        result = None
        if rs_id in self.sd.result_sets:
            for r in self.sd.result_sets[rs_id]:
                if r.get("result_key") == result_key:
                    result = r
                    break
        if not result:
            return None

        temp_flags = set(self.state.flags)
        for f in result.get("set_flags", []):
            temp_flags.add(f)
        for f in result.get("clear_flags", []):
            temp_flags.discard(f)

        newly_available = []
        all_items = (
            [(dd, "dialogue") for dd in self.sd.dialogues] +
            [(dd, "tutorial") for dd in self.sd.tutorial_dialogues] +
            [(dd, "campfire") for dd in self.sd.campfire_dialogues] +
            [(dd, "npc_dialogue") for dd in self.sd.npc_dialogues] +
            [(ee, "event") for ee in self.sd.story_events]
        )
        for item, item_type in all_items:
            iid = item.get("id") or item.get("event_id", "")
            req = set(item.get("required_flags", []))
            forb = set(item.get("forbidden_flags", []))
            temp_ok = req.issubset(temp_flags) and not forb.intersection(temp_flags)
            cur_ok = req.issubset(self.state.flags) and not forb.intersection(self.state.flags)
            if temp_ok and not cur_ok:
                newly_available.append({
                    "id": iid,
                    "title": item.get("title") or item.get("event_name", ""),
                    "type": item_type,
                })

        # 找选项文本
        choice_text = ""
        cs_id = e.get("choice_set_id", "")
        if cs_id in self.sd.choice_sets:
            for c in self.sd.choice_sets[cs_id]:
                if c.get("result_key") == result_key:
                    choice_text = c.get("choice_text", "")
                    break

        return {
            "choice_text": choice_text,
            "flags_set": result.get("set_flags", []),
            "flags_cleared": result.get("clear_flags", []),
            "ops": result.get("ops", []),
            "reward_desc": result.get("reward_desc", ""),
            "risk_desc": result.get("risk_desc", ""),
            "unlocks": newly_available,
        }

    # ---- 章节推进 ----

    def _check_chapter_advance(self):
        for ch in self.sd.chapters:
            if ch["chapter"] == self.state.chapter:
                cond = ch.get("advance_conditions", {})
                if self._check_advance_conditions(cond):
                    for f in ch.get("on_advance_flags", []):
                        self.state.flags.add(f)
                    self.state.chapter += 1
                    self.history.append({
                        "action": "chapter_advance",
                        "from_chapter": ch["id"],
                        "to_chapter_num": self.state.chapter,
                        "flags_set": ch.get("on_advance_flags", []),
                    })
                break

    def _check_advance_conditions(self, cond: dict) -> bool:
        if "flag" in cond and cond["flag"] not in self.state.flags:
            return False
        if "required_flags" in cond:
            for f in cond["required_flags"]:
                if f not in self.state.flags:
                    return False
        if "min_trips" in cond and self.state.trips < cond["min_trips"]:
            return False
        if "min_settlements_visited" in cond:
            if len(self.state.settlements_visited) < cond["min_settlements_visited"]:
                return False
        if "min_goodwill_level" in cond and "min_goodwill_count" in cond:
            count = sum(1 for v in self.state.goodwill.values()
                        if v >= cond["min_goodwill_level"])
            if count < cond["min_goodwill_count"]:
                return False
        if "min_hidden_nodes_found" in cond:
            if self.state.hidden_nodes_found < cond["min_hidden_nodes_found"]:
                return False
        return True

    # ---- 撤销 / 重置 ----

    def undo(self) -> bool:
        if not self._undo_stack:
            return False
        snap, hist_len = self._undo_stack.pop()
        self.state.restore(snap)
        self.history = self.history[:hist_len]
        return True

    def reset(self):
        self.state = PlayerState()
        self.history = []
        self._undo_stack = []

    def manual_set_flag(self, flag: str):
        self.state.flags.add(flag)
        self._check_chapter_advance()

    def manual_clear_flag(self, flag: str):
        self.state.flags.discard(flag)

    def manual_set_trips(self, n: int):
        self.state.trips = n
        self._check_chapter_advance()


# ---------------------------------------------------------------------------
# Key 列表管理
# ---------------------------------------------------------------------------

class KeyRegistry:
    def __init__(self, path: Path = KEY_REGISTRY_PATH):
        self.path = path
        self.lists: dict[str, list[str]] = {}
        self._load()

    def _load(self):
        if self.path.exists():
            with open(self.path, "r", encoding="utf-8") as f:
                self.lists = json.load(f)

    def _save(self):
        with open(self.path, "w", encoding="utf-8") as f:
            json.dump(self.lists, f, ensure_ascii=False, indent=2)
            f.write("\n")

    def create(self, name: str) -> dict:
        if name in self.lists:
            return {"error": f"List '{name}' already exists"}
        self.lists[name] = []
        self._save()
        return {"success": True, "name": name, "keys": []}

    def delete(self, name: str) -> dict:
        if name not in self.lists:
            return {"error": f"List '{name}' not found"}
        del self.lists[name]
        self._save()
        return {"success": True, "deleted": name}

    def add_keys(self, name: str, keys: list[str]) -> dict:
        if name not in self.lists:
            return {"error": f"List '{name}' not found. Create it first."}
        added = [k for k in keys if k not in self.lists[name]]
        self.lists[name].extend(added)
        self._save()
        return {"success": True, "added": added, "total": len(self.lists[name])}

    def remove_keys(self, name: str, keys: list[str]) -> dict:
        if name not in self.lists:
            return {"error": f"List '{name}' not found"}
        removed = [k for k in keys if k in self.lists[name]]
        self.lists[name] = [k for k in self.lists[name] if k not in keys]
        self._save()
        return {"success": True, "removed": removed, "total": len(self.lists[name])}

    def show(self, name: str) -> dict:
        if name not in self.lists:
            return {"error": f"List '{name}' not found"}
        return {"name": name, "keys": self.lists[name]}

    def list_all(self) -> dict:
        return {name: len(keys) for name, keys in self.lists.items()}


# ---------------------------------------------------------------------------
# CLI 接口
# ---------------------------------------------------------------------------

def cli_main(args: list[str]):
    parser = argparse.ArgumentParser(
        prog="story_tree",
        description="《末世行商》主线剧情分支树工具",
    )
    sub = parser.add_subparsers(dest="command")

    p = sub.add_parser("list-keys", help="列出某类 key")
    p.add_argument("type", choices=list(KEY_TYPE_LABELS.keys()))

    p = sub.add_parser("show", help="查看某条详情")
    p.add_argument("type", choices=list(KEY_TYPE_LABELS.keys()))
    p.add_argument("id")

    p = sub.add_parser("tree", help="查看主线分支树")
    p.add_argument("chapter", nargs="?", type=int, default=None)

    p = sub.add_parser("flag-graph", help="查看 flag 依赖图")
    p.add_argument("flag", nargs="?", default=None)

    p = sub.add_parser("search", help="全文搜索")
    p.add_argument("query")

    p = sub.add_parser("edit", help="编辑字段")
    p.add_argument("type", choices=list(KEY_TYPE_LABELS.keys()))
    p.add_argument("id")
    p.add_argument("field")
    p.add_argument("value")
    p.add_argument("--dry-run", action="store_true")

    p = sub.add_parser("key-list", help="管理 key 列表")
    p.add_argument("action", choices=["create", "add", "remove", "show", "list", "delete"])
    p.add_argument("name", nargs="?")
    p.add_argument("keys", nargs="*")

    p = sub.add_parser("simulate", help="模拟玩家走剧情 (JSON 输出)")
    p.add_argument("--steps", nargs="*", help="模拟步骤: dialogue:ID:choice_idx 或 event:ID:result_key 或 flag:FLAG_NAME 或 trips:N")
    p.add_argument("--state", nargs="?", help="初始状态 JSON")

    sub.add_parser("gui", help="启动 GUI")

    parsed = parser.parse_args(args)
    if not parsed.command:
        parser.print_help()
        return

    sd = StoryData()
    kr = KeyRegistry()

    if parsed.command == "list-keys":
        keys = sd.list_keys(parsed.type)
        print(json.dumps({"type": parsed.type, "count": len(keys), "keys": keys},
                         ensure_ascii=False, indent=2))
    elif parsed.command == "show":
        detail = sd.get_detail(parsed.type, parsed.id)
        if detail is None:
            print(json.dumps({"error": f"'{parsed.id}' not found in '{parsed.type}'"},
                             ensure_ascii=False))
        else:
            print(json.dumps(detail, ensure_ascii=False, indent=2))
    elif parsed.command == "tree":
        print(json.dumps(sd.get_chapter_tree(parsed.chapter), ensure_ascii=False, indent=2))
    elif parsed.command == "flag-graph":
        print(json.dumps(sd.get_flag_graph(parsed.flag), ensure_ascii=False, indent=2))
    elif parsed.command == "search":
        print(json.dumps(sd.search(parsed.query), ensure_ascii=False, indent=2))
    elif parsed.command == "edit":
        result = sd.edit_field(parsed.type, parsed.id, parsed.field, parsed.value,
                               dry_run=parsed.dry_run)
        print(json.dumps(result, ensure_ascii=False, indent=2))
    elif parsed.command == "key-list":
        if parsed.action == "create":
            result = kr.create(parsed.name) if parsed.name else {"error": "List name required"}
        elif parsed.action == "add":
            result = kr.add_keys(parsed.name, parsed.keys) if parsed.name else {"error": "List name required"}
        elif parsed.action == "remove":
            result = kr.remove_keys(parsed.name, parsed.keys) if parsed.name else {"error": "List name required"}
        elif parsed.action == "show":
            result = kr.show(parsed.name) if parsed.name else {"error": "List name required"}
        elif parsed.action == "delete":
            result = kr.delete(parsed.name) if parsed.name else {"error": "List name required"}
        elif parsed.action == "list":
            result = kr.list_all()
        else:
            result = {"error": f"Unknown action"}
        print(json.dumps(result, ensure_ascii=False, indent=2))
    elif parsed.command == "simulate":
        sim = StorySimulator(sd)
        if parsed.state:
            try:
                init = json.loads(parsed.state)
                sim.state.restore(init)
            except Exception:
                pass
        if parsed.steps:
            for step in parsed.steps:
                parts = step.split(":", 2)
                if parts[0] == "dialogue" and len(parts) == 3:
                    sim.trigger_dialogue(parts[1], int(parts[2]))
                elif parts[0] == "event" and len(parts) == 3:
                    sim.trigger_event(parts[1], parts[2])
                elif parts[0] == "flag" and len(parts) >= 2:
                    sim.manual_set_flag(parts[1])
                elif parts[0] == "trips" and len(parts) >= 2:
                    sim.manual_set_trips(int(parts[1]))
        output = {
            "state": sim.state.snapshot(),
            "available": {k: [item.get("id") or item.get("event_id", "")
                              for item in v]
                          for k, v in sim.get_available().items()},
            "history": sim.history,
        }
        print(json.dumps(output, ensure_ascii=False, indent=2))
    elif parsed.command == "gui":
        _launch_gui(sd, kr)


# ---------------------------------------------------------------------------
# GUI 接口
# ---------------------------------------------------------------------------

# ---- 颜色方案 ----
C_BG = "#1e1e2e"
C_FG = "#cdd6f4"
C_ACCENT = "#89b4fa"
C_GREEN = "#a6e3a1"
C_RED = "#f38ba8"
C_YELLOW = "#f9e2af"
C_PURPLE = "#cba6f7"
C_ORANGE = "#fab387"
C_CYAN = "#94e2d5"
C_DIM = "#6c7086"
C_CARD = "#313244"
C_CARD2 = "#45475a"


def _launch_gui(sd: StoryData, kr: KeyRegistry):
    import tkinter as tk
    from tkinter import ttk, messagebox, simpledialog, scrolledtext

    root = tk.Tk()
    root.title("末世行商 - 主线剧情分支树工具")
    root.geometry("1400x900")
    root.configure(bg=C_BG)

    # ---- 全局样式 ----
    style = ttk.Style()
    style.theme_use("clam")
    style.configure(".", background=C_BG, foreground=C_FG, fieldbackground=C_CARD,
                    borderwidth=0, font=("", 11))
    style.configure("TNotebook", background=C_BG, borderwidth=0)
    style.configure("TNotebook.Tab", background=C_CARD, foreground=C_FG,
                    padding=[12, 6], font=("", 11, "bold"))
    style.map("TNotebook.Tab",
              background=[("selected", C_ACCENT)],
              foreground=[("selected", C_BG)])
    style.configure("Treeview", background=C_CARD, foreground=C_FG,
                    fieldbackground=C_CARD, rowheight=28,
                    font=("", 11))
    style.configure("Treeview.Heading", background=C_CARD2, foreground=C_FG,
                    font=("", 10, "bold"))
    style.map("Treeview", background=[("selected", C_ACCENT)],
              foreground=[("selected", C_BG)])
    style.configure("TButton", background=C_CARD2, foreground=C_FG,
                    padding=[8, 4], font=("", 10))
    style.map("TButton", background=[("active", C_ACCENT)],
              foreground=[("active", C_BG)])
    style.configure("TLabel", background=C_BG, foreground=C_FG)
    style.configure("TFrame", background=C_BG)
    style.configure("Card.TFrame", background=C_CARD)
    style.configure("TLabelframe", background=C_CARD, foreground=C_ACCENT)
    style.configure("TLabelframe.Label", background=C_CARD, foreground=C_ACCENT,
                    font=("", 10, "bold"))
    style.configure("TEntry", fieldbackground=C_CARD, foreground=C_FG)
    style.configure("TCombobox", fieldbackground=C_CARD, foreground=C_FG)

    notebook = ttk.Notebook(root)
    notebook.pack(fill="both", expand=True, padx=8, pady=8)

    sim = StorySimulator(sd)

    # ==================================================================
    # Tab 1: 剧情模拟器
    # ==================================================================
    sim_frame = ttk.Frame(notebook)
    notebook.add(sim_frame, text="  剧情模拟  ")

    # 顶部工具栏
    toolbar = ttk.Frame(sim_frame)
    toolbar.pack(fill="x", padx=5, pady=(5, 0))
    ttk.Button(toolbar, text="重置", command=lambda: _sim_reset()).pack(side="left", padx=2)
    ttk.Button(toolbar, text="撤销", command=lambda: _sim_undo()).pack(side="left", padx=2)
    ttk.Separator(toolbar, orient="vertical").pack(side="left", fill="y", padx=8)
    ttk.Label(toolbar, text="手动设趟数:").pack(side="left")
    trips_var = tk.StringVar(value="0")
    trips_spin = tk.Spinbox(toolbar, from_=0, to=999, textvariable=trips_var, width=5,
                            bg=C_CARD, fg=C_FG, font=("", 11),
                            command=lambda: _set_trips())
    trips_spin.pack(side="left", padx=4)
    ttk.Separator(toolbar, orient="vertical").pack(side="left", fill="y", padx=8)
    ttk.Label(toolbar, text="手动设Flag:").pack(side="left")
    flag_add_var = tk.StringVar()
    flag_add_entry = ttk.Entry(toolbar, textvariable=flag_add_var, width=20)
    flag_add_entry.pack(side="left", padx=4)
    ttk.Button(toolbar, text="添加", command=lambda: _manual_add_flag()).pack(side="left", padx=2)
    ttk.Button(toolbar, text="移除", command=lambda: _manual_remove_flag()).pack(side="left", padx=2)

    # 三栏布局
    pw = ttk.PanedWindow(sim_frame, orient="horizontal")
    pw.pack(fill="both", expand=True, padx=5, pady=5)

    # ---- 左栏: 玩家状态 ----
    state_panel = ttk.Frame(pw, width=280)
    pw.add(state_panel, weight=1)

    state_card = tk.Frame(state_panel, bg=C_CARD, bd=0)
    state_card.pack(fill="both", expand=True, padx=2, pady=2)

    tk.Label(state_card, text="当前状态", bg=C_CARD, fg=C_ACCENT,
             font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(10, 5))

    state_display = tk.Text(state_card, bg=C_CARD, fg=C_FG, font=("Menlo", 11),
                            wrap="word", bd=0, height=10, state="disabled",
                            selectbackground=C_ACCENT, selectforeground=C_BG)
    state_display.pack(fill="x", padx=10, pady=5)

    tk.Label(state_card, text="已设 Flag", bg=C_CARD, fg=C_YELLOW,
             font=("", 11, "bold")).pack(anchor="w", padx=10, pady=(10, 2))

    flag_listbox = tk.Listbox(state_card, bg=C_CARD, fg=C_GREEN, font=("Menlo", 10),
                              selectbackground=C_ACCENT, selectforeground=C_BG,
                              bd=0, height=8)
    flag_listbox.pack(fill="both", expand=True, padx=10, pady=(0, 10))

    # ---- 中栏: 可触发内容 ----
    avail_panel = ttk.Frame(pw, width=380)
    pw.add(avail_panel, weight=2)

    avail_card = tk.Frame(avail_panel, bg=C_CARD, bd=0)
    avail_card.pack(fill="both", expand=True, padx=2, pady=2)

    tk.Label(avail_card, text="可触发内容", bg=C_CARD, fg=C_GREEN,
             font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(10, 5))

    avail_tree = ttk.Treeview(avail_card, selectmode="browse",
                               columns=("type", "id", "title"), show="headings",
                               height=12)
    avail_tree.heading("type", text="类型")
    avail_tree.heading("id", text="ID")
    avail_tree.heading("title", text="标题")
    avail_tree.column("type", width=70, minwidth=60)
    avail_tree.column("id", width=160, minwidth=100)
    avail_tree.column("title", width=150, minwidth=80)
    avail_tree.pack(fill="both", expand=True, padx=10, pady=5)

    # 锁定内容（折叠）
    locked_toggle = tk.Label(avail_card, text="▶ 锁定内容 (点击展开)", bg=C_CARD,
                              fg=C_DIM, font=("", 10), cursor="hand2")
    locked_toggle.pack(anchor="w", padx=10)

    locked_frame = tk.Frame(avail_card, bg=C_CARD)
    locked_tree = ttk.Treeview(locked_frame, selectmode="browse",
                                columns=("id", "reasons"), show="headings", height=6)
    locked_tree.heading("id", text="ID")
    locked_tree.heading("reasons", text="锁定原因")
    locked_tree.column("id", width=180, minwidth=100)
    locked_tree.column("reasons", width=300, minwidth=100)

    _locked_visible = [False]

    def _toggle_locked():
        if _locked_visible[0]:
            locked_frame.pack_forget()
            locked_toggle.configure(text="▶ 锁定内容 (点击展开)")
        else:
            locked_frame.pack(fill="both", expand=True, padx=10, pady=(0, 10))
            locked_toggle.configure(text="▼ 锁定内容 (点击折叠)")
        _locked_visible[0] = not _locked_visible[0]

    locked_toggle.bind("<Button-1>", lambda e: _toggle_locked())

    # ---- 右栏: 对话内容 + 选项 ----
    content_panel = ttk.Frame(pw, width=500)
    pw.add(content_panel, weight=3)

    content_card = tk.Frame(content_panel, bg=C_CARD, bd=0)
    content_card.pack(fill="both", expand=True, padx=2, pady=2)

    tk.Label(content_card, text="对话内容", bg=C_CARD, fg=C_ACCENT,
             font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(10, 5))

    dialogue_display = tk.Text(content_card, bg=C_CARD, fg=C_FG, font=("", 12),
                               wrap="word", bd=0, height=20, state="disabled",
                               selectbackground=C_ACCENT, selectforeground=C_BG)
    dialogue_display.pack(fill="both", expand=True, padx=10, pady=5)

    # 选项区域
    choice_frame = tk.Frame(content_card, bg=C_CARD2, bd=0)
    choice_frame.pack(fill="x", padx=10, pady=(0, 5))

    tk.Label(choice_frame, text="选择一个选项:", bg=C_CARD2, fg=C_YELLOW,
             font=("", 11, "bold")).pack(anchor="w", padx=8, pady=(8, 4))

    choice_buttons_frame = tk.Frame(choice_frame, bg=C_CARD2)
    choice_buttons_frame.pack(fill="x", padx=8, pady=(0, 8))

    # ---- 底栏: 操作历史 ----
    hist_card = tk.Frame(sim_frame, bg=C_CARD, height=120)
    hist_card.pack(fill="x", padx=5, pady=(0, 5))
    hist_card.pack_propagate(False)

    tk.Label(hist_card, text="操作历史", bg=C_CARD, fg=C_PURPLE,
             font=("", 11, "bold")).pack(anchor="w", padx=10, pady=(5, 2))

    hist_display = tk.Text(hist_card, bg=C_CARD, fg=C_DIM, font=("Menlo", 10),
                           wrap="word", bd=0, height=5, state="disabled")
    hist_display.pack(fill="both", expand=True, padx=10, pady=(0, 5))

    # ---- 颜色标签 ----
    dialogue_display.tag_configure("narrator", foreground=C_DIM, font=("", 12, "italic"))
    dialogue_display.tag_configure("linli", foreground=C_CYAN, font=("", 12))
    dialogue_display.tag_configure("taoxia", foreground=C_YELLOW, font=("", 12))
    dialogue_display.tag_configure("npc", foreground=C_PURPLE, font=("", 12))
    dialogue_display.tag_configure("radio", foreground=C_ORANGE, font=("", 12, "italic"))
    dialogue_display.tag_configure("speaker", foreground=C_ACCENT, font=("", 12, "bold"))
    dialogue_display.tag_configure("choice_btn", foreground=C_GREEN, font=("", 12, "bold"))
    dialogue_display.tag_configure("flag_tag", foreground=C_RED, font=("", 10))
    dialogue_display.tag_configure("unlock_tag", foreground=C_GREEN, font=("", 10, "bold"))
    dialogue_display.tag_configure("ops_tag", foreground=C_DIM, font=("", 10))
    dialogue_display.tag_configure("result_text", foreground=C_CYAN, font=("", 12, "italic"))

    # ---- 模拟器逻辑 ----

    def _sim_refresh():
        """刷新整个模拟器界面。"""
        # 状态
        s = sim.state
        state_display.configure(state="normal")
        state_display.delete("1.0", "end")
        ch_name = "?"
        for ch in sd.chapters:
            if ch["chapter"] == s.chapter:
                ch_name = f"{ch.get('name', '')}({ch['id']})"
                break
        state_display.insert("end", f"章节: {ch_name}\n")
        state_display.insert("end", f"趟数: {s.trips}\n")
        state_display.insert("end", f"林砾关系: {s.relation_linli}  陶夏关系: {s.relation_taoxia}\n")
        state_display.insert("end", f"信用: {s.credits}  燃料: {s.fuel}\n")
        gw = ", ".join(f"{k}={v}" for k, v in sorted(s.goodwill.items())) if s.goodwill else "无"
        state_display.insert("end", f"好感: {gw}\n")
        state_display.configure(state="disabled")

        # Flag 列表
        flag_listbox.delete(0, "end")
        for f in sorted(s.flags):
            flag_listbox.insert("end", f)

        # 可触发内容
        avail_tree.delete(*avail_tree.get_children())
        av = sim.get_available()
        type_labels = {"dialogues": "对话", "events": "事件",
                       "campfires": "篝火", "npc_dialogues": "NPC"}
        for cat, items in av.items():
            for item in items:
                iid = item.get("id") or item.get("event_id", "")
                title = item.get("title") or item.get("event_name", "")
                avail_tree.insert("", "end", values=(type_labels.get(cat, cat), iid, title))

        # 锁定内容
        locked_tree.delete(*locked_tree.get_children())
        for l in sim.get_locked():
            iid = l.get("id") or l.get("event_id", "")
            reasons = "; ".join(l.get("reasons", []))
            locked_tree.insert("", "end", values=(iid, reasons))

        # 历史
        hist_display.configure(state="normal")
        hist_display.delete("1.0", "end")
        for i, h in enumerate(sim.history):
            action = h.get("action", "")
            if action == "dialogue":
                hist_display.insert("end",
                    f"  [{i}] 对话 {h['id']}「{h.get('title', '')}」"
                    f" → {h.get('choice_text', '')[:20]}\n")
            elif action == "campfire":
                hist_display.insert("end",
                    f"  [{i}] 篝火 {h['id']}「{h.get('title', '')}」"
                    f" → {h.get('choice_text', '')[:20]}\n")
            elif action == "npc_dialogue":
                hist_display.insert("end",
                    f"  [{i}] NPC {h['id']} → {h.get('choice_text', '')[:20]}\n")
            elif action == "event":
                hist_display.insert("end",
                    f"  [{i}] 事件 {h['id']}「{h.get('name', '')}」"
                    f" → {h.get('choice_text', '')[:20]}\n")
            elif action == "chapter_advance":
                hist_display.insert("end",
                    f"  [{i}] 章节推进 → {h.get('from_chapter', '')} "
                    f"(设 {', '.join(h.get('flags_set', []))})\n")
        hist_display.configure(state="disabled")

    def _show_dialogue_content(d: dict, source: str = "dialogue"):
        """在右栏显示对话步骤和选项。"""
        dialogue_display.configure(state="normal")
        dialogue_display.delete("1.0", "end")

        # 标题
        did = d.get("id") or d.get("event_id", "")
        title = d.get("title") or d.get("event_name", "")
        dtype = d.get("type", source)
        dialogue_display.insert("end", f"【{did}】{title}\n", "speaker")
        dialogue_display.insert("end", f"类型: {dtype}  章节: {d.get('chapter', '?')}\n\n", "ops_tag")

        if source == "event":
            _show_event_content(d)
            return

        # 步骤
        for step in d.get("steps", []):
            speaker = step.get("speaker", "narrator")
            text = step.get("text", "")
            expr = step.get("expression", "")
            tag = speaker if speaker in ("narrator", "linli", "taoxia", "radio") else "npc"
            prefix = {"narrator": "", "radio": "📻 "}.get(speaker, f"{speaker}: ")
            expr_str = f"({expr}) " if expr else ""
            dialogue_display.insert("end", f"  {prefix}{expr_str}{text}\n", tag)

        # 选项
        choices = d.get("choices", [])
        if choices:
            dialogue_display.insert("end", "\n")
            # 清除旧选项按钮
            for w in choice_buttons_frame.winfo_children():
                w.destroy()

            for ci, ch in enumerate(choices):
                text = ch.get("text", "")
                set_f = ch.get("set_flags", [])
                ops = ch.get("ops", [])

                # 选项预览
                preview = sim.preview_choice(did, ci, source)
                unlock_text = ""
                if preview and preview.get("unlocks"):
                    unlock_names = [u.get("title") or u.get("id", "")
                                    for u in preview["unlocks"][:5]]
                    unlock_text = f"  ★ 解锁: {', '.join(unlock_names)}"
                    if len(preview["unlocks"]) > 5:
                        unlock_text += f" 等{len(preview['unlocks'])}项"

                # 按钮
                btn_text = f"{ci+1}. {text}"
                btn = tk.Button(choice_buttons_frame, text=btn_text,
                                bg=C_CARD, fg=C_GREEN, font=("", 11),
                                activebackground=C_ACCENT, activeforeground=C_BG,
                                bd=1, relief="groove", anchor="w",
                                padx=8, pady=4,
                                command=lambda c=ci: _make_choice(did, c, source))
                btn.pack(fill="x", pady=2)

                # 预览信息
                flag_text = f"    → 设: {', '.join(set_f)}" if set_f else ""
                ops_text = f"  效果: {', '.join(ops)}" if ops else ""
                preview_line = f"{flag_text}{ops_text}{unlock_text}\n"
                dialogue_display.insert("end", f"  [{ci+1}] {text}\n", "choice_btn")
                if flag_text:
                    dialogue_display.insert("end", f"      {', '.join(set_f)}\n", "flag_tag")
                if ops_text:
                    dialogue_display.insert("end", f"      {', '.join(ops)}\n", "ops_tag")
                if unlock_text:
                    dialogue_display.insert("end", f"      {unlock_text}\n", "unlock_tag")
        else:
            for w in choice_buttons_frame.winfo_children():
                w.destroy()

        dialogue_display.configure(state="disabled")

    def _show_event_content(e: dict):
        """在右栏显示事件内容和选项。"""
        eid = e["event_id"]
        ename = e.get("event_name", "")
        scene = e.get("scene", "")
        summary = e.get("summary", "")
        remark = e.get("remark", "")

        dialogue_display.insert("end", f"场景: {scene}\n", "ops_tag")
        if summary:
            dialogue_display.insert("end", f"\n{summary}\n\n", "narrator")
        if remark:
            dialogue_display.insert("end", f"(备注: {remark})\n\n", "ops_tag")

        # 选项
        cs_id = e.get("choice_set_id", "")
        choices = sd.choice_sets.get(cs_id, [])
        if choices:
            dialogue_display.insert("end", "选项:\n", "speaker")
            for w in choice_buttons_frame.winfo_children():
                w.destroy()

            for c in choices:
                rk = c.get("result_key", "")
                ctext = c.get("choice_text", "")
                show_cond = c.get("show_condition", [])

                # 预览
                preview = sim.preview_event_choice(eid, rk)
                unlock_text = ""
                if preview and preview.get("unlocks"):
                    unlock_names = [u.get("title") or u.get("id", "")
                                    for u in preview["unlocks"][:5]]
                    unlock_text = f"  ★ 解锁: {', '.join(unlock_names)}"

                cond_text = f"  (需: {', '.join(show_cond)})" if show_cond else ""
                btn = tk.Button(choice_buttons_frame,
                                text=f"{rk[-1]}. {ctext}",
                                bg=C_CARD, fg=C_GREEN, font=("", 11),
                                activebackground=C_ACCENT, activeforeground=C_BG,
                                bd=1, relief="groove", anchor="w",
                                padx=8, pady=4,
                                command=lambda r=rk: _make_event_choice(eid, r))
                btn.pack(fill="x", pady=2)

                dialogue_display.insert("end", f"  [{rk[-1]}] {ctext}{cond_text}\n", "choice_btn")

                if preview:
                    if preview.get("flags_set"):
                        dialogue_display.insert("end",
                            f"      → 设: {', '.join(preview['flags_set'])}\n", "flag_tag")
                    if preview.get("reward_desc"):
                        dialogue_display.insert("end",
                            f"      奖励: {preview['reward_desc'][:40]}\n", "ops_tag")
                    if preview.get("risk_desc"):
                        dialogue_display.insert("end",
                            f"      风险: {preview['risk_desc'][:40]}\n", "flag_tag")
                    if unlock_text:
                        dialogue_display.insert("end", f"      {unlock_text}\n", "unlock_tag")
        else:
            for w in choice_buttons_frame.winfo_children():
                w.destroy()

        dialogue_display.configure(state="disabled")

    def _make_choice(dialogue_id: str, choice_idx: int, source: str):
        if source == "dialogue":
            result = sim.trigger_dialogue(dialogue_id, choice_idx)
        elif source == "campfire":
            result = sim.trigger_campfire(dialogue_id, choice_idx)
        elif source == "npc_dialogue":
            result = sim.trigger_npc_dialogue(dialogue_id, choice_idx)
        else:
            return
        if result:
            _show_choice_result(result)
            _sim_refresh()

    def _make_event_choice(event_id: str, result_key: str):
        result = sim.trigger_event(event_id, result_key)
        if result:
            _show_choice_result(result)
            _sim_refresh()

    def _show_choice_result(result: dict):
        """显示选择后的结果文本。"""
        dialogue_display.configure(state="normal")
        dialogue_display.delete("1.0", "end")

        dialogue_display.insert("end", "──── 选择结果 ────\n\n", "speaker")
        rt = result.get("result_text") or result.get("reward_desc", "")
        if rt:
            dialogue_display.insert("end", f"  {rt}\n\n", "result_text")
        if result.get("risk_desc"):
            dialogue_display.insert("end", f"  风险: {result['risk_desc']}\n", "flag_tag")
        if result.get("flags_set"):
            dialogue_display.insert("end",
                f"  ✓ 设置 flag: {', '.join(result['flags_set'])}\n", "unlock_tag")
        if result.get("flags_cleared"):
            dialogue_display.insert("end",
                f"  ✗ 清除 flag: {', '.join(result['flags_cleared'])}\n", "flag_tag")
        if result.get("ops"):
            dialogue_display.insert("end",
                f"  效果: {', '.join(result['ops'])}\n", "ops_tag")
        if result.get("memory"):
            mem = result["memory"]
            dialogue_display.insert("end",
                f"\n  回忆碎片: {mem.get('title', '')}\n", "unlock_tag")
            dialogue_display.insert("end",
                f"     {mem.get('desc', '')}\n", "narrator")

        # 可触发内容变化
        diff = result.get("available_diff")
        if diff:
            added = diff.get("added", [])
            removed = diff.get("removed", [])
            added_labels = diff.get("added_labels", {})
            removed_labels = diff.get("removed_labels", {})
            if added or removed:
                dialogue_display.insert("end", "\n──── 可触发内容变化 ────\n\n", "speaker")
                if added:
                    dialogue_display.insert("end", f"  + 新增 {len(added)} 项:\n", "unlock_tag")
                    for iid in added:
                        label = added_labels.get(iid, iid)
                        dialogue_display.insert("end", f"    + {label} ({iid})\n", "unlock_tag")
                if removed:
                    dialogue_display.insert("end", f"  - 移除 {len(removed)} 项:\n", "flag_tag")
                    for iid in removed:
                        label = removed_labels.get(iid, iid)
                        dialogue_display.insert("end", f"    - {label} ({iid})\n", "flag_tag")
                if not added and not removed:
                    dialogue_display.insert("end", "  (无变化)\n", "ops_tag")

        dialogue_display.insert("end", "\n── 点击左侧可触发内容继续 ──\n", "ops_tag")
        dialogue_display.configure(state="disabled")

        # 清除选项按钮
        for w in choice_buttons_frame.winfo_children():
            w.destroy()

    def _on_avail_select(event):
        sel = avail_tree.selection()
        if not sel:
            return
        values = avail_tree.item(sel[0], "values")
        if not values or len(values) < 3:
            return
        cat_label, item_id, _ = values

        # 找到对应数据
        if cat_label == "对话":
            d = sd._dialogue_by_id.get(item_id)
            if d:
                _show_dialogue_content(d, "dialogue")
        elif cat_label == "事件":
            e = sd._event_by_id.get(item_id)
            if e:
                dialogue_display.configure(state="normal")
                dialogue_display.delete("1.0", "end")
                _show_event_content(e)
        elif cat_label == "篝火":
            d = sd._campfire_by_id.get(item_id)
            if d:
                _show_dialogue_content(d, "campfire")
        elif cat_label == "NPC":
            d = sd._npc_dialogue_by_id.get(item_id)
            if d:
                _show_dialogue_content(d, "npc_dialogue")

    avail_tree.bind("<<TreeviewSelect>>", _on_avail_select)

    def _on_locked_select(event):
        sel = locked_tree.selection()
        if not sel:
            return
        values = locked_tree.item(sel[0], "values")
        if not values or len(values) < 2:
            return
        item_id, reasons = values
        dialogue_display.configure(state="normal")
        dialogue_display.delete("1.0", "end")
        dialogue_display.insert("end", f"🔒 {item_id}\n\n", "speaker")
        dialogue_display.insert("end", f"锁定原因:\n{reasons}\n", "flag_tag")
        dialogue_display.configure(state="disabled")

    locked_tree.bind("<<TreeviewSelect>>", _on_locked_select)

    def _sim_reset():
        if messagebox.askyesno("确认", "重置模拟器？所有进度将丢失。"):
            sim.reset()
            _sim_refresh()
            dialogue_display.configure(state="normal")
            dialogue_display.delete("1.0", "end")
            dialogue_display.insert("end", "模拟器已重置。点击左侧可触发内容开始。\n", "ops_tag")
            dialogue_display.configure(state="disabled")
            for w in choice_buttons_frame.winfo_children():
                w.destroy()

    def _sim_undo():
        if sim.undo():
            _sim_refresh()
            dialogue_display.configure(state="normal")
            dialogue_display.delete("1.0", "end")
            dialogue_display.insert("end", "已撤销上一步操作。\n", "ops_tag")
            dialogue_display.configure(state="disabled")
            for w in choice_buttons_frame.winfo_children():
                w.destroy()

    def _set_trips():
        try:
            n = int(trips_var.get())
            sim.manual_set_trips(n)
            _sim_refresh()
        except ValueError:
            pass

    def _manual_add_flag():
        f = flag_add_var.get().strip()
        if f:
            sim.manual_set_flag(f)
            _sim_refresh()
            flag_add_var.set("")

    def _manual_remove_flag():
        sel = flag_listbox.curselection()
        if sel:
            f = flag_listbox.get(sel[0])
            sim.manual_clear_flag(f)
            _sim_refresh()

    # 初始刷新
    _sim_refresh()
    dialogue_display.configure(state="normal")
    dialogue_display.insert("end",
        "欢迎来到剧情模拟器！\n\n"
        "左侧显示当前玩家状态和已设 Flag。\n"
        "中间显示当前可触发的对话/事件。\n"
        "点击可触发内容后，在此处查看对话和选项。\n"
        "选择一个选项后，状态会更新，新的内容可能解锁。\n\n"
        "点击左侧可触发内容开始 →\n", "ops_tag")
    dialogue_display.configure(state="disabled")

    # ==================================================================
    # Tab 2: 分支地图
    # ==================================================================
    map_frame = ttk.Frame(notebook)
    notebook.add(map_frame, text="  分支地图  ")

    map_toolbar = ttk.Frame(map_frame)
    map_toolbar.pack(fill="x", padx=5, pady=5)
    ttk.Label(map_toolbar, text="章节:").pack(side="left")
    map_ch_var = tk.StringVar(value="all")
    map_ch_combo = ttk.Combobox(map_toolbar, textvariable=map_ch_var,
                                 values=["all"] + [str(i) for i in range(8)],
                                 width=8, state="readonly")
    map_ch_combo.pack(side="left", padx=5)
    ttk.Button(map_toolbar, text="刷新",
               command=lambda: _refresh_map()).pack(side="left", padx=5)

    map_canvas_frame = ttk.Frame(map_frame)
    map_canvas_frame.pack(fill="both", expand=True, padx=5, pady=5)

    map_canvas = tk.Canvas(map_canvas_frame, bg=C_BG, highlightthickness=0)
    map_scroll_h = ttk.Scrollbar(map_canvas_frame, orient="horizontal",
                                  command=map_canvas.xview)
    map_scroll_v = ttk.Scrollbar(map_canvas_frame, orient="vertical",
                                  command=map_canvas.yview)
    map_canvas.configure(xscrollcommand=map_scroll_h.set,
                         yscrollcommand=map_scroll_v.set)
    map_scroll_v.pack(side="right", fill="y")
    map_scroll_h.pack(side="bottom", fill="x")
    map_canvas.pack(fill="both", expand=True)

    map_detail = scrolledtext.ScrolledText(map_frame, height=6, wrap="word",
                                            bg=C_CARD, fg=C_FG, font=("Menlo", 10),
                                            bd=0)
    map_detail.pack(fill="x", padx=5, pady=(0, 5))

    _map_nodes = {}  # node_id → canvas rect coords

    def _refresh_map():
        map_canvas.delete("all")
        _map_nodes.clear()

        ch_filter = map_ch_var.get()
        target_chapters = []
        for ch in sorted(sd.chapters, key=lambda c: c["chapter"]):
            if ch_filter == "all" or ch["chapter"] == int(ch_filter):
                target_chapters.append(ch)

        # 构建节点数据
        nodes = []  # (x, y, w, h, node_id, label, color, data)
        y = 30
        x_start = 50
        node_w = 200
        node_h = 36

        for ch in target_chapters:
            cnum = ch["chapter"]
            # 章节头
            ch_id = f"ch_{ch['id']}"
            ch_label = f"[{cnum}] {ch.get('name', '')} - {ch.get('subtitle', '')}"
            nodes.append((x_start, y, 280, node_h, ch_id, ch_label, C_ACCENT, ch))
            y += node_h + 10

            # 该章的对话
            dials = [d for d in sd.dialogues if d.get("chapter") == cnum]
            for d in dials:
                did = d["id"]
                d_label = f"💬 {did} - {d.get('title', '')}"
                # 颜色：根据 flag 状态
                color = C_CYAN
                if d.get("required_flags"):
                    color = C_YELLOW
                nodes.append((x_start + 40, y, node_w, node_h - 4, did, d_label, color, d))

                # 选项分支
                choices = d.get("choices", [])
                if len(choices) > 1:
                    for ci, c in enumerate(choices):
                        ckey = f"{did}_c{ci}"
                        c_label = f"  → {c.get('text', '')[:25]}"
                        set_f = c.get("set_flags", [])
                        c_color = C_GREEN if set_f else C_DIM
                        nodes.append((x_start + 80, y, node_w, node_h - 8, ckey, c_label, c_color, c))
                        if ci < len(choices) - 1:
                            y += node_h - 4
                        # 分支标志 flag
                        if set_f:
                            flag_label = f"    flag: {', '.join(set_f[:2])}"
                            fid = f"{ckey}_f"
                            nodes.append((x_start + 120, y, node_w, node_h - 8, fid, flag_label, C_RED, None))
                            if ci < len(choices) - 1:
                                y += node_h - 4

                y += node_h

            # 该章的事件
            evts = [e for e in sd.story_events if e.get("chapter") == cnum]
            for e in evts:
                eid = e["event_id"]
                e_label = f"⚡ {eid} - {e.get('event_name', '')}"
                nodes.append((x_start + 40, y, node_w, node_h - 4, eid, e_label, C_PURPLE, e))

                # 选项
                cs_id = e.get("choice_set_id", "")
                choices = sd.choice_sets.get(cs_id, [])
                if len(choices) > 1:
                    for ci, c in enumerate(choices):
                        ckey = f"{eid}_c{ci}"
                        c_label = f"  → {c.get('choice_text', '')[:25]}"
                        rk = c.get("result_key", "")
                        # 查结果的 flag
                        rs_id = e.get("result_set_id", "")
                        set_f = []
                        if rs_id in sd.result_sets:
                            for r in sd.result_sets[rs_id]:
                                if r.get("result_key") == rk:
                                    set_f = r.get("set_flags", [])
                                    break
                        c_color = C_GREEN if set_f else C_DIM
                        nodes.append((x_start + 80, y, node_w, node_h - 8, ckey, c_label, c_color, c))
                        if ci < len(choices) - 1:
                            y += node_h - 4
                        if set_f:
                            flag_label = f"    flag: {', '.join(set_f[:2])}"
                            fid = f"{ckey}_f"
                            nodes.append((x_start + 120, y, node_w, node_h - 8, fid, flag_label, C_RED, None))
                            if ci < len(choices) - 1:
                                y += node_h - 4

                y += node_h

            y += 30  # 章节间距

        # 绘制节点
        for (x, yy, w, h, nid, label, color, data) in nodes:
            map_canvas.create_rectangle(x, yy, x + w, yy + h,
                                         fill=color, outline=C_BG, width=1,
                                         tags=("node", nid))
            # 文字
            text_color = C_BG if color in (C_ACCENT, C_GREEN, C_YELLOW) else C_FG
            map_canvas.create_text(x + 8, yy + h // 2, text=label,
                                    anchor="w", fill=text_color,
                                    font=("", 10), tags=("node", nid))
            _map_nodes[nid] = data

        # 连线：flag 依赖（简化版，只画章节内的）
        # ... 此处可扩展画 flag 依赖的箭头

        # 滚动区域
        if nodes:
            max_y = max(yy + h for (x, yy, w, h, *_) in nodes) + 50
            max_x = max(x + w for (x, yy, w, h, *_) in nodes) + 50
            map_canvas.configure(scrollregion=(0, 0, max_x, max_y))

    # 点击节点显示详情
    def _on_map_click(event):
        cx = map_canvas.canvasx(event.x)
        cy = map_canvas.canvasy(event.y)
        items = map_canvas.find_overlapping(cx - 2, cy - 2, cx + 2, cy + 2)
        for item in items:
            tags = map_canvas.gettags(item)
            for tag in tags:
                if tag in _map_nodes and _map_nodes[tag] is not None:
                    data = _map_nodes[tag]
                    map_detail.configure(state="normal")
                    map_detail.delete("1.0", "end")
                    map_detail.insert("end", json.dumps(data, ensure_ascii=False, indent=2))
                    map_detail.configure(state="disabled")
                    return

    map_canvas.bind("<Button-1>", _on_map_click)

    _refresh_map()

    # ==================================================================
    # Tab 3: Flag 流转
    # ==================================================================
    flag_frame = ttk.Frame(notebook)
    notebook.add(flag_frame, text="  Flag 流转  ")

    flag_toolbar = ttk.Frame(flag_frame)
    flag_toolbar.pack(fill="x", padx=5, pady=5)
    ttk.Label(flag_toolbar, text="Flag:").pack(side="left")
    flag_var = tk.StringVar()
    flag_entry = ttk.Combobox(flag_toolbar, textvariable=flag_var, width=40)
    flag_entry["values"] = sorted(sd.all_flags)
    flag_entry.pack(side="left", padx=5)
    ttk.Button(flag_toolbar, text="查询", command=lambda: _query_flag()).pack(side="left")
    ttk.Button(flag_toolbar, text="显示全图",
               command=lambda: _show_full_flags()).pack(side="left", padx=5)

    # 上下可视化
    flag_viz = tk.Frame(flag_frame, bg=C_BG)
    flag_viz.pack(fill="both", expand=True, padx=5, pady=5)

    # 上游 (谁设置了这个 flag)
    up_frame = tk.Frame(flag_viz, bg=C_CARD)
    up_frame.pack(side="left", fill="both", expand=True, padx=(0, 3))
    tk.Label(up_frame, text="↑ 设置此 Flag 的来源", bg=C_CARD, fg=C_GREEN,
             font=("", 11, "bold")).pack(anchor="w", padx=8, pady=(8, 4))

    up_listbox = tk.Listbox(up_frame, bg=C_CARD, fg=C_GREEN, font=("Menlo", 11),
                             selectbackground=C_ACCENT, bd=0)
    up_listbox.pack(fill="both", expand=True, padx=8, pady=(0, 8))

    # 中间 (flag 本身)
    mid_frame = tk.Frame(flag_viz, bg=C_CARD, width=200)
    mid_frame.pack(side="left", fill="y", padx=3)
    mid_frame.pack_propagate(False)

    tk.Label(mid_frame, text="Flag", bg=C_CARD, fg=C_YELLOW,
             font=("", 12, "bold")).pack(anchor="w", padx=8, pady=(8, 4))
    flag_name_label = tk.Label(mid_frame, text="(选择一个 Flag)", bg=C_CARD, fg=C_FG,
                                font=("", 11), wraplength=180)
    flag_name_label.pack(anchor="w", padx=8)

    # 下游 (谁需要这个 flag)
    down_frame = tk.Frame(flag_viz, bg=C_CARD)
    down_frame.pack(side="left", fill="both", expand=True, padx=(3, 0))
    tk.Label(down_frame, text="↓ 需要此 Flag 的内容", bg=C_CARD, fg=C_RED,
             font=("", 11, "bold")).pack(anchor="w", padx=8, pady=(8, 4))

    down_listbox = tk.Listbox(down_frame, bg=C_CARD, fg=C_RED, font=("Menlo", 11),
                               selectbackground=C_ACCENT, bd=0)
    down_listbox.pack(fill="both", expand=True, padx=8, pady=(0, 8))

    # 点击上下游条目查看详情
    flag_detail = scrolledtext.ScrolledText(flag_frame, height=6, wrap="word",
                                             bg=C_CARD, fg=C_FG, font=("Menlo", 10), bd=0)
    flag_detail.pack(fill="x", padx=5, pady=(0, 5))

    def _query_flag():
        f = flag_var.get().strip()
        if not f:
            return
        graph = sd.get_flag_graph(f)
        if "error" in graph:
            flag_name_label.configure(text=graph["error"])
            return

        flag_name_label.configure(text=f)

        up_listbox.delete(0, "end")
        for p in graph.get("produced_by", []):
            up_listbox.insert("end", p)

        down_listbox.delete(0, "end")
        for c in graph.get("consumed_by", []):
            down_listbox.insert("end", c)

    def _show_full_flags():
        graph = sd.get_flag_graph()
        flag_detail.configure(state="normal")
        flag_detail.delete("1.0", "end")
        for f, info in list(graph.items())[:30]:
            producers = ", ".join(info["produced_by"][:3])
            consumers = ", ".join(info["consumed_by"][:3])
            flag_detail.insert("end",
                f"{f}\n  ↑ {producers}\n  ↓ {consumers}\n\n")
        if len(graph) > 30:
            flag_detail.insert("end", f"... 共 {len(graph)} 个 flag\n")
        flag_detail.configure(state="disabled")

    def _on_up_select(event):
        sel = up_listbox.curselection()
        if not sel:
            return
        node_id = up_listbox.get(sel[0])
        _show_node_detail(node_id)

    def _on_down_select(event):
        sel = down_listbox.curselection()
        if not sel:
            return
        node_id = down_listbox.get(sel[0])
        _show_node_detail(node_id)

    def _show_node_detail(node_id: str):
        # 尝试在所有类型中查找
        for lookup in [sd._dialogue_by_id, sd._campfire_by_id,
                       sd._npc_dialogue_by_id, sd._event_by_id,
                       sd._chapter_by_id, sd._quest_by_id]:
            if node_id in lookup:
                data = lookup[node_id]
                flag_detail.configure(state="normal")
                flag_detail.delete("1.0", "end")
                flag_detail.insert("end", json.dumps(data, ensure_ascii=False, indent=2))
                flag_detail.configure(state="disabled")
                return
        # 结果条目
        for rs_list in sd.result_sets.values():
            for r in rs_list:
                if r.get("result_key") == node_id:
                    flag_detail.configure(state="normal")
                    flag_detail.delete("1.0", "end")
                    flag_detail.insert("end", json.dumps(r, ensure_ascii=False, indent=2))
                    flag_detail.configure(state="disabled")
                    return
        flag_detail.configure(state="normal")
        flag_detail.delete("1.0", "end")
        flag_detail.insert("end", f"(未找到 {node_id} 的详情)")
        flag_detail.configure(state="disabled")

    up_listbox.bind("<<ListboxSelect>>", _on_up_select)
    down_listbox.bind("<<ListboxSelect>>", _on_down_select)

    # ==================================================================
    # Tab 4: Key 列表
    # ==================================================================
    kl_frame = ttk.Frame(notebook)
    notebook.add(kl_frame, text="  Key 列表  ")

    kl_left = ttk.Frame(kl_frame, width=350)
    kl_left.pack(side="left", fill="y", padx=(5, 3), pady=5)
    kl_left.pack_propagate(False)

    kl_btn_frame = ttk.Frame(kl_left)
    kl_btn_frame.pack(fill="x", padx=5, pady=5)
    ttk.Button(kl_btn_frame, text="新建", command=lambda: _kl_create()).pack(side="left", padx=2)
    ttk.Button(kl_btn_frame, text="删除", command=lambda: _kl_delete()).pack(side="left", padx=2)
    ttk.Button(kl_btn_frame, text="刷新", command=lambda: _kl_refresh()).pack(side="left", padx=2)

    kl_tree = ttk.Treeview(kl_left, selectmode="browse", columns=("count",), show="tree headings")
    kl_tree.heading("#0", text="列表名")
    kl_tree.heading("count", text="数量")
    kl_scroll = ttk.Scrollbar(kl_left, orient="vertical", command=kl_tree.yview)
    kl_tree.configure(yscrollcommand=kl_scroll.set)
    kl_scroll.pack(side="right", fill="y")
    kl_tree.pack(fill="both", expand=True)

    kl_right = ttk.Frame(kl_frame)
    kl_right.pack(side="left", fill="both", expand=True, padx=(3, 5), pady=5)

    kl_content = tk.Listbox(kl_right, bg=C_CARD, fg=C_FG, font=("Menlo", 11),
                             selectbackground=C_ACCENT, bd=0)
    kl_content.pack(fill="both", expand=True)

    kl_input_frame = ttk.Frame(kl_right)
    kl_input_frame.pack(fill="x", padx=5, pady=5)
    ttk.Label(kl_input_frame, text="Key:").pack(side="left")
    kl_key_var = tk.StringVar()
    ttk.Entry(kl_input_frame, textvariable=kl_key_var, width=25).pack(side="left", padx=5)
    ttk.Button(kl_input_frame, text="添加",
               command=lambda: _kl_add_key()).pack(side="left", padx=2)
    ttk.Button(kl_input_frame, text="移除",
               command=lambda: _kl_remove_key()).pack(side="left", padx=2)

    kl_import_frame = ttk.Frame(kl_right)
    kl_import_frame.pack(fill="x", padx=5, pady=5)
    ttk.Label(kl_import_frame, text="从类型导入:").pack(side="left")
    kl_import_var = tk.StringVar(value="flags")
    ttk.Combobox(kl_import_frame, textvariable=kl_import_var,
                  values=list(KEY_TYPE_LABELS.keys()), width=12,
                  state="readonly").pack(side="left", padx=5)
    ttk.Button(kl_import_frame, text="导入",
               command=lambda: _kl_import()).pack(side="left", padx=2)

    kl_detail = scrolledtext.ScrolledText(kl_right, height=6, wrap="word",
                                           bg=C_CARD, fg=C_FG, font=("Menlo", 10), bd=0)
    kl_detail.pack(fill="both", expand=True, padx=5, pady=5)

    _kl_selected = [None]

    def _kl_refresh():
        kl_tree.delete(*kl_tree.get_children())
        for name, count in sorted(kr.list_all().items()):
            kl_tree.insert("", "end", text=name, values=(count,))

    def _kl_create():
        name = simpledialog.askstring("新建列表", "列表名称:", parent=root)
        if name:
            result = kr.create(name)
            if "error" in result:
                messagebox.showerror("错误", result["error"])
            else:
                _kl_refresh()

    def _kl_delete():
        sel = kl_tree.selection()
        if not sel:
            return
        name = kl_tree.item(sel[0], "text")
        if messagebox.askyesno("确认", f"删除列表 '{name}'？"):
            kr.delete(name)
            _kl_refresh()
            kl_content.delete(0, "end")
            _kl_selected[0] = None

    def _kl_show(name: str):
        kl_content.delete(0, "end")
        data = kr.show(name)
        if "error" in data:
            return
        for k in data["keys"]:
            kl_content.insert("end", k)
        _kl_selected[0] = name

    def _on_kl_select(event):
        sel = kl_tree.selection()
        if not sel:
            return
        name = kl_tree.item(sel[0], "text")
        _kl_show(name)

    kl_tree.bind("<<TreeviewSelect>>", _on_kl_select)

    def _kl_add_key():
        name = _kl_selected[0]
        if not name:
            return
        key = kl_key_var.get().strip()
        if key:
            kr.add_keys(name, [key])
            _kl_show(name)
            _kl_refresh()
            kl_key_var.set("")

    def _kl_remove_key():
        name = _kl_selected[0]
        if not name:
            return
        sel = kl_content.curselection()
        key = kl_content.get(sel[0]) if sel else kl_key_var.get().strip()
        if key:
            kr.remove_keys(name, [key])
            _kl_show(name)
            _kl_refresh()

    def _kl_import():
        name = _kl_selected[0]
        if not name:
            messagebox.showinfo("提示", "请先选择或创建一个列表")
            return
        keys = sd.list_keys(kl_import_var.get())
        if keys:
            result = kr.add_keys(name, keys)
            _kl_show(name)
            _kl_refresh()
            messagebox.showinfo("完成", f"导入 {len(result.get('added', []))} 个新 key")

    def _on_kl_content_select(event):
        sel = kl_content.curselection()
        if not sel:
            return
        key = kl_content.get(sel[0])
        kl_detail.configure(state="normal")
        kl_detail.delete("1.0", "end")
        for kt in KEY_TYPE_LABELS:
            detail = sd.get_detail(kt, key)
            if detail:
                kl_detail.insert("end", f"[{kt}]\n")
                kl_detail.insert("end", json.dumps(detail, ensure_ascii=False, indent=2))
                return
        if key in sd.all_flags:
            graph = sd.get_flag_graph(key)
            kl_detail.insert("end", "[flags]\n")
            kl_detail.insert("end", json.dumps(graph, ensure_ascii=False, indent=2))
            return
        kl_detail.insert("end", f"(未找到 '{key}')")
        kl_detail.configure(state="disabled")

    kl_content.bind("<<ListboxSelect>>", _on_kl_content_select)

    _kl_refresh()

    # ==================================================================
    # Tab 5: 搜索 / 编辑
    # ==================================================================
    se_frame = ttk.Frame(notebook)
    notebook.add(se_frame, text="  搜索 / 编辑  ")

    # 搜索
    search_bar = ttk.Frame(se_frame)
    search_bar.pack(fill="x", padx=5, pady=5)
    ttk.Label(search_bar, text="关键词:").pack(side="left")
    search_var = tk.StringVar()
    ttk.Entry(search_bar, textvariable=search_var, width=30).pack(side="left", padx=5)
    ttk.Button(search_bar, text="搜索", command=lambda: _do_search()).pack(side="left")

    sr_tree = ttk.Treeview(se_frame, selectmode="browse",
                            columns=("type", "id"), show="headings", height=8)
    sr_tree.heading("type", text="类型")
    sr_tree.heading("id", text="ID")
    sr_tree.column("type", width=120)
    sr_tree.column("id", width=300)
    sr_tree.pack(fill="both", expand=True, padx=5)

    sr_detail = scrolledtext.ScrolledText(se_frame, height=8, wrap="word",
                                           bg=C_CARD, fg=C_FG, font=("Menlo", 10), bd=0)
    sr_detail.pack(fill="both", expand=True, padx=5, pady=5)

    def _do_search():
        q = search_var.get().strip()
        if not q:
            return
        results = sd.search(q)
        sr_tree.delete(*sr_tree.get_children())
        for key_type, ids in results.items():
            for iid in ids:
                sr_tree.insert("", "end", values=(key_type, iid))

    def _on_sr_select(event):
        sel = sr_tree.selection()
        if not sel:
            return
        values = sr_tree.item(sel[0], "values")
        if values and len(values) >= 2:
            detail = sd.get_detail(values[0], values[1])
            sr_detail.configure(state="normal")
            sr_detail.delete("1.0", "end")
            if detail:
                sr_detail.insert("end", json.dumps(detail, ensure_ascii=False, indent=2))
            sr_detail.configure(state="disabled")

    sr_tree.bind("<<TreeviewSelect>>", _on_sr_select)

    # 编辑
    edit_sep = ttk.Separator(se_frame, orient="horizontal")
    edit_sep.pack(fill="x", padx=5, pady=10)

    edit_form = ttk.LabelFrame(se_frame, text="编辑字段", padding=8)
    edit_form.pack(fill="x", padx=5, pady=5)

    ef_row1 = ttk.Frame(edit_form)
    ef_row1.pack(fill="x", pady=2)
    ttk.Label(ef_row1, text="类型:", width=8).pack(side="left")
    ef_type_var = tk.StringVar(value="dialogues")
    ef_type_combo = ttk.Combobox(ef_row1, textvariable=ef_type_var,
                                  values=list(KEY_TYPE_LABELS.keys()), width=15, state="readonly")
    ef_type_combo.pack(side="left")

    ef_row2 = ttk.Frame(edit_form)
    ef_row2.pack(fill="x", pady=2)
    ttk.Label(ef_row2, text="ID:", width=8).pack(side="left")
    ef_id_var = tk.StringVar()
    ttk.Entry(ef_row2, textvariable=ef_id_var, width=30).pack(side="left")

    ef_row3 = ttk.Frame(edit_form)
    ef_row3.pack(fill="x", pady=2)
    ttk.Label(ef_row3, text="字段:", width=8).pack(side="left")
    ef_field_var = tk.StringVar()
    ttk.Entry(ef_row3, textvariable=ef_field_var, width=30).pack(side="left")

    ef_row4 = ttk.Frame(edit_form)
    ef_row4.pack(fill="x", pady=2)
    ttk.Label(ef_row4, text="新值:", width=8).pack(side="left")
    ef_value_var = tk.StringVar()
    ttk.Entry(ef_row4, textvariable=ef_value_var, width=50).pack(side="left")

    ef_btn_frame = ttk.Frame(edit_form)
    ef_btn_frame.pack(fill="x", pady=5)
    ttk.Button(ef_btn_frame, text="预览",
               command=lambda: _do_edit(True)).pack(side="left", padx=3)
    ttk.Button(ef_btn_frame, text="执行",
               command=lambda: _do_edit(False)).pack(side="left", padx=3)
    ttk.Button(ef_btn_frame, text="查看当前",
               command=lambda: _show_current()).pack(side="left", padx=3)

    edit_result = scrolledtext.ScrolledText(edit_form, height=4, wrap="word",
                                             bg=C_CARD, fg=C_FG, font=("Menlo", 10), bd=0)
    edit_result.pack(fill="x", pady=5)

    def _show_current():
        detail = sd.get_detail(ef_type_var.get(), ef_id_var.get().strip())
        edit_result.configure(state="normal")
        edit_result.delete("1.0", "end")
        edit_result.insert("end", json.dumps(detail, ensure_ascii=False, indent=2) if detail else "(未找到)")
        edit_result.configure(state="disabled")

    def _do_edit(dry_run: bool):
        result = sd.edit_field(ef_type_var.get(), ef_id_var.get().strip(),
                               ef_field_var.get().strip(), ef_value_var.get(),
                               dry_run=dry_run)
        edit_result.configure(state="normal")
        edit_result.delete("1.0", "end")
        edit_result.insert("end", json.dumps(result, ensure_ascii=False, indent=2))
        edit_result.configure(state="disabled")

    # ========== 启动 ==========
    root.mainloop()


# ---------------------------------------------------------------------------
# 入口
# ---------------------------------------------------------------------------

def main():
    cli_main(sys.argv[1:])


if __name__ == "__main__":
    main()
