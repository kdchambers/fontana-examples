// SPDX-License-Identifier: MIT
// Copyright (c) 2022 Keith Chambers

pub fn Extent2D(comptime BaseType: type) type {
    return packed struct {
        x: BaseType,
        y: BaseType,
        height: BaseType,
        width: BaseType,
    };
}