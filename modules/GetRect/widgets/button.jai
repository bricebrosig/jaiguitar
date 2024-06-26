update_action_durations :: (state: *Button_State, theme: *Button_Theme, begin: bool, dt: float) -> (pressed_flash_factor: float) {
    if begin {
        state.action_duration   = 0;
        state.action_duration_2 = 0;
    }

    pressed_factor := 0.0;
    if state.action_duration >= 0 {  // Some juice when you push the button.
        state.action_duration += dt;
        denom := theme.press_duration;
        if !denom  denom = 1;

        factor    := (state.action_duration / denom);
        pressed_factor = 1 - factor;
        if pressed_factor < 0  state.action_duration = -1;

        Clamp(*pressed_factor, 0, 1);
        pressed_factor *= pressed_factor;
    }

    if state.action_duration_2 >= 0 {  // Some juice when you push the button.
        state.action_duration_2 += dt;
    }

    return pressed_factor;
}

update_production_value_button :: (r: Rect, changed: bool, state: *Button_State, status: Status_Flags, theme: *Button_Theme) {
    dt := state.cosmetic_dt;

    if !dt {
        if state_stack {
            // If this is a subwidget, give it the cosmetic_dt of the parent widget.
            // Why? Because states have Button_States on them, etc, that they want t

            widget := peek(state_stack);
            dt = widget.cosmetic_dt;
        }
    }

    update_over_state(state, theme, status, dt);

    pressed_factor := update_action_durations(state, theme, changed, dt);

    blend_factor := sin(TAU * state.over_duration * .5);
    blend_factor += 1;
    blend_factor *= .5;
    Clamp(*blend_factor, 0, 1);

    STROBE_BASE   :: .6;
    STROBE_HEIGHT :: .4;

    base := STROBE_BASE * state.over_effect_t;
    over_factor := base + state.over_effect_t * blend_factor * .4;

    state.over\  _factor = over\  _factor;
    state.pressed_factor = pressed_factor;
}

update_over_state :: (state: *Button_State, theme: *Button_Theme, status: Status_Flags, dt: float) {
    if status & .OVER {
        state.over_effect_t = move_toward(state.over_effect_t, 1, dt * theme.over_fade_in_speed);
        state.over_duration += dt;
    } else {
        state.over_effect_t = move_toward(state.over_effect_t, 0, dt * theme.over_fade_out_speed);
        if !state.over_effect_t  state.over_duration = 0;
    }

    if status & .DOWN {
        state.down_effect_t = move_toward(state.down_effect_t, 1, dt * theme.down_fade_in_speed);
        state.down_duration += dt;
    } else {
        state.down_effect_t = move_toward(state.down_effect_t, 0, dt * theme.down_fade_out_speed);
        if !state.down_effect_t  state.down_duration = 0;
    }
}

core_draw_button_label :: (r: Rect, text: string, state: *Button_State, theme: *Button_Theme) {
    color := theme.text_color;
    color = lerp(color, theme.text_color_over,    state.over_factor);
    color = lerp(color, theme.text_color_pressed, state.pressed_factor);

    if color.w {
        label_theme := theme.label_theme;  // @Cleanup?
        label_theme.text_color = color;

        font := label_theme.font;
        if !font {
            pixels := max(r.h*.65, .1);
            font = get_default_font_at_size(pixels);
            label_theme.font = font;
        }

        off_t := state.down_effect_t*state.down_effect_t;  // Bias toward less offset, to kinda sync it better with the color offsets... make it look like it springs back faster.
        sx := em(theme.text_offset_down.x, font) * off_t;
        sy := em(theme.text_offset_down.y, font) * off_t;
        _r := r;
        _r.x += sx;
        _r.y += sy;
        _r.x += state.frame_pixels;
        _r.w -= 2*state.frame_pixels;

        label(_r, text, *label_theme);
    }
}

