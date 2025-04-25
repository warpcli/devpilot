#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 <major|minor|patch>"
    exit 1
}

# Check if argument is provided
if [ $# -ne 1 ]; then
    usage
fi

# Get current version from Cargo.toml
CURRENT_VERSION=$(grep '^version = ' Cargo.toml | sed -E 's/version = "(.*)"/\1/')

# Split version into components
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

# Update version based on argument
case $1 in
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
    *)
        usage
        ;;
esac

# Create new version string
NEW_VERSION="$MAJOR.$MINOR.$PATCH"

# Update version in Cargo.toml
sed -i "s/^version = \".*\"/version = \"$NEW_VERSION\"/" Cargo.toml

echo "Version bumped from $CURRENT_VERSION to $NEW_VERSION"