import sys

def apply_capture_exclusion(hwnd):
    """
    Applies native API window changes to prevent screen recording tools 
    from grabbing the content of the UI frame.
    """
    if sys.platform != "win32":
        return False
    try:
        import ctypes
        # SetWindowDisplayAffinity: WDA_EXCLUDE_FROM_CAPTURE = 0x00000011
        WDA_EXCLUDE_FROM_CAPTURE = 0x00000011
        result = ctypes.windll.user32.SetWindowDisplayAffinity(hwnd, WDA_EXCLUDE_FROM_CAPTURE)
        return bool(result)
    except Exception as e:
        print(f"Failed to set Windows capture exclusion: {e}", file=sys.stderr)
        return False
