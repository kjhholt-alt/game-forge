r"""Mirror the git-tracked Saga Engine mod source into CK3's live mod folder.

CK3 only loads mods from the Paradox user-data mod folder, which is NOT
inside this repo. Git-tracked source lives at ck3_saga_engine/mod/ -- this
script is the one-way sync from source control to the folder the game
actually reads. Run it after every content change, then run validate.py.

Usage:
    py deploy.py

Env override:
    CK3_MOD_DIR   the CK3 user-data mod folder
                  (default: ~\Documents\Paradox Interactive\Crusader Kings III\mod)
"""
import os
import shutil
import sys

REPO_MOD_ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "mod")
DEFAULT_CK3_MOD_DIR = os.path.join(
    os.path.expanduser("~"), "Documents", "Paradox Interactive", "Crusader Kings III", "mod"
)
CK3_MOD_DIR = os.environ.get("CK3_MOD_DIR", DEFAULT_CK3_MOD_DIR)


def deploy() -> int:
    if not os.path.isdir(REPO_MOD_ROOT):
        print(f"deploy.py: no mod source at {REPO_MOD_ROOT}", file=sys.stderr)
        return 2
    if not os.path.isdir(CK3_MOD_DIR):
        print(f"deploy.py: CK3 mod folder not found at {CK3_MOD_DIR}", file=sys.stderr)
        return 2

    copied = 0
    for entry in os.listdir(REPO_MOD_ROOT):
        src = os.path.join(REPO_MOD_ROOT, entry)
        dst = os.path.join(CK3_MOD_DIR, entry)
        if os.path.isdir(src):
            shutil.copytree(src, dst, dirs_exist_ok=True)
        else:
            shutil.copy2(src, dst)
        copied += 1
        print(f"  {entry} -> {dst}")

    print(f"deploy.py: synced {copied} item(s) from {REPO_MOD_ROOT} to {CK3_MOD_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(deploy())
