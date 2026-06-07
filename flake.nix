{
  description = "Pure Nix: Graphify + VHDL tree-sitter + Bedrock GovCloud — everything (including source) lives in /nix/store";

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

        # Fully patched graphify source — lives in /nix/store, immutable + cached
        graphifyPatched = pkgs.applyPatches {
          name = "graphify-with-vhdl";
          src = graphify-src;

          postPatch = ''
            # Inject VHDL extractor
            cp ${vhdlExtractor} graphify/vhdl_extractor.py

            # Register .vhd/.vhdl as code files
            sed -i 's|CODE_EXTENSIONS = {|CODE_EXTENSIONS = {\n    ".vhd", ".vhdl",|g' graphify/detect.py || true

            # Wire the extractor into the dispatch
            sed -i '/^from pathlib import Path/a from .vhdl_extractor import extract_vhdl' graphify/extract.py || true
            sed -i '/^def extract(path: Path):/a\    ext = path.suffix.lower()\n    if ext in {\x22.vhd\x22, \x22.vhdl\x22}:\n        return extract_vhdl(path)' graphify/extract.py || true
          '';
        };

        # Clean wrapper provided by Nix (no home dir writes)
        graphifyWrapper = pkgs.writeShellScriptBin "graphify" ''
          export GRAPHIFY_VHDL_GRAMMAR="${vhdlGrammar}/parser"
          export AWS_DEFAULT_REGION="us-gov-west-1"
          export PYTHONPATH="${graphifyPatched}:${graphifyPatched}/graphify:$PYTHONPATH"
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
            graphifyWrapper
          ];

          shellHook = ''
            set -euo pipefail

            export AWS_DEFAULT_REGION="us-gov-west-1"
            export GRAPHIFY_VHDL_GRAMMAR="${vhdlGrammar}/parser"
            export GRAPHIFY_SRC="${graphifyPatched}"

            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "  Graphify + VHDL (fully in /nix/store)"
            echo "  Zero modification to working directory or home"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "→ Using patched graphify from Nix store:"
            echo "   $GRAPHIFY_SRC"
            echo ""

            # Install graphify + deps from the store path (non-editable, clean)
            echo "→ Installing graphify from Nix store into this shell..."
            uv pip install "${graphifyPatched}" --quiet 2>/dev/null || \
            pip install "${graphifyPatched}" --quiet

            echo ""
            echo "✅ Ready. 'graphify' command is provided by Nix."
            echo ""
            echo "Usage on any VHDL repo:"
            echo "  graphify /path/to/your-vhdl-project"
            echo "  graphify ."
            echo ""
            echo "• .vhd/.vhdl → tree-sitter structural extraction (entities, architectures, processes...)"
            echo "• Docs, diagrams, tests → Bedrock Sonnet 4.5 semantic extraction"
            echo "• Register skill: graphify install --opencode"
            echo ""
            echo "Everything (grammar + patched source + command) lives in /nix/store."
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
          '';
        };
      });
}