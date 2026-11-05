using Adw;
using GLib;
using Gtk;

namespace PhotoOrganizer {
    public class MainWindow : Adw.ApplicationWindow {
        private Button choose_button;
        private Button organize_button;
        private Label folder_label;
        private Label status_label;
        private ProgressBar progress_bar;
        private string? source_path;

        public MainWindow (Adw.Application application) {
            Object (
                application: application,
                title: _("Photo Organizer"),
                default_width: 620,
                default_height: 420
            );
            set_icon_name ("org.example.PhotoOrganizer");

            Adw.HeaderBar header = new Adw.HeaderBar ();
            Label title = new Label (_("Photo Organizer"));
            title.add_css_class ("title");
            header.set_title_widget (title);
            SimpleAction about_action = new SimpleAction ("about", null);
            about_action.activate.connect (show_about);
            add_action (about_action);

            GLib.Menu menu = new GLib.Menu ();
            menu.append (_("About Photo Organizer"), "win.about");
            MenuButton menu_button = new MenuButton () {
                icon_name = "open-menu-symbolic",
                tooltip_text = _("Main Menu")
            };
            menu_button.set_menu_model (menu);
            header.pack_end (menu_button);

            choose_button = new Button.with_label (_("Choose Photo Folder…"));
            choose_button.clicked.connect (choose_folder);
            folder_label = new Label (_("No folder selected")) {
                xalign = 0,
                wrap = true,
                selectable = true
            };
            Box folder_row = new Box (Orientation.HORIZONTAL, 12);
            folder_row.append (choose_button);
            folder_row.append (folder_label);

            Label explanation = new Label (
                _("Unique photos are organized into YYYY/mm folders in the selected folder. For exact duplicates, a name without a numbered suffix is preferred; otherwise the earliest-modified copy is kept. Other duplicate photos are moved to %s. When capture-date metadata is missing, the file’s modified date is used.")
                    .printf ("Disorganized Photos")
            ) {
                xalign = 0,
                wrap = true
            };
            explanation.add_css_class ("dim-label");

            progress_bar = new ProgressBar () { show_text = true, visible = false };
            status_label = new Label (_("Choose a folder to get started.")) { xalign = 0, wrap = true };
            organize_button = new Button.with_label (_("Analyze and Organize"));
            organize_button.add_css_class ("suggested-action");
            organize_button.set_sensitive (false);
            organize_button.clicked.connect (start_organizing);

            Box content = new Box (Orientation.VERTICAL, 18) {
                margin_top = 24,
                margin_bottom = 24,
                margin_start = 24,
                margin_end = 24
            };
            content.append (folder_row);
            content.append (explanation);
            content.append (progress_bar);
            content.append (status_label);
            content.append (organize_button);
            Adw.ToolbarView layout = new Adw.ToolbarView ();
            layout.add_top_bar (header);
            layout.set_content (content);
            set_content (layout);
        }

        private void show_about () {
            Adw.AboutDialog about = new Adw.AboutDialog ();
            about.set_application_name (_("Photo Organizer"));
            about.set_application_icon ("org.example.PhotoOrganizer");
            about.set_version ("0.1.0");
            about.set_developer_name ("William Whittle");
            about.set_comments (_("Organize photos by capture date and find exact duplicates."));
            about.set_copyright ("© 2026 William Whittle");
            about.set_license_type (Gtk.License.GPL_3_0);
            about.present (this);
        }

        private void choose_folder () {
            Gtk.FileDialog chooser = new Gtk.FileDialog () { title = _("Choose Photo Folder") };
            string? pictures_path = Environment.get_user_special_dir (UserDirectory.PICTURES);
            if (pictures_path != null && FileUtils.test (pictures_path, FileTest.IS_DIR)) {
                chooser.initial_folder = File.new_for_path (pictures_path);
            }
            chooser.select_folder.begin (this, null, (object, response) => {
                try {
                    GLib.File? selected = chooser.select_folder.end (response);
                    string? selected_path = selected == null ? null : selected.get_path ();
                    if (selected_path == null) {
                        return;
                    }
                    source_path = selected_path;
                    folder_label.set_text (selected_path);
                    organize_button.set_sensitive (true);
                    status_label.set_text (_("Ready to analyze the selected folder."));
                } catch (Error error) {
                    if (!error.matches (IOError.quark (), IOError.CANCELLED)) {
                        status_label.set_text (_("Could not choose a folder: %s").printf (error.message));
                    }
                }
            });
        }

