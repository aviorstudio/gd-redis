#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive="${1:-$root/dist/@aviorstudio_gd-redis.zip}"
godot="${GODOT_BIN:-godot}"
scratch="$(mktemp -d)"; trap 'rm -rf "$scratch"' EXIT
allowlist="$root/tests/editor-log-allowlist.txt"

checked_editor() {
  label="$1"; shift; log="$scratch/$label.log"
  set +e
  HOME="$scratch/home" timeout --signal=TERM --kill-after=5 30s "$godot" "$@" 2>&1 | tee "$log"
  status="${PIPESTATUS[0]}"; set -e
  [ "$status" -eq 0 ] || { echo "Editor command $label exited $status" >&2; exit 1; }
  unexpected="$(grep -E '^(ERROR:|SCRIPT ERROR:|FAIL:)' "$log" | grep -Ev -f "$allowlist" || true)"
  if [ -n "$unexpected" ]; then echo "Unexpected editor error in $label: $unexpected" >&2; exit 1; fi
}
fixture="$scratch/project"
mkdir -p "$fixture/addons/@aviorstudio_gd-redis"
unzip -oq "$archive" -d "$fixture/addons/@aviorstudio_gd-redis"
installed_digest="$(cd "$fixture/addons/@aviorstudio_gd-redis" && while IFS= read -r path; do sha256sum "$path"; done < "$root/addon/package-manifest.txt" | sha256sum | cut -d' ' -f1)"
echo "Installed tree SHA-256: $installed_digest"
cat > "$fixture/consumer_owned.gd" <<'GD'
extends Node
GD
cat > "$fixture/project.godot" <<'CFG'
[application]
config/name="gd-redis package lifecycle"
[autoload]
ConsumerOwned="*res://consumer_owned.gd"
[editor_plugins]
enabled=PackedStringArray()
[rendering]
renderer/rendering_method="gl_compatibility"
CFG
cat > "$fixture/lifecycle.gd" <<'GD'
@tool
extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var plugin = load("res://addons/@aviorstudio_gd-redis/plugin.gd").new()
	root.add_child(plugin)
	await process_frame
	if not ProjectSettings.has_setting("autoload/GdRedis"):
		push_error("plugin did not add owned autoload"); quit(1); return
	if not ProjectSettings.has_setting("autoload/ConsumerOwned"):
		push_error("consumer autoload was removed"); quit(1); return
	plugin.queue_free()
	await process_frame
	if ProjectSettings.has_setting("autoload/GdRedis"):
		push_error("plugin did not remove owned autoload"); quit(1); return
	if not ProjectSettings.has_setting("autoload/ConsumerOwned"):
		push_error("consumer autoload was removed on disable"); quit(1); return
	print("PASS gd-redis packaged editor lifecycle")
	quit(0)
GD
checked_editor lifecycle --headless --editor --path "$fixture" --script "$fixture/lifecycle.gd"
grep -Fq 'PASS gd-redis packaged editor lifecycle' "$scratch/lifecycle.log"
checked_editor restart --headless --editor --path "$fixture" --quit-after 2
grep -Fq 'ConsumerOwned=' "$fixture/project.godot"
if grep -Fq 'GdRedis=' "$fixture/project.godot"; then echo "Owned autoload survived disable/restart" >&2; exit 1; fi
echo "PASS packaged editor enable/restart/disable/restart ownership lifecycle"
