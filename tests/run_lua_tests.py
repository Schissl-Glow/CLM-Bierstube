"""Optional Lua 5.1 runner: python -m pip install lupa==2.6; python tests/run_lua_tests.py."""
from pathlib import Path
import os
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
os.chdir(root)
for filename in ("world_buff_checker_spec.lua", "world_buff_gui_spec.lua"):
    LuaRuntime().execute((root / "tests" / filename).read_text(encoding="utf-8"))
