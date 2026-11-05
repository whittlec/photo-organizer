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

    private void write_photo_with_exif_tag (string path, string tag, string value) {
        try {
            Gdk.Pixbuf image = new Gdk.Pixbuf (Gdk.Colorspace.RGB, false, 8, 2, 2);
            image.fill ((uint32) 0x808080ff);
            image.savev (path, "jpeg", null, null);
            GExiv2.Metadata metadata = new GExiv2.Metadata ();
            metadata.open_path (path);
            metadata.try_set_tag_string (tag, value);
            metadata.save_file (path);
        } catch (Error error) {
            Test.fail_printf ("Could not create EXIF test photo: %s", error.message);
        }
    }

    private void write_photo_with_exif (string path) {
        write_photo_with_exif_tag (path, "Exif.Photo.DateTimeOriginal", "2020:03:04 05:06:07");
    }

    private OrganizeResult organize_temporary_directory (string path, string? protected_wallpaper_directory = null) {
        try {
            return organize (path, (message, fraction, determinate) => {}, protected_wallpaper_directory);
        } catch (Error error) {
            Test.fail_printf ("Could not organize test directory: %s", error.message);
            return new OrganizeResult ();
        }
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

    private void test_organizes_one_copy_and_moves_duplicates_aside () {
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
        DateTime captured = new DateTime.from_unix_local (1600000000);
        string organized = Path.build_filename (temporary, captured.format ("%Y"), captured.format ("%m"), "duplicate.jpg");
        string disorganized = Path.build_filename (temporary, "Disorganized Photos", "first.jpg");
        GLib.assert_cmpuint ((uint) result.errors.size, CompareOperator.EQ, 0);
        GLib.assert_cmpuint (result.photos_moved, CompareOperator.EQ, 1);
        GLib.assert_cmpuint (result.duplicate_files, CompareOperator.EQ, 1);
        GLib.assert_cmpuint (result.duplicate_files_moved, CompareOperator.EQ, 1);
        GLib.assert_cmpuint (result.filesystem_dates, CompareOperator.EQ, 1);
        GLib.assert_true (FileUtils.test (organized, FileTest.EXISTS));
        GLib.assert_true (FileUtils.test (disorganized, FileTest.EXISTS));
        GLib.assert_false (FileUtils.test (first, FileTest.EXISTS));
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
        DateTime captured = new DateTime.from_unix_local (1700000000);
        string organized = Path.build_filename (temporary, captured.format ("%Y"), captured.format ("%m"), "photo.jpg");
        string disorganized = Path.build_filename (temporary, "Disorganized Photos", "photo (2).jpg");
        GLib.assert_cmpuint ((uint) result.errors.size, CompareOperator.EQ, 0);
        GLib.assert_cmpuint (result.photos_moved, CompareOperator.EQ, 1);
        GLib.assert_cmpuint (result.duplicate_files, CompareOperator.EQ, 1);
        GLib.assert_cmpuint (result.duplicate_files_moved, CompareOperator.EQ, 1);
        GLib.assert_true (FileUtils.test (organized, FileTest.EXISTS));
        GLib.assert_true (FileUtils.test (disorganized, FileTest.EXISTS));
        GLib.assert_false (FileUtils.test (original, FileTest.EXISTS));
        GLib.assert_false (FileUtils.test (suffixed_copy, FileTest.EXISTS));
        remove_tree (temporary);
    }

    private void test_avoids_overwriting_existing_photos () {
        string temporary = make_temporary_directory ();
        string photo = Path.build_filename (temporary, "same.png");
        write_file (photo, "new photo");
        DateTime now = new DateTime.now_local ();
        string output_directory = Path.build_filename (
            temporary, now.format ("%Y"), now.format ("%m")
        );
        DirUtils.create_with_parents (output_directory, 0755);
        string existing = Path.build_filename (output_directory, "same.png");
        write_file (existing, "existing photo");

        OrganizeResult result = organize_temporary_directory (temporary);
        string collision = Path.build_filename (output_directory, "same (2).png");
        GLib.assert_cmpuint (result.photos_moved, CompareOperator.EQ, 1);
        GLib.assert_cmpuint ((uint) result.errors.size, CompareOperator.EQ, 0);
        GLib.assert_true (FileUtils.test (existing, FileTest.EXISTS));
        GLib.assert_true (FileUtils.test (collision, FileTest.EXISTS));
        string? contents = null;
        try {
            FileUtils.get_contents (existing, out contents);
        } catch (Error error) {
            Test.fail_printf ("Could not read existing photo: %s", error.message);
        }
        GLib.assert_cmpstr (contents, CompareOperator.EQ, "existing photo");
        try {
            FileUtils.get_contents (collision, out contents);
        } catch (Error error) {
            Test.fail_printf ("Could not read collision photo: %s", error.message);
        }
        GLib.assert_cmpstr (contents, CompareOperator.EQ, "new photo");
        remove_tree (temporary);
    }

    private void test_organizes_by_exif_capture_date () {
        string temporary = make_temporary_directory ();
        write_photo_with_exif (Path.build_filename (temporary, "captured.jpg"));

        OrganizeResult result = organize_temporary_directory (temporary);
        string organized_photo = Path.build_filename (
            temporary, "2020", "03", "captured.jpg"
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

    private void test_uses_digitized_date_when_original_date_is_missing () {
        string temporary = make_temporary_directory ();
        string photo = Path.build_filename (temporary, "digitized.jpg");
        write_photo_with_exif_tag (photo, "Exif.Photo.DateTimeDigitized", "2019:11:12 13:14:15");

        OrganizeResult result = organize_temporary_directory (temporary);
        string organized_photo = Path.build_filename (temporary, "2019", "11", "digitized.jpg");

        GLib.assert_cmpuint ((uint) result.errors.size, CompareOperator.EQ, 0);
        GLib.assert_cmpuint (result.photos_moved, CompareOperator.EQ, 1);
        GLib.assert_cmpuint (result.filesystem_dates, CompareOperator.EQ, 0);
        GLib.assert_true (FileUtils.test (organized_photo, FileTest.EXISTS));
        GLib.assert_true (
            get_modified_time (organized_photo) ==
            (uint64) new DateTime.local (2019, 11, 12, 13, 14, 15).to_unix ()
        );
        remove_tree (temporary);
    }

    private void test_falls_back_to_file_date_for_invalid_exif () {
        string temporary = make_temporary_directory ();
        string photo = Path.build_filename (temporary, "invalid-exif.jpg");
        write_photo_with_exif_tag (photo, "Exif.Photo.DateTimeOriginal", "not a valid date");
        set_modified_time (photo, 1600000000);
        DateTime captured = new DateTime.from_unix_local (1600000000);

        OrganizeResult result = organize_temporary_directory (temporary);
        string organized_photo = Path.build_filename (
            temporary, captured.format ("%Y"), captured.format ("%m"), "invalid-exif.jpg"
        );

        GLib.assert_cmpuint ((uint) result.errors.size, CompareOperator.EQ, 0);
        GLib.assert_cmpuint (result.photos_moved, CompareOperator.EQ, 1);
        GLib.assert_cmpuint (result.filesystem_dates, CompareOperator.EQ, 1);
        GLib.assert_true (FileUtils.test (organized_photo, FileTest.EXISTS));
        remove_tree (temporary);
    }

    private void test_ignores_non_photo_files_and_accepts_case_insensitive_extensions () {
        string temporary = make_temporary_directory ();
        string uppercase_photo = Path.build_filename (temporary, "PHOTO.JpG");
        string document = Path.build_filename (temporary, "notes.txt");
        write_file (uppercase_photo, "photo");
        write_file (document, "not a photo");
        DateTime captured = new DateTime.from_unix_local ((int64) get_modified_time (uppercase_photo));
        string organized_photo = Path.build_filename (
            temporary, captured.format ("%Y"), captured.format ("%m"), "PHOTO.JpG"
        );

        OrganizeResult result = organize_temporary_directory (temporary);

        GLib.assert_cmpuint ((uint) result.errors.size, CompareOperator.EQ, 0);
        GLib.assert_cmpuint (result.photos_moved, CompareOperator.EQ, 1);
        GLib.assert_true (FileUtils.test (organized_photo, FileTest.EXISTS));
        GLib.assert_true (FileUtils.test (document, FileTest.EXISTS));
        remove_tree (temporary);
    }

    private void test_moves_all_extra_copies_of_three_identical_photos () {
        string temporary = make_temporary_directory ();
        string first = Path.build_filename (temporary, "one.jpg");
        string second = Path.build_filename (temporary, "two.jpg");
        string third = Path.build_filename (temporary, "three.jpg");
        write_file (first, "same photo");
        write_file (second, "same photo");
        write_file (third, "same photo");
        set_modified_time (first, 1700000000);
        set_modified_time (second, 1600000000);
        set_modified_time (third, 1500000000);
        DateTime captured = new DateTime.from_unix_local (1500000000);

        OrganizeResult result = organize_temporary_directory (temporary);

        GLib.assert_cmpuint ((uint) result.errors.size, CompareOperator.EQ, 0);
        GLib.assert_cmpuint (result.photos_moved, CompareOperator.EQ, 1);
        GLib.assert_cmpuint (result.duplicate_files, CompareOperator.EQ, 2);
        GLib.assert_cmpuint (result.duplicate_files_moved, CompareOperator.EQ, 2);
        GLib.assert_true (FileUtils.test (Path.build_filename (
            temporary, captured.format ("%Y"), captured.format ("%m"), "three.jpg"
        ), FileTest.EXISTS));
        GLib.assert_true (FileUtils.test (Path.build_filename (temporary, "Disorganized Photos", "one.jpg"), FileTest.EXISTS));
        GLib.assert_true (FileUtils.test (Path.build_filename (temporary, "Disorganized Photos", "two.jpg"), FileTest.EXISTS));
        remove_tree (temporary);
    }

    private void test_empty_and_non_photo_folders_do_not_create_output () {
        string temporary = make_temporary_directory ();
        write_file (Path.build_filename (temporary, "notes.txt"), "not a photo");
        uint progress_events = 0;
        bool first_event_is_indeterminate = false;
        OrganizeResult result;
        try {
            result = organize (temporary, (message, fraction, determinate) => {
                if (progress_events == 0) {
                    first_event_is_indeterminate = !determinate && fraction == 0;
                }
                progress_events++;
            });
        } catch (Error error) {
            Test.fail_printf ("Could not organize empty test directory: %s", error.message);
            remove_tree (temporary);
            return;
        }

        GLib.assert_cmpuint ((uint) result.errors.size, CompareOperator.EQ, 0);
        GLib.assert_cmpuint (result.photos_moved, CompareOperator.EQ, 0);
        GLib.assert_cmpuint (result.duplicate_files, CompareOperator.EQ, 0);
        GLib.assert_cmpuint (progress_events, CompareOperator.EQ, 1);
        GLib.assert_true (first_event_is_indeterminate);
        GLib.assert_false (FileUtils.test (Path.build_filename (temporary, "Disorganized Photos"), FileTest.EXISTS));
        remove_tree (temporary);
    }

    private void test_progress_is_determinate_monotonic_and_finishes_at_one () {
        string temporary = make_temporary_directory ();
        write_file (Path.build_filename (temporary, "one.jpg"), "first");
        write_file (Path.build_filename (temporary, "two.jpg"), "second");
        double last_fraction = 0;
        bool saw_indeterminate = false;
        bool saw_determinate = false;
        bool monotonic = true;
        OrganizeResult result;
        try {
            result = organize (temporary, (message, fraction, determinate) => {
                if (!determinate) {
                    saw_indeterminate = true;
                    return;
                }
                saw_determinate = true;
                if (fraction < last_fraction || fraction < 0 || fraction > 1) {
                    monotonic = false;
                }
                last_fraction = fraction;
            });
        } catch (Error error) {
            Test.fail_printf ("Could not organize progress test directory: %s", error.message);
            remove_tree (temporary);
            return;
        }

        GLib.assert_cmpuint ((uint) result.errors.size, CompareOperator.EQ, 0);
        GLib.assert_true (saw_indeterminate);
        GLib.assert_true (saw_determinate);
        GLib.assert_true (monotonic);
        GLib.assert_cmpfloat (last_fraction, CompareOperator.EQ, 1.0);
        remove_tree (temporary);
    }

    private void test_disorganized_folder_is_ignored_on_repeat_run () {
        string temporary = make_temporary_directory ();
        string disorganized = Path.build_filename (temporary, "Disorganized Photos");
        DirUtils.create (disorganized, 0755);
        string photo = Path.build_filename (disorganized, "photo.jpg");
        write_file (photo, "leave this aside");

        OrganizeResult result = organize_temporary_directory (temporary);

        GLib.assert_cmpuint ((uint) result.errors.size, CompareOperator.EQ, 0);
        GLib.assert_cmpuint (result.photos_moved, CompareOperator.EQ, 0);
        GLib.assert_cmpuint (result.duplicate_files, CompareOperator.EQ, 0);
        GLib.assert_true (FileUtils.test (photo, FileTest.EXISTS));
        remove_tree (temporary);
    }

    private void test_symlinked_photos_and_directories_are_not_followed () {
        string temporary = make_temporary_directory ();
        string outside = make_temporary_directory ();
        string external_photo = Path.build_filename (outside, "external.jpg");
        write_file (external_photo, "external photo");
        string photo_link = Path.build_filename (temporary, "linked.jpg");
        string directory_link = Path.build_filename (temporary, "linked-directory");
        try {
            File.new_for_path (photo_link).make_symbolic_link (external_photo);
            File.new_for_path (directory_link).make_symbolic_link (outside);
        } catch (Error error) {
            Test.skip_printf ("Symbolic links are unavailable: %s", error.message);
            remove_tree (temporary);
            remove_tree (outside);
            return;
        }

        OrganizeResult result = organize_temporary_directory (temporary);

        GLib.assert_cmpuint ((uint) result.errors.size, CompareOperator.EQ, 0);
        GLib.assert_cmpuint (result.photos_moved, CompareOperator.EQ, 0);
        GLib.assert_true (FileUtils.test (external_photo, FileTest.EXISTS));
        GLib.assert_true (FileUtils.test (photo_link, FileTest.IS_SYMLINK));
        GLib.assert_true (FileUtils.test (directory_link, FileTest.IS_SYMLINK));
        remove_tree (temporary);
        remove_tree (outside);
    }

    private void test_rejects_missing_source_directory () {
        string temporary = make_temporary_directory ();
        string missing = Path.build_filename (temporary, "missing");
        bool failed = false;
        try {
            organize (missing, (message, fraction, determinate) => {});
        } catch (FileError error) {
            failed = error.code == FileError.NOTDIR;
        } catch (Error error) {
            Test.fail_printf ("Unexpected error for missing source directory: %s", error.message);
        }
        GLib.assert_true (failed);
        remove_tree (temporary);
    }

    private void test_rejects_disorganized_output_symlink () {
        string temporary = make_temporary_directory ();
        string target = make_temporary_directory ();
        string output_link = Path.build_filename (temporary, "Disorganized Photos");
        bool failed = false;
        try {
            File.new_for_path (output_link).make_symbolic_link (target);
        } catch (Error error) {
            Test.skip_printf ("Symbolic links are unavailable: %s", error.message);
            remove_tree (temporary);
            remove_tree (target);
            return;
        }
        try {
            organize (temporary, (message, fraction, determinate) => {});
        } catch (IOError error) {
            failed = error.code == IOError.FAILED;
        } catch (Error error) {
            Test.fail_printf ("Unexpected error for output symlink: %s", error.message);
        }
        GLib.assert_true (failed);
        remove_tree (temporary);
        remove_tree (target);
    }

    private void test_organized_folders_are_not_scanned_again () {
        string temporary = make_temporary_directory ();
        string photo = Path.build_filename (temporary, "photo.jpg");
        write_file (photo, "one photo");
        DateTime captured = new DateTime.from_unix_local ((int64) get_modified_time (photo));
        string organized = Path.build_filename (
            temporary, captured.format ("%Y"), captured.format ("%m"), "photo.jpg"
        );

        OrganizeResult first_result = organize_temporary_directory (temporary);
        OrganizeResult second_result = organize_temporary_directory (temporary);

        GLib.assert_cmpuint (first_result.photos_moved, CompareOperator.EQ, 1);
        GLib.assert_cmpuint (second_result.photos_moved, CompareOperator.EQ, 0);
        GLib.assert_cmpuint (second_result.duplicate_files, CompareOperator.EQ, 0);
        GLib.assert_cmpuint ((uint) second_result.errors.size, CompareOperator.EQ, 0);
        GLib.assert_true (FileUtils.test (organized, FileTest.EXISTS));
        remove_tree (temporary);
    }

    private void test_existing_organized_photo_wins_over_new_duplicate () {
        string temporary = make_temporary_directory ();
        string existing = Path.build_filename (temporary, "2020", "03", "photo.jpg");
        DirUtils.create_with_parents (Path.get_dirname (existing), 0755);
        write_file (existing, "identical photo bytes");
        string new_copy = Path.build_filename (temporary, "incoming", "photo (2).jpg");
        DirUtils.create (Path.get_dirname (new_copy), 0755);
        write_file (new_copy, "identical photo bytes");

        OrganizeResult result = organize_temporary_directory (temporary);
        string duplicate = Path.build_filename (temporary, "Disorganized Photos", "photo (2).jpg");

        GLib.assert_cmpuint ((uint) result.errors.size, CompareOperator.EQ, 0);
        GLib.assert_cmpuint (result.photos_moved, CompareOperator.EQ, 0);
        GLib.assert_cmpuint (result.duplicate_files, CompareOperator.EQ, 1);
        GLib.assert_cmpuint (result.duplicate_files_moved, CompareOperator.EQ, 1);
        GLib.assert_true (FileUtils.test (existing, FileTest.EXISTS));
        GLib.assert_true (FileUtils.test (duplicate, FileTest.EXISTS));
        GLib.assert_false (FileUtils.test (new_copy, FileTest.EXISTS));
        remove_tree (temporary);
    }

    private void test_moves_photos_from_legacy_organized_folder () {
        string temporary = make_temporary_directory ();
        string legacy_photo = Path.build_filename (temporary, "Organized Photos", "2020", "03", "photo.jpg");
        DirUtils.create_with_parents (Path.get_dirname (legacy_photo), 0755);
        write_file (legacy_photo, "legacy photo");
        set_modified_time (legacy_photo, 1600000000);

        OrganizeResult result = organize_temporary_directory (temporary);
        DateTime captured = new DateTime.from_unix_local (1600000000);
        string organized_photo = Path.build_filename (
            temporary, captured.format ("%Y"), captured.format ("%m"), "photo.jpg"
        );

        GLib.assert_cmpuint ((uint) result.errors.size, CompareOperator.EQ, 0);
        GLib.assert_cmpuint (result.photos_moved, CompareOperator.EQ, 1);
        GLib.assert_true (FileUtils.test (organized_photo, FileTest.EXISTS));
        GLib.assert_false (FileUtils.test (legacy_photo, FileTest.EXISTS));
        remove_tree (temporary);
    }

    private void test_scans_year_named_input_folder_without_month_folders () {
        string temporary = make_temporary_directory ();
        string input_year = Path.build_filename (temporary, "2020");
        DirUtils.create (input_year, 0755);
        string photo = Path.build_filename (input_year, "photo.jpg");
        write_file (photo, "photo in year folder");
        set_modified_time (photo, 1600000000);

        OrganizeResult result = organize_temporary_directory (temporary);
        DateTime captured = new DateTime.from_unix_local (1600000000);
        string organized_photo = Path.build_filename (
            temporary, "2020", captured.format ("%m"), "photo.jpg"
        );

        GLib.assert_cmpuint ((uint) result.errors.size, CompareOperator.EQ, 0);
        GLib.assert_cmpuint (result.photos_moved, CompareOperator.EQ, 1);
        GLib.assert_true (FileUtils.test (organized_photo, FileTest.EXISTS));
        remove_tree (temporary);
    }

    private void test_leaves_wallpaper_slideshow_directory_alone () {
        string temporary = make_temporary_directory ();
        string wallpaper_directory = Path.build_filename (temporary, "wallpaper-slideshow");
        DirUtils.create (wallpaper_directory, 0755);
        string wallpaper = Path.build_filename (wallpaper_directory, "wallpaper.jpg");
        write_file (wallpaper, "wallpaper image");
        string regular_photo = Path.build_filename (temporary, "photo.jpg");
        write_file (regular_photo, "photo to organize");
        DateTime captured = new DateTime.from_unix_local ((int64) get_modified_time (regular_photo));
        string organized_photo = Path.build_filename (
            temporary, captured.format ("%Y"), captured.format ("%m"), "photo.jpg"
        );

        OrganizeResult result = organize_temporary_directory (temporary, wallpaper_directory);

        GLib.assert_cmpuint ((uint) result.errors.size, CompareOperator.EQ, 0);
        GLib.assert_cmpuint (result.photos_moved, CompareOperator.EQ, 1);
        GLib.assert_true (FileUtils.test (wallpaper, FileTest.EXISTS));
        GLib.assert_false (FileUtils.test (regular_photo, FileTest.EXISTS));
        GLib.assert_true (FileUtils.test (organized_photo, FileTest.EXISTS));
        remove_tree (temporary);
    }

    public static int main (string[] args) {
        Test.init (ref args);
        Test.add_func ("/organizer/organizes-one-copy-and-moves-duplicates-aside", test_organizes_one_copy_and_moves_duplicates_aside);
        Test.add_func ("/organizer/prefers-unsuffixed-name", test_prefers_unsuffixed_name_over_earlier_suffixed_copy);
        Test.add_func ("/organizer/avoids-overwriting", test_avoids_overwriting_existing_photos);
        Test.add_func ("/organizer/uses-exif-capture-date", test_organizes_by_exif_capture_date);
        Test.add_func ("/organizer/skips-organized-folders-on-rerun", test_organized_folders_are_not_scanned_again);
        Test.add_func ("/organizer/existing-organized-photo-wins", test_existing_organized_photo_wins_over_new_duplicate);
        Test.add_func ("/organizer/moves-legacy-organized-photos", test_moves_photos_from_legacy_organized_folder);
        Test.add_func ("/organizer/scans-unorganized-year-folder", test_scans_year_named_input_folder_without_month_folders);
        Test.add_func ("/organizer/leaves-wallpaper-slideshow-directory-alone", test_leaves_wallpaper_slideshow_directory_alone);
        Test.add_func ("/organizer/empty-folder-progress", test_empty_and_non_photo_folders_do_not_create_output);
        Test.add_func ("/organizer/progress-is-monotonic", test_progress_is_determinate_monotonic_and_finishes_at_one);
        Test.add_func ("/organizer/ignores-disorganized-folder", test_disorganized_folder_is_ignored_on_repeat_run);
        Test.add_func ("/organizer/does-not-follow-symlinks", test_symlinked_photos_and_directories_are_not_followed);
        Test.add_func ("/organizer/rejects-missing-source", test_rejects_missing_source_directory);
        Test.add_func ("/organizer/rejects-output-symlink", test_rejects_disorganized_output_symlink);
        Test.add_func ("/organizer/uses-digitized-exif-date", test_uses_digitized_date_when_original_date_is_missing);
        Test.add_func ("/organizer/falls-back-on-invalid-exif", test_falls_back_to_file_date_for_invalid_exif);
        Test.add_func ("/organizer/filters-photo-formats", test_ignores_non_photo_files_and_accepts_case_insensitive_extensions);
        Test.add_func ("/organizer/moves-all-duplicate-copies", test_moves_all_extra_copies_of_three_identical_photos);
        return Test.run ();
    }
}
