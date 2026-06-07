#!/usr/bin/env python3
"""
VHDL tree-sitter extractor for Graphify.

Drop this file into graphify/graphify/vhdl_extractor.py
and wire it into extract.py + detect.py.

It provides basic but useful structural extraction for VHDL:
- Entities
- Architectures
- Processes
- Signals / Variables / Constants
- Ports
- Component instantiations
- Basic relationships (contains, declares, instantiates)

You can expand the mappings significantly.
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Dict, List, Optional

from tree_sitter import Language, Parser, Node

# Load the VHDL grammar built by the Nix flake
# The flake exports GRAPHIFY_VHDL_GRAMMAR pointing to the parser directory
_VHDL_GRAMMAR_PATH = os.environ.get(
    "GRAPHIFY_VHDL_GRAMMAR",
    "/nix/store/...-tree-sitter-vhdl/parser"  # fallback - will be set by nix develop
)

try:
    VHDL_LANGUAGE = Language(_VHDL_GRAMMAR_PATH)
except Exception:
    # Fallback: try to load from common locations or raise a clear error
    VHDL_LANGUAGE = None


def _get_parser() -> Parser:
    parser = Parser()
    if VHDL_LANGUAGE is None:
        raise RuntimeError(
            "VHDL tree-sitter grammar not found. "
            "Run inside the Nix dev shell or set GRAPHIFY_VHDL_GRAMMAR."
        )
    parser.set_language(VHDL_LANGUAGE)
    return parser


# Map tree-sitter node types to Graphify concept types
NODE_TYPE_TO_CONCEPT: Dict[str, str] = {
    "entity_declaration": "entity",
    "architecture_body": "architecture",
    "process_statement": "process",
    "signal_declaration": "signal",
    "variable_declaration": "variable",
    "constant_declaration": "constant",
    "port_clause": "port",
    "generic_clause": "generic",
    "component_instantiation_statement": "instance",
    "component_declaration": "component",
    "package_declaration": "package",
    "configuration_declaration": "configuration",
    "subprogram_body": "subprogram",
    "type_declaration": "type",
}


def _node_text(node: Node, source: bytes) -> str:
    return source[node.start_byte : node.end_byte].decode("utf-8", errors="replace")


def _find_child_by_type(node: Node, node_type: str) -> Optional[Node]:
    for child in node.children:
        if child.type == node_type:
            return child
    return None


def _collect_identifiers(node: Node, source: bytes) -> List[str]:
    """Recursively collect identifier names."""
    names: List[str] = []
    if node.type == "identifier":
        names.append(_node_text(node, source))
    for child in node.children:
        names.extend(_collect_identifiers(child, source))
    return names


def extract_vhdl(path: Path) -> Dict[str, Any]:
    """
    Main entry point expected by graphify.
    Returns a dict in the shape graphify expects:
        {
            "nodes": [...],
            "edges": [...],
            "language": "vhdl",
            ...
        }
    """
    if VHDL_LANGUAGE is None:
        # Graceful fallback: treat as plain text (still useful via LLM later)
        return {
            "nodes": [],
            "edges": [],
            "language": "vhdl",
            "error": "VHDL grammar not loaded - falling back to text extraction",
        }

    source_code = path.read_bytes()
    parser = _get_parser()
    tree = parser.parse(source_code)
    root = tree.root_node

    nodes: List[Dict[str, Any]] = []
    edges: List[Dict[str, Any]] = []
    node_id_counter = 0

    def new_id() -> str:
        nonlocal node_id_counter
        node_id_counter += 1
        return f"vhdl_{path.stem}_{node_id_counter}"

    def add_node(
        concept: str,
        name: str,
        node_type: str,
        start_line: int,
        end_line: int,
        extra: Optional[Dict] = None,
    ) -> str:
        nid = new_id()
        nodes.append(
            {
                "id": nid,
                "type": concept,
                "name": name,
                "file": str(path),
                "start_line": start_line,
                "end_line": end_line,
                "language": "vhdl",
                "extra": extra or {},
            }
        )
        return nid

    def add_edge(
        source: str,
        target: str,
        relation: str,
        confidence: str = "EXTRACTED",
    ) -> None:
        edges.append(
            {
                "source": source,
                "target": target,
                "relation": relation,
                "confidence": confidence,
            }
        )

    # Walk the tree and extract high-level constructs
    def visit(node: Node, parent_id: Optional[str] = None) -> None:
        node_type = node.type
        concept = NODE_TYPE_TO_CONCEPT.get(node_type)

        if concept:
            name = ""
            # Try to extract a meaningful name
            if node_type == "entity_declaration":
                ident = _find_child_by_type(node, "identifier")
                if ident:
                    name = _node_text(ident, source_code)
            elif node_type == "architecture_body":
                # architecture <name> of <entity>
                for child in node.children:
                    if child.type == "identifier":
                        name = _node_text(child, source_code)
                        break
            elif node_type in {"process_statement", "component_instantiation_statement"}:
                # Look for label
                label = _find_child_by_type(node, "label")
                if label:
                    name = _node_text(label, source_code).rstrip(":")
                else:
                    name = node_type.replace("_", " ")
            else:
                # Generic fallback: first identifier
                idents = _collect_identifiers(node, source_code)
                if idents:
                    name = idents[0]

            nid = add_node(
                concept=concept,
                name=name or node_type,
                node_type=node_type,
                start_line=node.start_point[0] + 1,
                end_line=node.end_point[0] + 1,
                extra={"node_type": node_type},
            )

            if parent_id:
                add_edge(parent_id, nid, "contains")

            # Special relationship extraction
            if node_type == "component_instantiation_statement":
                # Try to find what component is being instantiated
                idents = _collect_identifiers(node, source_code)
                if len(idents) >= 2:
                    # very rough heuristic
                    add_edge(nid, idents[1], "instantiates", confidence="INFERRED")

            current_parent = nid
        else:
            current_parent = parent_id

        for child in node.children:
            visit(child, current_parent)

    visit(root)

    return {
        "nodes": nodes,
        "edges": edges,
        "language": "vhdl",
        "file": str(path),
        "parser": "tree-sitter-vhdl",
    }


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        result = extract_vhdl(Path(sys.argv[1]))
        import json
        print(json.dumps(result, indent=2))
    else:
        print("Usage: python vhdl_extractor.py some_file.vhd")
