# Photo Organizer

A GNOME application written in Vala with GTK 4 and libadwaita. It scans the
chosen folder recursively, flags byte-for-byte duplicates using SHA-256, and
moves recognized images into `Organized Photos/YYYY/mm` based on their EXIF
capture date. If capture-date metadata is unavailable, the file's last-modified
date is used.

Duplicates are reported but kept. Files with the same name receive a numbered
suffix rather than being overwritten. The existing `Organized Photos`
directory is excluded from subsequent scans.

## Install and run

On Debian or Ubuntu, install the build tools and development libraries:

```sh
sudo apt install valac meson ninja-build libgtk-4-dev libadwaita-1-dev libgexiv2-dev libgee-0.8-dev
meson setup build
meson compile -C build
./build/photo-organizer
```

To run the tests:

```sh
meson test -C build --print-errorlogs
```
