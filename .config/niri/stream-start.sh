#!/bin/sh
# Stream setup.
# DP-2: stream-hub (Stream Firefox profile with dashboards via session restore,
#   Easy Effects, pavucontrol) and stream-games (left empty for whatever gets played).
# HDMI-A-2: stream-monitor, three columns: chats (stacked), OBS, Twitch channel page.

FIREFOX_DIR="$HOME/.mozilla/firefox"
HUB_PROFILE_NAME="Stream"
TWITCH_CHANNEL="your-channel"

# Prints the folder of a Firefox profile from its name in Firefox's profile manager.
# Profiles made there are stored in the Profile Groups database, not profiles.ini.
firefox_profile() {
  python3 -c '
import glob, os, sqlite3, sys
base, name = sys.argv[1], sys.argv[2]
for db in glob.glob(os.path.join(base, "Profile Groups", "*.sqlite")):
    row = sqlite3.connect(f"file:{db}?mode=ro", uri=True).execute(
        "select path from Profiles where name = ?", (name,)).fetchone()
    if row:
        print(os.path.join(base, row[0]))
        break
' "$FIREFOX_DIR" "$1"
}

# Names the empty workspace at the bottom of an output, unless the name already exists.
create_workspace() {
  name="$1"
  output="$2"

  niri msg -j workspaces | grep -q "\"name\":\"$name\"" && return

  idx="$(niri msg -j workspaces | python3 -c '
import json, sys
print(max(w["idx"] for w in json.load(sys.stdin) if w["output"] == sys.argv[1]))
' "$output")"

  niri msg action focus-monitor "$output"
  niri msg action focus-workspace "$idx"
  niri msg action set-workspace-name "$name"
}

# Prints the ids of all open windows with the given app-id, one per line.
window_ids() {
  niri msg -j windows | python3 -c '
import json, sys
for w in json.load(sys.stdin):
    if w["app_id"] == sys.argv[1]:
        print(w["id"])
' "$1"
}

# Prints the id of the first open window with the given app-id, if any.
window_id() {
  window_ids "$1" | head -n 1
}

# Waits up to 15s for a window with the given app-id to open, then prints its id.
wait_for_window() {
  for _ in $(seq 75); do
    id="$(window_id "$1")"
    [ -n "$id" ] && echo "$id" && return
    sleep 0.2
  done
}

# Moves an already open app to a workspace, or launches it (the window rule places it).
# Needed because window rules only apply to new windows.
open_on() {
  id="$(window_id "$2")"
  if [ -n "$id" ]; then
    niri msg action move-window-to-workspace --window-id "$id" --focus false "$1"
  else
    setsid -f "$3" >/dev/null 2>&1
  fi
}

# Opens a URL in a new window of the running hub Firefox and prints the new window's id.
# These share the hub's app-id, so the new one is found by comparing ids before and after.
new_firefox_window() {
  before="$(window_ids firefox-stream-hub)"
  setsid -f firefox --profile "$HUB_PROFILE" --name firefox-stream-hub --new-window "$1" >/dev/null 2>&1
  for _ in $(seq 75); do
    for id in $(window_ids firefox-stream-hub); do
      echo "$before" | grep -qx "$id" || { echo "$id"; return; }
    done
    sleep 0.2
  done
}

HUB_PROFILE="$(firefox_profile "$HUB_PROFILE_NAME")"
if [ -z "$HUB_PROFILE" ]; then
  echo "Firefox profile \"$HUB_PROFILE_NAME\" not found" >&2
  exit 1
fi

create_workspace stream-hub DP-2
create_workspace stream-games DP-2
create_workspace stream-monitor HDMI-A-2
# Keep them first on their monitors so Mod+1 / Mod+2 always reach them.
niri msg action move-workspace-to-index --reference stream-hub 1
niri msg action move-workspace-to-index --reference stream-games 2
niri msg action move-workspace-to-index --reference stream-monitor 1

# --- stream-hub ---

if [ -z "$(window_id firefox-stream-hub)" ]; then
  setsid -f firefox --profile "$HUB_PROFILE" --name firefox-stream-hub >/dev/null 2>&1
fi
firefox_id="$(wait_for_window firefox-stream-hub)"

open_on stream-hub com.github.wwmm.easyeffects easyeffects
open_on stream-hub org.pulseaudio.pavucontrol pavucontrol

# --- stream-monitor ---

open_on stream-monitor com.obsproject.Studio obs
obs_id="$(wait_for_window com.obsproject.Studio)"

chat1_id="$(new_firefox_window "https://www.twitch.tv/popout/stixout/chat?popout=")"
chat2_id="$(new_firefox_window "https://www.twitch.tv/popout/$TWITCH_CHANNEL/chat?popout=")"
channel_id="$(new_firefox_window "https://www.twitch.tv/stixout")"

# Columns, left to right: chats (stacked), OBS, channel page. Each one is moved to the
# front in reverse order, then chat 2 is pulled into chat 1's column.
for id in "$channel_id" "$obs_id" "$chat2_id" "$chat1_id"; do
  [ -n "$id" ] || continue
  niri msg action move-window-to-workspace --window-id "$id" --focus false stream-monitor
  niri msg action focus-window --id "$id"
  niri msg action move-column-to-first
  niri msg action set-column-width 33.333%
done
niri msg action consume-window-into-column

# --- finish on stream-hub ---

# Moved and newly opened windows don't land in a fixed order, so put Firefox in front.
if [ -n "$firefox_id" ]; then
  niri msg action focus-window --id "$firefox_id"
  niri msg action move-column-to-first
fi
