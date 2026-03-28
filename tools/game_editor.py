"""
Diabla Game Editor — Edit monsters, classes, skills, items, loot, progression, spawning, and world.
Reads/writes data/game_data.json alongside the Godot project.
"""

import copy
import json
import os
import sys
import tkinter as tk
from tkinter import colorchooser, ttk, messagebox

DATA_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "game_data.json")

# ── Field Definitions ─────────────────────────────────────────────────
# Format: (key, label, type, *args)
#   "float": min, max
#   "int":   min, max
#   "str":   (no extra args)
#   "choice": [options]
#   "bool":  (no extra args)
#   "color": (no extra args)

FIELDS = {
    "monsters": [
        ("max_health", "Max Health", "float", 1, 99999),
        ("move_speed", "Move Speed", "float", 0.1, 100),
        ("attack_damage", "Attack Damage", "float", 0, 99999),
        ("attack_range", "Attack Range", "float", 0.1, 100),
        ("aggro_range", "Aggro Range", "float", 0.1, 200),
        ("attack_cooldown", "Attack Cooldown", "float", 0.01, 60),
        ("xp_reward", "XP Reward", "float", 0, 99999),
        ("gold_min", "Gold Min", "int", 0, 99999),
        ("gold_max", "Gold Max", "int", 0, 99999),
    ],
    "classes": [
        ("strength", "Strength", "int", 1, 999),
        ("dexterity", "Dexterity", "int", 1, 999),
        ("intelligence", "Intelligence", "int", 1, 999),
        ("vitality", "Vitality", "int", 1, 999),
        ("max_health", "Max Health", "float", 1, 99999),
        ("max_mana", "Max Mana", "float", 1, 99999),
        ("attack_damage", "Attack Damage", "float", 0, 99999),
        ("attack_speed", "Attack Speed", "float", 0.1, 10),
        ("defense", "Defense", "float", 0, 99999),
        ("move_speed", "Move Speed", "float", 0.1, 100),
    ],
    "skills": [
        ("display_name", "Name", "str"),
        ("description", "Description", "str"),
        ("target_type", "Target Type", "choice", ["SELF", "POINT", "DIRECTION", "AREA"]),
        ("cooldown", "Cooldown", "float", 0.01, 300),
        ("mana_cost", "Mana Cost", "float", 0, 9999),
        ("damage", "Damage / Heal", "float", 0, 99999),
        ("radius", "Radius", "float", 0, 100),
        ("range_dist", "Range", "float", 0, 200),
        ("duration", "Duration", "float", 0, 3600),
        ("icon_color", "Icon Color", "color"),
    ],
    "items": [
        ("display_name", "Name", "str"),
        ("description", "Description", "str"),
        ("item_type", "Type", "choice", ["WEAPON", "HELMET", "CHEST", "BOOTS", "RING", "AMULET", "POTION", "MISC"]),
        ("rarity", "Rarity", "choice", ["COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY"]),
        ("stackable", "Stackable", "bool"),
        ("max_stack", "Max Stack", "int", 1, 999),
        ("level_requirement", "Level Req", "int", 1, 999),
        ("bonus_damage", "Bonus Damage", "float", 0, 99999),
        ("bonus_defense", "Bonus Defense", "float", 0, 99999),
        ("bonus_health", "Bonus Health", "float", 0, 99999),
        ("bonus_mana", "Bonus Mana", "float", 0, 99999),
        ("bonus_strength", "Bonus STR", "int", 0, 999),
        ("bonus_dexterity", "Bonus DEX", "int", 0, 999),
        ("bonus_intelligence", "Bonus INT", "int", 0, 999),
        ("heal_amount", "Heal Amount", "float", 0, 99999),
        ("mana_restore", "Mana Restore", "float", 0, 99999),
        ("icon_color", "Icon Color", "color"),
    ],
}

# Singleton tabs — one config object, no combo selector
SINGLETON_FIELDS = {
    "loot_config": [
        ("weapon_damage_base", "Weapon Dmg Base", "float", 0, 99999),
        ("weapon_damage_per_level", "Weapon Dmg / Level", "float", 0, 9999),
        ("armor_defense_base", "Armor Def Base", "float", 0, 99999),
        ("armor_defense_per_level", "Armor Def / Level", "float", 0, 9999),
        ("armor_health_per_level", "Armor HP / Level", "float", 0, 9999),
        ("rarity_bonus_mult", "Rarity Bonus Mult", "float", 0, 10),
        ("health_potion_drop_chance", "HP Potion Drop %", "float", 0, 1),
        ("mana_potion_drop_chance", "MP Potion Drop %", "float", 0, 1),
        ("equipment_drop_chance", "Equip Drop %", "float", 0, 1),
        ("rarity_common", "Rarity: Common", "float", 0, 1),
        ("rarity_uncommon", "Rarity: Uncommon", "float", 0, 1),
        ("rarity_rare", "Rarity: Rare", "float", 0, 1),
        ("rarity_epic", "Rarity: Epic", "float", 0, 1),
        ("rarity_legendary", "Rarity: Legendary", "float", 0, 1),
    ],
    "progression": [
        ("xp_per_level_base", "XP per Level Base", "int", 1, 999999),
        ("hp_per_level", "HP per Level", "float", 0, 99999),
        ("mana_per_level", "Mana per Level", "float", 0, 99999),
        ("stats_per_level", "Stats per Level", "int", 0, 100),
        ("defense_multiplier", "Defense Multiplier", "float", 0, 10),
    ],
    "spawning": [
        ("max_enemies", "Max Enemies (Open)", "int", 1, 999),
        ("spawn_interval", "Spawn Interval", "float", 0.1, 300),
        ("spawn_radius", "Spawn Radius", "float", 1, 500),
        ("dungeon_max_per_room", "Dungeon Max/Room", "int", 1, 99),
        ("dungeon_respawn_interval", "Dungeon Respawn", "float", 0.1, 600),
        ("dungeon_room_density_divisor", "Room Density Div", "int", 1, 999),
        ("type_weight_grunt", "Weight: Grunt", "float", 0, 1),
        ("type_weight_mage", "Weight: Mage", "float", 0, 1),
        ("type_weight_brute", "Weight: Brute", "float", 0, 1),
    ],
    "world": [
        ("tile_size", "Tile Size", "float", 0.1, 100),
        ("dungeon_width", "Dungeon Width", "int", 10, 999),
        ("dungeon_height", "Dungeon Height", "int", 10, 999),
        ("bsp_max_depth", "BSP Max Depth", "int", 1, 20),
        ("min_room_size", "Min Room Size", "int", 2, 100),
        ("max_room_size", "Max Room Size", "int", 2, 100),
        ("min_split_size", "Min Split Size", "int", 2, 200),
        ("corridor_width", "Corridor Width", "int", 1, 20),
        ("wall_height", "Wall Height", "float", 0.1, 100),
        ("town_width", "Town Width", "int", 10, 999),
        ("town_height", "Town Height", "int", 10, 999),
        ("town_wall_height", "Town Wall Height", "float", 0.1, 100),
        ("building_height", "Building Height", "float", 0.1, 100),
        ("roof_extra", "Roof Extra", "float", 0, 100),
    ],
}

