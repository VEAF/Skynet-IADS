#!/usr/bin/env bash
#
# Runs the two static-analysis gates -- luacheck and stylua --check -- over the same paths CI
# checks, from any working directory.
#
# It exists because doing that by hand on a Windows checkout needs two workarounds that are easy
# to get wrong and tedious to retype:
#
#   luacheck  a luarocks install can put the rock in a tree for a newer Lua than the interpreter
#             that has to run it; the binary then dies on "attempt to assign to const variable"
#             before checking anything. The fix is to run the rock's own bin script under a 5.1
#             interpreter with LUA_PATH pointed at the rock tree. Set LUACHECK_BIN, LUACHECK_TREE
#             and LUA51 to override what is guessed below.
#
#   stylua    stylua.toml asks for Unix line endings, and a checkout made with core.autocrlf=true
#             has CRLF on disk, so --check flags every file for line endings alone -- which says
#             nothing about the code. This copies the sources to a scratch directory with the CRs
#             stripped, puts stylua.toml beside them, and checks there. A real formatting problem
#             still fails; a checkout artefact no longer does.
#
# On Linux, where luacheck runs straight from PATH and the checkout is LF, both paths collapse to
# just running the tools. That is what CI does.
#
# Usage:  build-tools/lint.sh            both gates
#         build-tools/lint.sh luacheck   one of them
#         build-tools/lint.sh stylua

set -euo pipefail

cd "$(dirname "$0")/.."
readonly ROOT="$PWD"
readonly TARGETS=(skynet-iads-source test/lua)

fail() {
	echo "lint.sh: $*" >&2
	exit 1
}

# --- luacheck ---------------------------------------------------------------------------------

find_lua51() {
	if [ -n "${LUA51:-}" ]; then
		echo "$LUA51"
		return
	fi
	local candidate
	for candidate in lua5.1 lua51 lua "/c/Program Files (x86)/Lua/5.1/lua.exe"; do
		if command -v "$candidate" >/dev/null 2>&1; then
			if "$candidate" -e 'if _VERSION ~= "Lua 5.1" then os.exit(1) end' >/dev/null 2>&1; then
				command -v "$candidate"
				return
			fi
		elif [ -x "$candidate" ]; then
			echo "$candidate"
			return
		fi
	done
	return 1
}

# The rock's bin script, and the tree its modules live in, when luacheck cannot run on its own.
find_luacheck_rock() {
	if [ -n "${LUACHECK_BIN:-}" ]; then
		echo "$LUACHECK_BIN"
		return
	fi
	local luarocks_root
	luarocks_root="$(command -v luarocks 2>/dev/null || true)"
	[ -n "$luarocks_root" ] || return 1
	luarocks_root="$(dirname "$(dirname "$luarocks_root")")"
	find "$luarocks_root" -type f -name luacheck -path '*/bin/*' 2>/dev/null | head -1
}

# The rock's bin script sits several levels below the tree holding share/lua; walk up to it rather
# than counting directories, since the depth differs between luarocks layouts.
find_module_tree() {
	local dir
	dir="$(dirname "$1")"
	while [ "$dir" != "/" ] && [ -n "$dir" ]; do
		if [ -d "$dir/share/lua" ]; then
			echo "$dir"
			return
		fi
		local parent
		parent="$(dirname "$dir")"
		[ "$parent" = "$dir" ] && break
		dir="$parent"
	done
	return 1
}

run_luacheck() {
	if command -v luacheck >/dev/null 2>&1 && luacheck --version >/dev/null 2>&1; then
		luacheck "${TARGETS[@]}"
		return
	fi

	local lua bin tree
	lua="$(find_lua51)" || fail "no Lua 5.1 interpreter found; set LUA51"
	bin="$(find_luacheck_rock)" || fail "luacheck is broken and no rock was found; set LUACHECK_BIN"
	tree="${LUACHECK_TREE:-$(find_module_tree "$bin")}" || fail "no share/lua above $bin; set LUACHECK_TREE"

	echo "lint.sh: luacheck is not runnable on its own, using the rock under $(dirname "$bin")"
	local candidate path=""
	for candidate in "$tree"/share/lua/*; do
		# A native Windows interpreter cannot read the /c/... form: MSYS translates arguments that
		# look like paths, but never the contents of an environment variable, so LUA_PATH has to be
		# handed over already converted.
		[ -d "$candidate" ] || continue
		if command -v cygpath >/dev/null 2>&1; then
			candidate="$(cygpath -m "$candidate")"
		fi
		path="$path$candidate/?.lua;$candidate/?/init.lua;"
	done
	LUA_PATH="$path;" "$lua" "$bin" "${TARGETS[@]}"
}

# --- stylua -----------------------------------------------------------------------------------

run_stylua() {
	command -v stylua >/dev/null 2>&1 || fail "stylua is not on PATH"

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
	if ! (cd "$scratch" && stylua --check .) 2>&1 | sed "s|$scratch/||g"; then
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
