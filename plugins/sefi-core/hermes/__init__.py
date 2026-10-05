"""Hermes plugin exposing the packaged Sefi command set as slash commands.

WHY THIS EXISTS (live-confirmed 2026-10-03)
install-hermes.sh installs 20 skills and a managed runtime, and its success
message tells the user to run ``/sefi:init``. On Hermes that command did not
exist: the 13 packaged ``commands/*.md`` files ship inside the managed runtime,
and Hermes never reads them. The documented next step of a successful install
was therefore impossible, so a completed install still could not route.

The commands are agent INSTRUCTIONS, not scripts. Returning one as a handler's
string would only print it to the terminal -- verified in Hermes at
``cli.py:1309`` (``_cprint(str(result))``). The value is delivered to the model
with ``PluginContext.inject_message(..., role="user")`` instead, which queues a
real user turn into the live CLI/TUI session.

NAMING
``register_command`` accepts any name, but a colon cannot survive the
plugin-command lookup on every surface, so the slash form is ``/sefi-init``.
The installer's message says ``/sefi:init``; this plugin prints the exact
spelling to type, and records the alias in the injected body.
"""

from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

PLUGIN_ID = "sefi-commands"

# (slash suffix, packaged command stem, one-line hint)
COMMANDS = [
    ("init", "init", "Initialize Sefi in the current project root (run once per project)."),
    ("route", "route", "Deterministically route one task through the orchestration skill."),
    ("triage", "triage", "Run one discovery turn and write findings to state/triage.md."),
    ("status", "status", "Print open findings, pending reviews, and budget headroom."),
    ("retro", "retro", "Run the retro-improve self-improvement pass once."),
    ("close-session", "close-session", "Close the work session into one memory note."),
    ("memory-search", "memory-search", "Search private local memory notes."),
    ("memory-index", "memory-index", "Rebuild or check the disposable memory index."),
    ("cross-memory", "cross-memory", "Control the optional cross-project memory mirror."),
    ("loop-new", "loop-new", "Interview briefly, then generate a new loop spec."),
    ("audit", "audit", "Audit one department scope through systems-auditor."),
    ("map-codebase", "map-codebase", "Produce a bounded local codebase map."),
    ("scout", "scout", "Examine an external repo for adoption candidates."),
]

_ALIAS_NOTE = (
    "On this harness the packaged command is spelled `/sefi-{name}` rather than "
    "`/sefi:{name}`; a colon is not accepted in a plugin command name on every "
    "surface. The instruction body below is the packaged `commands/{name}.md`."
)

# Populated by register() with the plugin context's inject_message. Handlers
# close over it rather than the ctx object so the context is never retained past
# unregistration, which would keep a torn-down plugin alive.
_INJECTOR: dict = {}



def _runtime_root() -> Optional[Path]:
    """Locate the managed sefi-core runtime that holds commands/*.md."""
    override = os.environ.get("SEFI_RUNTIME_ROOT")
    candidates = []
    if override:
        candidates.append(Path(override))
    home = os.environ.get("HERMES_HOME")
    if home:
        candidates.append(Path(home) / "sefi-core")
    try:
        from hermes_constants import get_hermes_home

        candidates.append(Path(get_hermes_home()) / "sefi-core")
    except Exception:
        logger.debug("sefi-commands: get_hermes_home unavailable", exc_info=True)
    for candidate in candidates:
        try:
            if (candidate / "commands").is_dir():
                return candidate
        except OSError:
            continue
    return None


def _read_command_body(stem: str) -> Optional[str]:
    root = _runtime_root()
    if root is None:
        return None
    path = root / "commands" / f"{stem}.md"
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        logger.warning("sefi-commands: cannot read command body %s", path)
        return None


def _make_handler(stem: str, hint: str):
    def handler(raw_args: str) -> str:
        body = _read_command_body(stem)
        if body is None:
            return (
                f"/sefi-{stem} is registered but its instruction body is not installed.\n\n"
                "Expected it at <hermes-home>/sefi-core/commands/"
                f"{stem}.md. Re-run the installer:\n"
                "  bash plugins/sefi-core/scripts/install-hermes.sh --auto-update\n\n"
                "If it still cannot be found, set SEFI_RUNTIME_ROOT to the managed "
                "sefi-core directory."
            )
        extra = (raw_args or "").strip()
        instruction = f"{hint}\n\n{_ALIAS_NOTE.format(name=stem)}"
        if extra:
            instruction += f"\n\nUser instruction: {extra}"

        # Returning the body would only print it: Hermes consumes a plugin
        # command's return value with _cprint(str(result)) (cli.py:1309). The
        # command has to become a real user turn, so the payload goes through
        # inject_message and the return is a short receipt for the terminal.
        _INJECTOR["inject"](instruction + "\n\n" + body)
        return f"[sefi] /sefi-{stem} instructions delivered to this session."

    return handler


def register(ctx) -> None:
    """Plugin entry point: register every packaged command as a slash command."""
    _INJECTOR["inject"] = ctx.inject_message
    for suffix, stem, hint in COMMANDS:
        ctx.register_command(
            f"sefi-{suffix}",
            handler=_make_handler(stem, hint),
            description=f"[sefi] {hint}",
            args_hint="[instruction]",
            argument_mode="text",
        )
