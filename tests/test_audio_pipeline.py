import json
import queue
import threading
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import numpy as np

from backend.ai_stream import AIStreamProcessor
from backend.audio_listener import AudioListener
from backend.config import BLOCK


class FakeCompletions:
    def __init__(self, classification, answer_chunks=()):
        self.classification = classification
        self.answer_chunks = answer_chunks

    def create(self, **kwargs):
        if kwargs.get("stream"):
            return [
                SimpleNamespace(
                    choices=[
                        SimpleNamespace(
                            delta=SimpleNamespace(content=content)
                        )
                    ]
                )
                for content in self.answer_chunks
            ]
        return SimpleNamespace(
            choices=[
                SimpleNamespace(
                    message=SimpleNamespace(content=json.dumps(self.classification))
                )
            ]
        )


class AudioPipelineTests(unittest.TestCase):
    def test_quiet_system_audio_is_detected_without_startup_calibration(self):
        ui_queue = queue.Queue()
        task_queue = queue.Queue()
        listener = AudioListener(ui_queue, task_queue)
        listener_thread = threading.Thread(target=listener._process_audio)
        listener_thread.start()

        sample_indexes = np.arange(BLOCK * 4)
        quiet_voice = (30 * np.sin(2 * np.pi * 440 * sample_indexes / 16_000)).astype(
            np.int16
        )
        silence = np.zeros(BLOCK * 5, dtype=np.int16)
        listener.submit_pcm16(np.concatenate((quiet_voice, silence)).tobytes())

        try:
            captured = task_queue.get(timeout=2)
        finally:
            listener.stop()
            listener_thread.join(timeout=2)

        self.assertEqual(len(captured), 9)
        statuses = [value for kind, value in list(ui_queue.queue) if kind == "status"]
        self.assertIn("Computer audio detected; listening...", statuses)
        self.assertIn("Checking for an interviewer question...", statuses)

    def test_resamples_and_downmixes_screen_capture_audio(self):
        listener = AudioListener(queue.Queue(), queue.Queue())
        frame_count = 4800
        times = np.arange(frame_count) / 48_000
        left = 0.08 * np.sin(2 * np.pi * 440 * times)
        right = 0.04 * np.sin(2 * np.pi * 440 * times)
        stereo = np.column_stack((left, right)).astype("<f4")

        listener.submit_audio_bytes(
            stereo.tobytes(),
            "f32le",
            sample_rate=48_000,
            channels=2,
        )

        self.assertEqual(listener.audio_queue.qsize(), 1)
        resampled = listener.audio_queue.get_nowait()
        self.assertEqual(resampled.shape, (BLOCK, 1))
        self.assertGreater(float(np.max(np.abs(resampled))), 100)

    def test_ignored_transcript_never_reaches_ui(self):
        ui_queue = queue.Queue()
        client = SimpleNamespace(
            chat=SimpleNamespace(
                completions=FakeCompletions(
                    {"is_interviewer_question": False, "question": ""}
                )
            )
        )
        processor = AIStreamProcessor(
            client,
            queue.Queue(),
            ui_queue,
            threading.Event(),
        )

        with patch("backend.ai_stream.process_transcript", return_value="private speech"):
            processor.execute_pipeline([])

        self.assertEqual(
            list(ui_queue.queue),
            [
                ("status", "Checking for an interviewer question..."),
                ("status", "Listening to computer audio..."),
            ],
        )

    def test_only_classified_question_and_generated_answer_are_displayed(self):
        ui_queue = queue.Queue()
        client = SimpleNamespace(
            chat=SimpleNamespace(
                completions=FakeCompletions(
                    {
                        "is_interviewer_question": True,
                        "question": "What is polymorphism?",
                    },
                    ["It means ", "many forms."],
                )
            )
        )
        processor = AIStreamProcessor(
            client,
            queue.Queue(),
            ui_queue,
            threading.Event(),
        )

        with patch("backend.ai_stream.process_transcript", return_value="unfiltered text"):
            processor.execute_pipeline([])

        events = list(ui_queue.queue)
        self.assertIn(("user", "What is polymorphism?"), events)
        self.assertNotIn(("user", "unfiltered text"), events)
        self.assertEqual(
            "".join(value for kind, value in events if kind == "typewriter"),
            "It means many forms.",
        )


if __name__ == "__main__":
    unittest.main()
