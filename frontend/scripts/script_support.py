"""Small shared setup for isolated Godot test and preview projects."""
import os
from pathlib import Path

FRONTEND_DIR = Path(__file__).resolve().parents[1]


def isolated_environment(project):
    """Keep fixture editor settings and caches out of the user's Godot profile."""
    env = os.environ.copy()
    for name in ('DATA', 'CONFIG', 'CACHE'):
        env[f'XDG_{name}_HOME'] = str(project / f'xdg-{name.lower()}')
    return env
