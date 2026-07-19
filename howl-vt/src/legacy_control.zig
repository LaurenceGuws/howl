//! Names legacy control consequences retained for host inspection.

/// Identifies a legacy terminal mode transition retained for host observation.
pub const LegacyControlKind = enum {
    tek_point_plot,
    tek_graph,
    tek_incremental_plot,
    tek_alpha,
    tek_copy,
    tek_special_point_plot,
    tek_write_thru_short_dashed,
    hp_memory_lock,
};
