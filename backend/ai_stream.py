import queue
import threading
from backend.config import CHAT_MODEL
from backend.transcription import process_transcript

class AIStreamProcessor:
    def __init__(self, client, task_queue, ui_queue, running_event):
        self.client = client
        self.task_queue = task_queue
        self.ui_queue = ui_queue
        self.running_event = running_event
        self.client_lock = threading.Lock()

    def set_client(self, client):
        with self.client_lock:
            self.client = client

    def start_worker(self):
        while self.running_event.is_set():
            try:
                audio_blocks = self.task_queue.get(timeout=1.0)
            except queue.Empty:
                continue
            
            self.execute_pipeline(audio_blocks)
            self.task_queue.task_done()

    def execute_pipeline(self, audio_blocks):
        try:
            with self.client_lock:
                client = self.client
            if client is None:
                self.ui_queue.put(("setup_required", ""))
                return

            clean_query = process_transcript(client, audio_blocks)
            if not clean_query:
                return

            self.ui_queue.put(("user", clean_query))
            self.ui_queue.put(("assistant_start", ""))

            response = client.chat.completions.create(
                model=CHAT_MODEL,
                messages=[
                    {
                        "role": "system",
                        "content": (
                            "Reply in the same language as the user's question: use English for "
                            "English questions, and Hindi in Devanagari script for Hindi questions. "
                            "Never respond in Urdu or use the Perso-Arabic script. If the user asks "
                            "a question, answer it directly; do not merely repeat or translate it. "
                            "Keep the answer clear and concise, and start with the direct answer."
                        ),
                    },
                    {"role": "user", "content": clean_query},
                ],
                stream=True
            )

            for chunk in response:
                if chunk.choices and chunk.choices[0].delta.content:
                    text_chunk = chunk.choices[0].delta.content
                    self.ui_queue.put(("typewriter", text_chunk))

            self.ui_queue.put(("assistant_end", ""))
        except Exception as e:
            self.ui_queue.put(("error", str(e)))
