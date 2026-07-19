//! Typed rectangular protocol and copy request values.

/// Zero-based rectangular area whose optional lower bounds extend to the page edge.
pub const RectArea = struct {
    top: u16,
    left: u16,
    bottom: ?u16,
    right: ?u16,
};

/// Optional rectangular locator filter coordinates.
pub const OptionalRectArea = struct {
    top: ?u16,
    left: ?u16,
    bottom: ?u16,
    right: ?u16,
};

/// Page-qualified rectangular copy request.
pub const RectCopy = struct {
    area: RectArea,
    source_page: u16,
    dest_top: u16,
    dest_left: u16,
    dest_page: u16,
};
