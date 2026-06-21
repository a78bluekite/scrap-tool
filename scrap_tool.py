import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox, filedialog
import threading
import time
import os
import ctypes
import uuid
import webbrowser

try:
    from PIL import Image, ImageGrab, ImageTk
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False

try:
    import pytesseract
    tesseract_path = r"C:\Program Files\Tesseract-OCR\tesseract.exe"
    if os.path.exists(tesseract_path):
        pytesseract.pytesseract.tesseract_cmd = tesseract_path
        OCR_AVAILABLE = True
    else:
        OCR_AVAILABLE = False
except ImportError:
    OCR_AVAILABLE = False

try:
    import anthropic
    CLAUDE_AVAILABLE = True
except ImportError:
    CLAUDE_AVAILABLE = False

try:
    from pynput import mouse as pynput_mouse
    PYNPUT_AVAILABLE = True
except ImportError:
    PYNPUT_AVAILABLE = False


# 프로세스 DPI awareness 설정 (캡처 좌표 일치를 위해 가장 먼저 호출)
try:
    ctypes.windll.shcore.SetProcessDpiAwareness(2)   # Per-Monitor DPI Aware
except Exception:
    try:
        ctypes.windll.user32.SetProcessDPIAware()
    except Exception:
        pass

CLAUDE_MODEL = "claude-opus-4-8"
WINDOW_BG  = "#1e1e2e"
PANEL_BG   = "#2a2a3e"
ACCENT     = "#7c6af7"
ACCENT_H   = "#6a58e0"
TEXT_COLOR = "#cdd6f4"
MUTED      = "#6c7086"
BORDER     = "#3a3a5c"
DANGER     = "#f38ba8"
GREEN      = "#4a7c59"
GREEN_H    = "#3a6449"


def _simulate_ctrl_c():
    KEYEVENTF_KEYUP = 0x0002
    u32 = ctypes.windll.user32
    u32.keybd_event(0x11, 0, 0, 0)
    u32.keybd_event(0x43, 0, 0, 0)
    u32.keybd_event(0x43, 0, KEYEVENTF_KEYUP, 0)
    u32.keybd_event(0x11, 0, KEYEVENTF_KEYUP, 0)


def _get_clipboard_text():
    """Win32 API로 클립보드 텍스트 읽기 (스레드 안전, tkinter 불필요)"""
    CF_UNICODETEXT = 13
    u32 = ctypes.windll.user32
    k32 = ctypes.windll.kernel32
    # 64비트 Windows에서 핸들/포인터가 잘리지 않도록 c_size_t 지정
    u32.GetClipboardData.restype = ctypes.c_size_t
    k32.GlobalLock.restype       = ctypes.c_size_t
    if not u32.OpenClipboard(0):
        return ""
    try:
        hdata = u32.GetClipboardData(CF_UNICODETEXT)
        if not hdata:
            return ""
        ptr = k32.GlobalLock(ctypes.c_size_t(hdata))
        if not ptr:
            return ""
        try:
            return ctypes.wstring_at(ptr)
        finally:
            k32.GlobalUnlock(ctypes.c_size_t(hdata))
    except Exception:
        return ""
    finally:
        try:
            u32.CloseClipboard()
        except Exception:
            pass


