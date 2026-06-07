{
  description = "One-command Nix setup: Graphify + full VHDL tree-sitter + AWS Bedrock GovCloud (Sonnet 4.5) — everything stays inside the shell (no home dir pollution)";

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

        vhdlExtractor = ./vhdl_extractor.py;

        # Pure Nix wrapper — lives only inside this dev shell, nothing written to ~
        graphifyWrapper = pkgs.writeShellScriptBin "graphify" ''
          export GRAPHIFY_VHDL_GRAMMAR="${vhdlGrammar}/parser"
          export AWS_DEFAULT_REGION="us-gov-west-1"
          exec ${python}/bin/python -m graphify.cli "$@"
        '';

      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            python
            uv
            just
            git
            ripgrep
            tree-sitter
            graphifyWrapper   # <-- provides the `graphify` command cleanly
          ];

          shellHook = ''
            set -euo pipefail

            export AWS_DEFAULT_REGION="us-gov-west-1"
            export GRAPHIFY_VHDL_GRAMMAR="${vhdlGrammar}/parser"

            GRAPHIFY_DIR="$PWD/graphify"

            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "  Graphify + VHDL tree-sitter + Bedrock GovCloud"
            echo "  Pure Nix shell (nothing touches your home directory)"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""

            if [ ! -d "$GRAPHIFY_DIR" ]; then
              echo "→ Cloning graphify (v8) into ./graphify ..."
              git clone --depth 1 --branch v8 https://github.com/safishamsi/graphify.git "$GRAPHIFY_DIR"
            fi

            cd "$GRAPHIFY_DIR"

            echo "→ Injecting VHDL tree-sitter support..."
            cp -f "${vhdlExtractor}" graphify/vhdl_extractor.py

            # Register extensions (idempotent)
            grep -q ".vhd" graphify/detect.py || \
              sed -i 's|CODE_EXTENSIONS = {|CODE_EXTENSIONS = {\n    ".vhd", ".vhdl",|g' graphify/detect.py || true

            # Wire the extractor (idempotent)
            if ! grep -q "from .vhdl_extractor import extract_vhdl" graphify/extract.py; then
              sed -i '/^from pathlib import Path/a from .vhdl_extractor import extract_vhdl' graphify/extract.py || true
              sed -i '/^def extract(path: Path):/a\    ext = path.suffix.lower()\n    if ext in {\x22.vhd\x22, \x22.vhdl\x22}:\n        return extract_vhdl(path)' graphify/extract.py || true
            fi

            echo "→ Installing with uv (editable)..."
            uv pip install -e "[dev]" --quiet 2>/dev/null || uv pip install -e . --quiet

            cd "$OLDPWD"

            echo ""
            echo "✅ Ready. The 'graphify' command is provided by Nix (no ~/.local/bin pollution)."
            echo ""
            echo "Usage:"
            echo "  graphify /path/to/your-vhdl-repo"
            echo "  graphify ."
            echo ""
            echo "• VHDL files (.vhd/.vhdl) → tree-sitter structural extraction"
            echo "• Other files → Bedrock Sonnet 4.5 semantic extraction"
            echo "• Register with OpenCode:  graphify install --opencode"
            echo ""
            echo "Everything lives inside this shell environment."
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
          '';
        };
      });
}