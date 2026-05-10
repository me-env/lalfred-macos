# dmgbuild settings file for L'Alfred.
# Invoke with:
#   dmgbuild -s ci/dmg-settings.py -D app=path/to/App.app "Volume Name" out.dmg

import os.path

# ---------- inputs ----------
app_path = defines.get("app", "build/export/L'Alfred.app")
app_name = os.path.basename(app_path)

# ---------- container ----------
format = "UDZO"          # compressed, read-only
filesystem = "HFS+"
size = None              # auto-size

files = [app_path]
symlinks = {"Applications": "/Applications"}
hide_extension = [app_name]

# ---------- volume look ----------
# Use the .app's own icon as the disk image badge.
badge_icon = app_path

# ---------- window ----------
# (origin), (width, height)
window_rect = ((200, 200), (600, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False

background = None
icon_size = 128
text_size = 13
label_pos = "bottom"

icon_locations = {
    app_name: (150, 200),
    "Applications": (450, 200),
}

# ---------- list view (unused but required defaults) ----------
include_icon_view_settings = "auto"
include_list_view_settings = "auto"
arrange_by = None
grid_offset = (0, 0)
grid_spacing = 100
scroll_position = (0, 0)
