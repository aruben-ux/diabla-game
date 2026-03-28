"""
Diabla Monster Editor — View and edit monster stats.
Reads/writes data/monster_data.json alongside the Godot project.
"""

import json
import os
import sys
import tkinter as tk
from tkinter import ttk, messagebox

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


class MonsterEditor:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("Diabla — Monster Editor")
        self.root.resizable(False, False)
        self.data: dict = {}
        self.stat_vars: dict[str, tk.StringVar] = {}
        self.scaling_vars: dict[str, tk.StringVar] = {}
        self.dirty = False

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
        pad = {"padx": 8, "pady": 4}

        # ─── Monster selector ─────────────────────────────────────────
        top_frame = ttk.Frame(self.root)
        top_frame.pack(fill="x", **pad)

        ttk.Label(top_frame, text="Monster:").pack(side="left")
        self.monster_combo = ttk.Combobox(
            top_frame,
            values=list(self.data["monsters"].keys()),
            state="readonly",
            width=20,
        )
        self.monster_combo.pack(side="left", padx=(4, 0))
        self.monster_combo.current(0)
        self.monster_combo.bind("<<ComboboxSelected>>", self._on_monster_selected)

        # ─── Add / Remove buttons ─────────────────────────────────────
        ttk.Button(top_frame, text="+ Add", command=self._add_monster, width=7).pack(side="left", padx=(12, 2))
        ttk.Button(top_frame, text="− Remove", command=self._remove_monster, width=8).pack(side="left", padx=2)

        # ─── Stats frame ──────────────────────────────────────────────
        stats_frame = ttk.LabelFrame(self.root, text="Stats")
        stats_frame.pack(fill="x", **pad)

        for i, (key, defn) in enumerate(STAT_DEFINITIONS.items()):
            ttk.Label(stats_frame, text=defn["label"] + ":").grid(
                row=i, column=0, sticky="w", padx=(8, 4), pady=3
            )
            var = tk.StringVar()
            entry = ttk.Entry(stats_frame, textvariable=var, width=14)
            entry.grid(row=i, column=1, sticky="w", padx=(0, 8), pady=3)
            self.stat_vars[key] = var

            min_max_text = f"({defn['min']} – {defn['max']})"
            ttk.Label(stats_frame, text=min_max_text, foreground="grey").grid(
                row=i, column=2, sticky="w", padx=(0, 8), pady=3
            )

        # ─── Floor Scaling frame ──────────────────────────────────────
        scaling_frame = ttk.LabelFrame(self.root, text="Floor Scaling (Global)")
        scaling_frame.pack(fill="x", **pad)

        for i, (key, defn) in enumerate(SCALING_DEFINITIONS.items()):
            ttk.Label(scaling_frame, text=defn["label"] + ":").grid(
                row=i, column=0, sticky="w", padx=(8, 4), pady=3
            )
            var = tk.StringVar()
            entry = ttk.Entry(scaling_frame, textvariable=var, width=14)
            entry.grid(row=i, column=1, sticky="w", padx=(0, 8), pady=3)
            self.scaling_vars[key] = var

        # Load scaling values
        for key, var in self.scaling_vars.items():
            var.set(str(self.data["floor_scaling"].get(key, 0)))

        # ─── Bottom buttons ───────────────────────────────────────────
        btn_frame = ttk.Frame(self.root)
        btn_frame.pack(fill="x", **pad, pady=(4, 8))

        ttk.Button(btn_frame, text="Save", command=self._on_save).pack(side="right", padx=4)
        ttk.Button(btn_frame, text="Revert", command=self._on_revert).pack(side="right", padx=4)

    # ── Events ────────────────────────────────────────────────────────

    def _on_monster_selected(self, _event) -> None:
        name = self.monster_combo.get()
        stats = self.data["monsters"].get(name, {})
        for key, var in self.stat_vars.items():
            var.set(str(stats.get(key, 0)))

    def _on_save(self) -> None:
        # Validate & write current monster stats back into data
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
                messagebox.showwarning(
                    "Out of range",
                    f"{defn['label']} must be between {defn['min']} and {defn['max']}.",
                )
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
                messagebox.showwarning(
                    "Out of range",
                    f"{defn['label']} must be between {defn['min']} and {defn['max']}.",
                )
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
            # Copy defaults from GRUNT
            self.data["monsters"][n] = dict(self.data["monsters"].get("GRUNT", {}))
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