        private void start_organizing () {
            if (source_path == null) {
                return;
            }
            choose_button.set_sensitive (false);
            organize_button.set_sensitive (false);
            progress_bar.set_visible (true);
            progress_bar.set_fraction (0);
            status_label.set_text (_("Starting…"));

            string selected_path = source_path;
            new Thread<void*> ("organize-photos", () => {
                try {
                    OrganizeResult result = organize (selected_path, (message, fraction, determinate) => {
                        Idle.add (() => {
                            status_label.set_text (message);
                            if (determinate) {
                                progress_bar.set_fraction (fraction);
                                progress_bar.set_text (_("%.0f%%").printf (fraction * 100));
                            } else {
                                progress_bar.pulse ();
                            }
                            return Source.REMOVE;
                        });
                    });
                    Idle.add (() => {
                        show_result (result);
                        return Source.REMOVE;
                    });
                } catch (Error error) {
                    string message = error.message;
                    Idle.add (() => {
                        show_failure (message);
                        return Source.REMOVE;
                    });
                }
                return null;
            });
        }

        private void show_result (OrganizeResult result) {
            string summary =
                "%s %s %s".printf (
                    ngettext ("Moved %u unique photo.", "Moved %u unique photos.", result.photos_moved)
                        .printf (result.photos_moved),
                    ngettext (
                        "Moved %u duplicate photo to Disorganized Photos.",
                        "Moved %u duplicate photos to Disorganized Photos.",
                        result.duplicate_files_moved
                    ).printf (result.duplicate_files_moved),
                    ngettext (
                        "Used the file date for %u photo.",
                        "Used the file date for %u photos.",
                        result.filesystem_dates
                    ).printf (result.filesystem_dates)
                );
            if (result.errors.size > 0) {
                string[] details = {};
                int message_count = result.errors.size < 3 ? result.errors.size : 3;
                for (int i = 0; i < message_count; i++) {
                    details += result.errors[i];
                }
                summary += " " + ngettext ("%u issue: %s", "%u issues: %s", result.errors.size)
                    .printf (result.errors.size, string.joinv (" ", details));
            }
            if (result.creation_times_unavailable > 0) {
                summary += " " + ngettext (
                    "The file system did not allow setting the creation time for %u photo; modification times were set where possible.",
                    "The file system did not allow setting the creation time for %u photos; modification times were set where possible.",
                    result.creation_times_unavailable
                ).printf (
                    result.creation_times_unavailable
                );
            }
            status_label.set_text (summary);
            finish ();
        }

        private void show_failure (string message) {
            status_label.set_text (_("Could not organize photos: %s").printf (message));
            finish ();
        }

        private void finish () {
            choose_button.set_sensitive (true);
            organize_button.set_sensitive (source_path != null);
            progress_bar.set_fraction (1);
            progress_bar.set_text (_("Complete"));
        }
    }

    public class Application : Adw.Application {
        public Application () {
            Object (
                application_id: "org.example.PhotoOrganizer",
                flags: ApplicationFlags.DEFAULT_FLAGS
            );
        }

        protected override void activate () {
            Gtk.Window? window = active_window;
            if (window == null) {
                window = new MainWindow (this);
            }
            window.present ();
        }
    }

    public static int main (string[] args) {
        Intl.setlocale (LocaleCategory.MESSAGES, "");
        Intl.bindtextdomain (GETTEXT_PACKAGE, LOCALEDIR);
        Intl.bind_textdomain_codeset (GETTEXT_PACKAGE, "UTF-8");
        Intl.textdomain (GETTEXT_PACKAGE);
        Adw.init ();
        Application application = new Application ();
        return application.run (args);
    }
}
