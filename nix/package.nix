{
	lib,
	stdenv,
	src,
	version,
	fetchFromGitHub,
	pdfjs,
	chromium-hsts-preload-list,
	cargo,
	cmake,
	gitMinimal,
	glslang,
	ninja,
	perl,
	pkg-config,
	python3,
	rustPlatform,
	rustc,
	wayland-scanner,
	alsa-lib,
	angle,
	brotli,
	cpptrace,
	curlFull,
	fast-float,
	ffmpeg,
	fontconfig,
	glib,
	harfbuzz,
	icu78,
	libavif,
	libdrm,
	libedit,
	libGL,
	libjpeg_turbo,
	libpng,
	libpsl,
	libpulseaudio,
	libwebp,
	mimalloc,
	openssl,
	qt6Packages,
	sdl3,
	simdjson,
	simdutf,
	skia,
	sqlite,
	vulkan-headers,
	vulkan-loader,
	vulkan-memory-allocator,
	wayland,
	woff2,
	wuffs,
	libxcb-wm,
	zlib,
	zmij,
}:

let
	# Header-only math functions. Keep rev equal to the llvm-libc override in vcpkg.json.
	llvmLibcHeaders = stdenv.mkDerivation {
		pname = "llvm-libc-headers";
		version = "e54169423e7ee5d8b41c2f1b6f7a59000c901ee0";
		src = fetchFromGitHub {
			owner = "llvm";
			repo = "llvm-project";
			rev = "e54169423e7ee5d8b41c2f1b6f7a59000c901ee0";
			sparseCheckout = [ "libc" ];
			hash = "sha256-rYvY2rTNwA3Ovy3y/hI3nTp9v8kJbhxB2gseLcZ5vWA=";
		};
		dontConfigure = true;
		dontBuild = true;
		installPhase = ''
			runHook preInstall
			mkdir -p $out/include/llvm-libc
			cd libc
			find hdr include shared src/__support src/string/memory_utils -name '*.h' \
				-exec cp --parents -t $out/include/llvm-libc {} +
			runHook postInstall
		'';
	};

	# Copied one by one so that unrelated syncs do not rebuild FFmpeg.
	ffmpegPatch = name: builtins.path {
		inherit name;
		path = src + "/Meta/CMake/vcpkg/overlay-ports/ffmpeg/${name}";
	};

	# Ladybird uses an FFmpeg flag that its own patches add.
	patchedFfmpeg = ffmpeg.overrideAttrs (prev: {
		patches = (prev.patches or [ ]) ++ map ffmpegPatch [
			"0101-vulkan-decode-dpb-distinct-no-drm-modifiers.patch"
			"0102-vulkan-av1-clear-unused-ref-frame-mvs.patch"
		];
		doCheck = false;
	});
