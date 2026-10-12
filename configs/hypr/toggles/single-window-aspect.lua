-- Single-window aspect: a lone tile stays 16:9 and centred instead of stretching across a wide panel.
hl.config({
    layout = { single_window_aspect_ratio = { 16, 9 }, single_window_aspect_ratio_tolerance = 0.1 },
})
