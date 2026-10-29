#!/usr/bin/env python3
"""Camo & Stickers control panel for Into the Radius 2.

A desktop window that drives the CamoAndStickers mod while the game runs: pick a weapon,
click a camo, add stickers and drag them on a preview of the weapon's texture. No hotkeys,
so nothing clashes with other mods. In VR, open it through the SteamVR / Oculus / Virtual
Desktop desktop view.

It talks to the mod through two files in the mod's Panel folder:
  commands.txt  appended here, one "<seq>\t<command>\t<args>" line per action,
  state.txt     written by the mod: image lists, presets, weapon in hands, preview.

Run CamoPanel.bat (or `python CamoPanel.pyw`). Needs Python 3.8+ with tkinter, which the
python.org installer includes. Pillow (`pip install pillow`) is optional: with it JPG/BMP/
TGA thumbnails show and previews scale more smoothly.
"""
import os
import subprocess
import sys
import time
import tkinter as tk
from tkinter import messagebox, ttk

try:
    from PIL import Image, ImageTk
except ImportError:  # thumbnails fall back to tk's own PNG support
    Image = ImageTk = None

MOD_DIR = os.path.dirname(os.path.abspath(__file__))
PANEL_DIR = os.path.join(MOD_DIR, "Panel")
COMMANDS = os.path.join(PANEL_DIR, "commands.txt")
STATE = os.path.join(PANEL_DIR, "state.txt")
DIAG = os.path.join(PANEL_DIR, "diagnostics.txt")

THUMB = 84
PREVIEW = 512  # preview area in pixels; the mod renders previews at this size by default
POLL_MS = 300
PING_S = 2.0
STALE_S = 15

BG, PANEL_BG, CARD, FG, MUTED, ACCENT, OK, BAD = (
    "#1d1f21", "#25282b", "#30343a", "#e8e6e3", "#9aa0a6", "#d9a441", "#6fbf73", "#d9665b")


def pretty(cls):
    """BP_Weapon_AKM_C -> AKM"""
    name = cls
    for prefix in ("BP_", "Weapon_", "Firearm_", "ITR_", "Item_"):
        if name.startswith(prefix):
            name = name[len(prefix):]
    if name.endswith("_C"):
        name = name[:-2]
    return name.replace("_", " ") or cls


def pretty_image(name):
    """07_Tiger -> Tiger"""
    head, _, rest = name.partition("_")
    return (rest if head.isdigit() and rest else name).replace("_", " ")


# ------------------------------------------------------------------ link to the mod

class ModLink:
    """The panel's half of the file protocol."""

    def __init__(self):
        os.makedirs(PANEL_DIR, exist_ok=True)
        self.seq = self._max_seq()
        self.state_mtime = None
        self.state = None
        self.last_ping = 0.0

    def _max_seq(self):
        try:
            with open(COMMANDS, encoding="utf-8") as f:
                seqs = [int(line.split("\t", 1)[0]) for line in f if line.split("\t", 1)[0].isdigit()]
            return max(seqs, default=0)
        except FileNotFoundError:
            return 0

    def send(self, *fields):
        self.seq += 1
        line = "\t".join([str(self.seq)] + [str(x).replace("\t", " ").replace("\n", " ") for x in fields]) + "\n"
        with open(COMMANDS, "a", encoding="utf-8", newline="\n") as f:
            f.write(line)
        self.last_ping = time.time()
        self._rotate()

    def _rotate(self):
        """Keeps the file small; the last lines keep their numbers so nothing replays."""
        try:
            if os.path.getsize(COMMANDS) < 32 * 1024:
                return
            with open(COMMANDS, encoding="utf-8") as f:
                lines = f.readlines()[-20:]
            tmp = COMMANDS + ".tmp"
            with open(tmp, "w", encoding="utf-8", newline="\n") as f:
                f.writelines(lines)
            os.replace(tmp, COMMANDS)
        except OSError:
            pass

    def ping_if_due(self):
        if time.time() - self.last_ping >= PING_S:
            self.send("ping")

    def poll(self):
        """Re-reads state.txt when it changed. Returns True if the state is new."""
        try:
            mtime = os.path.getmtime(STATE)
        except OSError:
            return False
        if mtime == self.state_mtime:
            return False
        try:
            with open(STATE, encoding="utf-8") as f:
                text = f.read()
        except OSError:
            return False
        self.state_mtime = mtime
        self.state = parse_state(text)
        return True

    def connected(self):
        if not self.state:
            return False
        try:
            return time.time() - int(self.state["time"]) < STALE_S
        except (KeyError, ValueError):
            return False


