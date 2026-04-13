#!/usr/bin/env bash
# rename-demo.sh — initialize this template as a new GridGain demo project.
#
# Usage:
#   ./rename-demo.sh <new-project-name> [<new-group>]
#
# Example:
#   ./rename-demo.sh acme-gridgain-demo com.acme.demo
#
# What this does:
#   1. Sets `rootProject.name` in settings.gradle.kts to <new-project-name>.
#   2. If <new-group> provided, sets `group = "..."` in build.gradle.kts.
#   3. Copies src/main/resources/demo-config.yaml.template to demo-config.yaml
#      if it doesn't already exist (the .template stays under version control;
#      demo-config.yaml is gitignored because it will contain secrets).
#
# This script does NOT rename the containing directory — do that yourself.
# It does NOT initialize git — do that yourself if you want a fresh history.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

usage() {
    cat <<EOF
Usage: $0 <new-project-name> [<new-group>]

Arguments:
  <new-project-name>  Gradle rootProject.name (e.g. acme-gridgain-demo).
                      Must not contain whitespace.
  <new-group>         Optional Maven/Gradle group (e.g. com.acme.demo).
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage >&2
    exit 1
fi

NEW_NAME="$1"
NEW_GROUP="${2:-}"

if [[ "$NEW_NAME" =~ [[:space:]] ]]; then
    echo "ERROR: project name must not contain whitespace: '$NEW_NAME'" >&2
    exit 1
fi

if [[ ! -f settings.gradle.kts ]]; then
    echo "ERROR: settings.gradle.kts not found in $SCRIPT_DIR" >&2
    exit 1
fi
if [[ ! -f build.gradle.kts ]]; then
    echo "ERROR: build.gradle.kts not found in $SCRIPT_DIR" >&2
    exit 1
fi

# Portable sed -i (macOS BSD sed requires a suffix argument).
sed_inplace() {
    local pattern="$1"
    local file="$2"
    sed -i.bak "$pattern" "$file"
    rm -f "${file}.bak"
}

# 1. rootProject.name
if ! grep -qE '^rootProject\.name\s*=' settings.gradle.kts; then
    echo "ERROR: could not find 'rootProject.name' line in settings.gradle.kts" >&2
    exit 1
fi
sed_inplace "s|^rootProject\.name[[:space:]]*=.*|rootProject.name = \"${NEW_NAME}\"|" settings.gradle.kts
echo "Updated settings.gradle.kts: rootProject.name = \"${NEW_NAME}\""

# 2. group (optional)
if [[ -n "$NEW_GROUP" ]]; then
    if ! grep -qE '^group\s*=' build.gradle.kts; then
        echo "ERROR: could not find 'group = ...' line in build.gradle.kts" >&2
        exit 1
    fi
    sed_inplace "s|^group[[:space:]]*=.*|group = \"${NEW_GROUP}\"|" build.gradle.kts
    echo "Updated build.gradle.kts: group = \"${NEW_GROUP}\""
fi

# 3. Seed demo-config.yaml from the template (if not already present).
CONFIG_DIR="src/main/resources"
TEMPLATE="${CONFIG_DIR}/demo-config.yaml.template"
TARGET="${CONFIG_DIR}/demo-config.yaml"
if [[ -f "$TEMPLATE" ]]; then
    if [[ -f "$TARGET" ]]; then
        echo "Skipped: ${TARGET} already exists."
    else
        cp "$TEMPLATE" "$TARGET"
        echo "Created ${TARGET} from template (edit it to configure your demo)."
    fi
else
    echo "WARNING: ${TEMPLATE} not found; skipping demo-config.yaml creation." >&2
fi

cat <<EOF

Done.

Next steps:
  1. Rename the containing directory to '${NEW_NAME}' if you haven't already:
       cd .. && mv "$(basename "$SCRIPT_DIR")" "${NEW_NAME}"
  2. Edit ${TARGET} and fill in the <YOUR_...> placeholders.
  3. Initialize git if you want a fresh history:
       rm -rf .git && git init && git add . && git commit -m "Initial commit from gridgain-demo-template"
  4. List available tasks:
       ./gradlew tasks
EOF
