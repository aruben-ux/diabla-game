"""
Diabla Monster Editor — View and edit monster stats + visual appearance.
Reads/writes data/monster_data.json alongside the Godot project.
"""

import copy
import json
import math
import os
import sys
import tkinter as tk
from tkinter import colorchooser, ttk, messagebox

DATA_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "monster_data.json")

STAT_DEFINITIONS = {
    "max_health":      {"label": "Max Health",      "type": float, "min": 1,    "max": 99999},
    "move_speed":      {"label": "Move Speed",      "type": float, "min": 0.1,  "max": 100},
    "attack_damage":   {"label": "Attack Damage",   "type": float, "min": 0,    "max": 99999},
    "attack_range":    {"label": "Attack Range",    "type": float, "min": 0.1,  "max": 100},
    "aggro_range":     {"label": "Aggro Range",     "type": float, "min": 0.1,  "max": 200},
    "attack_cooldown": {"label": "Attack Cooldown", "type": float, "min": 0.01, "max": 60},
    "xp_reward":       {"label": "XP Reward",       "type": float, "min": 0,    "max": 99999},
    "gold_min":        {"label": "Gold Drop Min",   "type": int,   "min": 0,    "max": 99999},
    "gold_max":        {"label": "Gold Drop Max",   "type": int,   "min": 0,    "max": 99999},
}

SCALING_DEFINITIONS = {
    "health_damage_per_floor": {"label": "HP/DMG % per Floor", "type": float, "min": 0, "max": 10},
    "xp_per_floor":            {"label": "XP % per Floor",     "type": float, "min": 0, "max": 10},
}

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

# ── Helpers ───────────────────────────────────────────────────────────

def _color_to_hex(c: list) -> str:
    r, g, b = int(c[0] * 255), int(c[1] * 255), int(c[2] * 255)
    return f"#{r:02x}{g:02x}{b:02x}"


def _hex_to_color(h: str) -> list:
    h = h.lstrip("#")
    return [int(h[i:i+2], 16) / 255.0 for i in (0, 2, 4)] + [1.0]


# ── Main Editor ───────────────────────────────────────────────────────