def parse_state(text):
    st = {"camos": [], "stickers": [], "weapons": [], "presets": {}, "st": {}, "preview": None}
    for line in text.splitlines():
        f = line.split("\t")
        k = f[0]
        try:
            if k == "camo" and len(f) >= 3:
                st["camos"].append((f[1], f[2]))
            elif k == "sticker" and len(f) >= 3:
                st["stickers"].append((f[1], f[2]))
            elif k == "weapon":
                st["weapons"].append(f[1])
            elif k == "preset":
                st["presets"][f[1]] = {"camo": f[2], "scale": float(f[3]), "strength": float(f[4])}
            elif k == "st":
                st["st"].setdefault(f[1], []).append({
                    "i": int(f[2]), "name": f[3], "u": float(f[4]), "v": float(f[5]),
                    "size": float(f[6]), "rot": float(f[7]), "tex": int(f[8])})
            elif k == "preview":
                st["preview"] = {"cls": f[1], "tex": int(f[2]), "count": int(f[3]), "path": f[4],
                                 "counter": int(f[5]), "error": f[6] if len(f) > 6 else ""}
            elif len(f) >= 2:
                st[k] = f[1]
        except (IndexError, ValueError):
            continue
    return st


# ------------------------------------------------------------------ images

class Images:
    """Thumbnail cache. Without Pillow only PNGs get a picture."""

    def __init__(self):
        self.cache = {}

    def load(self, path, size):
        key = (path, size)
        if key in self.cache:
            return self.cache[key]
        img = None
        try:
            if Image:
                im = Image.open(path).convert("RGBA")
                im.thumbnail((size, size), Image.LANCZOS)
                img = ImageTk.PhotoImage(im)
            elif path.lower().endswith(".png"):
                img = tk.PhotoImage(file=path)
                factor = max(1, max(img.width(), img.height()) // size)
                img = img.subsample(factor, factor)
        except Exception:
            img = None
        self.cache[key] = img
        return img

    def load_fresh(self, path, size):
        """For the preview, which is rewritten by the mod. Without Pillow tk can only scale
        by whole factors, so the result may not be exactly `size`: callers use its width."""
        try:
            if Image:
                im = Image.open(path).convert("RGB")
                im = im.resize((size, size), Image.LANCZOS)
                return ImageTk.PhotoImage(im)
            img = tk.PhotoImage(file=path)
            w = img.width()
            if w > size:
                f = -(-w // size)  # ceil, so it never outgrows the area
                img = img.subsample(f, f)
            elif w * 2 <= size:
                f = size // w
                img = img.zoom(f, f)
            return img
        except Exception:
            return None

    def clear(self):
        self.cache.clear()


# ------------------------------------------------------------------ widgets

class TileGrid(tk.Frame):
    """Scrollable grid of clickable picture tiles."""

    def __init__(self, master, images, columns, on_pick):
        super().__init__(master, bg=PANEL_BG)
        self.images, self.columns, self.on_pick = images, columns, on_pick
        self.canvas = tk.Canvas(self, bg=PANEL_BG, highlightthickness=0, height=2 * (THUMB + 34))
        bar = ttk.Scrollbar(self, orient="vertical", command=self.canvas.yview)
        self.inner = tk.Frame(self.canvas, bg=PANEL_BG)
        self.inner.bind("<Configure>", lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all")))
        self.canvas.create_window((0, 0), window=self.inner, anchor="nw")
        self.canvas.configure(yscrollcommand=bar.set)
        self.canvas.pack(side="left", fill="both", expand=True)
        bar.pack(side="right", fill="y")
        self.canvas.bind("<Enter>", lambda e: self.canvas.bind_all("<MouseWheel>", self._wheel))
        self.canvas.bind("<Leave>", lambda e: self.canvas.unbind_all("<MouseWheel>"))
        self.items, self.tiles, self.selected = [], {}, None

    def _wheel(self, event):
        self.canvas.yview_scroll(-1 if event.delta > 0 else 1, "units")

    def set_items(self, items):
        """items: [(key, label, image path or None)]"""
        if items == self.items:
            return
        self.items = items
        for w in self.inner.winfo_children():
            w.destroy()
        self.tiles = {}
        for n, (key, label, path) in enumerate(items):
            tile = tk.Frame(self.inner, bg=CARD, highlightthickness=3, highlightbackground=CARD, cursor="hand2")
            tile.grid(row=n // self.columns, column=n % self.columns, padx=4, pady=4)
            img = self.images.load(path, THUMB) if path else None
            pic = tk.Label(tile, bg=CARD, width=THUMB, height=THUMB)
            if img:
                pic.configure(image=img, width=THUMB, height=THUMB)
                pic.image = img
            else:
                pic.configure(text="—" if path is None else "?", fg=MUTED, font=("Segoe UI", 20),
                              width=5, height=2)
            pic.pack(padx=2, pady=(2, 0))
            text = tk.Label(tile, text=label, bg=CARD, fg=FG, font=("Segoe UI", 9), width=12)
            text.pack(pady=(0, 3))
            for w in (tile, pic, text):
                w.bind("<Button-1>", lambda e, k=key: self.on_pick(k))
            self.tiles[key] = tile
        self.select(self.selected, force=True)

    def select(self, key, force=False):
        if key == self.selected and not force:
            return
        if self.selected in self.tiles:
            self.tiles[self.selected].configure(highlightbackground=CARD)
        self.selected = key
        if key in self.tiles:
            self.tiles[key].configure(highlightbackground=ACCENT)


class Slider(tk.Frame):
    """Labelled scale that only reports the value when you let go."""

    def __init__(self, master, label, lo, hi, step, fmt, on_commit):
        super().__init__(master, bg=PANEL_BG)
        self.fmt, self.on_commit, self.dragging = fmt, on_commit, False
        top = tk.Frame(self, bg=PANEL_BG)
        top.pack(fill="x")
        tk.Label(top, text=label, bg=PANEL_BG, fg=FG, font=("Segoe UI", 10)).pack(side="left")
        self.value_label = tk.Label(top, bg=PANEL_BG, fg=ACCENT, font=("Segoe UI", 10, "bold"))
        self.value_label.pack(side="right")
        self.var = tk.DoubleVar(value=lo)
        self.scale = tk.Scale(self, from_=lo, to=hi, resolution=step, orient="horizontal", variable=self.var,
                              showvalue=False, bg=PANEL_BG, fg=FG, troughcolor=CARD, highlightthickness=0,
                              activebackground=ACCENT, sliderlength=22, width=16,
                              command=lambda v: self._show())
        self.scale.pack(fill="x")
        self.scale.bind("<ButtonPress-1>", lambda e: setattr(self, "dragging", True))
        self.scale.bind("<ButtonRelease-1>", self._release)
        self._show()

    def _show(self):
        self.value_label.configure(text=self.fmt(self.var.get()))

    def _release(self, _event):
        self.dragging = False
        self.on_commit(self.var.get())

    def set(self, value):
        if not self.dragging:
            if abs(self.var.get() - value) > 1e-6:
                self.var.set(value)
            self._show()

    def enable(self, on):
        self.scale.configure(state="normal" if on else "disabled")


def button(master, text, command, accent=False, danger=False):
    color = ACCENT if accent else (BAD if danger else CARD)
    return tk.Button(master, text=text, command=command, bg=color, fg="#111" if (accent or danger) else FG,
                     activebackground=ACCENT, relief="flat", font=("Segoe UI", 10, "bold" if accent else "normal"),
                     padx=10, pady=5, cursor="hand2", bd=0)


# ------------------------------------------------------------------ the panel

class Panel(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Camo & Stickers — Into the Radius 2")
        self.configure(bg=BG)
        self.geometry("1340x820")
        self.minsize(1240, 740)
        style = ttk.Style(self)
        style.theme_use("clam")
        style.configure("TNotebook", background=BG, borderwidth=0)
        style.configure("TNotebook.Tab", background=CARD, foreground=FG, padding=(16, 6), font=("Segoe UI", 11))
        style.map("TNotebook.Tab", background=[("selected", ACCENT)], foreground=[("selected", "#111")])

        self.link = ModLink()
        self.images = Images()
        self.selected_cls = None
        self.selected_sticker = None   # 1-based index in the weapon's sticker list
        self.preview_tex = 1
        self.preview_counter = -1
        self.preview_img = None
        self.pv = PREVIEW              # size the preview is shown at; sticker frames use it
        self.drag = None               # (sticker index, u, v) while dragging on the preview
        self.follow_held = tk.BooleanVar(value=True)
        self.on_top = tk.BooleanVar(value=False)

        self._build()
        self.link.send("hello")
        self.link.send("scan")
        self.after(100, self._tick)

    # ---------------------------------------------------------- layout

    def _build(self):
        header = tk.Frame(self, bg=BG)
        header.pack(fill="x", padx=12, pady=(10, 4))
        self.dot = tk.Label(header, text="●", bg=BG, fg=BAD, font=("Segoe UI", 16))
        self.dot.pack(side="left")
        self.conn_label = tk.Label(header, text="Нет связи с игрой", bg=BG, fg=FG, font=("Segoe UI", 12, "bold"))
        self.conn_label.pack(side="left", padx=(4, 16))
        self.status_label = tk.Label(header, text="", bg=BG, fg=MUTED, font=("Segoe UI", 10), anchor="w")
        self.status_label.pack(side="left", fill="x", expand=True)
        tk.Checkbutton(header, text="Поверх всех окон", variable=self.on_top, command=self._toggle_top,
                       bg=BG, fg=FG, selectcolor=CARD, activebackground=BG, activeforeground=FG,
                       font=("Segoe UI", 10)).pack(side="right")

        body = tk.Frame(self, bg=BG)
        body.pack(fill="both", expand=True, padx=12, pady=4)

        # Weapons
        left = tk.Frame(body, bg=PANEL_BG, width=230)
        left.pack(side="left", fill="y", padx=(0, 10))
        left.pack_propagate(False)
        tk.Label(left, text="Оружие", bg=PANEL_BG, fg=FG, font=("Segoe UI", 13, "bold")).pack(anchor="w", padx=10, pady=(10, 4))
        tk.Checkbutton(left, text="Следить за оружием в руках", variable=self.follow_held, bg=PANEL_BG, fg=FG,
                       selectcolor=CARD, activebackground=PANEL_BG, activeforeground=FG,
                       font=("Segoe UI", 9), command=self._follow_changed).pack(anchor="w", padx=8)
        self.weapon_list = tk.Listbox(left, bg=CARD, fg=FG, selectbackground=ACCENT, selectforeground="#111",
                                      font=("Segoe UI", 11), activestyle="none", highlightthickness=0, bd=0)
        self.weapon_list.pack(fill="both", expand=True, padx=8, pady=6)
        self.weapon_list.bind("<<ListboxSelect>>", self._weapon_clicked)
        self.weapon_keys = []
        button(left, "Найти оружие рядом", lambda: self.link.send("scan")).pack(fill="x", padx=8, pady=2)
        button(left, "Диагностика", self._diagnostics).pack(fill="x", padx=8, pady=(2, 10))

        # Preview
        right = tk.Frame(body, bg=PANEL_BG)
        right.pack(side="right", fill="y", padx=(10, 0))
        tk.Label(right, text="Текстура оружия", bg=PANEL_BG, fg=FG, font=("Segoe UI", 13, "bold")).pack(anchor="w", padx=10, pady=(10, 0))
        tk.Label(right, text="Перетащите наклейку мышью", bg=PANEL_BG, fg=MUTED, font=("Segoe UI", 9)).pack(anchor="w", padx=10)
        self.preview = tk.Canvas(right, width=PREVIEW, height=PREVIEW, bg="#111", highlightthickness=0, cursor="crosshair")
        self.preview.pack(padx=10, pady=6)
        self.preview.bind("<ButtonPress-1>", self._preview_press)
        self.preview.bind("<B1-Motion>", self._preview_drag)
        self.preview.bind("<ButtonRelease-1>", self._preview_release)
        nav = tk.Frame(right, bg=PANEL_BG)
        nav.pack(fill="x", padx=10)
        button(nav, "◀", lambda: self._switch_tex(-1)).pack(side="left")
        self.tex_label = tk.Label(nav, text="Текстура —", bg=PANEL_BG, fg=FG, font=("Segoe UI", 10))
        self.tex_label.pack(side="left", expand=True)
        button(nav, "▶", lambda: self._switch_tex(1)).pack(side="right")
        button(right, "Обновить превью", self._request_preview).pack(fill="x", padx=10, pady=(6, 10))

        # Camo / stickers
        center = tk.Frame(body, bg=BG)
        center.pack(side="left", fill="both", expand=True)
        self.weapon_title = tk.Label(center, text="Выберите оружие", bg=BG, fg=ACCENT, font=("Segoe UI", 16, "bold"), anchor="w")
        self.weapon_title.pack(fill="x", pady=(0, 6))
        tabs = self.tabs = ttk.Notebook(center)
        tabs.pack(fill="both", expand=True)

        camo_tab = tk.Frame(tabs, bg=PANEL_BG)
        tabs.add(camo_tab, text="Камуфляж")
        self.camo_grid = TileGrid(camo_tab, self.images, 4, self._pick_camo)
        self.camo_grid.pack(fill="both", expand=True, padx=8, pady=8)
        self.scale_slider = Slider(camo_tab, "Масштаб узора (больше — мельче)", 0.5, 8, 0.25, lambda v: f"{v:.2f}×",
                                   lambda v: self._send_cls("scale", f"{v:.3f}"))
        self.scale_slider.pack(fill="x", padx=12, pady=4)
        self.strength_slider = Slider(camo_tab, "Сила покрытия", 0, 1, 0.05, lambda v: f"{v * 100:.0f}%",
                                      lambda v: self._send_cls("strength", f"{v:.3f}"))
        self.strength_slider.pack(fill="x", padx=12, pady=(4, 12))

        st_tab = tk.Frame(tabs, bg=PANEL_BG)
        tabs.add(st_tab, text="Наклейки")
        row = tk.Frame(st_tab, bg=PANEL_BG)
        row.pack(fill="x", padx=8, pady=(8, 2))
        tk.Label(row, text="На оружии:", bg=PANEL_BG, fg=FG, font=("Segoe UI", 10)).pack(side="left")
        self.sticker_bar = tk.Frame(row, bg=PANEL_BG)
        self.sticker_bar.pack(side="left", fill="x", expand=True, padx=6)
        button(row, "+ Добавить", self._add_sticker, accent=True).pack(side="right", padx=2)
        button(row, "Удалить", self._remove_sticker, danger=True).pack(side="right", padx=2)
        tk.Label(st_tab, text="Картинка выбранной наклейки:", bg=PANEL_BG, fg=MUTED,
                 font=("Segoe UI", 9)).pack(anchor="w", padx=10)
        self.sticker_grid = TileGrid(st_tab, self.images, 4, self._pick_sticker_image)
        self.sticker_grid.pack(fill="both", expand=True, padx=8, pady=4)
        self.size_slider = Slider(st_tab, "Размер", 0.02, 0.6, 0.01, lambda v: f"{v * 100:.0f}%",
                                  lambda v: self._set_sticker(size=v))
        self.size_slider.pack(fill="x", padx=12, pady=2)
        self.rot_slider = Slider(st_tab, "Поворот", 0, 359, 1, lambda v: f"{v:.0f}°",
                                 lambda v: self._set_sticker(rot=v))
        self.rot_slider.pack(fill="x", padx=12, pady=(2, 10))

        footer = tk.Frame(self, bg=BG)
        footer.pack(fill="x", padx=12, pady=(4, 10))
        button(footer, "Обновить картинки", lambda: self.link.send("reload")).pack(side="left", padx=(0, 6))
        button(footer, "Папка камуфляжей", lambda: self._open(os.path.join(MOD_DIR, "Camo"))).pack(side="left", padx=6)
        button(footer, "Папка наклеек", lambda: self._open(os.path.join(MOD_DIR, "Stickers"))).pack(side="left", padx=6)
        button(footer, "Сбросить оружие", self._reset, danger=True).pack(side="right")

    # ---------------------------------------------------------- state -> UI

    def _tick(self):
        try:
            self.link.ping_if_due()
            if self.link.poll():
                self._refresh()
            self._show_connection()
        finally:
            self.after(POLL_MS, self._tick)

    def _show_connection(self):
        if self.link.connected():
            self.dot.configure(fg=OK)
            self.conn_label.configure(text="Игра подключена")
        else:
            self.dot.configure(fg=BAD)
            self.conn_label.configure(text="Нет связи с игрой")
            if not self.link.state:
                self.status_label.configure(text="Запустите игру с модом и загрузите сохранение. Папка мода: " + MOD_DIR)

    def _refresh(self):
        st = self.link.state
        self.status_label.configure(text=st.get("status", ""))
        held = st.get("held") or None

        if self.follow_held.get() and held and held != self.selected_cls:
            self._select_weapon(held)
        elif self.selected_cls is None and st["weapons"]:
            self._select_weapon(held or st["weapons"][0])

        # Weapon list
        keys = list(st["weapons"])
        if keys != self.weapon_keys or held != getattr(self, "_held_shown", None):
            self.weapon_keys, self._held_shown = keys, held
            self.weapon_list.delete(0, "end")
            for cls in keys:
                mark = "✋ " if cls == held else ("● " if cls in st["presets"] else "   ")
                self.weapon_list.insert("end", mark + pretty(cls))
        if self.selected_cls in self.weapon_keys:
            i = self.weapon_keys.index(self.selected_cls)
            if self.weapon_list.curselection() != (i,):
                self.weapon_list.selection_clear(0, "end")
                self.weapon_list.selection_set(i)

        # Image grids
        self.camo_grid.set_items([("", "Без камуфляжа", None)] +
                                 [(name, pretty_image(name), path) for name, path in st["camos"]])
        self.sticker_grid.set_items([(name, pretty_image(name), path) for name, path in st["stickers"]])

        preset = st["presets"].get(self.selected_cls) if self.selected_cls else None
        has_weapon = self.selected_cls is not None
        self.weapon_title.configure(text=pretty(self.selected_cls) if has_weapon else "Выберите оружие")
        self.camo_grid.select(preset["camo"] if preset else "")
        self.scale_slider.set(preset["scale"] if preset else 2.0)
        self.strength_slider.set(preset["strength"] if preset else 0.85)
        for s in (self.scale_slider, self.strength_slider):
            s.enable(has_weapon)

        self._refresh_stickers()
        self._refresh_preview()

    def _stickers(self):
        st = self.link.state
        return st["st"].get(self.selected_cls, []) if st and self.selected_cls else []

    def _refresh_stickers(self):
        stickers = self._stickers()
        if self.selected_sticker and self.selected_sticker > len(stickers):
            self.selected_sticker = len(stickers) or None
        if self.selected_sticker is None and stickers:
            self.selected_sticker = len(stickers)
        for w in self.sticker_bar.winfo_children():
            w.destroy()
        names = dict(self.link.state["stickers"])
        for s in stickers:
            sel = s["i"] == self.selected_sticker
            img = self.images.load(names.get(s["name"]), 34) if names.get(s["name"]) else None
            b = tk.Button(self.sticker_bar, text=f" {s['i']}", image=img, compound="left",
                          bg=ACCENT if sel else CARD, fg="#111" if sel else FG, relief="flat", bd=0,
                          padx=4, pady=2, cursor="hand2", command=lambda i=s["i"]: self._choose_sticker(i))
            b.image = img
            b.pack(side="left", padx=2)
        current = stickers[self.selected_sticker - 1] if self.selected_sticker else None
        self.sticker_grid.select(current["name"] if current else None)
        if current:
            self.size_slider.set(current["size"])
            self.rot_slider.set(current["rot"])
        for s in (self.size_slider, self.rot_slider):
            s.enable(current is not None)

    def _refresh_preview(self):
        pv = self.link.state.get("preview") if self.link.state else None
        c = self.preview
        if pv and pv["cls"] == self.selected_cls:
            count = max(1, pv["count"])
            self.preview_tex = pv["tex"]
            self.tex_label.configure(text=f"Часть оружия {pv['tex']} из {count}")
            if pv["path"] and pv["counter"] != self.preview_counter:
                img = self.images.load_fresh(pv["path"], PREVIEW)
                if img:
                    self.preview_img, self.preview_counter = img, pv["counter"]
                    self.pv = img.width()
            if pv["error"]:
                self.preview_img = None
                self.preview_counter = -1
        else:
            self.tex_label.configure(text="Текстура —")
            self.preview_img = None
        self._draw_preview(pv["error"] if pv and pv["cls"] == self.selected_cls else "")

    def _draw_preview(self, error=""):
        c = self.preview
        c.delete("all")
        if self.preview_img:
            c.create_image(0, 0, image=self.preview_img, anchor="nw")
        else:
            msg = {
                "no weapon of this type is loaded nearby": "Такого оружия нет рядом.\nПодойдите к нему или возьмите в руки.",
                "preview needs composite mode": "Превью работает только в режиме\ncomposite (см. config.lua).",
            }.get(error, error or "Превью появится,\nкогда игра его отрисует.")
            c.create_text(self.pv / 2, self.pv / 2, text=msg, fill=MUTED, font=("Segoe UI", 11), justify="center")
        for s in self._stickers():
            if s["tex"] != self.preview_tex:
                continue
            u, v = (self.drag[1], self.drag[2]) if self.drag and self.drag[0] == s["i"] else (s["u"], s["v"])
            x, y, r = u * self.pv, v * self.pv, max(10, s["size"] * self.pv / 2)
            sel = s["i"] == self.selected_sticker
            color = ACCENT if sel else "#ffffff"
            c.create_rectangle(x - r, y - r, x + r, y + r, outline=color, width=3 if sel else 1, dash=() if sel else (4, 3))
            c.create_text(x - r + 4, y - r + 2, text=str(s["i"]), fill=color, anchor="nw", font=("Segoe UI", 10, "bold"))

    # ---------------------------------------------------------- actions

    def _send_cls(self, *args):
        if self.selected_cls:
            self.link.send(args[0], self.selected_cls, *args[1:])

    def _select_weapon(self, cls):
        if cls == self.selected_cls:
            return
        self.selected_cls = cls
        self.selected_sticker = None
        self.preview_tex = 1
        self.preview_counter = -1
        self.preview_img = None
        self.link.send("preview", cls, 1)

    def _weapon_clicked(self, _event):
        sel = self.weapon_list.curselection()
        if sel and sel[0] < len(self.weapon_keys):
            cls = self.weapon_keys[sel[0]]
            if cls != self.selected_cls:
                held = self.link.state.get("held") if self.link.state else None
                if cls != held:
                    self.follow_held.set(False)  # picking another gun by hand stops following
                self._select_weapon(cls)
                self._refresh()

    def _follow_changed(self):
        if self.follow_held.get() and self.link.state and self.link.state.get("held"):
            self._select_weapon(self.link.state["held"])
            self._refresh()

    def _pick_camo(self, name):
        self.camo_grid.select(name)
        self._send_cls("camo", name)

    def _add_sticker(self):
        if not self.selected_cls:
            return
        name = self.sticker_grid.selected or (self.link.state["stickers"][0][0] if self.link.state["stickers"] else "")
        self.link.send("add_sticker", self.selected_cls, name)
        self.selected_sticker = len(self._stickers()) + 1

    def _remove_sticker(self):
        if self.selected_cls and self.selected_sticker:
            self.link.send("remove_sticker", self.selected_cls, self.selected_sticker)
            self.selected_sticker = None

    def _choose_sticker(self, i):
        self.selected_sticker = i
        s = self._stickers()[i - 1]
        if s["tex"] != self.preview_tex:
            self.link.send("preview", self.selected_cls, s["tex"])
        self._refresh_stickers()
        self._draw_preview()

    def _pick_sticker_image(self, name):
        if self.selected_cls and self.selected_sticker:
            self.sticker_grid.select(name)
            self._set_sticker(name=name)
        else:
            self.sticker_grid.select(name)
            self._add_sticker()

    def _set_sticker(self, name="", u="", v="", size="", rot="", tex=""):
        if not (self.selected_cls and self.selected_sticker):
            return
        fmt = lambda x: f"{x:.4f}" if isinstance(x, float) else str(x)
        self.link.send("set_sticker", self.selected_cls, self.selected_sticker, name, fmt(u), fmt(v), fmt(size),
                       fmt(rot), fmt(tex))

    def _switch_tex(self, step):
        if not self.selected_cls:
            return
        pv = self.link.state.get("preview") if self.link.state else None
        count = max(1, pv["count"]) if pv and pv["cls"] == self.selected_cls else 1
        tex = (self.preview_tex - 1 + step) % count + 1
        self.link.send("preview", self.selected_cls, tex)
        # Moving to another part of the gun takes the selected sticker along.
        if self.selected_sticker and count > 1:
            self._set_sticker(tex=tex)

    def _request_preview(self):
        if self.selected_cls:
            self.link.send("preview", self.selected_cls, self.preview_tex)

    def _reset(self):
        if self.selected_cls and messagebox.askyesno(
                "Сбросить оружие", f"Убрать камуфляж и наклейки с «{pretty(self.selected_cls)}»?", parent=self):
            self._send_cls("reset")

    # ---------------------------------------------------------- preview dragging

    def _sticker_at(self, x, y):
        best = None
        for s in self._stickers():
            if s["tex"] != self.preview_tex:
                continue
            r = max(10, s["size"] * self.pv / 2)
            if abs(x - s["u"] * self.pv) <= r and abs(y - s["v"] * self.pv) <= r:
                best = s["i"]
        return best

    def _preview_press(self, event):
        if not self.selected_cls:
            return
        hit = self._sticker_at(event.x, event.y)
        if hit:
            self.selected_sticker = hit
            self._refresh_stickers()
        if self.selected_sticker:
            self.drag = (self.selected_sticker, event.x / self.pv, event.y / self.pv)
            self._draw_preview()

    def _preview_drag(self, event):
        if self.drag:
            u = min(max(event.x / self.pv, 0), 1)
            v = min(max(event.y / self.pv, 0), 1)
            self.drag = (self.drag[0], u, v)
            self._draw_preview()

    def _preview_release(self, _event):
        if not self.drag:
            return
        i, u, v = self.drag
        self.drag = None
        stickers = self._stickers()
        if 0 < i <= len(stickers) and stickers[i - 1]["tex"] != self.preview_tex:
            self._set_sticker(u=u, v=v, tex=self.preview_tex)
        else:
            self._set_sticker(u=u, v=v)

    # ---------------------------------------------------------- misc

    def _toggle_top(self):
        self.attributes("-topmost", self.on_top.get())

    def _open(self, path):
        try:
            if sys.platform == "win32":
                os.startfile(path)
            else:
                subprocess.Popen(["xdg-open", path])
        except OSError as e:
            messagebox.showerror("Папка", str(e), parent=self)

    def _diagnostics(self):
        try:
            os.remove(DIAG)
        except OSError:
            pass
        self.link.send("diagnostics")
        self._show_diag(time.time())

    def _show_diag(self, started):
        if not os.path.exists(DIAG):
            if time.time() - started < 5:
                self.after(300, lambda: self._show_diag(started))
            else:
                messagebox.showwarning("Диагностика", "Игра не ответила. Она запущена и мод загружен?", parent=self)
            return
        with open(DIAG, encoding="utf-8", errors="replace") as f:
            text = f.read()
        win = tk.Toplevel(self)
        win.title("Диагностика")
        win.configure(bg=BG)
        win.geometry("820x520")
        box = tk.Text(win, bg=PANEL_BG, fg=FG, font=("Consolas", 10), wrap="none", bd=0)
        box.insert("1.0", text)
        box.configure(state="disabled")
        box.pack(fill="both", expand=True, padx=8, pady=8)


if __name__ == "__main__":
    Panel().mainloop()
