"""Render the packaged Zellij defaults, plus mkZmux overrides, as pager help."""
import re
import sys
from pathlib import Path

OVERRIDES = {
    "F1": "Open this keyboard shortcut list (also available in locked mode)",
    "Alt s": "Toggle whether the vertical tab sidebar can be selected/resized",
    "Alt up": "Go to the previous tab (except in locked mode)",
    "Alt down": "Go to the next tab (except in locked mode)",
}


def body(text, opening):
    """Find a KDL block's end without counting braces inside strings/comments."""
    depth = 1
    for token in re.finditer(r'"(?:\\.|[^"\\])*"|//[^\n]*|[{}]', text[opening + 1:]):
        value = token.group()
        if value == "{":
            depth += 1
        elif value == "}":
            depth -= 1
            if depth == 0:
                return text[opening + 1:opening + 1 + token.start()]
    raise ValueError("Unclosed KDL block")


def render(defaults):
    defaults = re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*',
                      lambda match: "" if match.group().startswith("//") else match.group(), defaults)
    lines = [
        "ZELLIJ KEYBOARD SHORTCUTS", "",
        "Ctrl+Q  Quit this session and terminate ALL its tabs and their processes.",
        "        Other Zellij sessions are unaffected. In locked mode, Ctrl+G first.",
        "q       Close this help only. Arrow keys / PgUp / PgDn scroll; / searches.",
        "", "MY-NIX SHORTCUTS (override the defaults below)",
    ]
    for key, effect in OVERRIDES.items():
        lines.append(f"  {key:<20} {effect}")
    opening = re.search(r'\bkeybinds\s*\{', defaults).end() - 1
    bindings = body(defaults, opening)
    for group in re.finditer(r'(?m)^    ([a-z_-]+)([^\n{]*)\{', bindings):
        name, arguments = group.group(1, 2)
        content = body(bindings, group.end() - 1)
        rows = []
        for binding in re.finditer(r'\bbind\s+((?:"[^"\n]+"\s*)+)\{', content):
            keys = [key for key in re.findall(r'"([^"]+)"', binding.group(1)) if key not in OVERRIDES]
            if not keys:
                continue
            actions = body(content, binding.end() - 1)
            actions = re.sub(r'//[^\n]*', '', actions)
            actions = re.sub(r'\s+', ' ', actions).strip().rstrip(';')
            actions = actions.replace('Quit', 'Quit session: terminate all tabs and their processes')
            rows.append(f"  {', '.join(keys):<25} {actions}")
        if rows:
            title = name.replace('_', ' ').upper() + (" " + arguments.strip() if arguments.strip() else "")
            lines.extend(["", title, *rows])
    return '\n'.join(lines) + '\n'


if __name__ == '__main__':
    print(render(Path(sys.argv[1]).read_text()), end='')
