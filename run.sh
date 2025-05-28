#!/bin/bash

# @cmd build cargo project
# @alias b
build() {
    cargo build --release
}

run() {
    ./target/release/dp
}

# @cmd mark as releaser
# @arg type![patch|minor|major] Release type
release() {
    # echo "release $1"
    CURRENT_VERSION=$(grep '^version = ' Cargo.toml | sed -E 's/version = "(.*)"/\1/')
    IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
    echo $argc_type
    case $argc_type in
        major)
            MAJOR=$((MAJOR + 1))
            MINOR=0
            PATCH=0
            ;;
        minor)
            MINOR=$((MINOR + 1))
            PATCH=0
            ;;
        patch)
            PATCH=$((PATCH + 1))
            ;;
    esac
    version="$MAJOR.$MINOR.$PATCH"
    LATEST_TAG=$(git tag --list --sort=-version:refname | head -n 1)
    if [ -n "$LATEST_TAG" ]; then
        # Not the first release - get changes since last tag
        changelog=$(git cliff $LATEST_TAG..HEAD --strip all)
        git cliff --tag $version $LATEST_TAG..HEAD --prepend CHANGELOG.md
    else
        # First release - get all changes
        changelog=$(git cliff --unreleased --strip all)
        git cliff --tag $version --unreleased --prepend CHANGELOG.md
    fi
    sed -i "s/^version = \".*\"/version = \"$version\"/" Cargo.toml
    git add -A && git commit -m "chore(release): prepare for $version"
    echo "$changelog"
    git tag -a $version -m "$version" -m "$changelog"
    git push --follow-tags --force --set-upstream origin develop
    gh release create $version --notes "$changelog"
}


# @cmd compile mdbook
# @alias m
# @option    --dest_dir <dir>    Destination directory
# @flag      --monitor        Monitor after upload
mdbook() {
    mdbook build book --dest-dir ../docs
    git add -A && git commit -m "docs: building website/mdbook"
}


eval "$(argc --argc-eval "$0" "$@")"
