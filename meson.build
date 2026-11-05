project(
  'photo-organizer',
  'vala',
  version: '0.1.0',
  meson_version: '>= 0.60.0',
  default_options: ['warning_level=2'],
)

gettext_package = 'photo-organizer'
add_project_arguments('-DGETTEXT_PACKAGE="@0@"'.format(gettext_package), language: 'c')

gtk_dep = dependency('gtk4', version: '>= 4.12')
adw_dep = dependency('libadwaita-1', version: '>= 1.5')
gexiv2_dep = dependency('gexiv2', version: '>= 0.14')
gee_dep = dependency('gee-0.8')

config_data = configuration_data()
config_data.set_quoted('GETTEXT_PACKAGE', gettext_package)
config_data.set_quoted(
  'LOCALEDIR',
  join_paths(get_option('prefix'), get_option('localedir'))
)
config_vala = configure_file(
  input: 'src/config.vala.in',
  output: 'config.vala',
  configuration: config_data,
)

executable(
  'photo-organizer',
  config_vala,
  'src/main.vala',
  'src/organizer.vala',
  dependencies: [gtk_dep, adw_dep, gexiv2_dep, gee_dep],
  install: true,
)

subdir('po')

install_data(
  'data/org.example.PhotoOrganizer.svg',
  install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', 'scalable', 'apps'),
)
install_data(
  'data/org.example.PhotoOrganizer.desktop',
  install_dir: join_paths(get_option('datadir'), 'applications'),
)
install_data(
  'data/org.example.PhotoOrganizer.metainfo.xml',
  install_dir: join_paths(get_option('datadir'), 'metainfo'),
)

test_exe = executable(
  'organizer-test',
  'tests/organizer-test.vala',
  'src/organizer.vala',
  dependencies: [dependency('gdk-pixbuf-2.0'), gexiv2_dep, gee_dep],
)
test('organizer', test_exe)
