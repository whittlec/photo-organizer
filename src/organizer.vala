using GLib;
using Gee;

namespace PhotoOrganizer {
    public class OrganizeResult : Object {
        public uint photos_moved { get; set; }
        public uint duplicate_files { get; set; }
        public uint filesystem_dates { get; set; }
        public ArrayList<string> errors { get; private set; }

        public OrganizeResult () {
            errors = new ArrayList<string> ();
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
        ArrayList<string> photos,
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
                    photos.add (path);
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
        ArrayList<string> photos = new ArrayList<string> ();
        progress ("Scanning for photos…", 0, false);
        scan_directory (source, canonical_output, photos, result.errors);

        HashMap<string, ArrayList<string>> groups = new HashMap<string, ArrayList<string>> ();
        double photo_count = photos.size > 0 ? photos.size : 1;
        int hash_step = photos.size / 100;
        if (hash_step < 1) {
            hash_step = 1;
        }
        for (int i = 0; i < photos.size; i++) {
            string path = photos[i];
            string hash;
            try {
                hash = sha256_file (path);
            } catch (Error error) {
                result.errors.add ("Could not read %s: %s".printf (path, error.message));
                hash = "unreadable:%s".printf (path);
            }
            ArrayList<string>? group = groups.get (hash);
            if (group == null) {
                group = new ArrayList<string> ();
                groups.set (hash, group);
            }
            group.add (path);

            if ((i + 1) % hash_step == 0 || i + 1 == photos.size) {
                progress (
                    "Checking photos (%d of %d)…".printf (i + 1, photos.size),
                    (i + 1) / photo_count * 0.5,
                    true
                );
            }
        }

        ArrayList<string> photos_to_move = new ArrayList<string> ();
        foreach (Map.Entry<string, ArrayList<string>> entry in groups.entries) {
            ArrayList<string> group = entry.value;
            if (group.size > 1) {
                result.duplicate_files += group.size - 1;
            }
            foreach (string path in group) {
                photos_to_move.add (path);
            }
        }

        ensure_directory (output);

        int move_step = photos_to_move.size / 100;
        if (move_step < 1) {
            move_step = 1;
        }
        double photos_to_move_count = photos_to_move.size > 0 ? photos_to_move.size : 1;
        for (int i = 0; i < photos_to_move.size; i++) {
            string photo = photos_to_move[i];
            try {
                DateTime? captured = exif_capture_time (photo);
                if (captured == null) {
                    FileInfo info = File.new_for_path (photo).query_info (
                        "time::modified", FileQueryInfoFlags.NOFOLLOW_SYMLINKS
                    );
                    captured = new DateTime.from_unix_local ((int64) info.get_attribute_uint64 ("time::modified"));
                    result.filesystem_dates++;
                }
                string year_directory = Path.build_filename (output, captured.format ("%Y"));
                ensure_directory (year_directory);
                string month_directory = Path.build_filename (year_directory, captured.format ("%m"));
                ensure_directory (month_directory);
                string destination = unused_destination (month_directory, Path.get_basename (photo));
                File.new_for_path (photo).move (File.new_for_path (destination), FileCopyFlags.NONE);
                result.photos_moved++;
            } catch (Error error) {
                result.errors.add ("Could not organize %s: %s".printf (photo, error.message));
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
