//! Pinned memory-only FreeType/HarfBuzz builds for native and Wasm consumers.
const std = @import("std");

/// Adds the real text engine with target-built C/C++ dependencies. No source
/// lookup, browser API, renderer policy, or font data belongs in this build.
pub fn addModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const wasm = target.result.cpu.arch == .wasm32;
    if (wasm and (target.result.os.tag != .wasi or
        !target.result.cpu.features.isEnabled(@backingInt(std.Target.wasm.Feature.exception_handling))))
        @panic("bundled Wasm text requires wasm32-wasi with exception_handling");
    // A missing lazy package must restart configuration before a downstream
    // consumer asks for this module, not return a half-configured dependency.
    const ft = b.dependency("freetype", .{});
    const hb = b.dependency("harfbuzz", .{});
    // GitHub's content-pinned archives retain their commit-named top directory.
    const ft_root = ft.path("freetype-25a08f24cfc0da879d1938352d026532f280b77e");
    const hb_root = hb.path("harfbuzz-a95d2a18ab0084b3fed5e5c6737f60d2c985bbeb");
    const ft_include = ft_root.path(b, "include");
    const hb_include = hb_root.path(b, "src");
    const ftmod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    ftmod.addIncludePath(ft_include);
    ftmod.addIncludePath(b.path("config"));
    ftmod.addCSourceFiles(.{
        .root = ft_root,
        .files = &.{
            "src/autofit/autofit.c",   "src/base/ftbase.c",       "src/base/ftbbox.c",
            "src/base/ftbdf.c",        "src/base/ftbitmap.c",     "src/base/ftcid.c",
            "src/base/ftfstype.c",     "src/base/ftgasp.c",       "src/base/ftglyph.c",
            "src/base/ftgxval.c",      "src/base/ftinit.c",       "src/base/ftmm.c",
            "src/base/ftotval.c",      "src/base/ftpatent.c",     "src/base/ftpfr.c",
            "src/base/ftstroke.c",     "src/base/ftsynth.c",      "src/base/fttype1.c",
            "src/base/ftwinfnt.c",     "src/bdf/bdf.c",           "src/bzip2/ftbzip2.c",
            "src/cache/ftcache.c",     "src/cff/cff.c",           "src/cid/type1cid.c",
            "src/gzip/ftgzip.c",       "src/hvf/hvf.c",           "src/lzw/ftlzw.c",
            "src/pcf/pcf.c",           "src/pfr/pfr.c",           "src/psaux/psaux.c",
            "src/pshinter/pshinter.c", "src/psnames/psnames.c",   "src/raster/raster.c",
            "src/sdf/sdf.c",           "src/sfnt/sfnt.c",         "src/smooth/smooth.c",
            "src/svg/svg.c",           "src/truetype/truetype.c", "src/type1/type1.c",
            "src/type42/type42.c",     "src/winfonts/winfnt.c",   "src/base/ftsystem.c",
            "src/base/ftdebug.c",
        },
        .flags = if (wasm) &.{
            "-mllvm",              "-wasm-enable-sjlj",                         "-mllvm",                                    "-wasm-use-legacy-eh=false",
            "-DFT2_BUILD_LIBRARY", "-DFT_CONFIG_OPTIONS_H=\"howl-ftoption.h\"", "-DFT_CONFIG_OPTION_DISABLE_STREAM_SUPPORT",
        } else &.{ "-DFT2_BUILD_LIBRARY", "-DFT_CONFIG_OPTIONS_H=\"howl-ftoption.h\"", "-DFT_CONFIG_OPTION_DISABLE_STREAM_SUPPORT" },
    });
    const ftlib = b.addLibrary(.{ .name = "howl-freetype", .linkage = .static, .root_module = ftmod });
    const hbmod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true, .link_libcpp = true });
    hbmod.addIncludePath(ft_include);
    hbmod.addIncludePath(hb_include);
    hbmod.addCSourceFile(.{ .file = hb_root.path(b, "src/harfbuzz.cc"), .flags = &.{
        "-std=c++17",   "-fno-exceptions", "-fno-rtti",         "-DHAVE_FREETYPE", "-DHB_NO_MT",
        "-DHB_NO_MMAP", "-DHB_NO_OPEN",    "-DHB_NO_SETLOCALE", "-DHB_NO_GETENV",  "-DHB_NO_ATEXIT",
    } });
    const hblib = b.addLibrary(.{ .name = "howl-harfbuzz", .linkage = .static, .root_module = hbmod });
    const translated = b.addTranslateC(.{ .root_source_file = b.path("config/native.h"), .target = target, .optimize = optimize });
    // This exact Zig pin's TranslateC omits CPU-feature defines. Mirror the EH
    // declaration macro only; real C objects still use the actual target feature.
    if (wasm) translated.defineCMacro("__wasm_exception_handling__", "1");
    translated.addIncludePath(ft_include);
    translated.addIncludePath(hb_include);
    const module = b.addModule("howl_text", .{
        .root_source_file = b.path("src/text.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    module.addImport("native_c", translated.createModule());
    module.linkLibrary(hblib);
    module.linkLibrary(ftlib);
    // The pinned WASI libc has the real jump runtime, but needs LLVM 22's tag.
    // Keep the compatibility definition with its consuming target libraries.
    if (wasm) module.addCSourceFile(.{ .file = b.path("config/wasi-exception-tag.c"), .flags = &.{} });
    return module;
}