core_draw_button :: (r: Rect, text: string, state: *Button_State, status: Status_Flags, theme: *Button_Theme, texture: *Texture) {
    if !theme  theme = *default_overall_theme.button_theme;

    changed := cast(bool)(status & .PRESSED);
    update_production_value_button(r, changed, state, status, theme);

    if !is_visible_in_scissor(r) return;
    if theme.properties & .DO_NOT_DRAW      return;

    surface_color, frame_color, frame_thickness := get_colors_and_thickness_for_button(theme, state);
    draw_procs.set_shader_for_color(true);

    state.frame_pixels = rounded_rectangle(r, theme.rectangle_shape, surface_color, frame_color, frame_thickness_override = frame_thickness);

    if text  core_draw_button_label(r, text, state, theme);

    if texture {
        color := theme.text_color;

        color = lerp(color, theme.text_color_over,    state.over_factor);
        color = lerp(color, theme.text_color_pressed, state.pressed_factor);
        if color.w {
            p0, p1, p2, p3 := get_quad(r);
            draw_procs.set_shader_for_images(texture);
            center := lerp(p0, p2, .5);

            s := theme.texture_scale;
            q0 := lerp(center, p0, s);
            q1 := lerp(center, p1, s);
            q2 := lerp(center, p2, s);
            q3 := lerp(center, p3, s);

            v0 := 0.0;
            v1 := 1.0;
            if theme.properties & .TEXTURE_LEFT_HANDED {
                v0 = 1;
                v1 = 0;
            }

            u0 := v2(0, v0);
            u1 := v2(1, v0);
            u2 := v2(1, v1);
            u3 := v2(0, v1);
            draw_procs.immediate_quad(q0, q1, q2, q3, color, u0, u1, u2, u3);
        }
    }
}

button :: (r: Rect, text: string, theme: *Button_Theme = null, identifier: s64 = 0, loc := #caller_location, texture: *Texture = null, disable_over := false, disable_press := false) -> (was_just_pressed: bool, state: *Button_State, was_just_released: bool) {
    if !theme  theme = *default_overall_theme.button_theme;

    hash   := get_hash(loc, identifier);
    state  := find_or_create_state(Button_State, hash);
    defer stop_using_state(state);

    status := get_status_flags(r);
    if disable_press status &= ~.PRESSED;
    if disable_over  status = 0;

    state.status = status;
    state.rect   = r;

    released := false;

    result := false;
    if theme.properties & .TOGGLE {
        if status & .PRESSED {
            state.pressed = !state.pressed;
            result = state.pressed;
            // NOTE(Charles): There seemed to be no way (for a user) to tell that a a toggle button has just changed
            // from toggled on, to toggled off. To achieve what I wanted I changed it so was_just_pressed is true
            // when turned on, was_just_released is true when turned off.
            // This means there is no way to do stuff on release of the button when changing state.
            released = !result;
            active_widget_deactivate_all();
        }
    } else {
        if state.pressed {
            if !(mouse_button_left_state & .DOWN) {
                if status & .OVER released = true;
                state.pressed = false;
                active_widget_deactivate_all();
            }
        } else {
            if status & .PRESSED {
                state.pressed = true;
                result = true;
                active_widget_deactivate_all();
            }
        }
    }

    if state.pressed {
        // This just tells core_draw_button that we are pressed. @Cleanup, it is kinda dumb?
        status |= .DOWN;
    }

    core_draw_button(r, text, state, status, theme, texture);


    if theme.draw_callback {
        theme.draw_callback(r, text, theme, texture, state);
    }

    return result, state, released;
}

get_colors_and_thickness_for_button :: (theme: *Button_Theme, state: *Button_State) -> (surface_color: Vector4, frame_color: Vector4, frame_thickness: float) {
    surface_color := theme.surface_color;
    surface_color = lerp(surface_color, theme.surface_color_over,  state.over_factor);
    surface_color = lerp(surface_color, theme.surface_color_down,  state.down_effect_t);
    surface_color = lerp(surface_color, theme.surface_color_flash, state.pressed_factor);

    // @Copypasta from button.jai:
    // We should probably make a central routine for this?!?
    frame_thickness := FLOAT32_INFINITY;
    if theme.enable_variable_frame_thickness {
        frame_thickness = lerp(theme.rectangle_shape.frame_thickness, theme.frame_thickness_over, state.over_factor);
        frame_thickness = lerp(frame_thickness, theme.frame_thickness_down, state.down_effect_t);
        frame_thickness = lerp(frame_thickness, theme.frame_thickness_flash, state.pressed_factor);
    }

    frame_color := theme.frame_color;
    frame_color = lerp(frame_color, theme.frame_color_over,  state.over_factor);
    frame_color = lerp(frame_color, theme.frame_color_down,  state.down_effect_t);
    frame_color = lerp(frame_color, theme.frame_color_flash, state.pressed_factor);

    return surface_color, frame_color, frame_thickness;
}

