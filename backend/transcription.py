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
    if audio_data.size == 0:
        return None

    audio_float = audio_data.astype(np.float32) / 32768.0
    rms = float(np.sqrt(np.mean(audio_float * audio_float)))
    peak = float(np.max(np.abs(audio_float)))
    if rms > 0 and rms < 0.08:
        gain = min(0.08 / rms, 8.0, 0.9 / peak if peak > 0 else 8.0)
        audio_data = np.clip(audio_float * gain, -1.0, 1.0)
        audio_data = (audio_data * 32767).astype(np.int16)

    wav_file = to_wav(audio_data)

    raw_transcript = client.audio.transcriptions.create(
        model=TRANSCRIBE_MODEL,
        file=wav_file,
        prompt=(
            "Transcribe the audio verbatim. It is computer audio from an interview. "
            "Include every audible word and do not summarize, complete, or infer missing "
            "words. Preserve the speaker's language: use English spelling for English and "
            "Devanagari for Hindi. Do not use Urdu or Perso-Arabic script."
        ),
    ).text

    if not raw_transcript.strip():
        return None

    return raw_transcript.strip()
