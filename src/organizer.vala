using GLib;
using Gee;

namespace PhotoOrganizer {
    public class OrganizeResult : Object {
        public uint photos_moved { get; set; }
        public uint duplicate_files { get; set; }
        public uint duplicate_files_moved { get; set; }
        public uint filesystem_dates { get; set; }
        public uint creation_times_unavailable { get; set; }
        public ArrayList<string> errors { get; private set; }

        public OrganizeResult () {
            errors = new ArrayList<string> ();
        }
    }

    private bool has_collision_suffix (string path) {
        string basename = Path.get_basename (path);
        int extension_start = basename.last_index_of (".");
        string stem = extension_start > 0
            ? basename.substring (0, extension_start)
            : basename;
        int suffix_start = stem.last_index_of (" (");
        if (suffix_start < 0 || !stem.has_suffix (")")) {
            return false;
        }

        string? number_value = stem.substring (suffix_start + 2, stem.length - suffix_start - 3);
        if (number_value == null || number_value.length == 0) {
            return false;
        }
        string number = number_value;
        for (int i = 0; i < number.length; i++) {
            char digit = number[i];
            if (digit < '0' || digit > '9') {
                return false;
            }
        }
        while (number.length > 1 && number[0] == '0') {
            number = number.substring (1);
        }
        return number.length > 1 || number[0] > '1';
    }

    private class PhotoFile : Object {
        public string path { get; private set; }
        public uint64 modified_time { get; private set; }
        public bool has_collision_suffix { get; private set; }
        public bool already_organized { get; private set; }

        public PhotoFile (string path, uint64 modified_time, bool already_organized) {
            this.path = path;
            this.modified_time = modified_time;
            this.already_organized = already_organized;
            has_collision_suffix = PhotoOrganizer.has_collision_suffix (path);
        }
    }

    public delegate void ProgressCallback (string message, double fraction, bool determinate);

    private const string[] PHOTO_EXTENSIONS = {
        ".3fr", ".arw", ".avif", ".bmp", ".cr2", ".cr3", ".dcr", ".dng",
        ".erf", ".gif", ".heic", ".heif", ".iiq", ".jpeg", ".jpg", ".kdc",
        ".mef", ".mos", ".mrw", ".nef", ".nrw", ".orf", ".pef", ".png",
        ".raf", ".raw", ".rw2", ".rwl", ".sr2", ".srf", ".srw", ".tif",
        ".tiff", ".webp", ".x3f"
    };

    private bool is_photo (string path) {
        string lower = path.down ();
        foreach (string extension in PHOTO_EXTENSIONS) {
            if (lower.has_suffix (extension)) {
                return true;
            }
        }
        return false;
    }

    private bool is_organized_photo (string path, string source_directory) {
        string month_directory = Path.get_dirname (path);
        string year_directory = Path.get_dirname (month_directory);
        string month = Path.get_basename (month_directory);
        string year = Path.get_basename (year_directory);
        if (Path.get_dirname (year_directory) != source_directory ||
            month.length != 2 || year.length != 4) {
            return false;
        }
        for (int i = 0; i < year.length; i++) {
            if (year[i] < '0' || year[i] > '9') {
                return false;
            }
        }
        if (month[0] < '0' || month[0] > '9' || month[1] < '0' || month[1] > '9') {
            return false;
        }
        int month_number = int.parse (month);
        return month_number >= 1 && month_number <= 12;
    }

    private void scan_directory (
        string directory,
        string source_directory,
        string disorganized_directory,
        string? wallpaper_directory,
        ArrayList<PhotoFile> photos,
        ArrayList<string> errors
    ) {
        string canonical_directory = File.new_for_path (directory).get_path ();
        if (canonical_directory == disorganized_directory ||
            (wallpaper_directory != null && canonical_directory == wallpaper_directory)) {
            return;
        }

        try {
            Dir entries = Dir.open (directory);
            string? name;
            while ((name = entries.read_name ()) != null) {
                string path = Path.build_filename (directory, name);
                if (FileUtils.test (path, FileTest.IS_SYMLINK)) {
                    continue;
                }

                if (FileUtils.test (path, FileTest.IS_DIR)) {
                    scan_directory (
                        path,
                        source_directory,
                        disorganized_directory,
                        wallpaper_directory,
                        photos,
                        errors
                    );
                } else if (is_photo (path) && FileUtils.test (path, FileTest.IS_REGULAR)) {
                    try {
                        FileInfo info = File.new_for_path (path).query_info (
                            "time::modified", FileQueryInfoFlags.NOFOLLOW_SYMLINKS
                        );
                        photos.add (new PhotoFile (
                            path,
                            info.get_attribute_uint64 ("time::modified"),
                            is_organized_photo (path, source_directory)
                        ));
                    } catch (Error error) {
                        errors.add (_("Could not read modification time for %s: %s").printf (path, error.message));
                        photos.add (new PhotoFile (path, uint64.MAX, is_organized_photo (path, source_directory)));
                    }
                }
            }
        } catch (FileError error) {
            errors.add (_("Could not scan %s: %s").printf (directory, error.message));
        }
    }

