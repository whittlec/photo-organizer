project(
  'photo-organizer',
  'vala',
  version: '0.1.0',
  meson_version: '>= 0.60.0',
  default_options: ['warning_level=2'],
)

gtk_dep = dependency('gtk4', version: '>= 4.12')
adw_dep = dependency('libadwaita-1', version: '>= 1.4')
gexiv2_dep = dependency('gexiv2', version: '>= 0.14')
gee_dep = dependency('gee-0.8')

executable(
  'photo-organizer',
  'src/main.vala',
  'src/organizer.vala',
  dependencies: [gtk_dep, adw_dep, gexiv2_dep, gee_dep],
  install: true,
)

test_exe = executable(
  'organizer-test',
  'tests/organizer-test.vala',
  'src/organizer.vala',
  dependencies: [dependency('gdk-pixbuf-2.0'), gexiv2_dep, gee_dep],
)
test('organizer', test_exe)