SCALING_FIELDS = [
    ("health_damage_per_floor", "HP/DMG % per Floor", "float", 0, 10),
    ("xp_per_floor", "XP % per Floor", "float", 0, 10),
]

MESH_TYPES = ["box", "cylinder", "sphere"]

DEFAULT_VISUAL = {
    "parts": [
        {"name": "LeftLeg", "mesh": "cylinder", "position": [-0.15, 0.25, 0], "scale": [0.12, 0.25, 0.12], "color": [0.5, 0.5, 0.5, 1.0], "emissive": False},
        {"name": "RightLeg", "mesh": "cylinder", "position": [0.15, 0.25, 0], "scale": [0.12, 0.25, 0.12], "color": [0.5, 0.5, 0.5, 1.0], "emissive": False},
        {"name": "Torso", "mesh": "box", "position": [0, 0.7, 0], "scale": [0.4, 0.4, 0.3], "color": [0.6, 0.3, 0.3, 1.0], "emissive": False},
        {"name": "Head", "mesh": "sphere", "position": [0, 1.1, 0], "scale": [0.2, 0.2, 0.2], "color": [0.5, 0.5, 0.5, 1.0], "emissive": False},
        {"name": "LeftEye", "mesh": "sphere", "position": [-0.06, 1.13, 0.16], "scale": [0.04, 0.04, 0.04], "color": [1.0, 0.3, 0.1, 1.0], "emissive": True},
        {"name": "RightEye", "mesh": "sphere", "position": [0.06, 1.13, 0.16], "scale": [0.04, 0.04, 0.04], "color": [1.0, 0.3, 0.1, 1.0], "emissive": True},
    ],
    "pivots": [
        {
            "name": "RightArmPivot",
            "position": [0.3, 0.85, 0],
            "rotation_x": 0.3,
            "parts": [
                {"name": "RightArm", "mesh": "cylinder", "position": [0, -0.25, 0], "scale": [0.1, 0.25, 0.1], "color": [0.5, 0.5, 0.5, 1.0], "emissive": False},
            ],
        }
    ],
}

# Default data for new entries
DEFAULTS = {
    "monsters": lambda d: {**{f[0]: (0.0 if f[2] == "float" else 0) for f in FIELDS["monsters"]},
                            "max_health": 40.0, "move_speed": 5.0, "attack_damage": 8.0,
                            "attack_range": 2.0, "aggro_range": 14.0, "attack_cooldown": 0.7,
                            "xp_reward": 25.0, "gold_min": 5, "gold_max": 15,
                            "visual": copy.deepcopy(DEFAULT_VISUAL)},
    "classes": lambda d: {"strength": 10, "dexterity": 10, "intelligence": 10, "vitality": 10,
                          "max_health": 100.0, "max_mana": 50.0, "attack_damage": 10.0,
                          "attack_speed": 1.0, "defense": 5.0, "move_speed": 7.0},
    "skills": lambda d: {"display_name": "New Skill", "description": "", "target_type": "POINT",
                          "cooldown": 3.0, "mana_cost": 10.0, "damage": 20.0, "radius": 3.0,
                          "range_dist": 8.0, "duration": 0.0, "icon_color": [1.0, 1.0, 1.0, 1.0]},
    "items": lambda d: {"display_name": "New Item", "description": "", "item_type": "MISC",
                         "rarity": "COMMON", "stackable": False, "max_stack": 1, "level_requirement": 1,
                         "bonus_damage": 0.0, "bonus_defense": 0.0, "bonus_health": 0.0,
                         "bonus_mana": 0.0, "bonus_strength": 0, "bonus_dexterity": 0,
                         "bonus_intelligence": 0, "heal_amount": 0.0, "mana_restore": 0.0,
                         "icon_color": [1.0, 1.0, 1.0, 1.0]},
}


# ── Helpers ───────────────────────────────────────────────────────────

def _color_to_hex(c: list) -> str:
    r, g, b = int(c[0] * 255), int(c[1] * 255), int(c[2] * 255)
    return f"#{r:02x}{g:02x}{b:02x}"


def _hex_to_color(h: str) -> list:
    h = h.lstrip("#")
    return [int(h[i:i+2], 16) / 255.0 for i in (0, 2, 4)] + [1.0]


# ── Game Editor ───────────────────────────────────────────────────────

