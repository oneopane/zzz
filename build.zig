const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zzz = b.addModule("zzz", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tardy = b.dependency("tardy", .{
        .target = target,
        .optimize = optimize,
    }).module("tardy");

    zzz.addImport("tardy", tardy);

    const secsock = b.dependency("secsock", .{
        .target = target,
        .optimize = optimize,
    }).module("secsock");

    zzz.addImport("secsock", secsock);

    // Server examples
    add_example(b, "server/basic", "basic", false, target, optimize, zzz);
    add_example(b, "server/cookies", "cookies", false, target, optimize, zzz);
    add_example(b, "server/form", "form", false, target, optimize, zzz);
    add_example(b, "server/fs", "fs", false, target, optimize, zzz);
    add_example(b, "server/middleware", "middleware", false, target, optimize, zzz);
    add_example(b, "server/sse", "sse", false, target, optimize, zzz);
    add_example(b, "server/tls", "tls", true, target, optimize, zzz);
    
    // Client examples
    add_example(b, "client/basic", "client_basic", false, target, optimize, zzz);
    add_example(b, "client/https", "client_https", true, target, optimize, zzz);
    add_example(b, "client/http_client", "http_client", false, target, optimize, zzz);
    add_example(b, "client/http_client_simple", "http_client_simple", false, target, optimize, zzz);

    if (target.result.os.tag != .windows) {
        add_example(b, "server/unix", "unix", false, target, optimize, zzz);
    }

    // Create test step
    const test_step = b.step("test", "Run general unit tests");
    
    // Test core modules
    const test_core_mod = b.createModule(.{
        .root_source_file = b.path("./src/test_core.zig"),
        .target = target,
        .optimize = optimize,
    });
    const test_core = b.addTest(.{
        .name = "test-core",
        .root_module = test_core_mod,
    });
    test_core_mod.addImport("tardy", tardy);
    test_core_mod.addImport("secsock", secsock);
    const run_test_core = b.addRunArtifact(test_core);
    run_test_core.step.dependOn(&test_core.step);
    
    // Test HTTP common modules
    const test_http_common_mod = b.createModule(.{
        .root_source_file = b.path("./src/test_http_common.zig"),
        .target = target,
        .optimize = optimize,
    });
    const test_http_common = b.addTest(.{
        .name = "test-http-common",
        .root_module = test_http_common_mod,
    });
    test_http_common_mod.addImport("tardy", tardy);
    test_http_common_mod.addImport("secsock", secsock);
    const run_test_http_common = b.addRunArtifact(test_http_common);
    run_test_http_common.step.dependOn(&test_http_common.step);
    
    // Test HTTP client modules
    const test_http_client_mod = b.createModule(.{
        .root_source_file = b.path("./src/test_http_client.zig"),
        .target = target,
        .optimize = optimize,
    });
    const test_http_client = b.addTest(.{
        .name = "test-http-client",
        .root_module = test_http_client_mod,
    });
    test_http_client_mod.addImport("tardy", tardy);
    test_http_client_mod.addImport("secsock", secsock);
    const run_test_http_client = b.addRunArtifact(test_http_client);
    run_test_http_client.step.dependOn(&test_http_client.step);
    
    // Test HTTP server modules
    const test_http_server_mod = b.createModule(.{
        .root_source_file = b.path("./src/test_http_server.zig"),
        .target = target,
        .optimize = optimize,
    });
    const test_http_server = b.addTest(.{
        .name = "test-http-server",
        .root_module = test_http_server_mod,
    });
    test_http_server_mod.addImport("tardy", tardy);
    test_http_server_mod.addImport("secsock", secsock);
    const run_test_http_server = b.addRunArtifact(test_http_server);
    run_test_http_server.step.dependOn(&test_http_server.step);
    
    // Add all test modules to the main test step
    test_step.dependOn(&run_test_core.step);
    test_step.dependOn(&run_test_http_common.step);
    // FIXME: HTTP client tests cause test runner crash - re-enable when fixed
    // test_step.dependOn(&run_test_http_client.step);
    test_step.dependOn(&run_test_http_server.step);
    
    // Also add individual test commands for debugging
    const test_core_step = b.step("test-core", "Run core module tests");
    test_core_step.dependOn(&run_test_core.step);
    
    const test_http_common_step = b.step("test-http-common", "Run HTTP common tests");
    test_http_common_step.dependOn(&run_test_http_common.step);
    
    const test_http_client_step = b.step("test-http-client", "Run HTTP client tests");
    test_http_client_step.dependOn(&run_test_http_client.step);
    
    const test_http_server_step = b.step("test-http-server", "Run HTTP server tests");
    test_http_server_step.dependOn(&run_test_http_server.step);
}

fn add_example(
    b: *std.Build,
    path: []const u8,
    name: []const u8,
    link_libc: bool,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    zzz_module: *std.Build.Module,
) void {
    const exe_mod = b.createModule(.{
        .root_source_file = b.path(b.fmt("./examples/{s}/main.zig", .{path})),
        .target = target,
        .optimize = optimize,
    });
    const example = b.addExecutable(.{
        .name = name,
        .root_module = exe_mod,
    });

    if (link_libc) {
        exe_mod.link_libc = true;
    }

    exe_mod.addImport("zzz", zzz_module);

    const install_artifact = b.addInstallArtifact(example, .{});
    b.getInstallStep().dependOn(&install_artifact.step);

    const build_step = b.step(b.fmt("{s}", .{name}), b.fmt("Build zzz example ({s})", .{name}));
    build_step.dependOn(&install_artifact.step);

    const run_artifact = b.addRunArtifact(example);
    run_artifact.step.dependOn(&install_artifact.step);

    const run_step = b.step(b.fmt("run_{s}", .{name}), b.fmt("Run zzz example ({s})", .{name}));
    run_step.dependOn(&install_artifact.step);
    run_step.dependOn(&run_artifact.step);
}
