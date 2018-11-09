#!/bin/bash

# Copyright 2018 Scott Court
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Allow the user to specify a different root directory.
ROOT=${ROOT:-}

# The directory that the ports tree is in
export PORTSDIR=${PORTSDIR:-"$ROOT/usr/ports"}

# The directory that packages are in. This should be the root packages
# directory; not the cucumber subdirectory.
export PKGDIR=${PKGDIR:-"$ROOT/opt/packages"}

# The directory to store the output in
export OUTDIR=${OUTDIR:-"$ROOT/tmp"}

# Include the distribution-release file settings
source "$PORTSDIR/metadata/distribution-release"

export VERSION=${VERSION:-$DISTRIB_RELEASE}

OWD=$(dirname $(realpath $0))

cat << EOF
Building Installation ISO File to (\$OUTDIR) $OUTDIR,
Using the following settings:
	Distribution version (\$VERSION): $VERSION
	Ports tree (\$PORTSDIR): $PORTSDIR
	Package directory (\$PKGDIR): $PKGDIR

Change these settings by setting the variable named in the paranthesis.

EOF

# Clean up from any previous builds
if [ -f "$OWD/iso/initrd-*" ]; then
	rm "$OWD/iso/initrd-*" || exit 1
fi

# Build the initrd first
cd $OWD/initrd || exit 1
OUTDIR="$OWD/iso" "$OWD/initrd/initrd.buildscript" || exit 1

# Then build the ISO file
cd $OWD/iso || exit 1
"$OWD/iso/iso.buildscript" || exit 1