    private string sha256_file (string path) throws Error {
        Checksum checksum = new Checksum (ChecksumType.SHA256);
        FileInputStream stream = File.new_for_path (path).read ();
        uint8[] buffer = new uint8[64 * 1024];
        ssize_t bytes_read;
        while ((bytes_read = stream.read (buffer)) > 0) {
            checksum.update (buffer[0:(int) bytes_read], (size_t) bytes_read);
        }
        return checksum.get_string ();
    }

    private DateTime? exif_capture_time (string path) {
        try {
            GExiv2.Metadata metadata = new GExiv2.Metadata ();
            metadata.open_path (path);
            string? value = read_exif_tag (metadata, "Exif.Photo.DateTimeOriginal");
            if (value == null || value.strip ().length == 0) {
                value = read_exif_tag (metadata, "Exif.Photo.DateTimeDigitized");
            }
            if (value == null || value.strip ().length == 0) {
                value = read_exif_tag (metadata, "Exif.Image.DateTime");
            }
            if (value == null || value.strip ().length == 0) {
                return null;
            }

            string[] fields = value.strip ().split_set (": ");
            if (fields.length < 6) {
                return null;
            }
            int year = int.parse (fields[0]);
            int month = int.parse (fields[1]);
            int day = int.parse (fields[2]);
            int hour = int.parse (fields[3]);
            int minute = int.parse (fields[4]);
            double second = double.parse (fields[5]);
            return new DateTime.local (year, month, day, hour, minute, second);
        } catch (Error error) {
            return null;
        }
    }

    private string? read_exif_tag (GExiv2.Metadata metadata, string tag) {
        try {
            return metadata.try_get_tag_string (tag);
        } catch (Error error) {
            return null;
        }
    }

    private void ensure_directory (string path) throws Error {
        if (FileUtils.test (path, FileTest.IS_SYMLINK)) {
            throw new IOError.FAILED (_("Output path must not be a symbolic link: %s").printf (path));
        }
        if (FileUtils.test (path, FileTest.IS_DIR)) {
            return;
        }
        try {
            File.new_for_path (path).make_directory_with_parents ();
        } catch (IOError.EXISTS error) {
            if (FileUtils.test (path, FileTest.IS_SYMLINK) ||
                !FileUtils.test (path, FileTest.IS_DIR)) {
                throw error;
            }
        }
    }

    private string unused_destination (string directory, string filename) {
        string destination = Path.build_filename (directory, filename);
        if (!FileUtils.test (destination, FileTest.EXISTS)) {
            return destination;
        }

        string basename = Path.get_basename (filename);
        int dot = basename.last_index_of (".");
        bool has_extension = dot > 0;
        string stem = has_extension ? basename.substring (0, dot) : basename;
        string suffix = has_extension ? basename.substring (dot) : "";
        uint index = 2;
        do {
            destination = Path.build_filename (directory, "%s (%u)%s".printf (stem, index, suffix));
            index++;
        } while (FileUtils.test (destination, FileTest.EXISTS));
        return destination;
    }

    private SettingsSchema? wallpaper_slideshow_schema_in (string data_directory) {
        const string schema_id = "org.gnome.shell.extensions.azwallpaper";
        const string extension_id = "azwallpaper@azwallpaper.gitlab.com";
        SettingsSchemaSource? default_source = SettingsSchemaSource.get_default ();
        string schema_directory = Path.build_filename (
            data_directory,
            "gnome-shell",
            "extensions",
            extension_id,
            "schemas"
        );
        string compiled_schema = Path.build_filename (schema_directory, "gschemas.compiled");
        if (!FileUtils.test (compiled_schema, FileTest.IS_REGULAR)) {
            return null;
        }

        try {
            SettingsSchemaSource extension_source = new SettingsSchemaSource.from_directory (
                schema_directory,
                default_source,
                true
            );
            return extension_source.lookup (schema_id, true);
        } catch (Error error) {
            warning ("Could not load Wallpaper Slideshow settings from %s: %s"
                .printf (schema_directory, error.message));
            return null;
        }
    }

