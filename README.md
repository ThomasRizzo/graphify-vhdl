# Graphify + VHDL tree-sitter + AWS Bedrock GovCloud (Sonnet 4.5)

**One-command setup.** Just `nix develop` and everything is ready.

This flake automatically:
- Clones graphify (v8 branch)
- Builds the tree-sitter VHDL grammar
- Injects full VHDL structural extraction (entities, architectures, processes, ports, instantiations, etc.)
- Sets up AWS Bedrock GovCloud environment (inherits your existing credentials)
- Creates a working `graphify` command in your PATH
- Prepares everything for OpenCode / Cursor / agentic use with Sonnet 4.5

## Usage (exactly what you asked for)

Put this flake + `vhdl_extractor.py` in a repo on your GitHub (e.g. `ThomasRizzo/graphify-vhdl`).

Then anywhere:

```bash
git clone https://github.com/ThomasRizzo/graphify-vhdl.git
cd graphify-vhdl
nix develop
```

That's it. The shell will automatically set up everything. You can then run:

```bash
graphify /path/to/any-vhdl-repo
graphify .
```

VHDL files (`.vhd`, `.vhdl`) are now parsed with tree-sitter. All other files (docs, diagrams, testbenches, etc.) use Bedrock Sonnet 4.5 for semantic extraction.

## What you get in the shell

- Working `graphify` command (wrapper that knows about the VHDL grammar)
- `AWS_DEFAULT_REGION=us-gov-west-1` (change in flake if you use the other GovCloud region)
- Your existing AWS credentials are used automatically
- Clean, reproducible environment with `uv`

## Registering with OpenCode / Cursor

After `nix develop`:

```bash
graphify install --opencode
# or
graphify cursor install
```

## Notes

- The integration is idempotent — you can re-enter the shell safely.
- If upstream graphify changes the internal structure of `extract.py` or `detect.py`, the `sed` lines in the flake may need a one-line tweak (rare).
- You can later turn this into a fully built package with `nix build` if desired.
- Matches your existing patterns (Nix flakes, Bedrock GovCloud, agentic tooling, reproducible setups).

The `vhdl_extractor.py` is included in the repo and automatically copied in during setup. You can improve the concept mapping inside it anytime.

Enjoy! This should give you a very smooth experience working with your VHDL repos + the rest of your embedded / defense work.