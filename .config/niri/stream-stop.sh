#!/bin/sh
# Stream teardown: unnames the stream workspaces so niri removes them once they're
# empty. Windows are left open to close by hand.

for name in stream-hub stream-games stream-monitor; do
  niri msg -j workspaces | grep -q "\"name\":\"$name\"" &&
    niri msg action unset-workspace-name "$name"
done
