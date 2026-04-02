const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ExecResult = struct {
    stdout: []const u8,
    stderr: []const u8,
    success: bool,

    pub fn deinit(self: *ExecResult, allocator: Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

/// Execute a git command in the given directory.
/// Returns the captured stdout/stderr and whether the command succeeded.
pub fn exec(allocator: Allocator, repo_dir: []const u8, git_args: []const []const u8) !ExecResult {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    try argv.append(allocator, "git");
    try argv.appendSlice(allocator, git_args);

    var child = std.process.Child.init(argv.items, allocator);
    child.cwd = repo_dir;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    const max_output = 1024 * 1024;
    const stdout_result = child.stdout.?.readToEndAlloc(allocator, max_output) catch &.{};
    const stderr_result = child.stderr.?.readToEndAlloc(allocator, max_output) catch &.{};

    const term = try child.wait();
    const success = term.Exited == 0;

    return .{
        .stdout = stdout_result,
        .stderr = stderr_result,
        .success = success,
    };
}

/// Run `git init` in the given directory.
pub fn gitInit(allocator: Allocator, dir: []const u8) !ExecResult {
    return exec(allocator, dir, &.{"init"});
}

/// Run `git clone <url> <dir>`.
pub fn gitClone(allocator: Allocator, url: []const u8, dir: []const u8) !ExecResult {
    return exec(allocator, ".", &.{ "clone", url, dir });
}

/// Run `git add <paths...>` in the repo directory.
pub fn gitAdd(allocator: Allocator, repo_dir: []const u8, file_paths: []const []const u8) !ExecResult {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, "add");
    try argv.appendSlice(allocator, file_paths);
    return exec(allocator, repo_dir, argv.items);
}

/// Run `git commit -m <message>` in the repo directory.
pub fn gitCommit(allocator: Allocator, repo_dir: []const u8, message: []const u8) !ExecResult {
    return exec(allocator, repo_dir, &.{ "commit", "-m", message });
}

/// Run `git pull --rebase` in the repo directory.
pub fn gitPull(allocator: Allocator, repo_dir: []const u8) !ExecResult {
    return exec(allocator, repo_dir, &.{ "pull", "--rebase" });
}

/// Run `git push` in the repo directory.
pub fn gitPush(allocator: Allocator, repo_dir: []const u8) !ExecResult {
    return exec(allocator, repo_dir, &.{"push"});
}

/// Run `git status --porcelain` and return the output.
pub fn gitStatus(allocator: Allocator, repo_dir: []const u8) !ExecResult {
    return exec(allocator, repo_dir, &.{ "status", "--porcelain" });
}

/// Pass through arbitrary git arguments to the repo directory.
/// Stdout/stderr are inherited (shown directly to user).
pub fn passthrough(allocator: Allocator, repo_dir: []const u8, git_args: []const []const u8) !u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    try argv.append(allocator, "git");
    try argv.appendSlice(allocator, git_args);

    var child = std.process.Child.init(argv.items, allocator);
    child.cwd = repo_dir;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();
    const term = try child.wait();
    return term.Exited;
}

test "argv construction" {
    const allocator = std.testing.allocator;
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, "git");
    try argv.append(allocator, "status");
    try std.testing.expectEqual(@as(usize, 2), argv.items.len);
    try std.testing.expectEqualStrings("git", argv.items[0]);
}
