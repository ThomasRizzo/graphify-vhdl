{
  description = "One-command Nix setup: Graphify + full VHDL tree-sitter + AWS Bedrock GovCloud (Sonnet 4.5) for OpenCode";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    graphify-src = {
      url = "github:safishamsi/graphify/v8";
      flake = false;
    };
    tree-sitter-vhdl = {
      url = "github:jpt13653903/tree-sitter-vhdl";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, graphify-src, tree-sitter-vhdl }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        python = pkgs.python311;
        vhdlGrammar = pkgs.tree-sitter.buildGrammar {
          language = "vhdl";
          src = tree-sitter-vhdl;
          version = "0.1.0";
        };

        # vhdl_extractor.py lives next to this flake in your GitHub repo
        vhdlExtractor = ./vhdl_extractor.py;

      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            python
            uv
            just
            git
            ripgrep
            tree-sitter
          ];

          shellHook = ''
            set -euo pipefail

            export AWS_DEFAULT_REGION="us-gov-west-1"
            export GRAPHIFY_VHDL_GRAMMAR="${vhdlGrammar}/parser"
            export GRAPHIFY_VHDL_EXTRACTOR="${vhdlExtractor}"

            GRAPHIFY_DIR="$PWD/graphify"

            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "  Graphify + VHDL tree-sitter + Bedrock GovCloud"
            echo "  One-command setup (nix develop)"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""

            # Clone graphify (v8) if not already present
            if [ ! -d "$GRAPHIFY_DIR" ]; then
              echo "→ Cloning graphify into ./graphify ..."
              git clone --depth 1 --branch v8 https://github.com/safishamsi/graphify.git "$GRAPHIFY_DIR"
            fi

            cd "$GRAPHIFY_DIR"

            # Inject VHDL support (idempotent)
            echo "→ Adding VHDL tree-sitter support..."

            cp -f "$GRAPHIFY_VHDL_EXTRACTOR" graphify/vhdl_extractor.py

            # Register .vhd/.vhdl extensions (safe if already present)
            grep -q ".vhd" graphify/detect.py || \
              sed -i 's|CODE_EXTENSIONS = {|CODE_EXTENSIONS = {\n    ".vhd", ".vhdl",|g' graphify/detect.py || true

            # Wire the extractor (import + dispatch)
            if ! grep -q "vhdl_extractor" graphify/extract.py; then
              sed -i '/^from pathlib import Path/a from .vhdl_extractor import extract_vhdl' graphify/extract.py || true

              # Add dispatch right after the function definition
              sed -i '/^def extract(path: Path):/a\    ext = path.suffix.lower()\n    if ext in {".vhd", ".vhdl"}:\n        return extract_vhdl(path)' graphify/extract.py || true
            fi

            # Install with uv (editable)
            echo "→ Installing graphify with uv (first time can take 30-60s)..."
            uv pip install -e ".[dev]" --quiet 2>/dev/null || uv pip install -e . --quiet

            # Create convenient wrapper so plain `graphify` command works everywhere
            mkdir -p "$HOME/.local/bin"
            cat > "$HOME/.local/bin/graphify" <<'WRAPPER'
#!/usr/bin/env bash
            export GRAPHIFY_VHDL_GRAMMAR="__GRAMMAR_PATH__"
            export PYTHONPATH="__GRAPHIFY_DIR__:$PYTHONPATH"
            exec python -m graphify.cli "$@"
WRAPPER

            sed -i "s|__GRAMMAR_PATH__|${vhdlGrammar}/parser|g" "$HOME/.local/bin/graphify"
            sed -i "s|__GRAPHIFY_DIR__|$GRAPHIFY_DIR|g" "$HOME/.local/bin/graphify"
            chmod +x "$HOME/.local/bin/graphify"

            # Ensure wrapper is in PATH
            if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
              export PATH="$HOME/.local/bin:$PATH"
            fi

            cd "$OLDPWD"

            echo ""
            echo "✅ Everything ready!"
            echo ""
            echo "Run on any VHDL repo:"
            echo "  graphify /path/to/your-vhdl-project"
            echo "  graphify ."
            echo ""
            echo "• .vhd / .vhdl files → parsed with tree-sitter (entities, architectures, processes, etc.)"
            echo "• Docs, diagrams, testbenches etc. → semantic extraction via Bedrock Sonnet 4.5"
            echo "• AWS credentials inherited from your environment"
            echo ""
            echo "Register skill with OpenCode / Cursor:"
            echo "  graphify install --opencode"
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
          '';
        };

        packages.vhdl-grammar = vhdlGrammar;
      });
}