import io
import wave
import numpy as np
from backend.config import SAMPLE_RATE, TRANSCRIBE_MODEL

def to_wav(audio_data):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(audio_data.tobytes())
    buf.seek(0)
    buf.name = "audio.wav"
    return buf

def process_transcript(client, audio_blocks):
    audio_data = np.concatenate(audio_blocks)
    wav_file = to_wav(audio_data)

    raw_transcript = client.audio.transcriptions.create(
        model=TRANSCRIBE_MODEL,
        file=wav_file,
        prompt=(
            "Transcribe the speech in the language that is spoken. Use English script for "
            "English speech and Devanagari script for Hindi speech. Do not write Hindi speech "
            "in Urdu or Perso-Arabic script."
        ),
    ).text

    if not raw_transcript.strip():
        return None

    return raw_transcript.strip()
