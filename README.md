# Photo Organiser

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

The photo-folder chooser opens in the standard Pictures folder configured by
the desktop environment, when that folder exists.

After installing with `meson install -C build`, the app icon and launcher entry
are installed for your desktop environment. Launch Photo Organizer from the
GNOME app grid for GNOME Shell to match the running app with its desktop entry
and show the icon in the dock; the About dialog and window also use the app
icon. For a per-user install that GNOME discovers, use the standard
`~/.local` prefix:

```sh
meson configure build --prefix="$HOME/.local"
meson setup build --reconfigure
meson compile -C build
meson install -C build
```

To run the tests:

```sh
meson test -C build --print-errorlogs
```

## Translations

The application uses GNU gettext. To update the translation template after
changing user-visible strings:

```sh
ninja -C build photo-organizer-pot
```

The available catalogues provide British English (`en_GB`), German (`de`),
French (`fr`), Spanish (`es`), Welsh (`cy`), Italian (`it`), Dutch (`nl`),
and Japanese (`ja`).
To start another translation, create a PO file from `po/photo-organizer.pot`,
add its locale code to `po/LINGUAS`, then reconfigure and rebuild so Meson
includes the new catalogue. For example:

```sh
msginit --input=po/photo-organizer.pot --locale=fr --output-file=po/fr.po
echo fr >> po/LINGUAS
meson setup build --reconfigure
meson compile -C build
```

Use `ninja -C build photo-organizer-update-po` to refresh existing PO files
after updating the template. The compiled catalogues are installed under
`<localedir>/<locale>/LC_MESSAGES/photo-organizer.mo`.
