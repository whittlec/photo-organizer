using GLib;

namespace PhotoOrganizer.Tests {
    private string make_temporary_directory () {
        return DirUtils.mkdtemp ("photo-organizer-test-XXXXXX");
    }

    private void write_file (string path, string contents) {
        try {
            FileUtils.set_contents (path, contents);
        } catch (Error error) {
            Test.fail_printf ("Could not create test file: %s", error.message);
        }
    }

    private void set_modified_time (string path, uint64 timestamp) {
        try {
            File.new_for_path (path).set_attribute_uint64 (
                "time::modified",
                timestamp,
                FileQueryInfoFlags.NONE
            );
        } catch (Error error) {
            Test.fail_printf ("Could not set test modification time: %s", error.message);
        }
    }

    private uint64 get_modified_time (string path) {
        try {
            FileInfo info = File.new_for_path (path).query_info (
                "time::modified", FileQueryInfoFlags.NONE
            );
            return info.get_attribute_uint64 ("time::modified");
        } catch (Error error) {
            Test.fail_printf ("Could not read test modification time: %s", error.message);
            return 0;
        }
    }

    private void write_photo_with_exif (string path) {
        try {
            Gdk.Pixbuf image = new Gdk.Pixbuf (Gdk.Colorspace.RGB, false, 8, 2, 2);
            image.fill ((uint32) 0x808080ff);
            image.savev (path, "jpeg", null, null);
            GExiv2.Metadata metadata = new GExiv2.Metadata ();
            metadata.open_path (path);
            metadata.try_set_tag_string ("Exif.Photo.DateTimeOriginal", "2020:03:04 05:06:07");
            metadata.save_file (path);
        } catch (Error error) {
            Test.fail_printf ("Could not create EXIF test photo: %s", error.message);
        }
    }

    private OrganizeResult organize_temporary_directory (string path) {
        try {
            return organize (path, (message, fraction, determinate) => {});
        } catch (Error error) {
            Test.fail_printf ("Could not organize test directory: %s", error.message);
            return new OrganizeResult ();
        }
    }

    private uint count_files (string directory_path) {
        uint count = 0;
        try {
            Dir directory = Dir.open (directory_path);
            string? name;
            while ((name = directory.read_name ()) != null) {
                string path = Path.build_filename (directory_path, name);
                count += FileUtils.test (path, FileTest.IS_DIR) ? count_files (path) : 1;
            }
        } catch (Error error) {
            Test.fail_printf ("Could not inspect test directory: %s", error.message);
        }
        return count;
    }

    private void remove_tree (string path) {
        if (FileUtils.test (path, FileTest.IS_DIR)) {
            try {
                Dir directory = Dir.open (path);
                string? name;
                while ((name = directory.read_name ()) != null) {
                    remove_tree (Path.build_filename (path, name));
                }
            } catch (Error error) {
                Test.fail_printf ("Could not clean test directory: %s", error.message);
            }
        }
        try {
            File.new_for_path (path).delete ();
        } catch (Error error) {
            Test.fail_printf ("Could not remove test file: %s", error.message);
        }
    }

    private void test_moves_one_copy_and_leaves_duplicates_in_place () {
        string temporary = make_temporary_directory ();
        string nested = Path.build_filename (temporary, "nested");
        DirUtils.create (nested, 0755);
        string first = Path.build_filename (temporary, "first.jpg");
        string duplicate = Path.build_filename (nested, "duplicate.jpg");
        write_file (first, "same photo");
        write_file (duplicate, "same photo");
        set_modified_time (first, 1700000000);
        set_modified_time (duplicate, 1600000000);

        OrganizeResult result = organize_temporary_directory (temporary);
        string output = Path.build_filename (temporary, "Organized Photos");
        GLib.assert_cmpuint ((uint) result.errors.size, CompareOperator.EQ, 0);
        GLib.assert_cmpuint (result.photos_moved, CompareOperator.EQ, 1);
        GLib.assert_cmpuint (result.duplicate_files, CompareOperator.EQ, 1);
        GLib.assert_cmpuint (result.filesystem_dates, CompareOperator.EQ, 1);
        GLib.assert_cmpuint (count_files (output), CompareOperator.EQ, 1);
        GLib.assert_true (FileUtils.test (first, FileTest.EXISTS));
        GLib.assert_false (FileUtils.test (duplicate, FileTest.EXISTS));
        remove_tree (temporary);
    }

