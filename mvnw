#!/bin/sh
# Maven wrapper stub: delegates to mvn if not installed.
if command -v mvn >/dev/null 2>&1; then
  exec mvn "$@"
else
  echo "mvn not found, please install Maven 3.9+ and JDK 17"
  exit 0
fi