class GameEditor:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("Diabla — Game Editor")
        self.root.geometry("960x760")
        self.root.minsize(800, 600)
        self.data: dict = {}
        self.dirty = False

        # Per-tab state: {tab_name: {combo, vars, bools, colors, color_btns}}
        self.ts: dict = {}
        self.scaling_vars: dict[str, tk.StringVar] = {}

        # Visual editor state (monsters only)
        self._sel_part_path: tuple | None = None
        self.vis_vars: dict[str, tk.StringVar] = {}
        self._part_color = [0.5, 0.5, 0.5, 1.0]
        self.emissive_var: tk.BooleanVar | None = None

        # Preview camera rotation (right-click drag)
        self._view_angle: float = 0.0  # radians around Y axis
        self._drag_start_x: int | None = None
        self._drag_start_angle: float = 0.0
        self._part_hit_boxes: list = []  # [(x1,y1,x2,y2, path), ...]

        self._load_data()
        self._build_ui()
        self._init_all_tabs()

        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

    # ── Data I/O ──────────────────────────────────────────────────────

    def _load_data(self) -> None:
        if not os.path.isfile(DATA_FILE):
            messagebox.showerror("Error", f"Cannot find:\n{DATA_FILE}")
            sys.exit(1)
        with open(DATA_FILE, "r", encoding="utf-8") as f:
            self.data = json.load(f)

    def _save_data(self) -> None:
        with open(DATA_FILE, "w", encoding="utf-8") as f:
            json.dump(self.data, f, indent=4)
            f.write("\n")
        self.dirty = False
        self._update_title()

    # ── UI Construction ───────────────────────────────────────────────

    def _build_ui(self) -> None:
        self.notebook = ttk.Notebook(self.root)
        self.notebook.pack(fill="both", expand=True, padx=8, pady=4)

        self._build_monsters_tab()
        self._build_data_tab("classes", "Classes")
        self._build_data_tab("skills", "Skills")
        self._build_data_tab("items", "Items")
        self._build_singleton_tab("loot_config", "Loot")
        self._build_singleton_tab("progression", "Progression")
        self._build_singleton_tab("spawning", "Spawning")
        self._build_singleton_tab("world", "World")

        btn = ttk.Frame(self.root)
        btn.pack(fill="x", padx=8, pady=(4, 8))
        ttk.Button(btn, text="Save All", command=self._on_save).pack(side="right", padx=4)
        ttk.Button(btn, text="Revert", command=self._on_revert).pack(side="right", padx=4)

    # ── Monsters Tab ──────────────────────────────────────────────────

    def _build_monsters_tab(self) -> None:
        tab = ttk.Frame(self.notebook)
        self.notebook.add(tab, text="  Monsters  ")

        sel = ttk.Frame(tab)
        sel.pack(fill="x", padx=4, pady=4)
        ttk.Label(sel, text="Monster:").pack(side="left")
        combo = ttk.Combobox(sel, values=list(self.data.get("monsters", {}).keys()),
                             state="readonly", width=20)
        combo.pack(side="left", padx=(4, 0))
        if self.data.get("monsters"):
            combo.current(0)
        combo.bind("<<ComboboxSelected>>", lambda e: self._on_tab_selected("monsters"))
        ttk.Button(sel, text="+ Add", command=lambda: self._add_entry("monsters"), width=7).pack(side="left", padx=(12, 2))
        ttk.Button(sel, text="Remove", command=lambda: self._remove_entry("monsters"), width=7).pack(side="left", padx=2)

        self.ts["monsters"] = {"combo": combo, "vars": {}, "bools": {}, "colors": {}, "color_btns": {}}

        sub_nb = ttk.Notebook(tab)
        sub_nb.pack(fill="both", expand=True, padx=4, pady=4)

        # Stats sub-tab
        stats_frame = ttk.Frame(sub_nb)
        sub_nb.add(stats_frame, text="  Stats  ")
        grid = ttk.LabelFrame(stats_frame, text="Combat Stats")
        grid.pack(fill="x", padx=4, pady=4)
        self._build_field_grid(grid, "monsters")

        sc_frame = ttk.LabelFrame(stats_frame, text="Floor Scaling (Global)")
        sc_frame.pack(fill="x", padx=4, pady=4)
        for i, fd in enumerate(SCALING_FIELDS):
            ttk.Label(sc_frame, text=fd[1] + ":").grid(row=i, column=0, sticky="w", padx=(8, 4), pady=3)
            var = tk.StringVar()
            ttk.Entry(sc_frame, textvariable=var, width=14).grid(row=i, column=1, sticky="w", padx=(0, 8), pady=3)
            self.scaling_vars[fd[0]] = var
        for key, var in self.scaling_vars.items():
            var.set(str(self.data.get("floor_scaling", {}).get(key, 0)))

        # Visual sub-tab
        vis_frame = ttk.Frame(sub_nb)
        sub_nb.add(vis_frame, text="  Visual  ")
        self._build_visual_panel(vis_frame)

    # ── Generic Data Tab ──────────────────────────────────────────────

    def _build_data_tab(self, tab_name: str, display: str) -> None:
        tab = ttk.Frame(self.notebook)
        self.notebook.add(tab, text=f"  {display}  ")

        sel = ttk.Frame(tab)
        sel.pack(fill="x", padx=4, pady=4)
        singular = display.rstrip("es").rstrip("s") if display != "Classes" else "Class"
        ttk.Label(sel, text=f"{singular}:").pack(side="left")
        combo = ttk.Combobox(sel, values=list(self.data.get(tab_name, {}).keys()),
                             state="readonly", width=20)
        combo.pack(side="left", padx=(4, 0))
        if self.data.get(tab_name):
            combo.current(0)
        combo.bind("<<ComboboxSelected>>", lambda e, tn=tab_name: self._on_tab_selected(tn))
        ttk.Button(sel, text="+ Add", command=lambda tn=tab_name: self._add_entry(tn), width=7).pack(side="left", padx=(12, 2))
        ttk.Button(sel, text="Remove", command=lambda tn=tab_name: self._remove_entry(tn), width=7).pack(side="left", padx=2)

        self.ts[tab_name] = {"combo": combo, "vars": {}, "bools": {}, "colors": {}, "color_btns": {}}

        props = ttk.LabelFrame(tab, text="Properties")
        props.pack(fill="x", padx=4, pady=4)
        self._build_field_grid(props, tab_name)

    # ── Generic Field Grid Builder ────────────────────────────────────

    def _build_field_grid(self, parent: ttk.Frame, tab_name: str) -> None:
        st = self.ts[tab_name]
        for i, fd in enumerate(FIELDS[tab_name]):
            key, label, ftype = fd[0], fd[1], fd[2]
            ttk.Label(parent, text=label + ":").grid(row=i, column=0, sticky="w", padx=(8, 4), pady=2)

            if ftype in ("float", "int"):
                var = tk.StringVar()
                ttk.Entry(parent, textvariable=var, width=14).grid(row=i, column=1, sticky="w", padx=(0, 4), pady=2)
                st["vars"][key] = var
                ttk.Label(parent, text=f"({fd[3]}–{fd[4]})", foreground="grey").grid(
                    row=i, column=2, sticky="w", padx=(0, 8), pady=2)

            elif ftype == "str":
                var = tk.StringVar()
                ttk.Entry(parent, textvariable=var, width=30).grid(
                    row=i, column=1, columnspan=2, sticky="w", padx=(0, 8), pady=2)
                st["vars"][key] = var

            elif ftype == "choice":
                var = tk.StringVar()
                ttk.Combobox(parent, textvariable=var, values=fd[3], state="readonly", width=12).grid(
                    row=i, column=1, sticky="w", padx=(0, 8), pady=2)
                st["vars"][key] = var

            elif ftype == "bool":
                bvar = tk.BooleanVar()
                ttk.Checkbutton(parent, variable=bvar).grid(row=i, column=1, sticky="w", padx=(0, 8), pady=2)
                st["bools"][key] = bvar

            elif ftype == "color":
                st["colors"][key] = [0.5, 0.5, 0.5, 1.0]
                b = tk.Button(parent, text="    ", width=6, relief="solid",
                              command=lambda k=key, tn=tab_name: self._pick_tab_color(tn, k))
                b.grid(row=i, column=1, sticky="w", padx=(0, 8), pady=2)
                st["color_btns"][key] = b

    # ── Singleton Tab (single config object, no combo) ────────────────

    def _build_singleton_tab(self, data_key: str, display: str) -> None:
        tab = ttk.Frame(self.notebook)
        self.notebook.add(tab, text=f"  {display}  ")

        # Use a scrollable frame so many fields fit
        canvas = tk.Canvas(tab, highlightthickness=0)
        scrollbar = ttk.Scrollbar(tab, orient="vertical", command=canvas.yview)
        inner = ttk.Frame(canvas)
        inner.bind("<Configure>", lambda e: canvas.configure(scrollregion=canvas.bbox("all")))
        canvas.create_window((0, 0), window=inner, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)
        scrollbar.pack(side="right", fill="y")
        canvas.pack(side="left", fill="both", expand=True, padx=4, pady=4)

        props = ttk.LabelFrame(inner, text=f"{display} Settings")
        props.pack(fill="x", padx=4, pady=4)

        st = {"vars": {}}
        self.ts[data_key] = st

        for i, fd in enumerate(SINGLETON_FIELDS[data_key]):
            key, label, ftype = fd[0], fd[1], fd[2]
            ttk.Label(props, text=label + ":").grid(row=i, column=0, sticky="w", padx=(8, 4), pady=2)
            if ftype in ("float", "int"):
                var = tk.StringVar()
                ttk.Entry(props, textvariable=var, width=14).grid(row=i, column=1, sticky="w", padx=(0, 4), pady=2)
                st["vars"][key] = var
                ttk.Label(props, text=f"({fd[3]}–{fd[4]})", foreground="grey").grid(
                    row=i, column=2, sticky="w", padx=(0, 8), pady=2)

    def _populate_singleton(self, data_key: str) -> None:
        st = self.ts.get(data_key)
        if not st:
            return
        section = self.data.get(data_key, {})
        # For loot_config, flatten rarity_weights array into individual keys
        if data_key == "loot_config":
            rw = section.get("rarity_weights", [0.5, 0.3, 0.13, 0.06, 0.01])
            rarity_map = {"rarity_common": 0, "rarity_uncommon": 1, "rarity_rare": 2,
                          "rarity_epic": 3, "rarity_legendary": 4}
            for k, idx in rarity_map.items():
                if k in st["vars"]:
                    st["vars"][k].set(str(rw[idx] if idx < len(rw) else 0))
        for fd in SINGLETON_FIELDS[data_key]:
            key = fd[0]
            if key.startswith("rarity_") and data_key == "loot_config":
                continue  # Already handled above
            if key in st["vars"]:
                st["vars"][key].set(str(section.get(key, "")))

    def _collect_singleton(self, data_key: str) -> bool:
        st = self.ts.get(data_key)
        if not st:
            return True
        section = self.data.setdefault(data_key, {})
        for fd in SINGLETON_FIELDS[data_key]:
            key, label, ftype = fd[0], fd[1], fd[2]
            if key.startswith("rarity_") and data_key == "loot_config":
                continue  # Handled below
            raw = st["vars"][key].get().strip()
            if ftype == "float":
                fmin, fmax = fd[3], fd[4]
                try:
                    val = float(raw)
                except ValueError:
                    messagebox.showwarning("Invalid", f"[{data_key}] {label} must be a number.")
                    return False
                if val < fmin or val > fmax:
                    messagebox.showwarning("Range", f"[{data_key}] {label}: {fmin}–{fmax}.")
                    return False
                section[key] = val
            elif ftype == "int":
                fmin, fmax = fd[3], fd[4]
                try:
                    val = int(raw)
                except ValueError:
                    messagebox.showwarning("Invalid", f"[{data_key}] {label} must be integer.")
                    return False
                if val < fmin or val > fmax:
                    messagebox.showwarning("Range", f"[{data_key}] {label}: {fmin}–{fmax}.")
                    return False
                section[key] = val
        # Collect rarity_weights for loot_config
        if data_key == "loot_config":
            rarity_keys = ["rarity_common", "rarity_uncommon", "rarity_rare",
                           "rarity_epic", "rarity_legendary"]
            weights = []
            for rk in rarity_keys:
                raw = st["vars"][rk].get().strip()
                try:
                    val = float(raw)
                except ValueError:
                    messagebox.showwarning("Invalid", f"[Loot] {rk} must be a number.")
                    return False
                weights.append(val)
            section["rarity_weights"] = weights
        return True

    # ── Visual Panel (Monsters) ───────────────────────────────────────

    def _build_visual_panel(self, parent: ttk.Frame) -> None:
        left = ttk.Frame(parent, width=320)
        left.pack(side="left", fill="y", padx=(4, 0), pady=4)
        left.pack_propagate(False)
        right = ttk.Frame(parent)
        right.pack(side="left", fill="both", expand=True, padx=4, pady=4)

        # Parts tree
        tf = ttk.LabelFrame(left, text="Parts")
        tf.pack(fill="both", expand=True, padx=2, pady=2)
        self.parts_tree = ttk.Treeview(tf, selectmode="browse", show="tree", height=10)
        self.parts_tree.pack(fill="both", expand=True, padx=2, pady=2)
        self.parts_tree.bind("<<TreeviewSelect>>", self._on_tree_select)

        tb = ttk.Frame(tf)
        tb.pack(fill="x", padx=2, pady=(0, 4))
        ttk.Button(tb, text="+ Part", command=self._vis_add_part, width=8).pack(side="left", padx=2)
        ttk.Button(tb, text="+ Pivot", command=self._vis_add_pivot, width=8).pack(side="left", padx=2)
        ttk.Button(tb, text="Dup", command=self._vis_dup_part, width=5).pack(side="left", padx=2)
        ttk.Button(tb, text="Del", command=self._vis_del_part, width=5).pack(side="left", padx=2)

        # Part properties
        pf = ttk.LabelFrame(left, text="Properties")
        pf.pack(fill="x", padx=2, pady=2)
        prop_fields = [("name", "Name"), ("mesh", "Mesh"),
                       ("pos_x", "Pos X"), ("pos_y", "Pos Y"), ("pos_z", "Pos Z"),
                       ("scale_x", "Scale X"), ("scale_y", "Scale Y"), ("scale_z", "Scale Z")]
        for i, (key, label) in enumerate(prop_fields):
            ttk.Label(pf, text=label + ":").grid(row=i, column=0, sticky="w", padx=(6, 2), pady=2)
            var = tk.StringVar()
            if key == "mesh":
                ttk.Combobox(pf, textvariable=var, values=MESH_TYPES, state="readonly", width=10).grid(
                    row=i, column=1, sticky="w", padx=(0, 6), pady=2)
            else:
                ttk.Entry(pf, textvariable=var, width=12).grid(row=i, column=1, sticky="w", padx=(0, 6), pady=2)
            self.vis_vars[key] = var

        ri = len(prop_fields)
        ttk.Label(pf, text="Rot X:").grid(row=ri, column=0, sticky="w", padx=(6, 2), pady=2)
        self.vis_vars["rotation_x"] = tk.StringVar()
        ttk.Entry(pf, textvariable=self.vis_vars["rotation_x"], width=12).grid(row=ri, column=1, sticky="w", padx=(0, 6), pady=2)

        ttk.Label(pf, text="Color:").grid(row=ri + 1, column=0, sticky="w", padx=(6, 2), pady=2)
        self.vis_color_btn = tk.Button(pf, text="    ", width=6, relief="solid", command=self._vis_pick_color)
        self.vis_color_btn.grid(row=ri + 1, column=1, sticky="w", padx=(0, 6), pady=2)

        self.emissive_var = tk.BooleanVar()
        ttk.Checkbutton(pf, text="Emissive", variable=self.emissive_var).grid(
            row=ri + 2, column=0, columnspan=2, sticky="w", padx=6, pady=2)
        ttk.Button(pf, text="Apply", command=self._vis_apply_props).grid(
            row=ri + 3, column=0, columnspan=2, sticky="ew", padx=6, pady=(4, 6))

        # Preview canvas
        pvf = ttk.LabelFrame(right, text="Preview")
        pvf.pack(fill="both", expand=True, padx=2, pady=2)
        self.canvas = tk.Canvas(pvf, bg="#1a1a2e", highlightthickness=0)
        self.canvas.pack(fill="both", expand=True)
        self.canvas.bind("<Configure>", lambda e: self._redraw_preview())
        # Left-click to select part
        self.canvas.bind("<Button-1>", self._on_canvas_click)
        # Right-click drag to rotate camera
        self.canvas.bind("<ButtonPress-3>", self._on_canvas_drag_start)
        self.canvas.bind("<B3-Motion>", self._on_canvas_drag)
        self.canvas.bind("<ButtonRelease-3>", self._on_canvas_drag_end)

    # ── Tab Population / Collection ───────────────────────────────────

    def _init_all_tabs(self) -> None:
        for tn in ["monsters", "classes", "skills", "items"]:
            self._populate_tab(tn)
        for sk in ["loot_config", "progression", "spawning", "world"]:
            self._populate_singleton(sk)
        self._refresh_tree()
        self._redraw_preview()

    def _on_tab_selected(self, tab_name: str) -> None:
        self._populate_tab(tab_name)
        if tab_name == "monsters":
            self._sel_part_path = None
            self._refresh_tree()
            self._redraw_preview()

    def _populate_tab(self, tn: str) -> None:
        st = self.ts[tn]
        name = st["combo"].get()
        if not name:
            return
        entry = self.data.get(tn, {}).get(name, {})
        for fd in FIELDS[tn]:
            key, ftype = fd[0], fd[2]
            if ftype in ("float", "int", "str", "choice"):
                st["vars"][key].set(str(entry.get(key, "")))
            elif ftype == "bool":
                st["bools"][key].set(entry.get(key, False))
            elif ftype == "color":
                c = entry.get(key, [0.5, 0.5, 0.5, 1.0])
                st["colors"][key] = list(c)
                st["color_btns"][key].configure(bg=_color_to_hex(c))

    def _collect_tab(self, tn: str) -> bool:
        st = self.ts[tn]
        name = st["combo"].get()
        if not name:
            return True
        entry = self.data.setdefault(tn, {}).setdefault(name, {})
        for fd in FIELDS[tn]:
            key, label, ftype = fd[0], fd[1], fd[2]
            if ftype == "float":
                fmin, fmax = fd[3], fd[4]
                raw = st["vars"][key].get().strip()
                try:
                    val = float(raw)
                except ValueError:
                    messagebox.showwarning("Invalid", f"[{tn.title()}] {label} must be a number.")
                    return False
                if val < fmin or val > fmax:
                    messagebox.showwarning("Range", f"[{tn.title()}] {label}: {fmin}–{fmax}.")
                    return False
                entry[key] = val
            elif ftype == "int":
                fmin, fmax = fd[3], fd[4]
                raw = st["vars"][key].get().strip()
                try:
                    val = int(raw)
                except ValueError:
                    messagebox.showwarning("Invalid", f"[{tn.title()}] {label} must be integer.")
                    return False
                if val < fmin or val > fmax:
                    messagebox.showwarning("Range", f"[{tn.title()}] {label}: {fmin}–{fmax}.")
                    return False
                entry[key] = val
            elif ftype == "str":
                entry[key] = st["vars"][key].get()
            elif ftype == "choice":
                entry[key] = st["vars"][key].get()
            elif ftype == "bool":
                entry[key] = st["bools"][key].get()
            elif ftype == "color":
                entry[key] = list(st["colors"][key])
        return True

    def _pick_tab_color(self, tn: str, key: str) -> None:
        st = self.ts[tn]
        initial = _color_to_hex(st["colors"][key])
        result = colorchooser.askcolor(color=initial, title="Pick Color")
        if result and result[0]:
            r, g, b = result[0]
            st["colors"][key] = [r / 255.0, g / 255.0, b / 255.0, 1.0]
            st["color_btns"][key].configure(bg=result[1])

    # ── Add / Remove ──────────────────────────────────────────────────

    def _add_entry(self, tn: str) -> None:
        dialog = tk.Toplevel(self.root)
        dialog.title(f"Add {tn.rstrip('es').rstrip('s').title()}")
        dialog.resizable(False, False)
        dialog.grab_set()
        ttk.Label(dialog, text="ID / Name:").pack(padx=8, pady=(8, 2))
        name_var = tk.StringVar()
        entry = ttk.Entry(dialog, textvariable=name_var, width=24)
        entry.pack(padx=8, pady=2)
        entry.focus_set()

        def do_add() -> None:
            n = name_var.get().strip()
            if tn in ("monsters", "classes"):
                n = n.upper()
            else:
                n = n.lower().replace(" ", "_")
            if not n:
                messagebox.showwarning("Invalid", "Name cannot be empty.", parent=dialog)
                return
            if n in self.data.get(tn, {}):
                messagebox.showwarning("Exists", f"'{n}' already exists.", parent=dialog)
                return
            self.data.setdefault(tn, {})[n] = DEFAULTS[tn](self.data)
            self.ts[tn]["combo"]["values"] = list(self.data[tn].keys())
            self.ts[tn]["combo"].set(n)
            self._on_tab_selected(tn)
            self.dirty = True
            self._update_title()
            dialog.destroy()

        ttk.Button(dialog, text="Add", command=do_add).pack(padx=8, pady=8)
        entry.bind("<Return>", lambda _: do_add())

    def _remove_entry(self, tn: str) -> None:
        name = self.ts[tn]["combo"].get()
        if not name:
            return
        if not messagebox.askyesno("Confirm", f"Remove '{name}' from {tn}?"):
            return
        del self.data[tn][name]
        vals = list(self.data[tn].keys())
        self.ts[tn]["combo"]["values"] = vals
        if vals:
            self.ts[tn]["combo"].current(0)
        else:
            self.ts[tn]["combo"].set("")
        self._on_tab_selected(tn)
        self.dirty = True
        self._update_title()

    # ── Save / Revert ─────────────────────────────────────────────────

    def _on_save(self) -> None:
        for tn in ["monsters", "classes", "skills", "items"]:
            if not self._collect_tab(tn):
                return
        for sk in ["loot_config", "progression", "spawning", "world"]:
            if not self._collect_singleton(sk):
                return
        # Collect scaling
        for fd in SCALING_FIELDS:
            key, label, ftype, fmin, fmax = fd
            raw = self.scaling_vars[key].get().strip()
            try:
                val = float(raw)
            except ValueError:
                messagebox.showwarning("Invalid", f"{label} must be a number.")
                return
            if val < fmin or val > fmax:
                messagebox.showwarning("Range", f"{label}: {fmin}–{fmax}.")
                return
            self.data.setdefault("floor_scaling", {})[key] = val
        self._save_data()
        messagebox.showinfo("Saved", f"Game data saved to:\n{DATA_FILE}")

    def _on_revert(self) -> None:
        self._load_data()
        for tn in ["monsters", "classes", "skills", "items"]:
            vals = list(self.data.get(tn, {}).keys())
            self.ts[tn]["combo"]["values"] = vals
            if vals:
                self.ts[tn]["combo"].current(0)
            self._populate_tab(tn)
        for sk in ["loot_config", "progression", "spawning", "world"]:
            self._populate_singleton(sk)
        for key, var in self.scaling_vars.items():
            var.set(str(self.data.get("floor_scaling", {}).get(key, 0)))
        self._sel_part_path = None
        self._refresh_tree()
        self._redraw_preview()
        self.dirty = False
        self._update_title()

    def _update_title(self) -> None:
        t = "Diabla — Game Editor"
        if self.dirty:
            t += " *"
        self.root.title(t)

    def _on_close(self) -> None:
        if self.dirty:
            if not messagebox.askyesno("Unsaved", "Unsaved changes. Quit anyway?"):
                return
        self.root.destroy()

    # ── Visual: Tree ──────────────────────────────────────────────────

    def _get_visual(self) -> dict | None:
        name = self.ts["monsters"]["combo"].get()
        if not name:
            return None
        return self.data.get("monsters", {}).get(name, {}).get("visual")

    def _refresh_tree(self) -> None:
        self.parts_tree.delete(*self.parts_tree.get_children())
        vis = self._get_visual()
        if not vis:
            return
        for i, p in enumerate(vis.get("parts", [])):
            lbl = p.get("name", f"Part{i}")
            if p.get("emissive"):
                lbl += " *"
            self.parts_tree.insert("", "end", iid=f"r_{i}", text=f"  {lbl}  ({p.get('mesh', '?')})")
        for pi, pv in enumerate(vis.get("pivots", [])):
            pid = f"p_{pi}"
            self.parts_tree.insert("", "end", iid=pid, text=f"  {pv.get('name', 'Pivot')}  [pivot]", open=True)
            for ci, cp in enumerate(pv.get("parts", [])):
                lbl = cp.get("name", f"Part{ci}")
                if cp.get("emissive"):
                    lbl += " *"
                self.parts_tree.insert(pid, "end", iid=f"p_{pi}_{ci}", text=f"  {lbl}  ({cp.get('mesh', '?')})")

    def _on_tree_select(self, _e) -> None:
        sel = self.parts_tree.selection()
        if not sel:
            self._sel_part_path = None
            return
        self._sel_part_path = self._iid_to_path(sel[0])
        self._vis_load_props()
        self._redraw_preview()

    def _iid_to_path(self, iid: str) -> tuple | None:
        parts = iid.split("_")
        if parts[0] == "r":
            return ("root", int(parts[1]))
        elif parts[0] == "p":
            if len(parts) == 2:
                return ("pivot_node", int(parts[1]))
            return ("pivot", int(parts[1]), int(parts[2]))
        return None

    def _get_part(self, path: tuple | None) -> dict | None:
        vis = self._get_visual()
        if not vis or not path:
            return None
        if path[0] == "root":
            ps = vis.get("parts", [])
            return ps[path[1]] if path[1] < len(ps) else None
        elif path[0] == "pivot_node":
            pvs = vis.get("pivots", [])
            return pvs[path[1]] if path[1] < len(pvs) else None
        elif path[0] == "pivot":
            pvs = vis.get("pivots", [])
            if path[1] < len(pvs):
                cs = pvs[path[1]].get("parts", [])
                return cs[path[2]] if path[2] < len(cs) else None
        return None

    # ── Visual: Properties ────────────────────────────────────────────

    def _vis_load_props(self) -> None:
        part = self._get_part(self._sel_part_path)
        if not part:
            return
        is_pn = self._sel_part_path and self._sel_part_path[0] == "pivot_node"
        self.vis_vars["name"].set(part.get("name", ""))
        pos = part.get("position", [0, 0, 0])
        self.vis_vars["pos_x"].set(str(pos[0]))
        self.vis_vars["pos_y"].set(str(pos[1]))
        self.vis_vars["pos_z"].set(str(pos[2]))
        if is_pn:
            self.vis_vars["mesh"].set("")
            self.vis_vars["scale_x"].set("")
            self.vis_vars["scale_y"].set("")
            self.vis_vars["scale_z"].set("")
            self.vis_vars["rotation_x"].set(str(part.get("rotation_x", 0.0)))
            self._part_color = [0.5, 0.5, 0.5, 1.0]
            self.vis_color_btn.configure(bg="#808080")
            self.emissive_var.set(False)
        else:
            self.vis_vars["mesh"].set(part.get("mesh", "box"))
            scl = part.get("scale", [0.1, 0.1, 0.1])
            self.vis_vars["scale_x"].set(str(scl[0]))
            self.vis_vars["scale_y"].set(str(scl[1]))
            self.vis_vars["scale_z"].set(str(scl[2]))
            self.vis_vars["rotation_x"].set("")
            col = part.get("color", [0.5, 0.5, 0.5, 1.0])
            self._part_color = list(col)
            self.vis_color_btn.configure(bg=_color_to_hex(col))
            self.emissive_var.set(part.get("emissive", False))

    def _vis_apply_props(self) -> None:
        part = self._get_part(self._sel_part_path)
        if not part:
            return
        is_pn = self._sel_part_path[0] == "pivot_node"
        try:
            part["name"] = self.vis_vars["name"].get().strip()
            part["position"] = [float(self.vis_vars["pos_x"].get()),
                                float(self.vis_vars["pos_y"].get()),
                                float(self.vis_vars["pos_z"].get())]
            if is_pn:
                rx = self.vis_vars["rotation_x"].get().strip()
                if rx:
                    part["rotation_x"] = float(rx)
            else:
                part["mesh"] = self.vis_vars["mesh"].get()
                part["scale"] = [float(self.vis_vars["scale_x"].get()),
                                 float(self.vis_vars["scale_y"].get()),
                                 float(self.vis_vars["scale_z"].get())]
                part["color"] = list(self._part_color)
                part["emissive"] = self.emissive_var.get()
        except ValueError:
            messagebox.showwarning("Invalid", "Position/scale must be valid numbers.")
            return
        self.dirty = True
        self._update_title()
        self._refresh_tree()
        self._redraw_preview()

    def _vis_pick_color(self) -> None:
        result = colorchooser.askcolor(color=_color_to_hex(self._part_color), title="Part Color")
        if result and result[0]:
            r, g, b = result[0]
            self._part_color = [r / 255.0, g / 255.0, b / 255.0, 1.0]
            self.vis_color_btn.configure(bg=result[1])

    # ── Visual: Add / Dup / Del ───────────────────────────────────────

    def _vis_ensure(self) -> dict:
        vis = self._get_visual()
        if not vis:
            vis = copy.deepcopy(DEFAULT_VISUAL)
            name = self.ts["monsters"]["combo"].get()
            if name:
                self.data["monsters"][name]["visual"] = vis
        return vis

    def _vis_add_part(self) -> None:
        vis = self._vis_ensure()
        np = {"name": "NewPart", "mesh": "box", "position": [0, 0.5, 0],
              "scale": [0.2, 0.2, 0.2], "color": [0.5, 0.5, 0.5, 1.0], "emissive": False}
        if self._sel_part_path and self._sel_part_path[0] == "pivot_node":
            vis["pivots"][self._sel_part_path[1]].setdefault("parts", []).append(np)
        else:
            vis.setdefault("parts", []).append(np)
        self.dirty = True
        self._update_title()
        self._refresh_tree()
        self._redraw_preview()

    def _vis_add_pivot(self) -> None:
        vis = self._vis_ensure()
        vis.setdefault("pivots", []).append(
            {"name": "NewPivot", "position": [0.3, 0.8, 0], "rotation_x": 0.0, "parts": []})
        self.dirty = True
        self._update_title()
        self._refresh_tree()
        self._redraw_preview()

    def _vis_dup_part(self) -> None:
        part = self._get_part(self._sel_part_path)
        if not part:
            return
        vis = self._get_visual()
        dup = copy.deepcopy(part)
        dup["name"] = dup.get("name", "") + "_copy"
        p = self._sel_part_path
        if p[0] == "root":
            vis["parts"].append(dup)
        elif p[0] == "pivot_node":
            vis["pivots"].append(dup)
        elif p[0] == "pivot":
            vis["pivots"][p[1]]["parts"].append(dup)
        self.dirty = True
        self._update_title()
        self._refresh_tree()
        self._redraw_preview()

    def _vis_del_part(self) -> None:
        p = self._sel_part_path
        if not p:
            return
        vis = self._get_visual()
        if not vis:
            return
        if p[0] == "root" and p[1] < len(vis.get("parts", [])):
            vis["parts"].pop(p[1])
        elif p[0] == "pivot_node" and p[1] < len(vis.get("pivots", [])):
            vis["pivots"].pop(p[1])
        elif p[0] == "pivot":
            pvs = vis.get("pivots", [])
            if p[1] < len(pvs):
                cs = pvs[p[1]].get("parts", [])
                if p[2] < len(cs):
                    cs.pop(p[2])
        self._sel_part_path = None
        self.dirty = True
        self._update_title()
        self._refresh_tree()
        self._redraw_preview()

    # ── Visual: Canvas Interaction ────────────────────────────────────

    def _on_canvas_drag_start(self, event) -> None:
        self._drag_start_x = event.x
        self._drag_start_angle = self._view_angle

    def _on_canvas_drag(self, event) -> None:
        if self._drag_start_x is None:
            return
        dx = event.x - self._drag_start_x
        self._view_angle = self._drag_start_angle + dx * 0.01
        self._redraw_preview()

    def _on_canvas_drag_end(self, _event) -> None:
        self._drag_start_x = None

    def _on_canvas_click(self, event) -> None:
        """Select the top-most part whose bounding box contains the click."""
        mx, my = event.x, event.y
        # Iterate in reverse so top-drawn (last) parts get priority
        for x1, y1, x2, y2, path in reversed(self._part_hit_boxes):
            if x1 <= mx <= x2 and y1 <= my <= y2:
                self._sel_part_path = path
                self._vis_load_props()
                # Also select in treeview
                iid = self._path_to_iid(path)
                if iid:
                    self.parts_tree.selection_set(iid)
                    self.parts_tree.see(iid)
                self._redraw_preview()
                return
        # Clicked empty space — deselect
        self._sel_part_path = None
        self.parts_tree.selection_set()
        self._redraw_preview()

    def _path_to_iid(self, path: tuple | None) -> str | None:
        if not path:
            return None
        if path[0] == "root":
            return f"r_{path[1]}"
        elif path[0] == "pivot_node":
            return f"p_{path[1]}"
        elif path[0] == "pivot":
            return f"p_{path[1]}_{path[2]}"
        return None

    def _rotate_xz(self, x: float, z: float) -> float:
        """Rotate a point around Y axis by _view_angle, return projected X."""
        import math
        cos_a = math.cos(self._view_angle)
        sin_a = math.sin(self._view_angle)
        return x * cos_a + z * sin_a

    def _rotate_scale_xz(self, sx: float, sz: float) -> float:
        """Compute apparent width of a box after Y rotation."""
        import math
        cos_a = abs(math.cos(self._view_angle))
        sin_a = abs(math.sin(self._view_angle))
        return sx * cos_a + sz * sin_a

    # ── Visual: Preview ───────────────────────────────────────────────

    def _redraw_preview(self) -> None:
        c = self.canvas
        c.delete("all")
        self._part_hit_boxes.clear()
        w, h = c.winfo_width(), c.winfo_height()
        if w < 10 or h < 10:
            return
        vis = self._get_visual()
        if not vis:
            c.create_text(w // 2, h // 2, text="No visual data", fill="#555", font=("Consolas", 12))
            return
        spx = min(w, h) * 0.35
        cx, gy = w // 2, h - 40
        c.create_line(20, gy, w - 20, gy, fill="#333", width=1, dash=(4, 4))
        # Show angle indicator
        import math
        deg = math.degrees(self._view_angle) % 360
        c.create_text(w - 8, 12, text=f"{deg:.0f}\u00b0", fill="#555", anchor="ne", font=("Consolas", 9))
        sel = self._get_part(self._sel_part_path) if self._sel_part_path else None
        for i, p in enumerate(vis.get("parts", [])):
            self._draw_part(c, p, cx, gy, spx, 0, 0, p is sel, ("root", i))
        for pi, pv in enumerate(vis.get("pivots", [])):
            pp = pv.get("position", [0, 0, 0])
            rpx = self._rotate_xz(pp[0], pp[2])
            if pv is sel:
                px, py = cx + rpx * spx, gy - pp[1] * spx
                c.create_oval(px - 5, py - 5, px + 5, py + 5, outline="#ffff00", width=2)
            for ci, cp in enumerate(pv.get("parts", [])):
                self._draw_part(c, cp, cx, gy, spx, pp[0], pp[1], cp is sel, ("pivot", pi, ci), pp[2])

    def _draw_part(self, c: tk.Canvas, part: dict, cx: int, gy: int,
                   spx: float, ox: float, oy: float, selected: bool,
                   path: tuple = None, oz: float = 0.0) -> None:
        pos = part.get("position", [0, 0, 0])
        scl = part.get("scale", [0.1, 0.1, 0.1])
        mesh = part.get("mesh", "box")
        color = _color_to_hex(part.get("color", [0.5, 0.5, 0.5, 1.0]))
        # Rotate world-space X/Z by view angle
        world_x = pos[0] + ox
        world_z = pos[2] + oz
        rx = self._rotate_xz(world_x, world_z)
        px = cx + rx * spx
        py = gy - (pos[1] + oy) * spx
        # Apparent width depends on rotation
        if mesh == "sphere":
            app_w = self._rotate_scale_xz(scl[0], scl[2]) if len(scl) > 2 else scl[0]
            rx_s, ry_s = app_w * spx, scl[1] * spx
            c.create_oval(px - rx_s, py - ry_s, px + rx_s, py + ry_s, fill=color, outline="")
            if part.get("emissive"):
                c.create_oval(px - rx_s - 2, py - ry_s - 2, px + rx_s + 2, py + ry_s + 2, outline=color, width=2)
            bx1, by1, bx2, by2 = px - rx_s, py - ry_s, px + rx_s, py + ry_s
        elif mesh == "cylinder":
            app_w = self._rotate_scale_xz(scl[0], scl[2] if len(scl) > 2 else scl[0])
            hw, hh = app_w * spx, scl[1] * spx
            c.create_rectangle(px - hw, py - hh, px + hw, py + hh, fill=color, outline="")
            bx1, by1, bx2, by2 = px - hw, py - hh, px + hw, py + hh
        else:  # box
            app_w = self._rotate_scale_xz(scl[0] * 0.5, scl[2] * 0.5 if len(scl) > 2 else scl[0] * 0.5)
            hw, hh = app_w * spx, scl[1] * 0.5 * spx
            c.create_rectangle(px - hw, py - hh, px + hw, py + hh, fill=color, outline="")
            bx1, by1, bx2, by2 = px - hw, py - hh, px + hw, py + hh
        if selected:
            pad = 3
            if mesh == "sphere":
                c.create_oval(bx1 - pad, by1 - pad, bx2 + pad, by2 + pad, outline="#00ff00", width=2, dash=(3, 3))
            else:
                c.create_rectangle(bx1 - pad, by1 - pad, bx2 + pad, by2 + pad, outline="#00ff00", width=2, dash=(3, 3))
        # Store hit box for click selection
        if path:
            self._part_hit_boxes.append((bx1, by1, bx2, by2, path))


def main() -> None:
    root = tk.Tk()
    GameEditor(root)
    root.mainloop()


if __name__ == "__main__":
    main()
