import os
import stat
import sys
import tempfile
from pathlib import Path

SAMPLE_RATE = 16000
BLOCK = 1600                 # 0.1 second block slice
TRANSCRIBE_MODEL = "gpt-4o-mini-transcribe"
CHAT_MODEL = "gpt-4o-mini"

SILENCE_BLOCKS = 5           # 0.5 seconds trailing silence threshold
MIN_BLOCKS = 4               # Drop speech windows shorter than 0.4 seconds
MAX_BLOCKS = 200             # Max structural sentence limits capped at 20 seconds
VAD_START_RMS = 18           # Fixed threshold avoids learning speech as the noise floor
VAD_CONTINUE_RMS = 12        # Lower threshold prevents clipping quiet syllables
IDLE_TEXT = "कंप्यूटर की आवाज़ सुन रहा हूँ..."

def _config_directory():
    if sys.platform == "win32":
        base_directory = os.environ.get("APPDATA")
        if not base_directory:
            base_directory = str(Path.home() / "AppData" / "Roaming")
    elif sys.platform == "darwin":
        base_directory = str(Path.home() / "Library" / "Application Support")
    else:
        base_directory = os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))
    return Path(base_directory) / "N-AI"


_user_env_path = _config_directory() / ".env"
_legacy_user_env_path = _config_directory().parent / "ChikuAI" / ".env"
_project_env_path = Path(__file__).resolve().parent.parent / ".env"
if getattr(sys, "frozen", False):
    _default_env_path = (
        _user_env_path if _user_env_path.exists() else _legacy_user_env_path
    )
else:
    _default_env_path = (
        _user_env_path
        if _user_env_path.exists()
        else _legacy_user_env_path
        if _legacy_user_env_path.exists()
        else _project_env_path
    )
ENV_PATH = os.environ.get(
    "NAI_ENV_FILE",
    os.environ.get(
        "CHIKU_ENV_FILE",
        str(_default_env_path),
    ),
)


def load_env():
    if not os.path.exists(ENV_PATH):
        return
    with open(ENV_PATH, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def save_api_key(api_key):
    cleaned_key = api_key.strip()
    if not cleaned_key:
        raise ValueError("Enter an API key before saving.")
    if "\n" in cleaned_key or "\r" in cleaned_key:
        raise ValueError("The API key must be a single line.")

    env_path = Path(ENV_PATH).expanduser()
    env_path.parent.mkdir(parents=True, exist_ok=True)
    existing_lines = []
    if env_path.is_file():
        existing_lines = [
            line for line in env_path.read_text(encoding="utf-8").splitlines()
            if not line.strip().startswith("OPENAI_API_KEY=")
        ]

    contents = "\n".join([*existing_lines, f"OPENAI_API_KEY={cleaned_key}"]) + "\n"
    file_descriptor, temporary_path = tempfile.mkstemp(
        prefix=".nai-env-",
        dir=env_path.parent,
        text=True,
    )
    try:
        with os.fdopen(file_descriptor, "w", encoding="utf-8") as env_file:
            env_file.write(contents)
            env_file.flush()
            os.fsync(env_file.fileno())
        os.chmod(temporary_path, stat.S_IRUSR | stat.S_IWUSR)
        os.replace(temporary_path, env_path)
    except Exception:
        if os.path.exists(temporary_path):
            os.unlink(temporary_path)
        raise

    os.environ["OPENAI_API_KEY"] = cleaned_key
