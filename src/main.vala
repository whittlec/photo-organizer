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
            Object (application: application, title: "Photo Organizer", default_width: 620, default_height: 420);

            Adw.HeaderBar header = new Adw.HeaderBar ();
            Label title = new Label ("Photo Organizer");
            title.add_css_class ("title");
            header.set_title_widget (title);
            SimpleAction about_action = new SimpleAction ("about", null);
            about_action.activate.connect (show_about);
            add_action (about_action);

            GLib.Menu menu = new GLib.Menu ();
            menu.append ("About Photo Organizer", "win.about");
            MenuButton menu_button = new MenuButton () {
                icon_name = "open-menu-symbolic",
                tooltip_text = "Main Menu"
            };
            menu_button.set_menu_model (menu);
            header.pack_end (menu_button);

            choose_button = new Button.with_label ("Choose Photo Folder…");
            choose_button.clicked.connect (choose_folder);
            folder_label = new Label ("No folder selected") {
                xalign = 0,
                wrap = true,
                selectable = true
            };
            Box folder_row = new Box (Orientation.HORIZONTAL, 12);
            folder_row.append (choose_button);
            folder_row.append (folder_label);

            Label explanation = new Label (
                "For exact duplicates, a name without a numbered suffix is preferred; otherwise the earliest-modified copy is moved into Organized Photos/YYYY/mm. Additional duplicates are counted and left where they are. When capture-date metadata is missing, the file’s modified date is used."
            ) {
                xalign = 0,
                wrap = true
            };
            explanation.add_css_class ("dim-label");

            progress_bar = new ProgressBar () { show_text = true, visible = false };
            status_label = new Label ("Choose a folder to get started.") { xalign = 0, wrap = true };
            organize_button = new Button.with_label ("Analyze and Organize");
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
            about.set_application_name ("Photo Organizer");
            about.set_version ("0.1.0");
            about.set_developer_name ("Photo Organizer contributors");
            about.set_comments (
                "Organize photos by capture date and find exact duplicates."
            );
            about.present (this);
        }

        private void choose_folder () {
            Gtk.FileDialog chooser = new Gtk.FileDialog () { title = "Choose Photo Folder" };
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
                    status_label.set_text ("Ready to analyze the selected folder.");
                } catch (Error error) {
                    if (!error.matches (IOError.quark (), IOError.CANCELLED)) {
                        status_label.set_text ("Could not choose a folder: %s".printf (error.message));
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
            status_label.set_text ("Starting…");

            string selected_path = source_path;
            new Thread<void*> ("organize-photos", () => {
                try {
                    OrganizeResult result = organize (selected_path, (message, fraction, determinate) => {
                        Idle.add (() => {
                            status_label.set_text (message);
                            if (determinate) {
                                progress_bar.set_fraction (fraction);
                                progress_bar.set_text ("%.0f%%".printf (fraction * 100));
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
                "Moved %u unique photo(s). Skipped %u duplicate file(s), leaving them in place. Used file dates for %u photo(s).".printf (
                    result.photos_moved, result.duplicate_files, result.filesystem_dates
                );
            if (result.errors.size > 0) {
                string details = "";
                int message_count = result.errors.size < 3 ? result.errors.size : 3;
                for (int i = 0; i < message_count; i++) {
                    if (i > 0) {
                        details += " ";
                    }
                    details += result.errors[i];
                }
                summary += " %d issue(s): %s".printf (result.errors.size, details);
            }
            status_label.set_text (summary);
            finish ();
        }

        private void show_failure (string message) {
            status_label.set_text ("Could not organize photos: %s".printf (message));
            finish ();
        }

        private void finish () {
            choose_button.set_sensitive (true);
            organize_button.set_sensitive (source_path != null);
            progress_bar.set_fraction (1);
            progress_bar.set_text ("Complete");
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
        Adw.init ();
        Application application = new Application ();
        return application.run (args);
    }
}
