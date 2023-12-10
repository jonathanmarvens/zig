target: std.Target,
zig_backend: std.builtin.CompilerBackend,
output_mode: std.builtin.OutputMode,
link_mode: std.builtin.LinkMode,
is_test: bool,
test_evented_io: bool,
single_threaded: bool,
link_libc: bool,
link_libcpp: bool,
optimize_mode: std.builtin.OptimizeMode,
error_tracing: bool,
valgrind: bool,
sanitize_thread: bool,
pic: bool,
pie: bool,
strip: bool,
code_model: std.builtin.CodeModel,
omit_frame_pointer: bool,
wasi_exec_model: std.builtin.WasiExecModel,

pub fn generate(opts: @This(), allocator: Allocator) Allocator.Error![:0]u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    const target = opts.target;
    const generic_arch_name = target.cpu.arch.genericName();
    const zig_backend = opts.zig_backend;

    @setEvalBranchQuota(4000);
    try buffer.writer().print(
        \\const std = @import("std");
        \\/// Zig version. When writing code that supports multiple versions of Zig, prefer
        \\/// feature detection (i.e. with `@hasDecl` or `@hasField`) over version checks.
        \\pub const zig_version = std.SemanticVersion.parse(zig_version_string) catch unreachable;
        \\pub const zig_version_string = "{s}";
        \\pub const zig_backend = std.builtin.CompilerBackend.{};
        \\
        \\pub const output_mode = std.builtin.OutputMode.{};
        \\pub const link_mode = std.builtin.LinkMode.{};
        \\pub const is_test = {};
        \\pub const single_threaded = {};
        \\pub const abi = std.Target.Abi.{};
        \\pub const cpu: std.Target.Cpu = .{{
        \\    .arch = .{},
        \\    .model = &std.Target.{}.cpu.{},
        \\    .features = std.Target.{}.featureSet(&[_]std.Target.{}.Feature{{
        \\
    , .{
        build_options.version,
        std.zig.fmtId(@tagName(zig_backend)),
        std.zig.fmtId(@tagName(opts.output_mode)),
        std.zig.fmtId(@tagName(opts.link_mode)),
        opts.is_test,
        opts.single_threaded,
        std.zig.fmtId(@tagName(target.abi)),
        std.zig.fmtId(@tagName(target.cpu.arch)),
        std.zig.fmtId(generic_arch_name),
        std.zig.fmtId(target.cpu.model.name),
        std.zig.fmtId(generic_arch_name),
        std.zig.fmtId(generic_arch_name),
    });

    for (target.cpu.arch.allFeaturesList(), 0..) |feature, index_usize| {
        const index = @as(std.Target.Cpu.Feature.Set.Index, @intCast(index_usize));
        const is_enabled = target.cpu.features.isEnabled(index);
        if (is_enabled) {
            try buffer.writer().print("        .{},\n", .{std.zig.fmtId(feature.name)});
        }
    }
    try buffer.writer().print(
        \\    }}),
        \\}};
        \\pub const os = std.Target.Os{{
        \\    .tag = .{},
        \\    .version_range = .{{
    ,
        .{std.zig.fmtId(@tagName(target.os.tag))},
    );

    switch (target.os.getVersionRange()) {
        .none => try buffer.appendSlice(" .none = {} },\n"),
        .semver => |semver| try buffer.writer().print(
            \\ .semver = .{{
            \\        .min = .{{
            \\            .major = {},
            \\            .minor = {},
            \\            .patch = {},
            \\        }},
            \\        .max = .{{
            \\            .major = {},
            \\            .minor = {},
            \\            .patch = {},
            \\        }},
            \\    }}}},
            \\
        , .{
            semver.min.major,
            semver.min.minor,
            semver.min.patch,

            semver.max.major,
            semver.max.minor,
            semver.max.patch,
        }),
        .linux => |linux| try buffer.writer().print(
            \\ .linux = .{{
            \\        .range = .{{
            \\            .min = .{{
            \\                .major = {},
            \\                .minor = {},
            \\                .patch = {},
            \\            }},
            \\            .max = .{{
            \\                .major = {},
            \\                .minor = {},
            \\                .patch = {},
            \\            }},
            \\        }},
            \\        .glibc = .{{
            \\            .major = {},
            \\            .minor = {},
            \\            .patch = {},
            \\        }},
            \\    }}}},
            \\
        , .{
            linux.range.min.major,
            linux.range.min.minor,
            linux.range.min.patch,

            linux.range.max.major,
            linux.range.max.minor,
            linux.range.max.patch,

            linux.glibc.major,
            linux.glibc.minor,
            linux.glibc.patch,
        }),
        .windows => |windows| try buffer.writer().print(
            \\ .windows = .{{
            \\        .min = {s},
            \\        .max = {s},
            \\    }}}},
            \\
        ,
            .{ windows.min, windows.max },
        ),
    }
    try buffer.appendSlice(
        \\};
        \\pub const target: std.Target = .{
        \\    .cpu = cpu,
        \\    .os = os,
        \\    .abi = abi,
        \\    .ofmt = object_format,
        \\
    );

    if (target.dynamic_linker.get()) |dl| {
        try buffer.writer().print(
            \\    .dynamic_linker = std.Target.DynamicLinker.init("{s}"),
            \\}};
            \\
        , .{dl});
    } else {
        try buffer.appendSlice(
            \\    .dynamic_linker = std.Target.DynamicLinker.none,
            \\};
            \\
        );
    }

    // This is so that compiler_rt and libc.zig libraries know whether they
    // will eventually be linked with libc. They make different decisions
    // about what to export depending on whether another libc will be linked
    // in. For example, compiler_rt will not export the __chkstk symbol if it
    // knows libc will provide it, and likewise c.zig will not export memcpy.
    const link_libc = opts.link_libc;

    try buffer.writer().print(
        \\pub const object_format = std.Target.ObjectFormat.{};
        \\pub const mode = std.builtin.OptimizeMode.{};
        \\pub const link_libc = {};
        \\pub const link_libcpp = {};
        \\pub const have_error_return_tracing = {};
        \\pub const valgrind_support = {};
        \\pub const sanitize_thread = {};
        \\pub const position_independent_code = {};
        \\pub const position_independent_executable = {};
        \\pub const strip_debug_info = {};
        \\pub const code_model = std.builtin.CodeModel.{};
        \\pub const omit_frame_pointer = {};
        \\
    , .{
        std.zig.fmtId(@tagName(target.ofmt)),
        std.zig.fmtId(@tagName(opts.optimize_mode)),
        link_libc,
        opts.link_libcpp,
        opts.error_tracing,
        opts.valgrind,
        opts.sanitize_thread,
        opts.pic,
        opts.pie,
        opts.strip,
        std.zig.fmtId(@tagName(opts.code_model)),
        opts.omit_frame_pointer,
    });

    if (target.os.tag == .wasi) {
        const wasi_exec_model_fmt = std.zig.fmtId(@tagName(opts.wasi_exec_model));
        try buffer.writer().print(
            \\pub const wasi_exec_model = std.builtin.WasiExecModel.{};
            \\
        , .{wasi_exec_model_fmt});
    }

    if (opts.is_test) {
        try buffer.appendSlice(
            \\pub var test_functions: []const std.builtin.TestFn = undefined; // overwritten later
            \\
        );
        if (opts.test_evented_io) {
            try buffer.appendSlice(
                \\pub const test_io_mode = .evented;
                \\
            );
        } else {
            try buffer.appendSlice(
                \\pub const test_io_mode = .blocking;
                \\
            );
        }
    }

    return buffer.toOwnedSliceSentinel(0);
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const build_options = @import("build_options");
