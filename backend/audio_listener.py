import queue
import sys
import threading

import numpy as np

from backend.config import (
    BLOCK,
    CALIBRATE_BLOCKS,
    IDLE_TEXT,
    MAX_BLOCKS,
    MIN_BLOCKS,
    SAMPLE_RATE,
    SILENCE_BLOCKS,
)


class AudioListener:
    """Processes system-output loopback audio; microphone input is never opened."""

    def __init__(self, ui_queue, task_queue):
        self.ui_queue = ui_queue
        self.task_queue = task_queue
        self.audio_queue = queue.Queue()
        self.running = True
        self.pending_samples = np.empty(0, dtype=np.int16)
        self.pending_lock = threading.Lock()

    def submit_audio_bytes(self, data, encoding):
        if encoding == "f32le":
            samples = np.frombuffer(data, dtype="<f4")
            self.submit_float_audio(samples)
        elif encoding == "s16le":
            self.submit_pcm16(data)
        else:
            raise ValueError("Unsupported system-audio sample format.")

    def submit_pcm16(self, data):
        samples = np.frombuffer(data, dtype="<i2")
        self._submit_samples(samples)

    def submit_float_audio(self, data):
        audio = np.asarray(data, dtype=np.float32)
        if audio.ndim == 2:
            audio = audio.mean(axis=1)
        samples = np.clip(audio, -1.0, 1.0)
        self._submit_samples((samples * 32767).astype(np.int16))

    def _submit_samples(self, samples):
        if samples.size == 0:
            return

        with self.pending_lock:
            combined = np.concatenate((self.pending_samples, samples))
            complete_size = combined.size - combined.size % BLOCK
            for offset in range(0, complete_size, BLOCK):
                block = combined[offset:offset + BLOCK].copy().reshape(BLOCK, 1)
                self.audio_queue.put(block)
            self.pending_samples = combined[complete_size:].copy()

    def start(self):
        if sys.platform == "win32":
            threading.Thread(
                target=self._capture_windows_loopback,
                name="system-audio-loopback",
                daemon=True,
            ).start()
        self._process_audio()

    def _capture_windows_loopback(self):
        try:
            import soundcard as sc

            speaker = sc.default_speaker()
            if speaker is None:
                raise RuntimeError("No default speaker is available for system-audio capture.")
            loopback = sc.get_microphone(
                id=str(speaker.name),
                include_loopback=True,
            )
            self.ui_queue.put(("status", "Listening to computer audio..."))
            with loopback.recorder(
                samplerate=SAMPLE_RATE,
                channels=[0, 1],
                blocksize=BLOCK,
            ) as recorder:
                while self.running:
                    self.submit_float_audio(recorder.record(numframes=BLOCK))
        except Exception as error:
            if self.running:
                self.running = False
                self.ui_queue.put(
                    ("error", f"Could not capture Windows system audio: {error}")
                )
                self.audio_queue.put(None)

    def _process_audio(self):
        calibration_levels = []
        for _ in range(CALIBRATE_BLOCKS):
            block = self._next_audio_block()
            if block is None:
                return
            calibration_levels.append(np.max(np.abs(block)))

        threshold = max(float(np.mean(calibration_levels)) * 2.5, 400)
        speaking = False
        silence_counter = 0
        audio_buffer = []
        self.ui_queue.put(("status", "Listening to computer audio..."))

        while self.running:
            block = self._next_audio_block(timeout=1.0)
            if block is None:
                continue

            is_loud = np.max(np.abs(block)) > threshold
            if not speaking:
                if is_loud:
                    speaking = True
                    silence_counter = 0
                    audio_buffer = [block]
            else:
                audio_buffer.append(block)
                silence_counter = 0 if is_loud else silence_counter + 1

                if silence_counter >= SILENCE_BLOCKS or len(audio_buffer) >= MAX_BLOCKS:
                    speaking = False
                    if len(audio_buffer) >= MIN_BLOCKS:
                        self.task_queue.put(audio_buffer.copy())
                    audio_buffer.clear()
                    self.ui_queue.put(("status", IDLE_TEXT))

    def _next_audio_block(self, timeout=None):
        try:
            return self.audio_queue.get(timeout=timeout)
        except queue.Empty:
            if not self.running:
                return None
            return self.audio_queue.get()

    def stop(self):
        self.running = False
        self.audio_queue.put(None)
