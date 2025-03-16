const std = @import("std");

pub fn build(b: *std.Build) void {
    // WASM executable
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const wasm_exe = b.addExecutable(.{
        .name = "tinylisp",
        .root_source_file = b.path("src/wasm.zig"),
        .target = target,
        .optimize = .Debug,
    });
    wasm_exe.entry = .disabled;
    wasm_exe.rdynamic = true;
    b.installArtifact(wasm_exe);

    // Local executable
    const local_exe = b.addExecutable(.{
        .name = "tinylisp",
        .root_source_file = b.path("src/main.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });

    const local_exe_install = b.addInstallArtifact(local_exe, .{});
    const local_step = b.step("local", "Build the local executable");
    local_step.dependOn(&local_exe_install.step);

    const local_exe_run_cmd = b.addRunArtifact(local_exe);
    local_exe_run_cmd.step.dependOn(&local_exe_install.step);
    const run_step = b.step("run", "Run the local executable");
    run_step.dependOn(&local_exe_run_cmd.step);
}
