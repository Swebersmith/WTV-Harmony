# Third-party components

The application links dynamically to the HarmonyOS ARM64 build of libmpv. It does not embed a web player as its native playback engine.

- **mpv-arkts 1.0.0**, Bao Han, MIT: https://github.com/mpv-ohos/mpv-arkts . The vendored module retains its license and copyright notices. Local changes pin and verify the supplied binary and carry MPV end-file error and playlist-entry data across the native event bridge.
- **libmpv OHOS release 20260715**, based on mpv 0.41.0, built with `-Dgpl=false`. Source/build recipes: https://github.com/mpv-ohos/libmpv-ohos-build/tree/20260715 . MPV port: https://github.com/ErBWs/mpv/tree/feat-ohos-0.41.0 . The library uses LGPL-2.1-or-later components; embedded FFmpeg reports LGPL-3.0-or-later. License texts are included under `entry/src/main/resources/rawfile/licenses`.
- **AKI**, Apache-2.0: source and license are retained under `mpv/src/main/cpp/third_party/aki`.
- **simdjson**, Apache-2.0 / MIT: the upstream amalgamated source and its notices are retained under `mpv/src/main/cpp/third_party/simdjson`.

Unmodified `libmpv.so` SHA-256: `672e98d497199a89e20893979ecec686dee1113bbe1b609c9a9266aa1679bd32`.

Upstream binary archive SHA-256: `ac8b176dc4c86f4772d62ff530762ec187c3c46383bf2d476870d17dad806e5b`.

The fixed release build recipes and dependency versions are retained under `mpv/upstream-build-source-20260715`. They identify FFmpeg, mbedTLS, dav1d, libass, FreeType, HarfBuzz, fontconfig, libplacebo, shaderc, Little CMS, libxml2, FriBidi, dovi_tools and Lua sources. Their respective licenses continue to apply. The recipes are provided as source/reference; the Windows application build uses the supplied shared library and compiles the native wrapper locally.

The application and wrapper source are included in the source archive. `mpv/libs/arm64-v8a/libmpv.so` is a separate shared library. It may be replaced and the supplied project rebuilt; the integrity check in the module CMakeLists must then be updated to the replacement binary's hash. No application-specific restriction is imposed on debugging modifications to this library.