class MonsterEditor:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("Diabla — Monster Editor")
        self.root.geometry("920x720")
        self.root.minsize(800, 600)
        self.data: dict = {}
        self.stat_vars: dict[str, tk.StringVar] = {}
        self.scaling_vars: dict[str, tk.StringVar] = {}
        self.dirty = False

        # Visual editor state
        self._selected_part_path: tuple | None = None  # ("root", idx) or ("pivot", pi, idx)

        self._load_data()
        self._build_ui()
        self._on_monster_selected(None)

        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

    # ── Data I/O ──────────────────────────────────────────────────────

    def _load_data(self) -> None:
        if not os.path.isfile(DATA_FILE):
            messagebox.showerror("Error", f"Cannot find data file:\n{DATA_FILE}")
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
        # ─── Monster selector (top bar) ───────────────────────────────
        top_frame = ttk.Frame(self.root)
        top_frame.pack(fill="x", padx=8, pady=4)

        ttk.Label(top_frame, text="Monster:").pack(side="left")
        self.monster_combo = ttk.Combobox(
            top_frame, values=list(self.data["monsters"].keys()),
            state="readonly", width=20,
        )
        self.monster_combo.pack(side="left", padx=(4, 0))
        self.monster_combo.current(0)
        self.monster_combo.bind("<<ComboboxSelected>>", self._on_monster_selected)

        ttk.Button(top_frame, text="+ Add", command=self._add_monster, width=7).pack(side="left", padx=(12, 2))
        ttk.Button(top_frame, text="− Remove", command=self._remove_monster, width=8).pack(side="left", padx=2)

        # ─── Notebook (Stats / Visual) ────────────────────────────────
        self.notebook = ttk.Notebook(self.root)
        self.notebook.pack(fill="both", expand=True, padx=8, pady=4)

        self._build_stats_tab()
        self._build_visual_tab()

        # ─── Floor Scaling (below tabs) ───────────────────────────────
        scaling_frame = ttk.LabelFrame(self.root, text="Floor Scaling (Global)")
        scaling_frame.pack(fill="x", padx=8, pady=4)

        for i, (key, defn) in enumerate(SCALING_DEFINITIONS.items()):
            ttk.Label(scaling_frame, text=defn["label"] + ":").grid(row=i, column=0, sticky="w", padx=(8, 4), pady=3)
            var = tk.StringVar()
            ttk.Entry(scaling_frame, textvariable=var, width=14).grid(row=i, column=1, sticky="w", padx=(0, 8), pady=3)
            self.scaling_vars[key] = var

        for key, var in self.scaling_vars.items():
            var.set(str(self.data["floor_scaling"].get(key, 0)))

        # ─── Bottom buttons ───────────────────────────────────────────
        btn_frame = ttk.Frame(self.root)
        btn_frame.pack(fill="x", padx=8, pady=(4, 8))
        ttk.Button(btn_frame, text="Save", command=self._on_save).pack(side="right", padx=4)
        ttk.Button(btn_frame, text="Revert", command=self._on_revert).pack(side="right", padx=4)

    # ── Stats Tab ─────────────────────────────────────────────────────

    def _build_stats_tab(self) -> None:
        stats_tab = ttk.Frame(self.notebook)
        self.notebook.add(stats_tab, text="  Stats  ")

        for i, (key, defn) in enumerate(STAT_DEFINITIONS.items()):
            ttk.Label(stats_tab, text=defn["label"] + ":").grid(row=i, column=0, sticky="w", padx=(8, 4), pady=3)
            var = tk.StringVar()
            ttk.Entry(stats_tab, textvariable=var, width=14).grid(row=i, column=1, sticky="w", padx=(0, 8), pady=3)
            self.stat_vars[key] = var
            ttk.Label(stats_tab, text=f"({defn['min']} – {defn['max']})", foreground="grey").grid(row=i, column=2, sticky="w", padx=(0, 8), pady=3)

    # ── Visual Tab ────────────────────────────────────────────────────

    def _build_visual_tab(self) -> None:
        visual_tab = ttk.Frame(self.notebook)
        self.notebook.add(visual_tab, text="  Visual  ")

        # Split: left panel (parts list + props) | right panel (preview)
        left = ttk.Frame(visual_tab, width=320)
        left.pack(side="left", fill="y", padx=(4, 0), pady=4)
        left.pack_propagate(False)

        right = ttk.Frame(visual_tab)
        right.pack(side="left", fill="both", expand=True, padx=4, pady=4)

        # ─── Parts treeview ───────────────────────────────────────────
        tree_frame = ttk.LabelFrame(left, text="Parts")
        tree_frame.pack(fill="both", expand=True, padx=2, pady=2)

        self.parts_tree = ttk.Treeview(tree_frame, selectmode="browse", show="tree", height=10)
        self.parts_tree.pack(fill="both", expand=True, padx=2, pady=2)
        self.parts_tree.bind("<<TreeviewSelect>>", self._on_tree_select)

        tree_btns = ttk.Frame(tree_frame)
        tree_btns.pack(fill="x", padx=2, pady=(0, 4))
        ttk.Button(tree_btns, text="+ Part", command=self._add_part, width=8).pack(side="left", padx=2)
        ttk.Button(tree_btns, text="+ Pivot", command=self._add_pivot, width=8).pack(side="left", padx=2)
        ttk.Button(tree_btns, text="Duplicate", command=self._duplicate_part, width=8).pack(side="left", padx=2)
        ttk.Button(tree_btns, text="Delete", command=self._delete_part, width=7).pack(side="left", padx=2)

        # ─── Part properties ──────────────────────────────────────────
        props_frame = ttk.LabelFrame(left, text="Properties")
        props_frame.pack(fill="x", padx=2, pady=2)

        self.prop_vars: dict[str, tk.StringVar] = {}
        prop_fields = [
            ("name", "Name"),
            ("mesh", "Mesh"),
            ("pos_x", "Pos X"), ("pos_y", "Pos Y"), ("pos_z", "Pos Z"),
            ("scale_x", "Scale X"), ("scale_y", "Scale Y"), ("scale_z", "Scale Z"),
        ]

        for i, (key, label) in enumerate(prop_fields):
            ttk.Label(props_frame, text=label + ":").grid(row=i, column=0, sticky="w", padx=(6, 2), pady=2)
            var = tk.StringVar()
            if key == "mesh":
                combo = ttk.Combobox(props_frame, textvariable=var, values=MESH_TYPES, state="readonly", width=10)
                combo.grid(row=i, column=1, sticky="w", padx=(0, 6), pady=2)
            else:
                ttk.Entry(props_frame, textvariable=var, width=12).grid(row=i, column=1, sticky="w", padx=(0, 6), pady=2)
            self.prop_vars[key] = var

        # Pivot-only field: rotation_x
        row_rx = len(prop_fields)
        ttk.Label(props_frame, text="Rot X:").grid(row=row_rx, column=0, sticky="w", padx=(6, 2), pady=2)
        self.prop_vars["rotation_x"] = tk.StringVar()
        self.rot_x_entry = ttk.Entry(props_frame, textvariable=self.prop_vars["rotation_x"], width=12)
        self.rot_x_entry.grid(row=row_rx, column=1, sticky="w", padx=(0, 6), pady=2)

        # Color button
        row_c = row_rx + 1
        ttk.Label(props_frame, text="Color:").grid(row=row_c, column=0, sticky="w", padx=(6, 2), pady=2)
        self.color_btn = tk.Button(props_frame, text="    ", width=6, command=self._pick_color, relief="solid")
        self.color_btn.grid(row=row_c, column=1, sticky="w", padx=(0, 6), pady=2)
        self._current_color = [0.5, 0.5, 0.5, 1.0]

        # Emissive checkbox
        row_e = row_c + 1
        self.emissive_var = tk.BooleanVar()
        ttk.Checkbutton(props_frame, text="Emissive", variable=self.emissive_var).grid(row=row_e, column=0, columnspan=2, sticky="w", padx=6, pady=2)

        # Apply button
        row_a = row_e + 1
        ttk.Button(props_frame, text="Apply Changes", command=self._apply_part_props).grid(row=row_a, column=0, columnspan=2, sticky="ew", padx=6, pady=(4, 6))

        # ─── Preview canvas ───────────────────────────────────────────
        preview_frame = ttk.LabelFrame(right, text="Preview (Front View)")
        preview_frame.pack(fill="both", expand=True, padx=2, pady=2)

        self.canvas = tk.Canvas(preview_frame, bg="#1a1a2e", highlightthickness=0)
        self.canvas.pack(fill="both", expand=True)
        self.canvas.bind("<Configure>", lambda e: self._redraw_preview())

    # ── Tree Management ───────────────────────────────────────────────

    def _refresh_tree(self) -> None:
        self.parts_tree.delete(*self.parts_tree.get_children())
        visual = self._get_visual()
        if not visual:
            return

        # Root parts
        for i, p in enumerate(visual.get("parts", [])):
            iid = f"root_{i}"
            label = p.get("name", f"Part {i}")
            if p.get("emissive"):
                label += " *"
            self.parts_tree.insert("", "end", iid=iid, text=f"  {label}  ({p.get('mesh', '?')})")

        # Pivots
        for pi, pv in enumerate(visual.get("pivots", [])):
            pivot_iid = f"pivot_{pi}"
            self.parts_tree.insert("", "end", iid=pivot_iid, text=f"  {pv.get('name', 'Pivot')}  [pivot]", open=True)
            for ci, cp in enumerate(pv.get("parts", [])):
                child_iid = f"pivot_{pi}_{ci}"
                label = cp.get("name", f"Part {ci}")
                if cp.get("emissive"):
                    label += " *"
                self.parts_tree.insert(pivot_iid, "end", iid=child_iid, text=f"  {label}  ({cp.get('mesh', '?')})")

    def _get_visual(self) -> dict | None:
        name = self.monster_combo.get()
        if not name:
            return None
        monster = self.data["monsters"].get(name, {})
        return monster.get("visual")

    def _set_visual(self, visual: dict) -> None:
        name = self.monster_combo.get()
        if name:
            self.data["monsters"][name]["visual"] = visual
            self.dirty = True
            self._update_title()

    def _on_tree_select(self, _event) -> None:
        sel = self.parts_tree.selection()
        if not sel:
            self._selected_part_path = None
            return

        iid = sel[0]
        self._selected_part_path = self._iid_to_path(iid)
        self._load_part_props()
        self._redraw_preview()

    def _iid_to_path(self, iid: str) -> tuple | None:
        parts = iid.split("_")
        if parts[0] == "root":
            return ("root", int(parts[1]))
        elif parts[0] == "pivot":
            if len(parts) == 2:
                return ("pivot_node", int(parts[1]))
            else:
                return ("pivot", int(parts[1]), int(parts[2]))
        return None

    def _get_part_by_path(self, path: tuple) -> dict | None:
        visual = self._get_visual()
        if not visual or not path:
            return None
        if path[0] == "root":
            parts = visual.get("parts", [])
            return parts[path[1]] if path[1] < len(parts) else None
        elif path[0] == "pivot_node":
            pivots = visual.get("pivots", [])
            return pivots[path[1]] if path[1] < len(pivots) else None
        elif path[0] == "pivot":
            pivots = visual.get("pivots", [])
            if path[1] < len(pivots):
                children = pivots[path[1]].get("parts", [])
                return children[path[2]] if path[2] < len(children) else None
        return None

    # ── Part Properties ───────────────────────────────────────────────

    def _load_part_props(self) -> None:
        part = self._get_part_by_path(self._selected_part_path)
        if not part:
            return

        is_pivot_node = self._selected_part_path and self._selected_part_path[0] == "pivot_node"

        self.prop_vars["name"].set(part.get("name", ""))

        if is_pivot_node:
            self.prop_vars["mesh"].set("")
            pos = part.get("position", [0, 0, 0])
            self.prop_vars["pos_x"].set(str(pos[0]))
            self.prop_vars["pos_y"].set(str(pos[1]))
            self.prop_vars["pos_z"].set(str(pos[2]))
            self.prop_vars["scale_x"].set("")
            self.prop_vars["scale_y"].set("")
            self.prop_vars["scale_z"].set("")
            self.prop_vars["rotation_x"].set(str(part.get("rotation_x", 0.0)))
            self._current_color = [0.5, 0.5, 0.5, 1.0]
            self.color_btn.configure(bg="#808080")
            self.emissive_var.set(False)
        else:
            self.prop_vars["mesh"].set(part.get("mesh", "box"))
            pos = part.get("position", [0, 0, 0])
            self.prop_vars["pos_x"].set(str(pos[0]))
            self.prop_vars["pos_y"].set(str(pos[1]))
            self.prop_vars["pos_z"].set(str(pos[2]))
            scl = part.get("scale", [0.1, 0.1, 0.1])
            self.prop_vars["scale_x"].set(str(scl[0]))
            self.prop_vars["scale_y"].set(str(scl[1]))
            self.prop_vars["scale_z"].set(str(scl[2]))
            self.prop_vars["rotation_x"].set("")
            col = part.get("color", [0.5, 0.5, 0.5, 1.0])
            self._current_color = list(col)
            self.color_btn.configure(bg=_color_to_hex(col))
            self.emissive_var.set(part.get("emissive", False))

    def _apply_part_props(self) -> None:
        part = self._get_part_by_path(self._selected_part_path)
        if not part:
            return

        is_pivot_node = self._selected_part_path[0] == "pivot_node"

        try:
            part["name"] = self.prop_vars["name"].get().strip()
            part["position"] = [
                float(self.prop_vars["pos_x"].get()),
                float(self.prop_vars["pos_y"].get()),
                float(self.prop_vars["pos_z"].get()),
            ]
            if is_pivot_node:
                rx = self.prop_vars["rotation_x"].get().strip()
                if rx:
                    part["rotation_x"] = float(rx)
            else:
                part["mesh"] = self.prop_vars["mesh"].get()
                part["scale"] = [
                    float(self.prop_vars["scale_x"].get()),
                    float(self.prop_vars["scale_y"].get()),
                    float(self.prop_vars["scale_z"].get()),
                ]
                part["color"] = list(self._current_color)
                part["emissive"] = self.emissive_var.get()
        except ValueError:
            messagebox.showwarning("Invalid", "Position and scale must be valid numbers.")
            return

        self.dirty = True
        self._update_title()
        self._refresh_tree()
        self._redraw_preview()

    def _pick_color(self) -> None:
        initial = _color_to_hex(self._current_color)
        result = colorchooser.askcolor(color=initial, title="Pick Part Color")
        if result and result[0]:
            r, g, b = result[0]
            self._current_color = [r / 255.0, g / 255.0, b / 255.0, 1.0]
            self.color_btn.configure(bg=result[1])

    # ── Add / Remove / Duplicate ──────────────────────────────────────

    def _ensure_visual(self) -> dict:
        visual = self._get_visual()
        if not visual:
            visual = copy.deepcopy(DEFAULT_VISUAL)
            self._set_visual(visual)
        return visual

    def _add_part(self) -> None:
        visual = self._ensure_visual()
        new_part = {
            "name": f"NewPart{len(visual.get('parts', []))}",
            "mesh": "box",
            "position": [0, 0.5, 0],
            "scale": [0.2, 0.2, 0.2],
            "color": [0.5, 0.5, 0.5, 1.0],
            "emissive": False,
        }
        # If a pivot is selected, add as child of that pivot
        if self._selected_part_path and self._selected_part_path[0] == "pivot_node":
            pi = self._selected_part_path[1]
            visual["pivots"][pi].setdefault("parts", []).append(new_part)
        else:
            visual.setdefault("parts", []).append(new_part)
        self.dirty = True
        self._update_title()
        self._refresh_tree()
        self._redraw_preview()

    def _add_pivot(self) -> None:
        visual = self._ensure_visual()
        new_pivot = {
            "name": f"Pivot{len(visual.get('pivots', []))}",
            "position": [0.3, 0.8, 0],
            "rotation_x": 0.0,
            "parts": [],
        }
        visual.setdefault("pivots", []).append(new_pivot)
        self.dirty = True
        self._update_title()
        self._refresh_tree()
        self._redraw_preview()

    def _duplicate_part(self) -> None:
        part = self._get_part_by_path(self._selected_part_path)
        if not part:
            return
        visual = self._get_visual()
        dup = copy.deepcopy(part)
        dup["name"] = dup.get("name", "Part") + "_copy"

        path = self._selected_part_path
        if path[0] == "root":
            visual["parts"].append(dup)
        elif path[0] == "pivot_node":
            visual["pivots"].append(dup)
        elif path[0] == "pivot":
            visual["pivots"][path[1]]["parts"].append(dup)

        self.dirty = True
        self._update_title()
        self._refresh_tree()
        self._redraw_preview()

    def _delete_part(self) -> None:
        path = self._selected_part_path
        if not path:
            return
        visual = self._get_visual()
        if not visual:
            return

        if path[0] == "root":
            if path[1] < len(visual.get("parts", [])):
                visual["parts"].pop(path[1])
        elif path[0] == "pivot_node":
            if path[1] < len(visual.get("pivots", [])):
                visual["pivots"].pop(path[1])
        elif path[0] == "pivot":
            pivots = visual.get("pivots", [])
            if path[1] < len(pivots):
                children = pivots[path[1]].get("parts", [])
                if path[2] < len(children):
                    children.pop(path[2])

        self._selected_part_path = None
        self.dirty = True
        self._update_title()
        self._refresh_tree()
        self._redraw_preview()

    # ── Preview Canvas ────────────────────────────────────────────────

    def _redraw_preview(self) -> None:
        c = self.canvas
        c.delete("all")
        w = c.winfo_width()
        h = c.winfo_height()
        if w < 10 or h < 10:
            return

        visual = self._get_visual()
        if not visual:
            c.create_text(w // 2, h // 2, text="No visual data", fill="#555", font=("Consolas", 12))
            return

        # Coordinate system: center-bottom of canvas, Y up
        scale_px = min(w, h) * 0.35  # pixels per world unit
        cx = w // 2
        ground_y = h - 40  # ground line

        # Draw ground line
        c.create_line(20, ground_y, w - 20, ground_y, fill="#333", width=1, dash=(4, 4))

        sel_part = self._get_part_by_path(self._selected_part_path) if self._selected_part_path else None

        # Draw root parts
        for part in visual.get("parts", []):
            self._draw_part(c, part, cx, ground_y, scale_px, 0, 0, part is sel_part)

        # Draw pivot parts (offset by pivot position)
        for pv in visual.get("pivots", []):
            pv_pos = pv.get("position", [0, 0, 0])
            pv_selected = (pv is sel_part)
            if pv_selected:
                # Draw pivot marker
                px = cx + pv_pos[0] * scale_px
                py = ground_y - pv_pos[1] * scale_px
                c.create_oval(px - 5, py - 5, px + 5, py + 5, outline="#ffff00", width=2)

            for cp in pv.get("parts", []):
                self._draw_part(c, cp, cx, ground_y, scale_px, pv_pos[0], pv_pos[1], cp is sel_part)

    def _draw_part(self, c: tk.Canvas, part: dict, cx: int, ground_y: int,
                   scale_px: float, offset_x: float, offset_y: float, selected: bool) -> None:
        pos = part.get("position", [0, 0, 0])
        scl = part.get("scale", [0.1, 0.1, 0.1])
        mesh = part.get("mesh", "box")
        color = _color_to_hex(part.get("color", [0.5, 0.5, 0.5, 1.0]))

        world_x = pos[0] + offset_x
        world_y = pos[1] + offset_y

        px = cx + world_x * scale_px
        py = ground_y - world_y * scale_px

        # Size depends on mesh type (front view: X and Y visible)
        if mesh == "sphere":
            rx = scl[0] * scale_px
            ry = scl[1] * scale_px
            c.create_oval(px - rx, py - ry, px + rx, py + ry, fill=color, outline="")
            if part.get("emissive"):
                # Glow ring
                c.create_oval(px - rx - 2, py - ry - 2, px + rx + 2, py + ry + 2,
                              outline=color, width=2)
        elif mesh == "cylinder":
            half_w = scl[0] * scale_px
            half_h = scl[1] * scale_px
            c.create_rectangle(px - half_w, py - half_h, px + half_w, py + half_h,
                               fill=color, outline="")
        else:  # box
            half_w = scl[0] * 0.5 * scale_px
            half_h = scl[1] * 0.5 * scale_px
            c.create_rectangle(px - half_w, py - half_h, px + half_w, py + half_h,
                               fill=color, outline="")

        # Selection highlight
        if selected:
            if mesh == "sphere":
                rx = scl[0] * scale_px + 3
                ry = scl[1] * scale_px + 3
                c.create_oval(px - rx, py - ry, px + rx, py + ry,
                              outline="#00ff00", width=2, dash=(3, 3))
            else:
                if mesh == "cylinder":
                    half_w = scl[0] * scale_px + 3
                    half_h = scl[1] * scale_px + 3
                else:
                    half_w = scl[0] * 0.5 * scale_px + 3
                    half_h = scl[1] * 0.5 * scale_px + 3
                c.create_rectangle(px - half_w, py - half_h, px + half_w, py + half_h,
                                   outline="#00ff00", width=2, dash=(3, 3))

    # ── Events ────────────────────────────────────────────────────────

    def _on_monster_selected(self, _event) -> None:
        name = self.monster_combo.get()
        stats = self.data["monsters"].get(name, {})
        for key, var in self.stat_vars.items():
            var.set(str(stats.get(key, 0)))
        self._selected_part_path = None
        self._refresh_tree()
        self._redraw_preview()

    def _on_save(self) -> None:
        name = self.monster_combo.get()
        if not name:
            return

        # Validate monster stats
        for key, defn in STAT_DEFINITIONS.items():
            raw = self.stat_vars[key].get().strip()
            try:
                value = defn["type"](raw)
            except (ValueError, TypeError):
                messagebox.showwarning("Invalid value", f"{defn['label']} must be a valid {defn['type'].__name__}.")
                return
            if value < defn["min"] or value > defn["max"]:
                messagebox.showwarning("Out of range", f"{defn['label']} must be between {defn['min']} and {defn['max']}.")
                return
            self.data["monsters"][name][key] = value

        # Validate scaling
        for key, defn in SCALING_DEFINITIONS.items():
            raw = self.scaling_vars[key].get().strip()
            try:
                value = defn["type"](raw)
            except (ValueError, TypeError):
                messagebox.showwarning("Invalid value", f"{defn['label']} must be a valid {defn['type'].__name__}.")
                return
            if value < defn["min"] or value > defn["max"]:
                messagebox.showwarning("Out of range", f"{defn['label']} must be between {defn['min']} and {defn['max']}.")
                return
            self.data["floor_scaling"][key] = value

        self._save_data()
        messagebox.showinfo("Saved", f"Monster data saved to:\n{DATA_FILE}")

    def _on_revert(self) -> None:
        self._load_data()
        self.monster_combo["values"] = list(self.data["monsters"].keys())
        self._on_monster_selected(None)
        for key, var in self.scaling_vars.items():
            var.set(str(self.data["floor_scaling"].get(key, 0)))
        self.dirty = False
        self._update_title()

    def _add_monster(self) -> None:
        dialog = tk.Toplevel(self.root)
        dialog.title("Add Monster")
        dialog.resizable(False, False)
        dialog.grab_set()

        ttk.Label(dialog, text="Monster name (UPPERCASE):").pack(padx=8, pady=(8, 2))
        name_var = tk.StringVar()
        entry = ttk.Entry(dialog, textvariable=name_var, width=24)
        entry.pack(padx=8, pady=2)
        entry.focus_set()

        def do_add() -> None:
            n = name_var.get().strip().upper()
            if not n or not n.isalpha():
                messagebox.showwarning("Invalid", "Name must be non-empty and alphabetic.", parent=dialog)
                return
            if n in self.data["monsters"]:
                messagebox.showwarning("Exists", f"'{n}' already exists.", parent=dialog)
                return
            base = copy.deepcopy(self.data["monsters"].get("GRUNT", {}))
            base["visual"] = copy.deepcopy(DEFAULT_VISUAL)
            self.data["monsters"][n] = base
            self.monster_combo["values"] = list(self.data["monsters"].keys())
            self.monster_combo.set(n)
            self._on_monster_selected(None)
            self.dirty = True
            self._update_title()
            dialog.destroy()

        ttk.Button(dialog, text="Add", command=do_add).pack(padx=8, pady=8)
        entry.bind("<Return>", lambda _: do_add())

    def _remove_monster(self) -> None:
        name = self.monster_combo.get()
        if not name:
            return
        if name in ("GRUNT", "MAGE", "BRUTE"):
            messagebox.showwarning("Cannot remove", f"'{name}' is a core monster type and cannot be removed.")
            return
        if not messagebox.askyesno("Confirm", f"Remove '{name}'?"):
            return
        del self.data["monsters"][name]
        self.monster_combo["values"] = list(self.data["monsters"].keys())
        self.monster_combo.current(0)
        self._on_monster_selected(None)
        self.dirty = True
        self._update_title()

    def _update_title(self) -> None:
        title = "Diabla — Monster Editor"
        if self.dirty:
            title += " *"
        self.root.title(title)

    def _on_close(self) -> None:
        if self.dirty:
            if not messagebox.askyesno("Unsaved changes", "You have unsaved changes. Quit anyway?"):
                return
        self.root.destroy()


def main() -> None:
    root = tk.Tk()
    MonsterEditor(root)
    root.mainloop()


if __name__ == "__main__":
    main()
