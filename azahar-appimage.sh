#!/bin/sh

set -ex

export ARCH="$(uname -m)"

REPO="https://github.com/azahar-emu/azahar.git"
LIB4BN="https://raw.githubusercontent.com/VHSgunzo/sharun/refs/heads/main/lib4bin"
GRON="https://raw.githubusercontent.com/xonixx/gron.awk/refs/heads/main/gron.awk"
URUNTIME="https://github.com/VHSgunzo/uruntime/releases/latest/download/uruntime-appimage-dwarfs-$ARCH"
UPINFO="gh-releases-zsync|$(echo "$GITHUB_REPOSITORY" | tr '/' '|')|latest|*$ARCH.AppImage.zsync"

if [ "$ARCH" = 'x86_64' ]; then
	if [ "$1" = 'v3' ]; then
		echo "Making x86-64-v3 optimized build of azahar..."
		ARCH="${ARCH}_v3"
		ARCH_FLAGS="-march=x86-64-v3 -O3 -flto=thin -DNDEBUG"
	else
		echo "Making x86-64 generic build of azahar..."
		ARCH_FLAGS="-march=x86-64 -mtune=generic -O3 -flto=thin -DNDEBUG"
	fi
else
	echo "Making aarch64 build of azahar..."
	ARCH_FLAGS="-march=armv8-a -mtune=generic -O3 -flto=thin -DNDEBUG"
fi

UPINFO="gh-releases-zsync|$(echo "$GITHUB_REPOSITORY" | tr '/' '|')|latest|*$ARCH.AppImage.zsync"

# Determine to build nightly or stable
if [ "DEVEL" = 'true' ]; then
	echo "Making nightly build of azahar..."
	VERSION="$(git ls-remote "$REPO" HEAD | cut -c 1-9)"
	git clone "$REPO" ./azahar
else
	echo "Making stable build of azahar..."
	wget "$GRON" -O ./gron.awk
	chmod +x ./gron.awk
	VERSION=$(wget https://api.github.com/repos/azahar-emu/azahar/tags -O - \
		| ./gron.awk | awk -F'=|"' '/name/ {print $3; exit}')
	git clone --branch "$VERSION" --single-branch "$REPO" ./azahar
fi
echo "$VERSION" > ~/version

# BUILD AZAAHR
(
	cd ./azahar
	git submodule update --init --recursive -j$(nproc)

	# HACK
	sed -i '10a #include <memory>' ./src/video_core/shader/shader_jit_a64_compiler.*

	mkdir ./build
	cd ./build
	cmake .. -DCMAKE_CXX_COMPILER=clang++ \
		-DCMAKE_C_COMPILER=clang \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DENABLE_QT_TRANSLATION=ON \
		-DUSE_SYSTEM_BOOST=OFF \
		-DCMAKE_BUILD_TYPE=Release \
		-DUSE_DISCORD_PRESENCE=OFF \
		-DCMAKE_C_FLAGS="$ARCH_FLAGS" \
		-DUSE_SYSTEM_VULKAN_HEADERS=ON \
		-DENABLE_LTO=OFF \
		-DUSE_SYSTEM_GLSLANG=ON \
		-DSIRIT_USE_SYSTEM_SPIRV_HEADERS=ON \
		-DCITRA_USE_PRECOMPILED_HEADERS=OFF \
		-DCMAKE_C_FLAGS="$ARCH_FLAGS" \
		-DCMAKE_CXX_FLAGS="$ARCH_FLAGS" \
		-DCMAKE_VERBOSE_MAKEFILE=ON \
		-Wno-dev
	cmake --build . -- -j"$(nproc)"
	sudo make install
)
rm -rf ./azahar

# NOW MAKE APPIMAGE
mkdir ./AppDir
cd ./AppDir

cp -v /usr/share/applications/org.azahar_emu.Azahar.desktop            ./azahar.desktop
cp -v /usr/share/icons/hicolor/512x512/apps/org.azahar_emu.Azahar.png  ./azahar.png
cp -v /usr/share/icons/hicolor/512x512/apps/org.azahar_emu.Azahar.png  ./.DirIcon

if [ "$DEVEL" = 'true' ]; then
	sed -i 's|Name=Azahar|Name=Azahar nightly|' ./azahar.desktop
	UPINFO="$(echo "$UPINFO" | sed 's|latest|nightly|')"
fi

# Bundle all libs
wget --retry-connrefused --tries=30 "$LIB4BN" -O ./lib4bin
chmod +x ./lib4bin
xvfb-run -a -- ./lib4bin -p -v -e -s -k \
	/usr/bin/azahar* \
	/usr/lib/libGLX* \
	/usr/lib/libGL.so* \
	/usr/lib/libEGL* \
	/usr/lib/dri/* \
	/usr/lib/vdpau/* \
	/usr/lib/libvulkan* \
	/usr/lib/libVkLayer* \
	/usr/lib/libXss.so* \
	/usr/lib/libdecor-0.so* \
	/usr/lib/libgamemode.so* \
	/usr/lib/qt6/plugins/audio/* \
	/usr/lib/qt6/plugins/bearer/* \
	/usr/lib/qt6/plugins/imageformats/* \
	/usr/lib/qt6/plugins/iconengines/* \
	/usr/lib/qt6/plugins/platforms/* \
	/usr/lib/qt6/plugins/platformthemes/* \
	/usr/lib/qt6/plugins/platforminputcontexts/* \
	/usr/lib/qt6/plugins/styles/* \
	/usr/lib/qt6/plugins/xcbglintegrations/* \
	/usr/lib/qt6/plugins/wayland-*/* \
	/usr/lib/pulseaudio/* \
	/usr/lib/pipewire-*/* \
	/usr/lib/spa-*/*/* \
	/usr/lib/alsa-lib/*

# Prepare sharun
if [ "$ARCH" = 'aarch64' ]; then
	# allow the host vulkan to be used for aarch64 given the sed situation
	echo 'SHARUN_ALLOW_SYS_VKICD=1' > ./.env
fi
ln ./sharun ./AppRun
./sharun -g

# turn appdir into appimage
cd ..
wget -q "$URUNTIME" -O ./uruntime
chmod +x ./uruntime

#Add udpate info to runtime
echo "Adding update information \"$UPINFO\" to runtime..."
./uruntime --appimage-addupdinfo "$UPINFO"

echo "Generating AppImage..."
./uruntime --appimage-mkdwarfs -f \
	--set-owner 0 --set-group 0 \
	--no-history --no-create-timestamp \
	--compression zstd:level=22 -S26 -B8 \
	--header uruntime \
	-i ./AppDir -o Azahar-Enhanced-"$VERSION"-anylinux-"$ARCH".AppImage

echo "Generating zsync file..."
zsyncmake *.AppImage -u *.AppImage
echo "All Done!"
