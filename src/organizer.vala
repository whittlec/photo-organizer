using GLib;
using Gee;

namespace PhotoOrganizer {
    public class OrganizeResult : Object {
        public uint photos_moved { get; set; }
        public uint duplicate_files { get; set; }
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

        public PhotoFile (string path, uint64 modified_time) {
            this.path = path;
            this.modified_time = modified_time;
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

    private void scan_directory (
        string directory,
        string output_directory,
        ArrayList<PhotoFile> photos,
        ArrayList<string> errors
    ) {
        string canonical_directory = File.new_for_path (directory).get_path ();
        if (canonical_directory == output_directory) {
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
                    scan_directory (path, output_directory, photos, errors);
                } else if (is_photo (path) && FileUtils.test (path, FileTest.IS_REGULAR)) {
                    try {
                        FileInfo info = File.new_for_path (path).query_info (
                            "time::modified", FileQueryInfoFlags.NOFOLLOW_SYMLINKS
                        );
                        photos.add (new PhotoFile (path, info.get_attribute_uint64 ("time::modified")));
                    } catch (Error error) {
                        errors.add ("Could not read modification time for %s: %s".printf (path, error.message));
                        photos.add (new PhotoFile (path, uint64.MAX));
                    }
                }
            }
        } catch (FileError error) {
            errors.add ("Could not scan %s: %s".printf (directory, error.message));
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
            throw new IOError.FAILED ("Output path must not be a symbolic link: %s".printf (path));
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

    public OrganizeResult organize (string source_path, ProgressCallback progress) throws Error {
        string? local_path = File.new_for_path (source_path).get_path ();
        if (local_path == null) {
            throw new FileError.NOTDIR ("Selected folder must be a local directory.");
        }
        string source = local_path;
        if (!FileUtils.test (source, FileTest.IS_DIR)) {
            throw new FileError.NOTDIR ("Selected folder does not exist: %s".printf (source));
        }

        string output = Path.build_filename (source, "Organized Photos");
        if (FileUtils.test (output, FileTest.IS_SYMLINK)) {
            throw new IOError.FAILED ("Output directory must not be a symbolic link: %s".printf (output));
        }
        string canonical_output = File.new_for_path (output).get_path ();

        OrganizeResult result = new OrganizeResult ();
        ArrayList<PhotoFile> photos = new ArrayList<PhotoFile> ();
        progress ("Scanning for photos…", 0, false);
        scan_directory (source, canonical_output, photos, result.errors);
        photos.sort ((a, b) => {
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
                result.errors.add ("Could not read %s: %s".printf (photo.path, error.message));
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
                    "Checking photos (%d of %d)…".printf (i + 1, photos.size),
                    (i + 1) / photo_count * 0.5,
                    true
                );
            }
        }

        ArrayList<PhotoFile> photos_to_move = new ArrayList<PhotoFile> ();
        foreach (Map.Entry<string, ArrayList<PhotoFile>> entry in groups.entries) {
            ArrayList<PhotoFile> group = entry.value;
            if (group.size > 1) {
                result.duplicate_files += group.size - 1;
            }
            photos_to_move.add (group[0]);
        }

        ensure_directory (output);

        int move_step = photos_to_move.size / 100;
        if (move_step < 1) {
            move_step = 1;
        }
        double photos_to_move_count = photos_to_move.size > 0 ? photos_to_move.size : 1;
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
                string year_directory = Path.build_filename (output, captured.format ("%Y"));
                ensure_directory (year_directory);
                string month_directory = Path.build_filename (year_directory, captured.format ("%m"));
                ensure_directory (month_directory);
                destination = unused_destination (month_directory, Path.get_basename (photo.path));
                File.new_for_path (photo.path).move (File.new_for_path (destination), FileCopyFlags.NONE);
                result.photos_moved++;
                moved = true;
            } catch (Error error) {
                result.errors.add ("Could not organize %s: %s".printf (photo.path, error.message));
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
                        "Moved %s but could not set its modification time: %s".printf (destination, error.message)
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
                        "Moved %s but could not set its creation time: %s".printf (destination, error.message)
                    );
                }
            }

            if ((i + 1) % move_step == 0 ||
                i + 1 == photos_to_move.size) {
                progress (
                    "Organizing photos (%d of %d)…".printf (i + 1, photos_to_move.size),
                    0.5 + (i + 1) / photos_to_move_count * 0.5,
                    true
                );
            }
        }
        return result;
    }
}