/*
Rounded_Rectangle_Point :: struct {
    inner: Vector2;
    frame: Vector2;
    outer: Vector2;
}
*/

get_roundedness_for_rect :: (r: Rect, type: Size_Computation, roundedness: float, global_value: float, limit := 0.5) -> float {
    radius_pixels := get_float_parameter(r, type, roundedness, global_value);

    shortest := min(r.w, r.h);
    Clamp(*radius_pixels, 0, shortest*limit);
    radius_pixels = floor(radius_pixels + .5);

    return radius_pixels;
}

rounded_rectangle :: (r: Rect, shape: Rectangle_Shape, color: Vector4, frame_color: Vector4, frame_thickness_override := FLOAT32_INFINITY /*, return_points := false*/) -> (frame_pixels: float, actual_roundedness: float/*, points: [] Rounded_Rectangle_Point*/) {
/*
    points: [..] Rounded_Rectangle_Point;  // We only fill this if return_points == true.
    points.allocator = temp;
*/

    radius_pixels := get_roundedness_for_rect(r, shape.roundedness_type, shape.roundedness, global_rounding_radius_in_pixels, .5);

    draw_procs.set_shader_for_color(true);
    frame_pixels := get_float_parameter(r, shape.frame_thickness_type, shape.frame_thickness, global_frame_thickness_in_pixels);
    shortest := min(r.w, r.h);
    Clamp(*frame_pixels, 0, shortest*.5);

    if (frame_pixels > 0) && (frame_pixels < 1) frame_pixels = 1;  // Give them at least 1 pixel if they are asking for a frame...
    frame_pixels = floor(frame_pixels + .5);

    if !frame_color.w  frame_pixels = 0;  // Kill drawing of the frame.
    if (color.w == 0) && (frame_pixels == 0) return 0, 0;  // Early out and do not draw!

    flags := shape.rounding_flags;
    if radius_pixels == 0 {
        flags = 0;  // Just don't do corners, but, go do the rest of the code, because we want to draw frames etc and don't want to dupe that code here.
    }

    extra_w := radius_pixels;
    extra_h := radius_pixels;

    // i0..i3: inside  vertices, of the interior quad.
    // o0..o7: outside vertices, that protrude out like flaps.
    // f0..f7: frame   vertices, recessed by frame_pixels from the outside vertices.

    p0, p1, p2, p3 := get_quad(r, snap_coordinates=true);

    i0 := p0 + v2( extra_w,  extra_h);
    i1 := p1 + v2(-extra_w,  extra_h);
    i2 := p2 + v2(-extra_w, -extra_h);
    i3 := p3 + v2( extra_w, -extra_h);

    o0 := i0;
    o1 := i1;
    o2 := i1;
    o3 := i2;
    o4 := i2;
    o5 := i3;
    o6 := i3;
    o7 := i0;

    o0.y = p0.y;
    o1.y = p0.y;
    o2.x = p1.x;
    o3.x = p1.x;
    o4.y = p2.y;
    o5.y = p2.y;
    o6.x = p0.x;
    o7.x = p0.x;

    if color.w {
        draw_procs.immediate_quad(o0, o1, i1, i0, color);
        draw_procs.immediate_quad(i1, o2, o3, i2, color);
        draw_procs.immediate_quad(i3, i2, o4, o5, color);
        draw_procs.immediate_quad(o7, i0, i3, o6, color);
        draw_procs.immediate_quad(i0, i1, i2, i3, color);
    }

    f0, f1, f2, f3, f4, f5, f6, f7: Vector2 = ---;

    if frame_pixels {
        f0 = o0;
        f1 = o1;
        f2 = o2;
        f3 = o3;
        f4 = o4;
        f5 = o5;
        f6 = o6;
        f7 = o7;

        f0.y += frame_pixels;

        f1.y += frame_pixels;
        f2.x -= frame_pixels;
        f3.x -= frame_pixels;
        f4.y -= frame_pixels;
        f5.y -= frame_pixels;
        f6.x += frame_pixels;
        f7.x += frame_pixels;

        draw_procs.immediate_quad(o0, o1, f1, f0, frame_color);
        draw_procs.immediate_quad(f2, o2, o3, f3, frame_color);
        draw_procs.immediate_quad(f5, f4, o4, o5, frame_color);
        draw_procs.immediate_quad(o7, f7, f6, o6, frame_color);
    }

    denom := shape.pixels_per_edge_segment;
    if denom <= 0 {
        denom = 4.0;  // Fail over to some value. Who knows if this is a good idea.
    }

    num_segments := cast(s32) floor(TAU * radius_pixels / denom + .5);
    if num_segments < 1  num_segments = 1;

    dtheta := TAU * .25 * (1 / cast(float) num_segments);

    // @Speed: Vector3 stuff.
    i0_3 := to_vec3(i0);
    i1_3 := to_vec3(i1);
    i2_3 := to_vec3(i2);
    i3_3 := to_vec3(i3);

    for i: 0..num_segments - 1 {
        // @Speed: Record old theta and re-use.
        theta0 := dtheta * i;
        theta1 := theta0 + dtheta;

        ct0 := cos(theta0);
        ct1 := cos(theta1);
        st0 := sin(theta0);
        st1 := sin(theta1);

        w0 := v3(ct0*radius_pixels, st0*radius_pixels, 0);
        w1 := v3(ct1*radius_pixels, st1*radius_pixels, 0);

        v0 := v2(ct0*(radius_pixels-frame_pixels), st0*(radius_pixels-frame_pixels));
        v1 := v2(ct1*(radius_pixels-frame_pixels), st1*(radius_pixels-frame_pixels));

        q0 := i2_3 + w0;
        q1 := i2_3 + w1;
        if flags & .NORTHEAST  {
            draw_procs.immediate_triangle(i2_3, i2_3 + w0, i2_3 + w1, color, color, color);
            if frame_pixels  draw_procs.immediate_quad(i2 + v1, i2 + v0, i2 + w0.xy, i2 + w1.xy, frame_color);
        }

        if flags & .SOUTHWEST  {
            draw_procs.immediate_triangle(i0_3, i0_3 - w0, i0_3 - w1, color, color, color);
            if frame_pixels  draw_procs.immediate_quad(i0 - v1, i0 - v0, i0 - w0.xy, i0 - w1.xy, frame_color);
        }

        m0 := v3(-w0.y, w0.x, 0);
        m1 := v3(-w1.y, w1.x, 0);
        n0 := v2(-v0.y, v0.x);
        n1 := v2(-v1.y, v1.x);
        if flags & .NORTHWEST  {
            draw_procs.immediate_triangle(i3_3, i3_3 + m0, i3_3 + m1, color, color, color);
            if frame_pixels  draw_procs.immediate_quad(i3 + n1, i3 + n0, i3 + m0.xy, i3 + m1.xy, frame_color);
        }

        if flags & .SOUTHEAST  {
            draw_procs.immediate_triangle(i1_3, i1_3 - m0, i1_3 - m1, color, color, color);
            if frame_pixels  draw_procs.immediate_quad(i1 - n1, i1 - n0, i1 - m0.xy, i1 - m1.xy, frame_color);
        }
    }

    if !(flags & .NORTHEAST) {
        draw_procs.immediate_quad(i2, o3, p2, o4, color);

        // Our two quads are non-rectangular, so that we don't make a T junction
        // or generate unsightly alpha overlap.
        // See how much I care about you???

        if frame_pixels {
            f34 := v2(f3.x, f4.y);
            draw_procs.immediate_quad(f4, f34, p2, o4, frame_color);
            draw_procs.immediate_quad(f3, o3, p2, f34, frame_color);
        }
    }

    if !(flags & .NORTHWEST) {
        draw_procs.immediate_quad(o6, i3, o5, p3, color);

        if frame_pixels {
            f65 := v2(f6.x, f5.y);
            draw_procs.immediate_quad(f65, f5, o5, p3, frame_color);
            draw_procs.immediate_quad(o6, f6, f65, p3, frame_color);
        }
    }

    if !(flags & .SOUTHWEST) {
        draw_procs.immediate_quad(p0, o0, i0, o7, color);

        if frame_pixels {
            f70 := v2(f7.x, f0.y);
            draw_procs.immediate_quad(p0, f70, f7, o7, frame_color);
            draw_procs.immediate_quad(p0, o0, f0, f70, frame_color);
        }
    }

    if !(flags & .SOUTHEAST) {
        draw_procs.immediate_quad(o1, p1, o2, i1, color);

        if frame_pixels {
            f21 := v2(f2.x, f1.y);
            draw_procs.immediate_quad(o1, p1, f21, f1, frame_color);
            draw_procs.immediate_quad(f21, p1, o2, f2, frame_color);
        }
    }

    draw_procs.immediate_flush();

    return frame_pixels, radius_pixels;  // Sometimes used in scissoring.
}

