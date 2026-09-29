#!/usr/bin/env bash
#
# Runs the two static-analysis gates -- luacheck and stylua --check -- over the same paths, locally
# and in CI (.github/workflows/lint.yml runs this script), from any working directory.
#
# Nothing has to be installed first. On Windows under Git Bash and on Linux x86-64, the script
# downloads a pinned release binary of each tool into .tools/ (git-ignored), checks it against the
# SHA-256 below, and reuses it on later runs. The versions live here and nowhere else: bumping a
# tool means changing its version and the hashes of its assets. On any other platform -- macOS,
# for which luacheck publishes no binary -- the tools are taken from PATH.
#
# One workaround remains, for stylua: stylua.toml asks for Unix line endings, and a checkout made
# with core.autocrlf=true has CRLF on disk, so --check flags every file for line endings alone --
# which says nothing about the code. This copies the sources to a scratch directory with the CRs
# stripped, puts stylua.toml beside them, and checks there. A real formatting problem still fails;
# a checkout artefact no longer does.
#
# Usage:  build-tools/lint.sh            both gates
#         build-tools/lint.sh luacheck   one of them
#         build-tools/lint.sh stylua

set -euo pipefail

cd "$(dirname "$0")/.."
readonly ROOT="$PWD"
readonly TARGETS=(skynet-iads-source test/lua)

readonly LUACHECK_VERSION=1.2.0
readonly STYLUA_VERSION=2.4.0

fail() {
	echo "lint.sh: $*" >&2
	exit 1
}

# --- tools ------------------------------------------------------------------------------------

platform() {
	case "$(uname -s)" in
	MINGW* | MSYS* | CYGWIN*) echo windows ;;
	Linux) [ "$(uname -m)" = x86_64 ] && echo linux || echo other ;;
	*) echo other ;;
	esac
}

# The release asset of a tool for a platform, and its SHA-256. Each platform gets only its own
# build: Git Bash resolves an extensionless `luacheck` before `luacheck.exe` in the same folder.
asset() {
	case "$1-$2" in
	luacheck-windows) echo "luacheck.exe 0f1c69c4d09f1ebb4d8df14c215e4553e2e639bd4cb7bf3c639b0daa6198317b" ;;
	luacheck-linux) echo "luacheck d68da17fca0697d9e2fb04201f3884abd259fa558b3a449bccaed47f1390defc" ;;
	stylua-windows) echo "stylua-windows-x86_64.zip 3803853280cb524560c6ce0d4140f6d9f02e03f55e1ce50bb4f5e51e07565794" ;;
	stylua-linux) echo "stylua-linux-x86_64.zip f9c84c210712061cb03ab8354a34a5d4f5fcf1f369d2ce916bea3ab9f7addac8" ;;
	*) return 1 ;;
	esac
}

release_url() {
	case "$1" in
	luacheck) echo "https://github.com/lunarmodules/luacheck/releases/download/v$LUACHECK_VERSION/$2" ;;
	stylua) echo "https://github.com/JohnnyMorganz/StyLua/releases/download/v$STYLUA_VERSION/$2" ;;
	esac
}

# Prints the path of the tool's executable, downloading it first if it is not cached yet. The cache
# directory carries the version, so a bump fetches the new binary instead of reusing the old one.
tool() {
	local name="$1" platform entry
	platform="$(platform)"
	if ! entry="$(asset "$name" "$platform")"; then
		command -v "$name" >/dev/null 2>&1 || fail "no pinned $name for this platform, and none on PATH"
		command -v "$name"
		return
	fi

	local file="${entry% *}" sha="${entry#* }" version exe
	[ "$name" = luacheck ] && version="$LUACHECK_VERSION" || version="$STYLUA_VERSION"
	local dir="$ROOT/.tools/$name-$version"
	exe="$dir/$name"
	[ "$platform" = windows ] && exe="$exe.exe"
	if [ -x "$exe" ]; then
		echo "$exe"
		return
	fi

	echo "lint.sh: fetching $name $version into .tools/" >&2
	mkdir -p "$dir"
	local part="$dir/$file.part"
	curl -fsSL -o "$part" "$(release_url "$name" "$file")" || fail "could not download $file"
	local actual
	actual="$(sha256sum "$part" | cut -d ' ' -f 1)"
	if [ "$actual" != "$sha" ]; then
		rm -f "$part"
		fail "$file has SHA-256 $actual, expected $sha"
	fi
	case "$file" in
	*.zip)
		unzip -oq "$part" -d "$dir"
		rm -f "$part"
		;;
	*) mv "$part" "$exe" ;;
	esac
	chmod +x "$exe"
	echo "$exe"
}

# --- luacheck ---------------------------------------------------------------------------------

run_luacheck() {
	local luacheck
	luacheck="$(tool luacheck)"
	"$luacheck" --codes "${TARGETS[@]}"
}

# --- stylua -----------------------------------------------------------------------------------

run_stylua() {
	local stylua
	stylua="$(tool stylua)"

	local scratch
	scratch="$(mktemp -d)"
	trap 'rm -rf "$scratch"' RETURN

	cp "$ROOT/stylua.toml" "$scratch/"
	[ -f "$ROOT/.styluaignore" ] && cp "$ROOT/.styluaignore" "$scratch/"

	local target file
	for target in "${TARGETS[@]}"; do
		while IFS= read -r file; do
			mkdir -p "$scratch/$(dirname "$file")"
			tr -d '\r' <"$ROOT/$file" >"$scratch/$file"
		done < <(find "$target" -name '*.lua' -type f)
	done

	# Reported paths are the scratch copies; the trailing sed points them back at the repository.
	if ! (cd "$scratch" && "$stylua" --check .) 2>&1 | sed "s|$scratch/||g"; then
		return 1
	fi
}

# --- entry point ------------------------------------------------------------------------------

case "${1:-all}" in
luacheck) run_luacheck ;;
stylua) run_stylua ;;
all)
	run_luacheck
	run_stylua
	echo "lint.sh: both gates clean"
	;;
*) fail "unknown gate '$1' (expected luacheck, stylua, or nothing)" ;;
esac
