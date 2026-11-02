import json
import os
import sys
import queue
import threading
from openai import OpenAI

# Fix working path vectors to allow modular sub-imports
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from backend.config import load_env, save_api_key
from backend.audio_listener import AudioListener
from backend.ai_stream import AIStreamProcessor

def main():
    load_env()
    api_key = os.getenv("OPENAI_API_KEY")
    openai_client = OpenAI(api_key=api_key) if api_key else None
    
    ui_queue = queue.Queue()
    task_queue = queue.Queue()
    running_event = threading.Event()
    running_event.set()

    # Spin up background components
    listener = AudioListener(ui_queue, task_queue)
    ai_processor = AIStreamProcessor(openai_client, task_queue, ui_queue, running_event)

    def configure_api_key(api_key_value):
        try:
            save_api_key(api_key_value)
            client = OpenAI(api_key=api_key_value.strip())
            ai_processor.set_client(client)
            ui_queue.put(("api_key_saved", "API key saved. N-AI is ready."))
        except (OSError, ValueError) as error:
            ui_queue.put(("error", f"Could not save API key: {error}"))
        except Exception as error:
            ui_queue.put(("error", f"Could not initialize the API client: {error}"))

    if not api_key:
        ui_queue.put(("setup_required", ""))

    # IMPORTANT: We launch the audio listener stream in a clean background thread
    listener_thread = threading.Thread(target=listener.start, daemon=True)
    worker_thread = threading.Thread(target=ai_processor.start_worker, daemon=True)

    listener_thread.start()
    worker_thread.start()

    def on_shutdown():
        running_event.clear()
        listener.stop()

    # Platform Routing Engine
    if sys.platform == "darwin":
        def read_commands():
            for line in sys.stdin:
                if not running_event.is_set():
                    break
                try:
                    command = json.loads(line)
                except json.JSONDecodeError:
                    ui_queue.put(("error", "Could not read the API-key setup request."))
                    continue
                if command.get("type") == "set_api_key" and isinstance(command.get("data"), str):
                    configure_api_key(command["data"])

        threading.Thread(target=read_commands, daemon=True).start()
        try:
            while running_event.is_set():
                try:
                    msg_type, data = ui_queue.get(timeout=1.0)
                    print(
                        json.dumps(
                            {"type": msg_type, "data": data},
                            ensure_ascii=False,
                        ),
                        flush=True,
                    )
                except queue.Empty:
                    continue
        except (BrokenPipeError, KeyboardInterrupt):
            pass
        finally:
            on_shutdown()
    else:
        # Native Windows Graphical Deployment Layer
        import tkinter as tk
        from windows.overlay import WindowsOverlay
        root_win = tk.Tk()
        WindowsOverlay(
            root_win,
            ui_queue,
            on_close_callback=lambda: [on_shutdown(), root_win.destroy()],
            on_save_api_key=configure_api_key,
            needs_api_key=not bool(api_key),
        )
        try:
            root_win.mainloop()
        finally:
            on_shutdown()

if __name__ == "__main__":
    main()