    private void test_prefers_unsuffixed_name_over_earlier_suffixed_copy () {
        string temporary = make_temporary_directory ();
        string original = Path.build_filename (temporary, "photo.jpg");
        string suffixed_copy = Path.build_filename (temporary, "photo (2).jpg");
        write_file (original, "same photo");
        write_file (suffixed_copy, "same photo");
        set_modified_time (suffixed_copy, 1500000000);
        set_modified_time (original, 1700000000);

        OrganizeResult result = organize_temporary_directory (temporary);
        string output = Path.build_filename (temporary, "Organized Photos");
        GLib.assert_cmpuint ((uint) result.errors.size, CompareOperator.EQ, 0);
        GLib.assert_cmpuint (result.photos_moved, CompareOperator.EQ, 1);
        GLib.assert_cmpuint (result.duplicate_files, CompareOperator.EQ, 1);
        GLib.assert_true (FileUtils.test (suffixed_copy, FileTest.EXISTS));
        GLib.assert_false (FileUtils.test (original, FileTest.EXISTS));
        GLib.assert_cmpuint (count_files (output), CompareOperator.EQ, 1);
        remove_tree (temporary);
    }

    private void test_avoids_overwriting_existing_photos () {
        string temporary = make_temporary_directory ();
        string photo = Path.build_filename (temporary, "same.png");
        write_file (photo, "new photo");
        DateTime now = new DateTime.now_local ();
        string output_directory = Path.build_filename (
            temporary, "Organized Photos", now.format ("%Y"), now.format ("%m")
        );
        DirUtils.create_with_parents (output_directory, 0755);
        string existing = Path.build_filename (output_directory, "same.png");
        write_file (existing, "existing photo");

        OrganizeResult result = organize_temporary_directory (temporary);
        GLib.assert_cmpuint (result.photos_moved, CompareOperator.EQ, 1);
        GLib.assert_true (FileUtils.test (Path.build_filename (output_directory, "same (2).png"), FileTest.EXISTS));
        remove_tree (temporary);
    }

    private void test_organizes_by_exif_capture_date () {
        string temporary = make_temporary_directory ();
        write_photo_with_exif (Path.build_filename (temporary, "captured.jpg"));

        OrganizeResult result = organize_temporary_directory (temporary);
        string organized_photo = Path.build_filename (
            temporary, "Organized Photos", "2020", "03", "captured.jpg"
        );
        GLib.assert_cmpuint ((uint) result.errors.size, CompareOperator.EQ, 0);
        GLib.assert_cmpuint (result.photos_moved, CompareOperator.EQ, 1);
        GLib.assert_cmpuint (result.filesystem_dates, CompareOperator.EQ, 0);
        GLib.assert_true (FileUtils.test (organized_photo, FileTest.EXISTS));
        GLib.assert_true (
            get_modified_time (organized_photo) ==
            (uint64) new DateTime.local (2020, 3, 4, 5, 6, 7).to_unix ()
        );
        remove_tree (temporary);
    }

    public static int main (string[] args) {
        Test.init (ref args);
        Test.add_func ("/organizer/moves-one-copy-and-leaves-duplicates", test_moves_one_copy_and_leaves_duplicates_in_place);
        Test.add_func ("/organizer/prefers-unsuffixed-name", test_prefers_unsuffixed_name_over_earlier_suffixed_copy);
        Test.add_func ("/organizer/avoids-overwriting", test_avoids_overwriting_existing_photos);
        Test.add_func ("/organizer/uses-exif-capture-date", test_organizes_by_exif_capture_date);
        return Test.run ();
    }
}