    private SettingsSchema? wallpaper_slideshow_schema () {
        const string schema_id = "org.gnome.shell.extensions.azwallpaper";
        SettingsSchemaSource? default_source = SettingsSchemaSource.get_default ();
        SettingsSchema? schema = default_source == null
            ? null
            : default_source.lookup (schema_id, true);
        if (schema != null) {
            return schema;
        }

        schema = wallpaper_slideshow_schema_in (Environment.get_user_data_dir ());
        if (schema != null) {
            return schema;
        }

        string? configured_data_directories = Environment.get_variable ("XDG_DATA_DIRS");
        string[] system_data_directories;
        if (configured_data_directories == null || configured_data_directories.length == 0) {
            system_data_directories = { "/usr/local/share", "/usr/share" };
        } else {
            system_data_directories = configured_data_directories.split (":");
        }
        foreach (string data_directory in system_data_directories) {
            if (data_directory.length == 0) {
                continue;
            }
            schema = wallpaper_slideshow_schema_in (data_directory);
            if (schema != null) {
                return schema;
            }
        }
        return null;
    }

    private string? wallpaper_slideshow_directory () {
        SettingsSchema? schema = wallpaper_slideshow_schema ();
        if (schema == null || !schema.has_key ("slideshow-directory")) {
            return null;
        }

        Settings settings = new Settings.full (schema, null, null);
        string path = settings.get_string ("slideshow-directory");
        if (path.length == 0) {
            return null;
        }
        string? canonical_path = File.new_for_path (path).get_path ();
        if (canonical_path != null) {
            debug ("Excluding Wallpaper Slideshow directory: %s", canonical_path);
        }
        return canonical_path;
    }

