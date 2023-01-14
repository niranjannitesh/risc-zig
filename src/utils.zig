pub fn range(n: usize) []const void {
    return @as([*]const void, undefined)[0..n];
}
