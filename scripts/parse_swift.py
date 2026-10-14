"""Optional syntax-only check (pip install tree-sitter tree-sitter-swift).
Type checking, API availability, Swift concurrency and execution require Xcode CI.
"""
from pathlib import Path
from tree_sitter import Language,Parser
import tree_sitter_swift

root = Path(__file__).resolve().parent.parent
parser = Parser(Language(tree_sitter_swift.language()))
failures = []
for path in root.rglob("*.swift"):
    if ".build" in path.parts or "build" in path.parts: continue
    tree = parser.parse(path.read_bytes())
    def inspect(node):
        if node.type == "ERROR" or node.is_missing:
            failures.append(f"{path.relative_to(root)}:{node.start_point.row+1}:{node.start_point.column+1}: {node.type}")
        for child in node.children: inspect(child)
    inspect(tree.root_node)
if failures:
    raise SystemExit("\n".join(failures))
print("All Swift files parsed without syntax errors (not Swift compilation).")
