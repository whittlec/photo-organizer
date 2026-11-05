# Photo Organiser

A GNOME application written in Vala with GTK 4 and libadwaita. It scans the
chosen folder recursively, flags byte-for-byte duplicates using SHA-256, and
moves one copy of each unique image into `YYYY/mm` folders inside the chosen
folder, based on its EXIF capture date. For byte-for-byte duplicates, a
filename without the app's numbered collision suffix (such as ` (2)`) is
preferred. If all copies have the same suffix status, the file with the
earliest filesystem modification time is chosen. The other copies are moved
into `Disorganized Photos`. If capture-date metadata is unavailable, the
selected file's last-modified date is used. When EXIF capture time is
available, the app also sets the organized file's modification time to that
timestamp. It sets the filesystem creation time only on filesystems that
allow changing it; most Linux filesystems do not, and the app reports when
that is unavailable.

Files with the same name receive a numbered suffix rather than being
overwritten. Existing `YYYY/mm` photos are included when checking for
duplicates but are not moved again. The `Disorganized Photos` folder is
excluded from subsequent scans. Photos from a previous `Organized Photos`
output folder are moved into the new in-place date structure.
When the GNOME Wallpaper Slideshow extension is installed, its configured
slideshow directory is excluded from scanning and left untouched.

## Install and run

On Debian or Ubuntu, install the build tools and development libraries:

```sh
sudo apt install valac meson ninja-build libgtk-4-dev libadwaita-1-dev libgexiv2-dev libgee-0.8-dev
meson setup build
meson compile -C build
./build/photo-organizer
```

The standard Pictures folder configured by the desktop environment is
selected automatically when it exists. Use “Choose Photo Folder…” to select
a different folder. The chooser also opens in the Pictures folder by default.

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

## Debian package

The project includes Debian packaging metadata targeting Debian Trixie. To
build a `.deb` on Trixie, install the package build tools and project
dependencies, then build the binary package from the project root:

```sh
sudo apt install build-essential debhelper gettext \
  libadwaita-1-dev libgee-0.8-dev libgexiv2-dev libgtk-4-dev meson valac
dpkg-buildpackage --build=binary --no-sign
```

The resulting `photo-organizer_0.1.0-3_*.deb` is written to the parent
directory. Install it with `sudo apt install ../photo-organizer_0.1.0-3_*.deb`.
The package installs the app, GNOME launcher and icon, and translations into
the system directories. Debian package metadata and dependency versions are in
`debian/`.

The package also installs AppStream metadata in `/usr/share/metainfo`, which
provides GNOME Software with the app description, features, categories,
developer, license, and age rating.

To run the tests:

```sh
meson test -C build --print-errorlogs
```

The organizer regression tests cover duplicate selection and preservation,
EXIF and filesystem date handling, reruns and legacy folders, wallpaper and
symlink exclusions, invalid input and output paths, supported photo formats,
and progress reporting. The GTK window and interactive dialogs are not
automated; verify those manually in a GNOME session.

To generate source-level coverage for the organizer tests, install `gcovr`
and enable Meson's coverage instrumentation:

```sh
sudo apt install gcovr
meson setup build --reconfigure -Db_coverage=true
meson compile -C build
meson test -C build --print-errorlogs
gcovr --root . --filter 'src/organizer\.vala$' \
  --html-details=build/coverage.html --html-single-page --txt-summary
```

Open `build/coverage.html` for the annotated report. The filter keeps the
report focused on the organizer implementation exercised by the tests.

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
