const std = @import("std");
const testing = std.testing;

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}

const module_bits = 12; 
const module_base = 1 << module_bits; 
// const module_ntt = 6597069766657; 
const module_ntt = 4179340454199820289; 
// const module_ntt = 469762049; 
const g = 3;

fn calcPow(origin: u128, power: u128, module: u128) u128 {
    var ans : u128 = 1; 
    var less_p: u128 = power; 
    var current: u128 = origin; 
    while (less_p != 0) : (less_p >>= 1) {
        if (less_p & 1 == 1) {
            ans = ans * current; 
            ans = ans % module; 
        } 
        current = current * current; 
        current = current % module; 
    }
    return ans; 
}

fn powerInline(x: u64, p: u64) u64 {
    var current: u128 = x; 
    var ans : u128 = 1; 
    var p_n : u64 = p; 
    while (p_n != 0) : (p_n >>= 1) {
        if (p_n & 1 == 1) {
            ans = ans * current; 
            ans = ans % module_ntt; 
        }
        current = current * current; 
        current = current % module_ntt; 
    } 
    return @intCast(ans); 
}

fn nTTImpl(src: [*]const u64, step: usize, length: usize, rst: []u64, buffer: []u64, q: u64) void {
    if (length == 1) {
        rst[0] = src[0]; 
        return ; 
    }
    std.debug.assert( rst.len == length ); 
    std.debug.assert( buffer.len == length ); 
    std.debug.assert( @popCount(length) == 1 ); 
    const half_len = @divExact(length, 2); 
    const qInner: u128 = q; 
    const q2 : u64 = @intCast( (qInner * qInner) % module_ntt ); 
    // nTTImpl(src, step * 2, half_len, rst[0..half_len], buffer[0..half_len], q2); 
    // nTTImpl(src + 1, step * 2, half_len, rst[half_len..], buffer[half_len..], q2); 
    // @memcpy(buffer, rst); 
    nTTImpl(src, step * 2, half_len, buffer[0..half_len], rst[0..half_len], q2); 
    nTTImpl(src + step, step * 2, half_len, buffer[half_len..], rst[half_len..], q2); 
    var starter: u128 = 1; 
    for (0..half_len) |i| {
        rst[i] = @intCast(starter); 
        starter = starter * q; 
        starter = starter % module_ntt; 
    }
    @memcpy(rst[half_len..], rst[0..half_len]);  
    for (rst[0..half_len], buffer[half_len..]) |*x, y| {
        const rx: u128 = x.*; 
        const y2: u128 = y; 
        const mul = ( rx * y2 ) % module_ntt; 
        x.* = @intCast(mul); 
    }
    for (rst[half_len..], buffer[half_len..]) |*x, y| {
        const rx: u128 = x.*; 
        const y2: u128 = y; 
        const mul = ( rx * y2 ) % module_ntt; 
        const mul2 = ( mul * (module_ntt - 1) ) % module_ntt; 
        x.* = @intCast(mul2); 
    }
    for (rst[0..half_len], buffer[0..half_len]) |*r, a| {
        const rx : u128 = r.*; 
        const ra : u128 = a; 
        r.* = @intCast( (rx + ra) % module_ntt ); 
    }
    for (rst[half_len..], buffer[0..half_len]) |*r, a| {
        const rx : u128 = r.*; 
        const ra : u128 = a; 
        r.* = @intCast( (rx + ra) % module_ntt ); 
    }
}

fn nTT(src: []const u64, rst: []u64, buffer: []u64) void {
    const length = src.len; 
    std.debug.assert(src.len == rst.len); 
    std.debug.assert(src.len == buffer.len); 
    std.debug.assert( @popCount(length) == 1 ); 
    const q = powerInline(3, (module_ntt - 1) / length); 
    return nTTImpl(src.ptr, 1, length, rst, buffer, q); 
}

fn iNTT(src: []const u64, rst: []u64, buffer: []u64) void {
    const length = src.len; 
    std.debug.assert(src.len == rst.len); 
    std.debug.assert(src.len == buffer.len); 
    std.debug.assert( @popCount(length) == 1 ); 
    const qInv = powerInline(g, module_ntt - 2); 
    const q = powerInline(qInv, (module_ntt - 1) / length); 
    std.log.warn("qInv: {d}", .{ qInv }); 
    const nInv = powerInline(src.len, module_ntt - 2); 
    nTTImpl(src.ptr, 1, length, rst, buffer, q); 
    for (rst) |*r| {
        var rr : u128 = r.*; 
        rr = rr * nInv; 
        rr = rr % module_ntt; 
        r.* = @intCast(rr); 
    }
}

fn multiplyEqLen(l_src: []const u64, r_src: []const u64, rst: []u64, buf0: []u64, buf1: []u64) u64 {
    std.debug.assert(l_src.len <= 1 << (61 - 24));
    nTT(l_src, buf0, rst); 
    nTT(r_src, buf1, rst); 
    for (buf0, buf1) |*b0, b1| { 
        var multi: u128 = b0.*; 
        multi = multi * b1; 
        multi = multi % module_ntt; 
        b0.* = @intCast(multi); 
    }
    iNTT(buf0, rst, buf1); 
    var less : u64 = 0; 
    for (rst) |*r| {
        r.* += less; 
        if (r.* >= module_base) {
            const to_add = r.* / module_base; 
            less = to_add; 
            r.* %= module_base; 
        } else {
            less = 0; 
        }
    }
    return less; 
}

test {
    const rst = calcPow(g, module_ntt - 2, module_ntt); 
    std.log.warn("rst: {d}", .{ rst }); 
}

test {
    const allo = std.testing.allocator; 
    var src = [_] u64 { 1, 2, 3, 4, 0, 0, 0, 0, }; 
    // var src2 = [_] u64 { 5, 6, 7, 8, 0, 0, 0, 0, }; 
    const target = try allo.alloc(u64, 8); 
    defer allo.free(target); 
    const buf = try allo.alloc(u64, 8); 
    buf[0] = 1; 
    defer allo.free(buf); 
    nTT(&src, target, buf); 
    for (target, 0..) |t, idx| {
        std.log.warn("[{d}]: {d}", .{ idx, t, } ); 
    }
    std.log.warn("start intt. ", .{}); 
    iNTT(target, buf, &src); 
    for (buf, 0..) |t, idx| {
        std.log.warn("[{d}]: {d}", .{ idx, t, } ); 
    }
}

test {
    const allo = std.testing.allocator; 
    var src = [_] u64 { 1, 2, 3, 4, 0, 0, 0, 0, }; 
    var src2 = [_] u64 { 5, 6, 7, 8, 0, 0, 0, 0, }; 
    const target = try allo.alloc(u64, 8); 
    defer allo.free(target); 
    const buf = try allo.alloc(u64, 8); 
    defer allo.free(buf); 
    const buf2 = try allo.alloc(u64, 8); 
    defer allo.free(buf2); 
    const r = multiplyEqLen(&src, &src2, target, buf, buf2); 
    std.log.warn("start multiply", .{}); 
    for (target, 0..) |t, i| {
        std.log.warn("[{d}]: {d}", .{ i, t }); 
    }
    std.log.warn("I Get: {d} as result. ", .{ r }); 
}