    public OrganizeResult organize (
        string source_path,
        ProgressCallback progress,
        string? protected_wallpaper_directory = null
    ) throws Error {
        string? local_path = File.new_for_path (source_path).get_path ();
        if (local_path == null) {
            throw new FileError.NOTDIR (_("Selected folder must be a local directory."));
        }
        string source = local_path;
        if (!FileUtils.test (source, FileTest.IS_DIR)) {
            throw new FileError.NOTDIR (_("Selected folder does not exist: %s").printf (source));
        }

        string? wallpaper_directory = protected_wallpaper_directory != null
            ? File.new_for_path (protected_wallpaper_directory).get_path ()
            : wallpaper_slideshow_directory ();
        string disorganized = Path.build_filename (source, "Disorganized Photos");
        if (FileUtils.test (disorganized, FileTest.IS_SYMLINK)) {
            throw new IOError.FAILED (_("Output directory must not be a symbolic link: %s").printf (disorganized));
        }
        string canonical_disorganized = File.new_for_path (disorganized).get_path ();

        OrganizeResult result = new OrganizeResult ();
        ArrayList<PhotoFile> photos = new ArrayList<PhotoFile> ();
        progress (_("Scanning for photos…"), 0, false);
        scan_directory (
            source,
            source,
            canonical_disorganized,
            wallpaper_directory,
            photos,
            result.errors
        );
        photos.sort ((a, b) => {
            if (a.already_organized != b.already_organized) {
                return a.already_organized ? -1 : 1;
            }
            if (a.has_collision_suffix != b.has_collision_suffix) {
                return a.has_collision_suffix ? 1 : -1;
            }
            if (a.modified_time < b.modified_time) {
                return -1;
            }
            if (a.modified_time > b.modified_time) {
                return 1;
            }
            return strcmp (a.path, b.path);
        });

        HashMap<string, ArrayList<PhotoFile>> groups = new HashMap<string, ArrayList<PhotoFile>> ();
        double photo_count = photos.size > 0 ? photos.size : 1;
        int hash_step = photos.size / 100;
        if (hash_step < 1) {
            hash_step = 1;
        }
        for (int i = 0; i < photos.size; i++) {
            PhotoFile photo = photos[i];
            string hash;
            try {
                hash = sha256_file (photo.path);
            } catch (Error error) {
                result.errors.add (_("Could not read %s: %s").printf (photo.path, error.message));
                hash = "unreadable:%s".printf (photo.path);
            }
            ArrayList<PhotoFile>? group = groups.get (hash);
            if (group == null) {
                group = new ArrayList<PhotoFile> ();
                groups.set (hash, group);
            }
            group.add (photo);

            if ((i + 1) % hash_step == 0 || i + 1 == photos.size) {
                progress (
                    _("Checking photos (%d of %d)…").printf (i + 1, photos.size),
                    (i + 1) / photo_count * 0.5,
                    true
                );
            }
        }

        ArrayList<PhotoFile> photos_to_move = new ArrayList<PhotoFile> ();
        ArrayList<PhotoFile> duplicates_to_move = new ArrayList<PhotoFile> ();
        foreach (Map.Entry<string, ArrayList<PhotoFile>> entry in groups.entries) {
            ArrayList<PhotoFile> group = entry.value;
            if (group.size > 1) {
                result.duplicate_files += group.size - 1;
            }
            if (group[0].already_organized) {
                for (int i = 1; i < group.size; i++) {
                    duplicates_to_move.add (group[i]);
                }
            } else {
                photos_to_move.add (group[0]);
                for (int i = 1; i < group.size; i++) {
                    duplicates_to_move.add (group[i]);
                }
            }
        }

        if (duplicates_to_move.size > 0) {
            ensure_directory (disorganized);
        }

        int move_step = photos_to_move.size / 100;
        if (move_step < 1) {
            move_step = 1;
        }
        double all_moves_count = photos_to_move.size + duplicates_to_move.size;
        if (all_moves_count < 1) {
            all_moves_count = 1;
        }
        for (int i = 0; i < photos_to_move.size; i++) {
            PhotoFile photo = photos_to_move[i];
            string? destination = null;
            int64? exif_timestamp = null;
            bool moved = false;
            try {
                DateTime? captured = exif_capture_time (photo.path);
                if (captured != null) {
                    exif_timestamp = captured.to_unix ();
                } else {
                    FileInfo info = File.new_for_path (photo.path).query_info (
                        "time::modified", FileQueryInfoFlags.NOFOLLOW_SYMLINKS
                    );
                    captured = new DateTime.from_unix_local ((int64) info.get_attribute_uint64 ("time::modified"));
                    result.filesystem_dates++;
                }
                string year_directory = Path.build_filename (source, captured.format ("%Y"));
                ensure_directory (year_directory);
                string month_directory = Path.build_filename (year_directory, captured.format ("%m"));
                ensure_directory (month_directory);
                destination = unused_destination (month_directory, Path.get_basename (photo.path));
                File.new_for_path (photo.path).move (File.new_for_path (destination), FileCopyFlags.NONE);
                result.photos_moved++;
                moved = true;
            } catch (Error error) {
                result.errors.add (_("Could not organize %s: %s").printf (photo.path, error.message));
            }

            if (moved && destination != null && exif_timestamp != null) {
                File organized_photo = File.new_for_path (destination);
                try {
                    organized_photo.set_attribute_uint64 (
                        "time::modified",
                        (uint64) exif_timestamp,
                        FileQueryInfoFlags.NONE
                    );
                } catch (Error error) {
                    result.errors.add (
                        _("Moved %s but could not set its modification time: %s").printf (destination, error.message)
                    );
                }

                try {
                    FileAttributeInfoList settable = organized_photo.query_settable_attributes ();
                    if (settable.lookup ("time::created") == null) {
                        result.creation_times_unavailable++;
                    } else {
                        organized_photo.set_attribute_uint64 (
                            "time::created",
                            (uint64) exif_timestamp,
                            FileQueryInfoFlags.NONE
                        );
                    }
                } catch (Error error) {
                    result.creation_times_unavailable++;
                    result.errors.add (
                        _("Moved %s but could not set its creation time: %s").printf (destination, error.message)
                    );
                }
            }

            if ((i + 1) % move_step == 0 ||
                i + 1 == photos_to_move.size) {
                progress (
                    _("Organizing photos (%d of %d)…").printf (i + 1, (int) all_moves_count),
                    0.5 + (i + 1) / all_moves_count * 0.5,
                    true
                );
            }
        }

        for (int i = 0; i < duplicates_to_move.size; i++) {
            PhotoFile duplicate = duplicates_to_move[i];
            try {
                string destination = unused_destination (disorganized, Path.get_basename (duplicate.path));
                File.new_for_path (duplicate.path).move (File.new_for_path (destination), FileCopyFlags.NONE);
                result.duplicate_files_moved++;
            } catch (Error error) {
                result.errors.add (_("Could not move duplicate %s: %s").printf (duplicate.path, error.message));
            }

            if ((i + 1) % move_step == 0 || i + 1 == duplicates_to_move.size) {
                int completed_moves = photos_to_move.size + i + 1;
                progress (
                    _("Moving duplicate photos (%d of %d)…").printf (completed_moves, (int) all_moves_count),
                    0.5 + completed_moves / all_moves_count * 0.5,
                    true
                );
            }
        }
        return result;
    }
}
