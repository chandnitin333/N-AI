import tkinter as tk
from tkinter import scrolledtext
import queue
import re
from backend.config import IDLE_TEXT
from windows.capture_exclusion import apply_capture_exclusion

class WindowsOverlay:
    def __init__(self, root, ui_queue, on_close_callback, on_save_api_key, needs_api_key=False):
        self.root = root
        self.ui_queue = ui_queue
        self.on_close_callback = on_close_callback
        self.on_save_api_key = on_save_api_key
        self.settings_visible = needs_api_key
        self.current_assistant_start = None
        self.current_assistant_text = ""
        self.opacity = tk.DoubleVar(value=85)

        # N-AI floating assistant layout
        root.geometry("480x620+100+100")
        root.overrideredirect(True)
        root.attributes("-topmost", True)
        root.attributes("-alpha", 0.85)
        root.configure(bg="#0F111A")

        # Custom Frameless Window Controls Drag Canvas 
        self.title_bar = tk.Frame(root, bg="#1A1C28", height=35)
        self.title_bar.pack(fill=tk.X)
        self.title_bar.pack_propagate(False)
        self.title_bar.bind("<Button-1>", self.start_drag)
        self.title_bar.bind("<B1-Motion>", self.drag_window)

        # UI branding title
        self.title_label = tk.Label(self.title_bar, text="N-AI", font=("Segoe UI", 10, "bold"), bg="#1A1C28", fg="#4FD1C5")
        self.title_label.pack(side=tk.LEFT, padx=12)

        self.close_btn = tk.Button(self.title_bar, text="✕", font=("Segoe UI", 10), bg="#1A1C28", fg="#E53E3E", bd=0, cursor="hand2", command=self.close)
        self.close_btn.pack(side=tk.RIGHT, padx=5)

        self.toggle_btn = tk.Button(self.title_bar, text="◐", font=("Segoe UI", 11), bg="#1A1C28", fg="#A0AEC0", bd=0, cursor="hand2", command=self.toggle_opacity_controls)
        self.toggle_btn.pack(side=tk.RIGHT, padx=5)

        self.settings_btn = tk.Button(self.title_bar, text="⚿", font=("Segoe UI", 11), bg="#1A1C28", fg="#A0AEC0", bd=0, cursor="hand2", command=self.toggle_settings)
        self.settings_btn.pack(side=tk.RIGHT, padx=5)

        self.opacity_frame = tk.Frame(root, bg="#1A1C28", padx=13, pady=8)
        tk.Label(self.opacity_frame, text="Overlay opacity", font=("Segoe UI", 9, "bold"), bg="#1A1C28", fg="#EDF2F7").pack(side=tk.LEFT)
        self.opacity_value = tk.Label(self.opacity_frame, text="85%", font=("Segoe UI", 9), bg="#1A1C28", fg="#A0AEC0", width=5)
        self.opacity_value.pack(side=tk.RIGHT)
        self.opacity_scale = tk.Scale(
            self.opacity_frame,
            from_=35,
            to=100,
            orient=tk.HORIZONTAL,
            showvalue=False,
            variable=self.opacity,
            bg="#1A1C28",
            fg="#EDF2F7",
            troughcolor="#0B0D14",
            highlightthickness=0,
            bd=0,
            command=self.set_opacity,
        )
        self.opacity_scale.pack(side=tk.RIGHT, fill=tk.X, expand=True, padx=8)
        self.opacity_visible = False

        self.settings_frame = tk.Frame(root, bg="#1A1C28", padx=13, pady=11)
        tk.Label(self.settings_frame, text="Connect your OpenAI account", font=("Segoe UI", 10, "bold"), bg="#1A1C28", fg="#EDF2F7").pack(anchor=tk.W)
        tk.Label(self.settings_frame, text="Your API key is saved locally and never shown in the chat.", font=("Segoe UI", 8), bg="#1A1C28", fg="#A0AEC0", wraplength=410).pack(anchor=tk.W, pady=(4, 8))
        self.api_key_entry = tk.Entry(self.settings_frame, show="•", font=("Segoe UI", 10), bg="#0B0D14", fg="#EDF2F7", insertbackground="#4FD1C5", relief=tk.FLAT, bd=0)
        self.api_key_entry.pack(fill=tk.X, ipady=8, pady=(0, 7))
        self.api_key_entry.bind("<Return>", lambda _event: self.save_api_key())
        key_actions = tk.Frame(self.settings_frame, bg="#1A1C28")
        key_actions.pack(fill=tk.X)
        self.api_key_message = tk.Label(key_actions, text="", font=("Segoe UI", 8), bg="#1A1C28", fg="#A0AEC0", wraplength=280, justify=tk.LEFT)
        self.api_key_message.pack(side=tk.LEFT, fill=tk.X, expand=True)
        self.save_key_btn = tk.Button(key_actions, text="Save key", font=("Segoe UI", 9, "bold"), bg="#319795", fg="white", bd=0, padx=13, pady=5, cursor="hand2", command=self.save_api_key)
        self.save_key_btn.pack(side=tk.RIGHT)

        # Live Dynamic Visualizer / Status Banner
        self.status_frame = tk.Frame(root, bg="#0F111A")
        self.status_frame.pack(fill=tk.X, padx=20, pady=(15, 5))
        
        self.status_dot = tk.Label(self.status_frame, text="●", font=("Segoe UI", 10), bg="#0F111A", fg="#4FD1C5")
        self.status_dot.pack(side=tk.LEFT)
        
        self.status_label = tk.Label(self.status_frame, text=IDLE_TEXT, font=("Segoe UI", 10), bg="#0F111A", fg="#718096")
        self.status_label.pack(side=tk.LEFT, padx=8)
        if self.settings_visible:
            self.settings_frame.pack(fill=tk.X, padx=16, pady=(0, 8), before=self.status_frame)

        # High-Fidelity Text Display Canvas Container
        self.text_area = scrolledtext.ScrolledText(root, font=("Segoe UI", 11), bg="#141522", fg="#EDF2F7", insertbackground="#4FD1C5", wrap=tk.WORD, bd=0, highlightthickness=0, padx=14, pady=12, spacing1=5, spacing3=10)
        self.text_area.pack(fill=tk.BOTH, expand=True, padx=20, pady=(0, 20))
        self.text_area.tag_configure("user_label", foreground="#4FD1C5", font=("Segoe UI", 9, "bold"), spacing1=8, spacing3=4)
        self.text_area.tag_configure("assistant_label", foreground="#A0AEC0", font=("Segoe UI", 9, "bold"), spacing1=8, spacing3=4)
        self.text_area.tag_configure("message", foreground="#EDF2F7", font=("Segoe UI", 11), lmargin1=2, lmargin2=2, spacing3=8)
        self.text_area.tag_configure("error", foreground="#F6AD55", font=("Segoe UI", 10), spacing1=8, spacing3=8)
        self.text_area.tag_configure("markdown_bold", font=("Segoe UI", 11, "bold"))
        self.text_area.tag_configure("markdown_italic", font=("Segoe UI", 11, "italic"))
        self.text_area.tag_configure("markdown_code", font=("Consolas", 10), background="#0B0D14")
        self.text_area.tag_configure("markdown_heading", font=("Segoe UI", 12, "bold"), foreground="#81E6D9")
        self.text_area.tag_configure("markdown_code_block", font=("Consolas", 10), background="#0B0D14")
        self.text_area.configure(state=tk.DISABLED)
        if not needs_api_key:
            self.text_area.configure(state=tk.NORMAL)
            self.text_area.insert(tk.END, "Ready when you are\n", "assistant_label")
            self.text_area.insert(tk.END, "Interviewer questions from computer audio and AI answers appear here. Microphone audio is not captured.", "message")
            self.text_area.configure(state=tk.DISABLED)

        # Enforce Hardware Window Capture Exclusion Rules
        self.root.update()
        apply_capture_exclusion(self.root.winfo_id())
        
        # Start reading the UI rendering updates queue
        self.root.after(20, self.poll_ui_queue)

    def start_drag(self, event):
        self.drag_x = event.x
        self.drag_y = event.y

    def drag_window(self, event):
        x = self.root.winfo_x() + (event.x - self.drag_x)
        y = self.root.winfo_y() + (event.y - self.drag_y)
        self.root.geometry(f"+{x}+{y}")

    def toggle_opacity_controls(self):
        if self.opacity_visible:
            self.opacity_frame.pack_forget()
            self.opacity_visible = False
        else:
            self.opacity_frame.pack(fill=tk.X, padx=16, pady=(0, 8), after=self.title_bar)
            self.opacity_visible = True

    def set_opacity(self, value):
        opacity = float(value)
        self.root.attributes("-alpha", opacity / 100)
        self.opacity_value.configure(text=f"{round(opacity)}%")

    def toggle_settings(self):
        if self.settings_visible:
            self.settings_frame.pack_forget()
            self.settings_visible = False
        else:
            self.settings_frame.pack(fill=tk.X, padx=16, pady=(0, 8), before=self.status_frame)
            self.settings_visible = True
            self.api_key_entry.focus_set()

    def save_api_key(self):
        api_key = self.api_key_entry.get().strip()
        if not api_key:
            self.api_key_message.configure(text="Enter your API key first.", fg="#F6AD55")
            return
        self.save_key_btn.configure(state=tk.DISABLED, text="Saving…")
        self.api_key_message.configure(text="Saving securely…", fg="#A0AEC0")
        self.on_save_api_key(api_key)

    def finish_assistant_message(self):
        if self.current_assistant_start is None:
            return

        self.text_area.delete(self.current_assistant_start, "end-1c")
        in_code_block = False
        inline_pattern = re.compile(
            r"(\*\*.+?\*\*|__.+?__|`[^`]+`|(?<!\*)\*[^*]+\*|(?<!_)_[^_]+_)"
        )

        for line in self.current_assistant_text.splitlines(keepends=True):
            newline = "\n" if line.endswith("\n") else ""
            content = line[:-1] if newline else line
            if content.strip().startswith("```"):
                in_code_block = not in_code_block
                continue
            if in_code_block:
                self.text_area.insert(tk.END, content + newline, "markdown_code_block")
                continue

            heading = re.match(r"^\s*#{1,6}\s+(.*)$", content)
            bullet = re.match(r"^(\s*)[-*+]\s+(.*)$", content)
            numbered = re.match(r"^(\s*)\d+[.)]\s+(.*)$", content)
            if heading:
                self.text_area.insert(tk.END, heading.group(1), "markdown_heading")
            elif bullet or numbered:
                match = bullet or numbered
                self.text_area.insert(tk.END, f"{match.group(1)}• ")
                self._insert_inline_markdown(match.group(2), inline_pattern)
            else:
                self._insert_inline_markdown(content, inline_pattern)
            self.text_area.insert(tk.END, newline)

        self.current_assistant_start = None
        self.current_assistant_text = ""

    def _insert_inline_markdown(self, content, pattern):
        cursor = 0
        for match in pattern.finditer(content):
            self.text_area.insert(tk.END, content[cursor:match.start()])
            markup = match.group()
            if markup.startswith(("**", "__")):
                self.text_area.insert(tk.END, markup[2:-2], "markdown_bold")
            elif markup.startswith("`"):
                self.text_area.insert(tk.END, markup[1:-1], "markdown_code")
            else:
                self.text_area.insert(tk.END, markup[1:-1], "markdown_italic")
            cursor = match.end()
        self.text_area.insert(tk.END, content[cursor:])

    def poll_ui_queue(self):
        while not self.ui_queue.empty():
            try:
                msg_type, data = self.ui_queue.get_nowait()
            except queue.Empty:
                break
                
            if msg_type == "status":
                self.status_label.config(text=data)
                self.status_dot.config(fg="#E53E3E" if "Listening" in data else "#4FD1C5")
            elif msg_type == "setup_required":
                self.status_label.config(text="Add your OpenAI API key to get started")
                if not self.settings_visible:
                    self.settings_frame.pack(fill=tk.X, padx=16, pady=(0, 8), before=self.status_frame)
                    self.settings_visible = True
            elif msg_type == "api_key_saved":
                self.api_key_entry.delete(0, tk.END)
                self.api_key_message.configure(text=data, fg="#4FD1C5")
                self.save_key_btn.configure(state=tk.NORMAL, text="Save key")
                self.settings_frame.pack_forget()
                self.settings_visible = False
                self.status_label.config(text="Ready")
            elif msg_type in ("user", "assistant_start", "typewriter", "assistant_end", "error"):
                self.text_area.configure(state=tk.NORMAL)
                if msg_type == "user":
                    self.text_area.insert(tk.END, "YOU SAID\n", "user_label")
                    self.text_area.insert(tk.END, f"{data}\n", "message")
                elif msg_type == "assistant_start":
                    self.text_area.insert(tk.END, "N-AI\n", "assistant_label")
                    self.current_assistant_start = self.text_area.index(tk.END)
                    self.current_assistant_text = ""
                elif msg_type == "typewriter":
                    self.current_assistant_text += data
                    self.text_area.insert(tk.END, data, "message")
                elif msg_type == "assistant_end":
                    self.finish_assistant_message()
                else:
                    self.finish_assistant_message()
                    if self.settings_visible:
                        self.api_key_message.configure(text=data, fg="#F6AD55")
                        self.save_key_btn.configure(state=tk.NORMAL, text="Save key")
                    else:
                        self.text_area.insert(tk.END, "NOTICE\n", "error")
                        self.text_area.insert(tk.END, f"{data}\n", "error")
                self.text_area.see(tk.END)
                self.text_area.configure(state=tk.DISABLED)
                
        if self.root:
            self.root.after(20, self.poll_ui_queue)

    def close(self):
        self.on_close_callback()
