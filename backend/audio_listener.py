import queue
import sys
import threading
from collections import deque

import numpy as np

from backend.config import (
    BLOCK,
    IDLE_TEXT,
    MAX_BLOCKS,
    MIN_BLOCKS,
    PRE_ROLL_BLOCKS,
    SAMPLE_RATE,
    SILENCE_BLOCKS,
    VAD_CONTINUE_RMS,
    VAD_START_RMS,
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

    def submit_audio_bytes(
        self,
        data,
        encoding,
        sample_rate=SAMPLE_RATE,
        channels=1,
    ):
        try:
            sample_rate = int(sample_rate)
            channels = int(channels)
        except (TypeError, ValueError) as error:
            raise ValueError("Invalid system-audio format metadata.") from error
        if sample_rate <= 0 or channels <= 0:
            raise ValueError("Invalid system-audio format metadata.")

        if encoding == "f32le":
            samples = np.frombuffer(data, dtype="<f4")
            if samples.size % channels:
                raise ValueError("Incomplete system-audio frame.")
            if channels > 1:
                samples = samples.reshape(-1, channels)
            self.submit_float_audio(samples, sample_rate=sample_rate)
        elif encoding == "s16le":
            samples = np.frombuffer(data, dtype="<i2").astype(np.float32) / 32768.0
            if samples.size % channels:
                raise ValueError("Incomplete system-audio frame.")
            if channels > 1:
                samples = samples.reshape(-1, channels)
            self.submit_float_audio(samples, sample_rate=sample_rate)
        else:
            raise ValueError("Unsupported system-audio sample format.")

    def submit_pcm16(self, data):
        self.submit_audio_bytes(data, "s16le")

    def submit_float_audio(self, data, sample_rate=SAMPLE_RATE):
        audio = np.asarray(data, dtype=np.float32)
        if audio.ndim == 2:
            audio = audio.mean(axis=1)
        audio = np.nan_to_num(audio, nan=0.0, posinf=1.0, neginf=-1.0)
        samples = np.clip(audio, -1.0, 1.0)
        if sample_rate != SAMPLE_RATE and samples.size:
            output_count = max(1, round(samples.size * SAMPLE_RATE / sample_rate))
            source_positions = np.arange(samples.size, dtype=np.float64)
            target_positions = np.arange(output_count, dtype=np.float64) * (
                sample_rate / SAMPLE_RATE
            )
            samples = np.interp(
                target_positions,
                source_positions,
                samples,
            ).astype(np.float32)
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
        speaking = False
        silence_counter = 0
        audio_buffer = []
        pre_roll = deque(maxlen=PRE_ROLL_BLOCKS)
        has_received_audio = False
        self.ui_queue.put(("status", "Listening to computer audio..."))

        while self.running:
            block = self._next_audio_block(timeout=1.0)
            if block is None:
                continue

            if not has_received_audio:
                has_received_audio = True
                self.ui_queue.put(
                    ("status", "System audio received; monitoring for speech...")
                )

            samples = block.astype(np.float32)
            rms = float(np.sqrt(np.mean(samples * samples)))
            if not speaking:
                if rms >= VAD_START_RMS:
                    speaking = True
                    silence_counter = 0
                    audio_buffer = [*pre_roll, block]
                    pre_roll.clear()
                    self.ui_queue.put(("status", "Computer audio detected; listening..."))
                else:
                    pre_roll.append(block)
            else:
                audio_buffer.append(block)
                silence_counter = (
                    0 if rms >= VAD_CONTINUE_RMS else silence_counter + 1
                )

                if silence_counter >= SILENCE_BLOCKS or len(audio_buffer) >= MAX_BLOCKS:
                    speaking = False
                    if len(audio_buffer) >= MIN_BLOCKS:
                        self.task_queue.put(audio_buffer.copy())
                        self.ui_queue.put(("status", "Checking for an interviewer question..."))
                    else:
                        self.ui_queue.put(("status", IDLE_TEXT))
                    audio_buffer.clear()

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
