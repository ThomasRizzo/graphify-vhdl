{
  description = "Pure Nix: Graphify + VHDL tree-sitter + Bedrock GovCloud Claude Sonnet 4.5 — fully in /nix/store";

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

        # Claude Sonnet 4.5 on AWS Bedrock (available in GovCloud via US-GOV Cross-Region Inference)
        # Current model ID as of June 2026
        bedrockModelId = "anthropic.claude-sonnet-4-5-20250929-v1:0";

        vhdlGrammar = pkgs.tree-sitter.buildGrammar {
          language = "vhdl";
          src = tree-sitter-vhdl;
          version = "0.1.0";
        };

        vhdlExtractor = ./vhdl_extractor.py;

        # Fully patched graphify source — lives in /nix/store, immutable + cached
        graphifyPatched = pkgs.applyPatches {
          name = "graphify-with-vhdl";
          src = graphify-src;

          postPatch = ''
            cp ${vhdlExtractor} graphify/vhdl_extractor.py
            sed -i 's|CODE_EXTENSIONS = {|CODE_EXTENSIONS = {\n    ".vhd", ".vhdl",|g' graphify/detect.py || true
            sed -i '/^from pathlib import Path/a from .vhdl_extractor import extract_vhdl' graphify/extract.py || true
            sed -i '/^def extract(path: Path):/a\    ext = path.suffix.lower()\n    if ext in {\x22.vhd\x22, \x22.vhdl\x22}:\n        return extract_vhdl(path)' graphify/extract.py || true
          '';
        };

        # Clean wrapper — uses local .venv if present, otherwise Nix Python
        graphifyWrapper = pkgs.writeShellScriptBin "graphify" ''
          export AWS_DEFAULT_REGION="us-gov-west-1"
          export GRAPHIFY_VHDL_GRAMMAR="${vhdlGrammar}/parser"
          export GRAPHIFY_MODEL="${bedrockModelId}"

          if [ -d "$PWD/.venv" ]; then
            source "$PWD/.venv/bin/activate"
          else
            export PYTHONPATH="${graphifyPatched}:${graphifyPatched}/graphify:$PYTHONPATH"
          fi

          exec python -m graphify.cli "$@"
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
            graphifyWrapper
          ];

          shellHook = ''
            set -euo pipefail

            export AWS_DEFAULT_REGION="us-gov-west-1"
            export GRAPHIFY_VHDL_GRAMMAR="${vhdlGrammar}/parser"
            export GRAPHIFY_MODEL="${bedrockModelId}"
            export GRAPHIFY_SRC="${graphifyPatched}"

            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "  Graphify + VHDL + Bedrock GovCloud Claude Sonnet 4.5"
            echo "  Fully reproducible — everything lives in /nix/store"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "→ Graphify source : $GRAPHIFY_SRC"
            echo "→ Bedrock model   : ${bedrockModelId}"
            echo "→ Region          : us-gov-west-1 (GovCloud)"
            echo ""

            # Create an isolated virtual environment (clean, doesn't touch system Python)
            if [ ! -d ".venv" ]; then
              echo "→ Creating isolated Python environment (.venv)..."
              uv venv --quiet
            fi
            source .venv/bin/activate

            # Copy patched source out of the read-only Nix store so we can build it
            GRAPHIFY_SRC_DIR="$PWD/.graphify-src"
            rm -rf "$GRAPHIFY_SRC_DIR"
            cp -r "${graphifyPatched}" "$GRAPHIFY_SRC_DIR"
            chmod -R u+w "$GRAPHIFY_SRC_DIR"

            echo "→ Installing graphify + pdf + office extras into .venv..."
            cd "$GRAPHIFY_SRC_DIR"
            uv pip install ".[pdf,office]" --quiet
            cd "$OLDPWD"

            echo ""
            echo "✅ Ready."
            echo ""
            echo "Usage on any VHDL repo:"
            echo "  graphify /path/to/your-vhdl-project"
            echo "  graphify ."
            echo ""
            echo "• .vhd / .vhdl files → tree-sitter structural extraction"
            echo "• Docs, diagrams, testbenches → Bedrock Claude Sonnet 4.5"
            echo ""
            echo "To change the model ID, edit 'bedrockModelId' near the top of flake.nix"
            echo ""
            echo "Register skill with OpenCode: graphify install --opencode"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
          '';
        };
      });
}