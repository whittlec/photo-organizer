#!/bin/sh
set -eu

version=$1
mode=$2
source_root=${MESON_SOURCE_ROOT:?This script must be run through Meson}
build_root=${MESON_BUILD_ROOT:?This script must be run through Meson}
tag="v$version"
release_dir="$build_root/release"

cd "$source_root"

if [ -n "$(git status --porcelain --untracked-files=normal)" ]; then
    echo "Refusing to release from a dirty working tree." >&2
    exit 1
fi

case "$mode" in
    artifacts)
        source_ref=$(git rev-parse HEAD)
        ;;
    publish)
        if ! command -v gh >/dev/null 2>&1; then
            echo "GitHub CLI (gh) is required to publish a release." >&2
            exit 1
        fi
        gh auth status
        tagged_commit=$(git rev-parse --verify "$tag^{commit}" 2>/dev/null) || {
            echo "Tag $tag does not exist. Create and push it before publishing." >&2
            exit 1
        }
        head_commit=$(git rev-parse HEAD)
        if [ "$tagged_commit" != "$head_commit" ]; then
            echo "Tag $tag must point to the current HEAD." >&2
            exit 1
        fi
        source_ref=$tag
        ;;
    *)
        echo "Unknown release mode: $mode" >&2
        exit 2
        ;;
esac

package_version=$(dpkg-parsechangelog --show-field Version)
case "$package_version" in
    "$version"-*) ;;
    *)
        echo "Debian package version $package_version does not match app version $version." >&2
        exit 1
        ;;
esac

meson test -C "$build_root" --print-errorlogs
dpkg-buildpackage --build=binary --no-sign

architecture=$(dpkg --print-architecture)
deb_name="photo-organizer_${package_version}_${architecture}.deb"
deb_path="$source_root/../$deb_name"
if [ ! -f "$deb_path" ]; then
    echo "Expected Debian package was not produced: $deb_path" >&2
    exit 1
fi

mkdir -p "$release_dir"
cp "$deb_path" "$release_dir/$deb_name"

archive_name="photo-organizer-$version.tar.gz"
git archive --format=tar.gz --prefix="photo-organizer-$version/" \
    --output="$release_dir/$archive_name" "$source_ref"

(
    cd "$release_dir"
    sha256sum "$deb_name" "$archive_name" > SHA256SUMS
)

echo "Release artifacts are ready in $release_dir:"
printf '  %s\n' "$deb_name" "$archive_name" SHA256SUMS

if [ "$mode" = publish ]; then
    gh release create "$tag" \
        "$release_dir/$deb_name" \
        "$release_dir/$archive_name" \
        "$release_dir/SHA256SUMS" \
        --verify-tag \
        --title "Photo Organizer $version" \
        --generate-notes
fi
