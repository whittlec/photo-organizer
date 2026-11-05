# Photo Organizer

A GNOME application written in Vala with GTK 4 and libadwaita. It scans the
chosen folder recursively, flags byte-for-byte duplicates using SHA-256, and
moves one copy of each unique image into `Organized Photos/YYYY/mm` based on
its EXIF capture date. For byte-for-byte duplicates, a filename without the
app's numbered collision suffix (such as ` (2)`) is preferred. If all copies
have the same suffix status, the file with the earliest filesystem
modification time is chosen. Other copies are counted and left at their
original locations. This selection uses filesystem modification times, not
EXIF dates. If capture-date metadata is unavailable, the selected file's
last-modified date is used. When EXIF capture time is available, the app also
sets the organized file's modification time to that timestamp. It sets the
filesystem creation time only on filesystems that allow changing it; most
Linux filesystems do not, and the app reports when that is unavailable.

Files with the same name receive a numbered suffix rather than being
overwritten. The existing `Organized Photos` directory is excluded from
subsequent scans.

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