# ── 화면 캡처 오버레이 ───────────────────────────────────────
class SelectionOverlay(tk.Toplevel):
    def __init__(self, parent, on_selected):
        super().__init__(parent)
        self.on_selected = on_selected
        self.start_x = self.start_y = 0
        self._cx = self._cy = 0
        self.rect_id = None

        # -fullscreen 대신 명시적 geometry로 정확히 (0,0) 배치
        u32 = ctypes.windll.user32
        sw = u32.GetSystemMetrics(0)
        sh = u32.GetSystemMetrics(1)

        self.overrideredirect(True)
        self.attributes("-alpha", 0.25)
        self.attributes("-topmost", True)
        self.geometry(f"{sw}x{sh}+0+0")
        self.configure(bg="black", cursor="crosshair")

        self.canvas = tk.Canvas(self, bg="black", highlightthickness=0,
                                width=sw, height=sh)
        self.canvas.place(x=0, y=0)
        self.canvas.bind("<ButtonPress-1>", self._on_press)
        self.canvas.bind("<B1-Motion>", self._on_drag)
        self.canvas.bind("<ButtonRelease-1>", self._on_release)
        self.bind("<Escape>", lambda e: self.destroy())
        self.focus_force()

        label = tk.Label(
            self.canvas, text="드래그하여 영역 선택  |  ESC: 취소",
            bg="#1a1a2e", fg="#a0a0c0", font=("맑은 고딕", 11), padx=12, pady=6)
        self.canvas.create_window(sw // 2, 20, window=label, anchor="n")

    def _on_press(self, event):
        # 캔버스 내 상대 좌표 → 오버레이가 (0,0)에 있으므로 곧 화면 좌표
        self.start_x, self.start_y = event.x, event.y
        self._cx, self._cy = event.x, event.y
        if self.rect_id:
            self.canvas.delete(self.rect_id)
        self.rect_id = self.canvas.create_rectangle(
            event.x, event.y, event.x, event.y,
            outline="#7c6af7", width=2, fill="#7c6af7", stipple="gray12")

    def _on_drag(self, event):
        if self.rect_id:
            self.canvas.coords(self.rect_id, self._cx, self._cy, event.x, event.y)

    def _on_release(self, event):
        x1 = min(self.start_x, event.x)
        y1 = min(self.start_y, event.y)
        x2 = max(self.start_x, event.x)
        y2 = max(self.start_y, event.y)
        self.destroy()
        if x2 - x1 > 5 and y2 - y1 > 5:
            self.after(1, lambda: self.on_selected(x1, y1, x2, y2))


# ── 드래그 선택 스크랩 팝업 ─────────────────────────────────
class ScrapPopup(tk.Toplevel):
    AUTO_DISMISS_MS = 4000

    def __init__(self, parent, x1, y1, x2, y2, text, on_scrap):
        super().__init__(parent)
        self.overrideredirect(True)
        self.attributes("-topmost", True)
        self.attributes("-alpha", 0.95)
        self.configure(bg="#1a1a2e")

        # 선택 영역 오른쪽 중앙에 위치
        sw = self.winfo_screenwidth()
        sh = self.winfo_screenheight()
        w, h = 96, 30
        mid_y = (y1 + y2) // 2
        px = min(x2 + 10, sw - w - 4)
        py = max(min(mid_y - h // 2, sh - h - 4), 4)
        self.geometry(f"{w}x{h}+{px}+{py}")

        inner = tk.Frame(self, bg="#252538",
                         highlightthickness=1, highlightbackground=GREEN)
        inner.pack(fill=tk.BOTH, expand=True)

        tk.Button(
            inner, text="✂  스크랩", bg="#252538", fg="#a6e3a1",
            font=("맑은 고딕", 9, "bold"), bd=0, padx=6,
            activebackground=GREEN, activeforeground="white",
            cursor="hand2", relief=tk.FLAT,
            command=lambda: self._do_scrap(text, on_scrap)
        ).pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        tk.Button(
            inner, text="✕", bg="#252538", fg=MUTED,
            font=("Arial", 8), bd=0, padx=4,
            activebackground="#252538", activeforeground=DANGER,
            cursor="hand2", relief=tk.FLAT, command=self.destroy
        ).pack(side=tk.RIGHT)

        self._timer = self.after(self.AUTO_DISMISS_MS, self._dismiss)

    def _do_scrap(self, text, on_scrap):
        if self._timer:
            self.after_cancel(self._timer)
        self.destroy()
        on_scrap(text)

    def _dismiss(self):
        try:
            self.destroy()
        except Exception:
            pass


# ── AI 결과 창 ───────────────────────────────────────────────
class ResultWindow(tk.Toplevel):
    def __init__(self, parent, title, content):
        super().__init__(parent)
        self.title(title)
        self.configure(bg=WINDOW_BG)
        self.geometry("700x520")
        self.attributes("-topmost", True)
        self.resizable(True, True)

        header = tk.Frame(self, bg=PANEL_BG)
        header.pack(fill=tk.X)
        tk.Label(header, text=title, bg=PANEL_BG, fg=ACCENT,
                 font=("맑은 고딕", 13, "bold"), padx=16, pady=10).pack(side=tk.LEFT)
        tk.Button(header, text="✕", bg=PANEL_BG, fg=MUTED,
                  font=("Arial", 11), bd=0, padx=10,
                  activebackground=PANEL_BG, activeforeground=DANGER,
                  cursor="hand2", command=self.destroy).pack(side=tk.RIGHT)

        tf = tk.Frame(self, bg=WINDOW_BG)
        tf.pack(fill=tk.BOTH, expand=True, padx=16, pady=12)
        self.text_area = scrolledtext.ScrolledText(
            tf, bg=PANEL_BG, fg=TEXT_COLOR, font=("맑은 고딕", 11),
            wrap=tk.WORD, bd=0, padx=12, pady=10,
            insertbackground=TEXT_COLOR, selectbackground=ACCENT)
        self.text_area.pack(fill=tk.BOTH, expand=True)
        self.text_area.insert(tk.END, content)
        self.text_area.configure(state=tk.DISABLED)

        tk.Button(self, text="클립보드 복사", bg=ACCENT, fg="white",
                  font=("맑은 고딕", 10), bd=0, padx=14, pady=7,
                  activebackground=ACCENT_H, cursor="hand2",
                  command=lambda: (
                      self.clipboard_clear(), self.clipboard_append(content),
                      messagebox.showinfo("복사 완료", "클립보드에 복사되었습니다.", parent=self)
                  )).pack(pady=12)


# ── 스크랩 항목 위젯 (드래그 순서 이동 지원) ─────────────────
class ScrapItem(tk.Frame):
    def __init__(self, parent, item_data, on_delete, on_export, on_ocr,
                 on_drag_start, on_drag_motion, on_drag_end, index):
        super().__init__(parent, bg=PANEL_BG, bd=0,
                         highlightthickness=1, highlightbackground=BORDER)
        self.item_data = item_data
        self.on_delete = on_delete
        self.on_export = on_export
        self.on_ocr = on_ocr
        self.index = index
        self._build()

        # 드래그 순서 이동 바인딩
        self.bind("<ButtonPress-1>",   on_drag_start)
        self.bind("<B1-Motion>",       on_drag_motion)
        self.bind("<ButtonRelease-1>", on_drag_end)
        for child in self.winfo_children():
            self._bind_drag(child, on_drag_start, on_drag_motion, on_drag_end)

    def _bind_drag(self, widget, start, motion, end):
        # 버튼 등 클릭 가능한 위젯은 제외
        if isinstance(widget, tk.Button):
            return
        widget.bind("<ButtonPress-1>",   start)
        widget.bind("<B1-Motion>",       motion)
        widget.bind("<ButtonRelease-1>", end)
        for child in widget.winfo_children():
            self._bind_drag(child, start, motion, end)

    def _build(self):
        item_type = self.item_data.get("type", "capture")
        text      = self.item_data.get("text", "").strip()
        cur_align = self.item_data.get("align", "left")

        header = tk.Frame(self, bg=PANEL_BG)
        header.pack(fill=tk.X, padx=8, pady=4)

        tk.Label(header, text="⠿", bg=PANEL_BG, fg=MUTED,
                 font=("Arial", 11), cursor="fleur").pack(side=tk.LEFT)
        tk.Label(header, text=f"#{self.index}", bg=PANEL_BG, fg=ACCENT,
                 font=("맑은 고딕", 9, "bold")).pack(side=tk.LEFT, padx=(4, 0))

        if item_type == "text":
            bt, bf, bb = "✍ 텍스트", "#a6e3a1", "#1e3a2e"
        else:
            bt, bf, bb = "📷 캡처", "#89b4fa", "#1e2a3e"
        tk.Label(header, text=bt, bg=bb, fg=bf,
                 font=("맑은 고딕", 7, "bold"), padx=5, pady=1
                 ).pack(side=tk.LEFT, padx=4)
        tk.Label(header, text=self.item_data.get("timestamp", ""),
                 bg=PANEL_BG, fg=MUTED, font=("맑은 고딕", 8)
                 ).pack(side=tk.LEFT, padx=2)

        # ✕ 삭제 버튼 (맨 오른쪽)
        tk.Button(header, text="✕", bg=PANEL_BG, fg=MUTED,
                  font=("Arial", 9), bd=0,
                  activebackground=PANEL_BG, activeforeground=DANGER,
                  cursor="hand2", command=self.on_delete).pack(side=tk.RIGHT)

        # 이미지 내보내기 / OCR
        if self.item_data.get("image"):
            tk.Button(header, text="💾", bg=PANEL_BG, fg=MUTED,
                      font=("Arial", 9), bd=0,
                      activebackground=PANEL_BG, activeforeground=ACCENT,
                      cursor="hand2", command=self.on_export
                      ).pack(side=tk.RIGHT, padx=(0, 2))
            tk.Button(header, text="📝", bg=PANEL_BG, fg=MUTED,
                      font=("Arial", 9), bd=0,
                      activebackground=PANEL_BG, activeforeground="#a6e3a1",
                      cursor="hand2", command=self.on_ocr
                      ).pack(side=tk.RIGHT, padx=(0, 2))

        # 정렬 버튼 (텍스트가 있는 항목만)
        if text:
            self._align_btns = {}
            af = tk.Frame(header, bg=PANEL_BG)
            af.pack(side=tk.RIGHT, padx=(0, 6))
            for key, sym in [("left", "←"), ("center", "≡"), ("right", "→")]:
                active = key == cur_align
                btn = tk.Button(
                    af, text=sym,
                    bg=ACCENT if active else PANEL_BG,
                    fg="white" if active else MUTED,
                    font=("Arial", 9), bd=0, padx=5, pady=1,
                    activebackground=ACCENT_H, activeforeground="white",
                    cursor="hand2", relief=tk.FLAT,
                    command=lambda k=key: self._set_align(k)
                )
                btn.pack(side=tk.LEFT)
                self._align_btns[key] = btn

        if self.item_data.get("image") and PIL_AVAILABLE and item_type == "capture":
            try:
                thumb = self.item_data["image"].copy()
                thumb.thumbnail((240, 140), Image.LANCZOS)
                self._photo = ImageTk.PhotoImage(thumb)
                tk.Label(self, image=self._photo, bg=PANEL_BG).pack(pady=4)
            except Exception:
                pass

        if text:
            anchor_map  = {"left": "w", "center": "center", "right": "e"}
            justify_map = {"left": tk.LEFT, "center": tk.CENTER, "right": tk.RIGHT}
            self._text_label = tk.Label(
                self, text=text, bg=PANEL_BG, fg=TEXT_COLOR,
                font=("맑은 고딕", 10), wraplength=300,
                anchor=anchor_map[cur_align],
                justify=justify_map[cur_align],
                padx=8, pady=4)
            self._text_label.pack(fill=tk.X)
            self._text_label.bind(
                "<Configure>",
                lambda e, l=self._text_label: l.configure(wraplength=max(1, e.width - 16)))

        tk.Frame(self, bg=BORDER, height=1).pack(fill=tk.X)

    def _set_align(self, align):
        self.item_data["align"] = align
        anchor_map  = {"left": "w", "center": "center", "right": "e"}
        justify_map = {"left": tk.LEFT, "center": tk.CENTER, "right": tk.RIGHT}
        if hasattr(self, "_text_label"):
            self._text_label.configure(
                anchor=anchor_map[align],
                justify=justify_map[align])
        if hasattr(self, "_align_btns"):
            for key, btn in self._align_btns.items():
                btn.configure(
                    bg=ACCENT if key == align else PANEL_BG,
                    fg="white" if key == align else MUTED)


# ── 메인 앱 ─────────────────────────────────────────────────
class ScrapApp:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("스크랩 도구")
        self.root.configure(bg=WINDOW_BG)
        self.root.geometry("520x720+50+50")
        self.root.attributes("-topmost", True)
        self.root.resizable(True, True)

        self.scraps = []
        self._drag_start_pos = None
        self._active_popup = None
        self._mouse_listener = None
        self._selection_mode = False
        # 드래그 순서이동 상태
        self._order_drag_widget = None
        self._order_drag_data = None
        self._order_drag_ghost = None
        self._order_drag_start_y = 0
        # 폴더 관리
        self.folders = [{"id": "default", "name": "기본"}]
        self.current_folder_id = "default"
        # 자주 가는 사이트
        self.favorites = [
            {"name": "Google", "url": "https://www.google.com"},
            {"name": "Naver",  "url": "https://www.naver.com"},
        ]

        self.client = None
        if CLAUDE_AVAILABLE:
            try:
                self.client = anthropic.Anthropic()
            except Exception:
                pass

        self._build_ui()
        self._check_dependencies()
        self._start_mouse_listener()
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

    # ── UI ───────────────────────────────────────────────────

    def _check_dependencies(self):
        msgs = []
        if not PIL_AVAILABLE:
            msgs.append("Pillow 미설치: pip install pillow")
        if not PYNPUT_AVAILABLE:
            msgs.append("pynput 미설치: pip install pynput")
        if not CLAUDE_AVAILABLE:
            msgs.append("anthropic 미설치: pip install anthropic")
        elif not self.client:
            msgs.append("ANTHROPIC_API_KEY 미설정 — AI 기능 비활성화")
        if not OCR_AVAILABLE:
            msgs.append("Tesseract 미설치 — OCR(📝) 비활성화")
        if msgs:
            self.status_var.set("⚠ " + msgs[0])

    def _build_ui(self):
        # ── 상태바 (맨 먼저 pack side=BOTTOM) ───────────────────
        self.status_var = tk.StringVar(value="준비  |  '선택 텍스트' 버튼을 눌러 드래그 스크랩을 활성화하세요")
        tk.Label(self.root, textvariable=self.status_var,
                 bg="#131320", fg=MUTED, font=("맑은 고딕", 8),
                 anchor="w", padx=10, pady=4).pack(fill=tk.X, side=tk.BOTTOM)

        # ── 타이틀 바 ────────────────────────────────────────────
        title_bar = tk.Frame(self.root, bg=PANEL_BG)
        title_bar.pack(fill=tk.X)
        tk.Label(title_bar, text="✂  스크랩 도구", bg=PANEL_BG, fg=ACCENT,
                 font=("맑은 고딕", 13, "bold"), padx=14, pady=8).pack(side=tk.LEFT)

        # ── 본문: 사이드바 + 구분선 + 메인 ──────────────────────
        body = tk.Frame(self.root, bg=WINDOW_BG)
        body.pack(fill=tk.BOTH, expand=True)

        # 왼쪽 사이드바
        sidebar = tk.Frame(body, bg=PANEL_BG, width=150)
        sidebar.pack(side=tk.LEFT, fill=tk.Y)
        sidebar.pack_propagate(False)
        self._build_sidebar(sidebar)

        tk.Frame(body, bg=BORDER, width=1).pack(side=tk.LEFT, fill=tk.Y)

        # 오른쪽 메인 영역
        main = tk.Frame(body, bg=WINDOW_BG)
        main.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self._build_main(main)

    def _build_sidebar(self, parent):
        # ── 폴더 섹션 ────────────────────────────────────────────
        fh = tk.Frame(parent, bg=PANEL_BG)
        fh.pack(fill=tk.X)
        tk.Label(fh, text="📁 폴더", bg=PANEL_BG, fg=ACCENT,
                 font=("맑은 고딕", 9, "bold"), padx=8, pady=6).pack(side=tk.LEFT)
        tk.Button(fh, text="+", bg=PANEL_BG, fg=MUTED,
                  font=("Arial", 12), bd=0, padx=6,
                  activebackground=PANEL_BG, activeforeground=ACCENT,
                  cursor="hand2", command=self._add_folder).pack(side=tk.RIGHT)
        tk.Frame(parent, bg=BORDER, height=1).pack(fill=tk.X)

        self._folder_list_frame = tk.Frame(parent, bg=PANEL_BG)
        self._folder_list_frame.pack(fill=tk.X)

        # ── 즐겨찾기 섹션 ────────────────────────────────────────
        tk.Frame(parent, bg=BORDER, height=1).pack(fill=tk.X, pady=(8, 0))
        fvh = tk.Frame(parent, bg=PANEL_BG)
        fvh.pack(fill=tk.X)
        tk.Label(fvh, text="🌐 즐겨찾기", bg=PANEL_BG, fg=ACCENT,
                 font=("맑은 고딕", 9, "bold"), padx=8, pady=6).pack(side=tk.LEFT)
        tk.Button(fvh, text="+", bg=PANEL_BG, fg=MUTED,
                  font=("Arial", 12), bd=0, padx=6,
                  activebackground=PANEL_BG, activeforeground=ACCENT,
                  cursor="hand2", command=self._add_favorite).pack(side=tk.RIGHT)
        tk.Frame(parent, bg=BORDER, height=1).pack(fill=tk.X)

        self._fav_list_frame = tk.Frame(parent, bg=PANEL_BG)
        self._fav_list_frame.pack(fill=tk.X)

        # 초기 렌더링
        self._rebuild_folder_list()
        self._rebuild_fav_list()

    def _build_main(self, parent):
        row1 = tk.Frame(parent, bg=WINDOW_BG)
        row1.pack(fill=tk.X, padx=8, pady=(8, 3))
        self._make_btn(row1, "📷  화면 캡처", ACCENT, ACCENT_H,
                       self._start_capture).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=(0, 4))
        self.sel_mode_btn = self._make_btn(
            row1, "✂  선택 텍스트", GREEN, GREEN_H, self._toggle_selection_mode)
        self.sel_mode_btn.pack(side=tk.LEFT, expand=True, fill=tk.X)

        row2 = tk.Frame(parent, bg=WINDOW_BG)
        row2.pack(fill=tk.X, padx=8, pady=(0, 6))
        self.text_toggle_btn = self._make_btn(
            row2, "✍  텍스트 입력", "#3d5a80", "#2d4a70", self._toggle_text_panel)
        self.text_toggle_btn.pack(side=tk.LEFT, expand=True, fill=tk.X, padx=(0, 4))
        self._make_btn(row2, "🗑  현재 폴더 삭제", "#3a3a5c", "#4a4a6c",
                       self._clear_all).pack(side=tk.LEFT, expand=True, fill=tk.X)

        # 텍스트 입력 패널
        self._text_panel_visible = False
        self._text_panel = tk.Frame(parent, bg=PANEL_BG)
        tk.Label(self._text_panel, text="텍스트 입력  (Ctrl+Enter로 추가)",
                 bg=PANEL_BG, fg=MUTED, font=("맑은 고딕", 8), anchor="w"
                 ).pack(fill=tk.X, padx=10, pady=(6, 2))
        self._text_input = tk.Text(
            self._text_panel, bg="#1a1a2e", fg=TEXT_COLOR,
            insertbackground=TEXT_COLOR, font=("맑은 고딕", 10),
            height=4, wrap=tk.WORD, bd=0, padx=8, pady=6,
            selectbackground=ACCENT, relief=tk.FLAT,
            highlightthickness=1, highlightbackground=BORDER, highlightcolor=ACCENT)
        self._text_input.pack(fill=tk.X, padx=10, pady=(0, 4))
        self._text_input.bind("<Control-Return>", lambda e: self._add_text_scrap())
        add_row = tk.Frame(self._text_panel, bg=PANEL_BG)
        add_row.pack(fill=tk.X, padx=10, pady=(0, 8))
        self._make_btn(add_row, "추가", "#3d5a80", "#2d4a70",
                       self._add_text_scrap).pack(side=tk.RIGHT)
        self._make_btn(add_row, "지우기", "#3a3a5c", "#4a4a6c",
                       lambda: self._text_input.delete("1.0", tk.END)
                       ).pack(side=tk.RIGHT, padx=(0, 6))

        # 취합 + AI 버튼
        ai_row = tk.Frame(parent, bg=WINDOW_BG)
        ai_row.pack(fill=tk.X, padx=8, pady=(2, 0))
        self._make_btn(ai_row, "📋  취합", "#4a5568", "#3d4a5c",
                       self._do_collect).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=(0, 3))
        self.summary_btn = self._make_btn(
            ai_row, "✨  요약", "#5a4fcf", "#4a3fbf", self._do_summary)
        self.summary_btn.pack(side=tk.LEFT, expand=True, fill=tk.X, padx=(0, 3))
        self.analyze_btn = self._make_btn(
            ai_row, "🔍  분석", "#2d6a4f", "#236040", self._do_analysis)
        self.analyze_btn.pack(side=tk.LEFT, expand=True, fill=tk.X)
        if not self.client:
            self.summary_btn.configure(state=tk.DISABLED, bg="#2a2a3e")
            self.analyze_btn.configure(state=tk.DISABLED, bg="#2a2a3e")

        tk.Frame(parent, bg=BORDER, height=1).pack(fill=tk.X, padx=8, pady=4)
        self.count_var = tk.StringVar(value="스크랩 없음")
        tk.Label(parent, textvariable=self.count_var,
                 bg=WINDOW_BG, fg=MUTED, font=("맑은 고딕", 9),
                 anchor="w", padx=10).pack(fill=tk.X)

        list_container = tk.Frame(parent, bg=WINDOW_BG)
        list_container.pack(fill=tk.BOTH, expand=True, padx=6, pady=4)
        self.canvas_list = tk.Canvas(list_container, bg=WINDOW_BG, highlightthickness=0)
        scrollbar = ttk.Scrollbar(list_container, orient="vertical",
                                  command=self.canvas_list.yview)
        self.canvas_list.configure(yscrollcommand=scrollbar.set)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.canvas_list.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.list_frame = tk.Frame(self.canvas_list, bg=WINDOW_BG)
        self._list_window = self.canvas_list.create_window(
            (0, 0), window=self.list_frame, anchor="nw")
        self.list_frame.bind("<Configure>", self._on_frame_configure)
        self.canvas_list.bind("<Configure>", self._on_canvas_configure)
        self.canvas_list.bind("<MouseWheel>", self._on_mousewheel)

    def _make_btn(self, parent, text, bg, hover_bg, command):
        btn = tk.Button(
            parent, text=text, bg=bg, fg="white",
            font=("맑은 고딕", 10), bd=0, padx=8, pady=7,
            activebackground=hover_bg, activeforeground="white",
            cursor="hand2", command=command, relief=tk.FLAT)
        btn.bind("<Enter>", lambda e: btn.configure(bg=hover_bg))
        btn.bind("<Leave>", lambda e: btn.configure(bg=bg))
        return btn

    def _on_frame_configure(self, event):
        self.canvas_list.configure(scrollregion=self.canvas_list.bbox("all"))

    def _on_canvas_configure(self, event):
        self.canvas_list.itemconfig(self._list_window, width=event.width)

    def _on_mousewheel(self, event):
        self.canvas_list.yview_scroll(int(-1 * (event.delta / 120)), "units")

    # ── 선택 텍스트 모드 토글 ────────────────────────────────

    def _toggle_selection_mode(self):
        self._selection_mode = not self._selection_mode
        if self._selection_mode:
            # 활성화: 버튼을 밝은 초록으로, 안내 표시
            self.sel_mode_btn.configure(
                bg="#a6e3a1", fg="#1e3a2e",
                text="✂  선택 모드 ON  (다시 누르면 종료)")
            self.sel_mode_btn.bind("<Enter>", lambda e: None)  # hover 비활성
            self.sel_mode_btn.bind("<Leave>", lambda e: None)
            self.status_var.set("✂ 선택 모드 활성화 — 텍스트를 드래그하면 스크랩 버튼이 나타납니다")
            self._dismiss_popup()
        else:
            # 비활성화: 원래 버튼 모습으로 복원
            self.sel_mode_btn.configure(
                bg=GREEN, fg="white", text="✂  선택 텍스트")
            self.sel_mode_btn.bind(
                "<Enter>", lambda e: self.sel_mode_btn.configure(bg=GREEN_H))
            self.sel_mode_btn.bind(
                "<Leave>", lambda e: self.sel_mode_btn.configure(bg=GREEN))
            self.status_var.set("선택 모드 종료")
            self._dismiss_popup()

    # ── 전역 마우스 감지 & 스크랩 팝업 ─────────────────────

    def _start_mouse_listener(self):
        if not PYNPUT_AVAILABLE:
            return

        def on_click(x, y, button, pressed):
            if button != pynput_mouse.Button.left:
                return
            if pressed:
                self._drag_start_pos = (x, y)
                # 팝업 위에서의 클릭은 팝업을 닫지 않음 (버튼 작동 보장)
                if self._selection_mode and not self._is_in_our_window(x, y):
                    self.root.after(0, self._dismiss_popup)
                return

            # 마우스 버튼 해제
            if not self._selection_mode:
                self._drag_start_pos = None
                return
            if self._drag_start_pos is None:
                return

            sx, sy = self._drag_start_pos
            self._drag_start_pos = None

            # 드래그 거리 미달 → 일반 클릭
            if abs(x - sx) < 10 and abs(y - sy) < 10:
                return
            # 앱 자체 창 안에서의 드래그는 무시
            if self._is_in_our_window(sx, sy) or self._is_in_our_window(x, y):
                return

            # pynput 스레드에서 직접 처리 (소스 창이 아직 포커스 보유)
            old_text = _get_clipboard_text()
            _simulate_ctrl_c()
            time.sleep(0.20)
            new_text = _get_clipboard_text()
            captured = new_text.strip()

            if not captured or captured == old_text.strip():
                return

            x1 = min(sx, x); y1 = min(sy, y)
            x2 = max(sx, x); y2 = max(sy, y)
            self.root.after(0, lambda: self._show_scrap_popup(x1, y1, x2, y2, captured))

        self._mouse_listener = pynput_mouse.Listener(on_click=on_click)
        self._mouse_listener.daemon = True
        self._mouse_listener.start()

    def _show_scrap_popup(self, x1, y1, x2, y2, text):
        self._dismiss_popup()
        popup = ScrapPopup(self.root, x1, y1, x2, y2, text, self._on_popup_scrap)
        self._active_popup = popup

    def _dismiss_popup(self):
        if self._active_popup is not None:
            try:
                if self._active_popup.winfo_exists():
                    self._active_popup.destroy()
            except Exception:
                pass
            self._active_popup = None

    def _on_popup_scrap(self, text):
        self._active_popup = None
        now = time.strftime("%H:%M:%S")
        self._append_scrap({"type": "text", "image": None,
                             "text": text, "timestamp": now})
        self.status_var.set(f"드래그 스크랩 — {now} | {len(text)}자")

    def _is_in_our_window(self, x, y):
        try:
            wx = self.root.winfo_rootx()
            wy = self.root.winfo_rooty()
            if wx <= x <= wx + self.root.winfo_width() and \
               wy <= y <= wy + self.root.winfo_height():
                return True
        except Exception:
            pass
        # 활성 팝업 창도 확인 (팝업 버튼 클릭이 무효화되지 않도록)
        if self._active_popup is not None:
            try:
                if self._active_popup.winfo_exists():
                    px = self._active_popup.winfo_rootx()
                    py = self._active_popup.winfo_rooty()
                    pw = self._active_popup.winfo_width()
                    ph = self._active_popup.winfo_height()
                    if px <= x <= px + pw and py <= y <= py + ph:
                        return True
            except Exception:
                pass
        return False


    # ── 텍스트 입력 ──────────────────────────────────────────

    def _toggle_text_panel(self):
        self._text_panel_visible = not self._text_panel_visible
        if self._text_panel_visible:
            self._text_panel.pack(fill=tk.X, after=self.text_toggle_btn.master)
            self.text_toggle_btn.configure(bg="#2d4a70")
            self._text_input.focus_set()
        else:
            self._text_panel.pack_forget()
            self.text_toggle_btn.configure(bg="#3d5a80")

    def _add_text_scrap(self):
        text = self._text_input.get("1.0", tk.END).strip()
        if not text:
            return
        now = time.strftime("%H:%M:%S")
        self._append_scrap({"type": "text", "image": None, "text": text, "timestamp": now})
        self._text_input.delete("1.0", tk.END)
        self.status_var.set(f"텍스트 추가 — {now}")

    # ── 화면 캡처 ────────────────────────────────────────────

    def _start_capture(self):
        self.root.iconify()
        self.root.after(200, lambda: SelectionOverlay(self.root, self._capture_region))

    def _capture_region(self, x1, y1, x2, y2):
        self.root.after(250, lambda: self._take_screenshot(x1, y1, x2, y2))

    def _take_screenshot(self, x1, y1, x2, y2):
        self.root.deiconify()
        if not PIL_AVAILABLE:
            self.status_var.set("Pillow 미설치 — pip install pillow")
            return
        try:
            # 정수 좌표 보장 + DPI 보정 없이 실제 화면 픽셀 그대로 캡처
            bbox = (int(x1), int(y1), int(x2), int(y2))
            screenshot = ImageGrab.grab(bbox=bbox, all_screens=True)
        except Exception as e:
            # all_screens 미지원 버전 폴백
            try:
                screenshot = ImageGrab.grab(bbox=(int(x1), int(y1), int(x2), int(y2)))
            except Exception as e2:
                self.status_var.set(f"캡처 실패: {e2}")
                return

        text = ""
        if OCR_AVAILABLE:
            try:
                text = pytesseract.image_to_string(screenshot, lang="kor+eng").strip()
            except Exception:
                try:
                    text = pytesseract.image_to_string(screenshot).strip()
                except Exception:
                    pass

        now = time.strftime("%H:%M:%S")
        self._append_scrap({"type": "capture", "image": screenshot,
                             "text": text, "timestamp": now,
                             "bbox": (int(x1), int(y1), int(x2), int(y2))})
        self.status_var.set(f"캡처 완료 — {now}" +
                            (f" | 텍스트 {len(text)}자" if text else ""))

    # ── 이미지 내보내기 ──────────────────────────────────────

    def _export_image(self, item_data):
        img = item_data.get("image")
        if img is None or not PIL_AVAILABLE:
            messagebox.showinfo("알림", "내보낼 이미지가 없습니다.", parent=self.root)
            return

        filetypes = [
            ("PNG (무손실)", "*.png"),
            ("JPEG", "*.jpg"),
            ("BMP", "*.bmp"),
            ("TIFF (무손실)", "*.tiff"),
            ("WebP", "*.webp"),
        ]
        ext_map = {".png": "PNG", ".jpg": "JPEG", ".jpeg": "JPEG",
                   ".bmp": "BMP", ".tiff": "TIFF", ".webp": "WEBP"}

        ts = item_data.get("timestamp", "scrap").replace(":", "-")
        path = filedialog.asksaveasfilename(
            parent=self.root,
            title="이미지 내보내기",
            initialfile=f"scrap_{ts}",
            defaultextension=".png",
            filetypes=filetypes
        )
        if not path:
            return

        _, ext = os.path.splitext(path.lower())
        fmt = ext_map.get(ext, "PNG")

        try:
            save_img = img.copy()
            if fmt == "JPEG" and save_img.mode in ("RGBA", "P"):
                save_img = save_img.convert("RGB")
            if fmt == "JPEG":
                save_img.save(path, format=fmt, quality=95, subsampling=0)
            else:
                save_img.save(path, format=fmt)
            self.status_var.set(f"저장 완료: {os.path.basename(path)}")
        except Exception as e:
            messagebox.showerror("저장 실패", str(e), parent=self.root)

    # ── 이미지 → 텍스트 변환 (OCR) ──────────────────────────

    def _ocr_image(self, item_data):
        img = item_data.get("image")
        if img is None:
            messagebox.showinfo("알림", "이미지가 없습니다.", parent=self.root)
            return
        if not OCR_AVAILABLE:
            messagebox.showinfo(
                "OCR 미설치",
                "pytesseract와 Tesseract-OCR이 필요합니다.\n"
                "pip install pytesseract\n"
                "https://github.com/UB-Mannheim/tesseract/wiki",
                parent=self.root
            )
            return

        self.status_var.set("OCR 변환 중…")
        self.root.update_idletasks()

        def run_ocr():
            try:
                text = pytesseract.image_to_string(img, lang="kor+eng").strip()
                if not text:
                    text = pytesseract.image_to_string(img).strip()
            except Exception as e:
                text = f"[OCR 오류] {e}"
            self.root.after(0, lambda: self._show_ocr_result(item_data, text))

        threading.Thread(target=run_ocr, daemon=True).start()

    def _show_ocr_result(self, item_data, text):
        if not text:
            self.status_var.set("OCR 결과 없음 — 텍스트를 인식하지 못했습니다")
            return

        # 결과 창
        win = tk.Toplevel(self.root)
        win.title("📝 텍스트 변환 결과")
        win.configure(bg=WINDOW_BG)
        win.geometry("600x420")
        win.attributes("-topmost", True)

        header = tk.Frame(win, bg=PANEL_BG)
        header.pack(fill=tk.X)
        tk.Label(header, text="📝  텍스트 변환 결과", bg=PANEL_BG, fg=ACCENT,
                 font=("맑은 고딕", 12, "bold"), padx=14, pady=8).pack(side=tk.LEFT)
        tk.Button(header, text="✕", bg=PANEL_BG, fg=MUTED,
                  font=("Arial", 11), bd=0, padx=10,
                  activebackground=PANEL_BG, activeforeground=DANGER,
                  cursor="hand2", command=win.destroy).pack(side=tk.RIGHT)

        tf = tk.Frame(win, bg=WINDOW_BG)
        tf.pack(fill=tk.BOTH, expand=True, padx=14, pady=10)
        ta = scrolledtext.ScrolledText(
            tf, bg=PANEL_BG, fg=TEXT_COLOR, font=("맑은 고딕", 11),
            wrap=tk.WORD, bd=0, padx=10, pady=8,
            insertbackground=TEXT_COLOR, selectbackground=ACCENT)
        ta.pack(fill=tk.BOTH, expand=True)
        ta.insert(tk.END, text)
        ta.configure(state=tk.DISABLED)

        btn_row = tk.Frame(win, bg=WINDOW_BG)
        btn_row.pack(pady=(0, 10))

        def copy_text():
            win.clipboard_clear()
            win.clipboard_append(text)
            self.status_var.set("클립보드에 복사되었습니다")

        def add_as_scrap():
            now = time.strftime("%H:%M:%S")
            self._append_scrap({"type": "text", "image": None,
                                 "text": text, "timestamp": now})
            self.status_var.set(f"텍스트 스크랩 추가 — {now}")
            win.destroy()

        tk.Button(btn_row, text="클립보드 복사", bg=ACCENT, fg="white",
                  font=("맑은 고딕", 10), bd=0, padx=14, pady=6,
                  activebackground=ACCENT_H, cursor="hand2",
                  command=copy_text).pack(side=tk.LEFT, padx=4)
        tk.Button(btn_row, text="스크랩으로 추가", bg=GREEN, fg="white",
                  font=("맑은 고딕", 10), bd=0, padx=14, pady=6,
                  activebackground=GREEN_H, cursor="hand2",
                  command=add_as_scrap).pack(side=tk.LEFT, padx=4)

        self.status_var.set(f"OCR 완료 — {len(text)}자 인식")

    # ── 드래그 순서 이동 ─────────────────────────────────────

    def _order_drag_start(self, event):
        widget = event.widget
        # ScrapItem 자신을 찾아 올라감
        while widget and not isinstance(widget, ScrapItem):
            widget = widget.master
        if not isinstance(widget, ScrapItem):
            return
        self._order_drag_widget = widget
        self._order_drag_data = widget.item_data
        self._order_drag_start_y = event.y_root

        # 고스트(반투명 복사본 레이블)
        ghost = tk.Toplevel(self.root)
        ghost.overrideredirect(True)
        ghost.attributes("-topmost", True)
        ghost.attributes("-alpha", 0.55)
        ghost.configure(bg=PANEL_BG)
        text = widget.item_data.get("text", "")[:60] or "📷 이미지"
        tk.Label(ghost, text=text, bg=PANEL_BG, fg=TEXT_COLOR,
                 font=("맑은 고딕", 9), padx=10, pady=6,
                 wraplength=280).pack()
        ghost.geometry(f"+{event.x_root + 12}+{event.y_root - 10}")
        self._order_drag_ghost = ghost

    def _order_drag_motion(self, event):
        if self._order_drag_ghost:
            self._order_drag_ghost.geometry(
                f"+{event.x_root + 12}+{event.y_root - 10}")

    def _order_drag_end(self, event):
        if self._order_drag_ghost:
            self._order_drag_ghost.destroy()
            self._order_drag_ghost = None

        if self._order_drag_widget is None:
            return

        # 드롭 위치에서 어떤 ScrapItem 위에 있는지 찾기
        target_data = None
        rx, ry = event.x_root, event.y_root
        for child in self.list_frame.winfo_children():
            if not isinstance(child, ScrapItem):
                continue
            if child is self._order_drag_widget:
                continue
            cx = child.winfo_rootx()
            cy = child.winfo_rooty()
            cw = child.winfo_width()
            ch = child.winfo_height()
            if cx <= rx <= cx + cw and cy <= ry <= cy + ch:
                target_data = child.item_data
                break

        src_data = self._order_drag_data
        self._order_drag_widget = None
        self._order_drag_data = None

        if target_data is None or target_data is src_data:
            return

        # 리스트에서 순서 교환
        si = self.scraps.index(src_data)
        ti = self.scraps.index(target_data)
        self.scraps.insert(ti, self.scraps.pop(si))
        self._rebuild_list()

    # ── 스크랩 목록 관리 ─────────────────────────────────────

    def _cur_scraps(self):
        return [s for s in self.scraps
                if s.get("folder_id", "default") == self.current_folder_id]

    def _append_scrap(self, item_data):
        if "folder_id" not in item_data:
            item_data["folder_id"] = self.current_folder_id
        self.scraps.append(item_data)
        if item_data["folder_id"] == self.current_folder_id:
            self._add_scrap_widget(item_data, len(self._cur_scraps()))
            self.canvas_list.after(50, lambda: self.canvas_list.yview_moveto(1.0))
        self._rebuild_folder_list()
        self._update_count()

    def _add_scrap_widget(self, item_data, index):
        ScrapItem(
            self.list_frame, item_data,
            on_delete=self._make_delete_fn(item_data),
            on_export=lambda d=item_data: self._export_image(d),
            on_ocr=lambda d=item_data: self._ocr_image(d),
            on_move=lambda d=item_data: self._move_scrap(d),
            on_drag_start=self._order_drag_start,
            on_drag_motion=self._order_drag_motion,
            on_drag_end=self._order_drag_end,
            index=index,
        ).pack(fill=tk.X, pady=(0, 6))

    def _delete_scrap(self, item_data):
        if item_data in self.scraps:
            self.scraps.remove(item_data)
        self._rebuild_folder_list()
        self._rebuild_list()
        self._update_count()

    def _rebuild_list(self):
        for w in self.list_frame.winfo_children():
            w.destroy()
        for i, data in enumerate(self._cur_scraps(), 1):
            self._add_scrap_widget(data, i)

    def _make_delete_fn(self, data):
        def _del():
            self._delete_scrap(data)
        return _del

    def _clear_all(self):
        cur = self._cur_scraps()
        if not cur:
            return
        fname = next((f["name"] for f in self.folders
                      if f["id"] == self.current_folder_id), "현재")
        if messagebox.askyesno("폴더 스크랩 삭제",
                               f"'{fname}' 폴더의 스크랩 {len(cur)}개를 삭제할까요?",
                               parent=self.root):
            for s in cur:
                self.scraps.remove(s)
            self._rebuild_folder_list()
            self._rebuild_list()
            self._update_count()
            self.status_var.set("삭제 완료")

    def _update_count(self):
        n = len(self._cur_scraps())
        total = len(self.scraps)
        if n:
            extra = f" / 전체 {total}개" if total != n else ""
            self.count_var.set(f"스크랩 {n}개{extra}")
        else:
            self.count_var.set("스크랩 없음")

    # ── AI 기능 ──────────────────────────────────────────────

    def _collect_text(self):
        parts = [f"[스크랩 {i}]\n{s['text'].strip()}"
                 for i, s in enumerate(self.scraps, 1)
                 if s.get("text", "").strip()]
        return "\n\n".join(parts)

    def _set_ai_buttons(self, enabled):
        state = tk.NORMAL if (enabled and self.client) else tk.DISABLED
        self.summary_btn.configure(state=state)
        self.analyze_btn.configure(state=state)

    def _do_collect(self):
        if not self.scraps:
            messagebox.showinfo("알림", "스크랩된 내용이 없습니다.", parent=self.root)
            return
        parts = []
        for i, s in enumerate(self.scraps, 1):
            t = s.get("type", "capture")
            ts = s.get("timestamp", "")
            label = f"{'✍ 텍스트' if t == 'text' else '📷 캡처'}  #{i}  {ts}"
            body = s.get("text", "").strip()
            if not body and s.get("image"):
                body = "[이미지 (텍스트 없음)]"
            parts.append(f"{'─' * 40}\n{label}\n{'─' * 40}\n{body}")
        combined = "\n\n".join(parts)
        ResultWindow(self.root, f"📋 취합 결과  ({len(self.scraps)}개)", combined)
        self.status_var.set(f"취합 완료 — {len(self.scraps)}개")

    def _ensure_client(self):
        """API 키 없으면 입력창 띄워 클라이언트 초기화"""
        if self.client:
            return True
        key = self._ask_api_key()
        if not key:
            return False
        try:
            self.client = anthropic.Anthropic(api_key=key)
            self._set_ai_buttons(True)
            self.status_var.set("API 키 등록 완료")
            return True
        except Exception as e:
            messagebox.showerror("API 키 오류", str(e), parent=self.root)
            return False

    def _ask_api_key(self):
        """API 키 입력 다이얼로그"""
        win = tk.Toplevel(self.root)
        win.title("Anthropic API 키 입력")
        win.configure(bg=WINDOW_BG)
        win.geometry("420x160")
        win.attributes("-topmost", True)
        win.resizable(False, False)
        win.grab_set()

        tk.Label(win, text="ANTHROPIC_API_KEY를 입력하세요",
                 bg=WINDOW_BG, fg=TEXT_COLOR,
                 font=("맑은 고딕", 10)).pack(pady=(18, 6))

        entry = tk.Entry(win, width=48, show="*",
                         bg=PANEL_BG, fg=TEXT_COLOR,
                         insertbackground=TEXT_COLOR,
                         font=("Consolas", 10), bd=0,
                         highlightthickness=1, highlightbackground=BORDER,
                         highlightcolor=ACCENT)
        entry.pack(padx=20, ipady=5)
        entry.focus_set()

        result = [None]

        def _ok(e=None):
            result[0] = entry.get().strip()
            win.destroy()

        def _cancel():
            win.destroy()

        btn_row = tk.Frame(win, bg=WINDOW_BG)
        btn_row.pack(pady=14)
        tk.Button(btn_row, text="확인", bg=ACCENT, fg="white",
                  font=("맑은 고딕", 10), bd=0, padx=16, pady=5,
                  activebackground=ACCENT_H, cursor="hand2",
                  command=_ok).pack(side=tk.LEFT, padx=6)
        tk.Button(btn_row, text="취소", bg=PANEL_BG, fg=MUTED,
                  font=("맑은 고딕", 10), bd=0, padx=16, pady=5,
                  activebackground=BORDER, cursor="hand2",
                  command=_cancel).pack(side=tk.LEFT, padx=6)
        entry.bind("<Return>", _ok)
        win.wait_window()
        return result[0]

    def _do_summary(self):
        if not self._ensure_client():
            return
        combined = self._collect_text()
        if not combined:
            messagebox.showinfo("알림", "텍스트가 포함된 스크랩이 없습니다.", parent=self.root)
            return
        self._set_ai_buttons(False)
        self.status_var.set("요약 정리 중… (Claude AI)")
        threading.Thread(target=self._call_claude, args=(
            "요약 정리",
            f"다음 스크랩 텍스트를 핵심 내용 위주로 체계적으로 요약 정리해 주세요.\n\n{combined}",
            "✨ 요약 정리 결과"), daemon=True).start()

    def _do_analysis(self):
        if not self._ensure_client():
            return
        combined = self._collect_text()
        if not combined:
            messagebox.showinfo("알림", "텍스트가 포함된 스크랩이 없습니다.", parent=self.root)
            return
        self._set_ai_buttons(False)
        self.status_var.set("분석 중… (Claude AI)")
        threading.Thread(target=self._call_claude, args=(
            "분석",
            f"다음 스크랩 텍스트를 심층 분석해 주세요. 주제, 핵심 개념, 인사이트, 시사점을 포함해 주세요.\n\n{combined}",
            "🔍 분석 결과"), daemon=True).start()

    def _call_claude(self, task_name, prompt, window_title):
        try:
            with self.client.messages.stream(
                model=CLAUDE_MODEL,
                max_tokens=8192,
                messages=[{"role": "user", "content": prompt}],
            ) as stream:
                output = stream.get_final_text()
            if not output:
                output = "(응답 없음)"
        except Exception as e:
            output = f"오류 발생: {type(e).__name__}\n{e}"
        self.root.after(0, lambda: self._show_result(window_title, output, task_name))

    def _show_result(self, title, content, task_name):
        self._set_ai_buttons(True)
        self.status_var.set(f"{task_name} 완료")
        ResultWindow(self.root, title, content)

    def _on_close(self):
        if self._mouse_listener:
            self._mouse_listener.stop()
        self.root.destroy()

    def run(self):
        self.root.mainloop()


if __name__ == "__main__":
    app = ScrapApp()
    app.run()
