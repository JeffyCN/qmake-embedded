#!/bin/bash -e

SCRIPT_DIR=$(dirname $(readlink -f "$0"))
SYSROOT=${1:-sysroot}
ABS_SYSROOT=$(realpath "$SYSROOT")
DEVICE_IP=$2

DIRS="lib usr/include usr/lib usr/share/qt5 usr/share/qtchooser"
FILES="usr/lib/*/qt5/qt.conf usr/lib/*/qt5/mkspecs/"

function error_msg() {
	echo $@
	exit 1
}

function create_sysroot_adb() {
        echo "Creating $SYSROOT from adb..."

        mkdir -p "$SYSROOT"
        adb shell "apt-get install -fy libqt5*-dev qt*-dev qt5-qmake"

        for d in $DIRS; do
                mkdir -p "$SYSROOT/$d"
                adb pull "/$d" "$SYSROOT/$d/.." || true
        done
}

function create_sysroot_rsync() {
        echo "Creating $SYSROOT from $DEVICE_IP..."

	type rsync >/dev/null || error_msg "Please install rsync."

        mkdir -p "$SYSROOT"
        adb shell "apt-get install -fy rsync libqt5*-dev qt*-dev qt5-qmake"

	rsync -rl --delete-after --safe-links $DEVICE_IP:/{lib,usr} "$SYSROOT"
}

# Query host & target's qmake properties as env
function qmake_env() {
        {
                qmake -query |grep HOST
                qmake -query -qtconf "$SYSROOT/usr/lib/$ARCH/qt5/qt.conf" |grep INSTALL
        } |sed -e "s#:\(/usr/\)\?#=#" -e "s/^/export /"
}

type qmake >/dev/null || error_msg "Please install qt5-qmake."

# Prepare sysroot
if [ -d "$SYSROOT" ]; then
        read -t 10 -p "$SYSROOT exists, recreate? (y/n):" YES
        [ "$YES" = "y" ] && rm -rf "$SYSROOT"
fi

if [ ! -d "$SYSROOT" ]; then
	if [ -n "$DEVICE_IP" ]; then
		create_sysroot_rsync
	else
		create_sysroot_adb
	fi
fi
for d in $DIRS $FILES; do
	[ -e "$SYSROOT"/$d ] || error_msg "$SYSROOT/$d not found!"
done

# Add mkspecs
case $(ls "$SYSROOT"/lib/ld-linux-*) in
        *aarch64*)
                MKSPEC=linux-aarch64-g++
                ARCH=aarch64-linux-gnu
                ;;
        *armhf*)
                MKSPEC=linux-armhf-g++
                ARCH=arm-linux-gnueabihf
                ;;
        *)
		error_msg "Unknown arch!"
		;;
esac
cp -rp "$SCRIPT_DIR/mkspecs/$MKSPEC" "$SYSROOT/usr/lib/$ARCH/qt5/mkspecs/devices"

# Gen qtconf
QT_CONF="$ABS_SYSROOT/qt.conf"
$(qmake_env)
source "$SCRIPT_DIR/gen_qtconf.sh"

# Gen qmake wrapper
QMAKE_WRAPPER="$SYSROOT/qmake"
echo -e "#!/bin/sh\nqmake \"\$@\" -before -qtconf \"$QT_CONF\"" > "$QMAKE_WRAPPER"
chmod +x "$QMAKE_WRAPPER"
echo "$QMAKE_WRAPPER (for $ARCH) is ready!"

type $ARCH-gcc >/dev/null || error_msg "Please install gcc-$ARCH."
type $ARCH-g++ >/dev/null || error_msg "Please install g++-$ARCH."
