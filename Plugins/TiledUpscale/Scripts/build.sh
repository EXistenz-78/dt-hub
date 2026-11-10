#!/bin/zsh
# build.sh OUT_FOLDER
# Builds this plug-in into OUT_FOLDER/<Name>.dthubplugin (ad-hoc signed); the work is in Plugins/build-plugin.sh, which
# reads the identifier and the version from the plug-in's manifest. Run from anywhere.
exec "${0:A:h:h:h}/build-plugin.sh" "${0:A:h:h:t}" "$@"