#scope_export

Button_Theme :: struct {
    using label_theme: Label_Theme;

    rectangle_shape:   Rectangle_Shape;

    surface_color            := Vector4.{.08, .08, .08, 1.0};
    surface_color_over       := Vector4.{.15, .15, .20, 1.0};

    surface_color_flash      := Vector4.{.60, .77, .62, 1.0};
    surface_color_down       := Vector4.{.28, .28, .38, 1.0};  // When held down.

    text_color                = Vector4.{.82, .82, .82, 1.0};  // (Inherited from Label_Theme).
    text_color_over          := Vector4.{.95, .95, .95, 1.0};
    text_color_pressed       := Vector4.{.99, .99, .99, 1.0};  // @Cleanup: Should change this to "text_color_down".

    text_offset_down         := Vector2.{.12, -.12};  // In ems.

    // Default frame thickness comes from rectangle_shape.
    frame_thickness_over     := .04;
    frame_thickness_down     := .05;
    frame_thickness_flash    := .07;
    enable_variable_frame_thickness := false;

    frame_color              := Vector4.{.40, .40, .50, 1.0};
    frame_color_over         := Vector4.{.55, .55, .45, 1.0};
    frame_color_flash        := Vector4.{.99, .99, .65, 1.0};
    frame_color_down         := Vector4.{.75, .75, .55, 1.0};

    press_duration       := 0.7;    // The flash when you press the button.

    over_fade_in_speed   := 10.0;  // Higher is faster; 10 == 1/10 second for full fade in.
    over_fade_out_speed  := 4.0;   // 4 == 1/4 second for full fade in.

    down_fade_in_speed   := 12.0;
    down_fade_out_speed  := 4.0;

    highlight_lighten_parameter := .15; // For lighter theme colors, you might want more ligten and less darken.
    highlight_darken_parameter  := .6;

    alpha_scale := 1.0;  // @Incomplete: This does not yet do anything!

    texture_scale := 1.0;  // Relative to the size of the button, if a texture is being drawn.

    draw_callback: (r: Rect, text: string, theme: *Button_Theme, texture: *Texture, state: *Button_State);

    properties: enum u64 {
        TOGGLE              :: 0x1;
        TEXTURE_LEFT_HANDED :: 0x2;
        DO_NOT_DRAW         :: 0x4;  // If your callback wants to draw the entire button, set this to cause us to do nothing visual (but run all button logic).
    } = .TEXTURE_LEFT_HANDED;
}

Button_State :: struct #type_info_none {
    #as using widget: Active_Widget;

    hash:    u64;

    status: Status_Flags;
    rect:   Rect;

    frame_pixels: float;

    over_duration := 0.0;
    over_effect_t := 0.0;

    down_duration := 0.0;
    down_effect_t := 0.0;

    action_duration   := -1.0;  // Set to 0 when an action first happens.
    action_duration_2 := -1.0;  // Set to 0 when an action first happens.

    over_factor    := 0.0;
    pressed_factor := 0.0;

    pressed := false;

    user_data_float: float;
    user_data_s64:   s64;
}

