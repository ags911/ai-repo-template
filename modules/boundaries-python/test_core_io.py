"""Domain and application code must not do I/O directly.

import-linter (.importlinter) blocks top-level packages, including indirect imports. This
test covers what it can't express: subpackages (google.cloud, urllib.request), modules that
are mostly I/O (os, pathlib, io), and bare calls to open() and __import__().

Copy into your tests/ directory and edit CORE_DIRS and BANNED to match ARCHITECTURE.md.
"""

import ast
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Directories, relative to ROOT, whose code must not do I/O directly.
CORE_DIRS = ["app/domain", "app/application"]

# Dotted module names, matched with their submodules (banning "os" also bans "os.path").
BANNED = {
    "google.cloud": "a cloud SDK; call it from infrastructure",
    "urllib.request": "network I/O",
    "os": "file system, processes and environment; pass config in from the edge",
    "pathlib": "file system access",
    "io": "file and stream I/O",
    "tempfile": "file system access",
    "glob": "file system access",
    "shelve": "file-backed storage",
    "importlib": "dynamic imports bypass the boundary checks",
    "builtins": "reaches open() and __import__() indirectly",
}

# Built-in calls that do I/O or bypass import checks, unless the file binds the name itself.
BANNED_CALLS = {
    "open": "file I/O",
    "__import__": "dynamic imports bypass the boundary checks",
}


def _banned(module: str) -> str | None:
    for name, reason in BANNED.items():
        if module == name or module.startswith(name + "."):
            return reason
    return None


def _target_names(target: ast.expr) -> set[str]:
    """Names an assignment target binds: `x` and `a, b`, but not `d[open]` or `obj.open`."""
    if isinstance(target, ast.Name):
        return {target.id}
    if isinstance(target, (ast.Tuple, ast.List)):
        return {n for t in target.elts for n in _target_names(t)}
    if isinstance(target, ast.Starred):
        return _target_names(target.value)
    return set()


def _bound_names(tree: ast.Module) -> set[str]:
    """Names bound at the top level of the module. A method or nested function named
    `open` doesn't shadow the builtin elsewhere in the file, so it doesn't count."""
    names: set[str] = set()
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            names.add(node.name)
        elif isinstance(node, (ast.Import, ast.ImportFrom)):
            names.update((a.asname or a.name).split(".")[0] for a in node.names)
        elif isinstance(node, (ast.Assign, ast.AnnAssign, ast.AugAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            for target in targets:
                names.update(_target_names(target))
    return names


def _violations(path: Path) -> list[str]:
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    bound = _bound_names(tree)
    where = path.relative_to(ROOT)
    found: list[str] = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            if isinstance(node, ast.Import):
                modules = [a.name for a in node.names]
            elif node.level == 0 and node.module:
                modules = [node.module] + [
                    f"{node.module}.{a.name}" for a in node.names
                ]
            else:
                modules = []  # relative import: inside the project, checked by import-linter
            for module in modules:
                reason = _banned(module)
                if reason:
                    found.append(f"{where}:{node.lineno} imports {module} ({reason})")
                    break
        elif (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id in BANNED_CALLS
            and node.func.id not in bound
        ):
            found.append(
                f"{where}:{node.lineno} calls {node.func.id}() ({BANNED_CALLS[node.func.id]})"
            )
    return found


def test_core_dirs_exist() -> None:
    missing = [d for d in CORE_DIRS if not (ROOT / d).is_dir()]
    assert not missing, (
        f"CORE_DIRS not found (the I/O check would pass vacuously): {missing}"
    )


def test_core_does_no_direct_io() -> None:
    found = [
        v
        for d in CORE_DIRS
        for p in sorted((ROOT / d).rglob("*.py"))
        for v in _violations(p)
    ]
    assert not found, "direct I/O in domain or application code:\n" + "\n".join(found)
