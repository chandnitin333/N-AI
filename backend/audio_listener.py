import queue
import sys
import numpy as np
import sounddevice as sd
from backend.config import SAMPLE_RATE, BLOCK, CALIBRATE_BLOCKS, SILENCE_BLOCKS, MIN_BLOCKS, MAX_BLOCKS, IDLE_TEXT

class AudioListener:
    def __init__(self, ui_queue, task_queue):
        self.ui_queue = ui_queue
        self.task_queue = task_queue
        self.audio_queue = queue.Queue()
        self.running = True
        self.stream = None

    def audio_callback(self, indata, frames, time, status):
        if status:
            print(status, file=sys.stderr)
        self.audio_queue.put(indata.copy())

    def start(self):
        self.stream = sd.InputStream(
            samplerate=SAMPLE_RATE, 
            channels=1, 
            callback=self.audio_callback, 
            blocksize=BLOCK, 
            dtype='int16'
        )
        self.stream.start()
        
        # Noise Calibration
        calibration_data = []
        for _ in range(CALIBRATE_BLOCKS):
            block = self.audio_queue.get()
            calibration_data.append(np.max(np.abs(block)))
        
        threshold = max(np.mean(calibration_data) * 2.5, 400)
        speaking = False
        silence_counter = 0
        audio_buffer = []

        while self.running:
            try:
                block = self.audio_queue.get(timeout=1.0)
            except queue.Empty:
                continue

            volume = np.max(np.abs(block))
            is_loud = volume > threshold

            if not speaking:
                if is_loud:
                    speaking = True
                    silence_counter = 0
                    audio_buffer = [block]
                    self.ui_queue.put(("status", "Listening..."))
            else:
                audio_buffer.append(block)
                if not is_loud:
                    silence_counter += 1
                else:
                    silence_counter = 0

                if silence_counter >= SILENCE_BLOCKS or len(audio_buffer) >= MAX_BLOCKS:
                    speaking = False
                    final_buffer = audio_buffer.copy()
                    audio_buffer.clear()

                    if len(final_buffer) >= MIN_BLOCKS:
                        self.task_queue.put(final_buffer)
                    
                    self.ui_queue.put(("status", IDLE_TEXT))

    def stop(self):
        self.running = False
        if self.stream:
            self.stream.stop()
            self.stream.close()