in
stdenv.mkDerivation {
	pname = "ladybird";
	inherit version src;

	# Read from the lock file so that syncing upstream needs no new hash.
	cargoDeps = rustPlatform.importCargoLock { lockFile = src + "/Cargo.lock"; };

	postPatch = ''
		# nixpkgs can carry a newer Rust than upstream pins, with new warnings.
		substituteInPlace Meta/CMake/rust_crate.cmake \
			--replace-fail 'set(RUSTC_TARGET_FLAGS -Dwarnings ' 'set(RUSTC_TARGET_FLAGS '

		# Use the FFmpeg from nixpkgs instead of upstream's suffixed build.
		substituteInPlace Meta/CMake/check_for_dependencies.cmake \
			--replace-fail libavcodec-ladybird libavcodec \
			--replace-fail libavutil-ladybird libavutil \
			--replace-fail libswresample-ladybird libswresample

		perl -0pi -e \
			's/find_package\(ICU 78\.[0-9]+ EXACT REQUIRED COMPONENTS data i18n uc\)/find_package(ICU ${icu78.version} EXACT REQUIRED COMPONENTS data i18n uc)/ or die "ICU dependency not found\n"' \
			Meta/CMake/check_for_dependencies.cmake

		# Install the same PDF viewer assets and integration patch as the vcpkg build.
		cp -r ${pdfjs}/share/pdf.js pdfjs
		chmod -R u+w pdfjs
		patch -d pdfjs -p1 < Meta/CMake/vcpkg/overlay-ports/pdfjs/0001-ladybird-embed.patch
		cmakeFlagsArray+=("-DPDFJS_DIR=$PWD/pdfjs")

		# Do not put absolute paths in RPATH.
		substituteInPlace Meta/CMake/lagom_install_options.cmake \
			--replace-fail "\''${CMAKE_INSTALL_BINDIR}" "bin" \
			--replace-fail "\''${CMAKE_INSTALL_LIBDIR}" "lib"
	'';

	preConfigure = ''
		mkdir -p build/Caches/HSTSPreload
		cp ${chromium-hsts-preload-list}/share/chromium-hsts-preload-list/transport_security_state_static.json \
			build/Caches/HSTSPreload
		cmakeFlagsArray+=("-DLADYBIRD_CACHE_DIR=$PWD/build/Caches")
	'';

	nativeBuildInputs = [
		brotli
		cargo
		cmake
		gitMinimal
		glslang
		ninja
		perl
		pkg-config
		python3
		rustPlatform.cargoSetupHook
		rustc
		qt6Packages.wrapQtAppsHook
		wayland-scanner
	];

	buildInputs = [
		alsa-lib
		angle
		brotli
		cpptrace
		curlFull
		fast-float
		patchedFfmpeg
		fontconfig
		glib
		harfbuzz
		icu78
		libavif
		libdrm
		libedit
		libGL
		libjpeg_turbo
		libpng
		libpsl
		libpulseaudio.dev
		libwebp
		libxcb-wm
		llvmLibcHeaders
		# Ladybird uses heap APIs removed in mimalloc 3.
		(mimalloc.overrideAttrs {
			version = "2.2.7";
			src = fetchFromGitHub {
				owner = "microsoft";
				repo = "mimalloc";
				tag = "v2.2.7";
				hash = "sha256-z9qMOTcGkURblZChXDGfQ58hrql52lG6EE1NQmxxuj0=";
			};
		})
		openssl
		qt6Packages.qtbase
		qt6Packages.qtpositioning
		qt6Packages.qtwayland
		sdl3
		simdjson
		simdutf
		# Ladybird also uses Skia's color management API directly.
		(skia.overrideAttrs (prev: {
			gnFlags = prev.gnFlags ++ [
				"extra_cflags+=[\"-DSKCMS_DLL\"]"
			];
		}))
		sqlite
		vulkan-headers
		vulkan-loader
		vulkan-memory-allocator
		wayland
		woff2
		wuffs
		zlib
		zmij
	];

	cmakeFlags = [
		(lib.cmakeBool "ENABLE_NETWORK_DOWNLOADS" false)
		(lib.cmakeBool "LADYBIRD_BASELINE_CPU_TARGET" true)
		(lib.cmakeBool "LADYBIRD_ENABLE_UPDATE_CHECK" false)
		(lib.cmakeBool "LADYBIRD_ENABLE_CCACHE" false)
		(lib.cmakeFeature "ICU_ROOT" (toString icu78.dev))
		(lib.cmakeFeature "CMAKE_INSTALL_LIBEXECDIR" "libexec")
	];

	# https://github.com/LadybirdBrowser/ladybird/issues/371#issuecomment-2616415434
	env.NIX_LDFLAGS = "-lGL -lfontconfig";

	meta = {
		description = "Independent web browser with its own engine";
		homepage = "https://ladybird.org";
		license = lib.licenses.bsd2;
		platforms = [
			"x86_64-linux"
			"aarch64-linux"
		];
		mainProgram = "Ladybird";
	};
}
