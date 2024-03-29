//
// The way this works is:
//
// Call slidable_region to start doing a slidable region. It will return you the top and bottom rects.
// Upon returning you will be scissored to the top rect and can draw in there.
//
// When you are done with the top and want to do the bottom, call switch_to_bottom_rect().
//
// When you are done with both, call finish().
//
// @Incomplete: We should assert that you remembered to call slidable_region_finish().
//

slidable_region :: (r: Rect, theme: *Slidable_Region_Theme = null, identifier: s64 = 0, loc := #caller_location) -> (state: *Slidable_Region_State, left_or_top_rect: Rect, right_or_bottom_rect: Rect, divider_rect: Rect) {
    if !theme  theme = *default_overall_theme.slidable_region_theme;

    hash   := get_hash(loc, identifier);
    state, created := find_or_create_state(Slidable_Region_State, hash);
    defer stop_using_state(state);

    state.theme = theme;

    // Figure out where the divider rect is and how big it is.

    divider_thickness_in_pixels := get_float_parameter(r, theme.divider_thickness_type, theme.divider_thickness, global_divider_thickness_in_pixels);

    active_pointer: Pointer_Image;
    
    slide_dimension: float;
    slide_vector:    Vector2 = ---;
    if theme.orientation == .HORIZONTAL {
        slide_dimension = r.w;
        slide_vector    = .{x=1};
        active_pointer  = .DRAGGING_HORIZONTAL;
    } else {
        slide_dimension = r.h;
        slide_vector    = .{y=1};  // Because we are thinking about top as being first, as layout goes top to bottom. Sigh!!
        active_pointer  = .DRAGGING_VERTICAL;
    }

    
    divider_offset_in_pixels := get_float_parameter(r, theme.initial_divider_position_type, theme.initial_divider_position, global_initial_divider_position_in_pixels);
    
    if created {
        denom := slide_dimension;
        if denom == 0  denom = 1;
        state.divider_t = divider_offset_in_pixels / denom;
    }

    //
    // Do dragging to update the divider rect.
    //

    // Get the divider rect the first time, because we need to know its current value
    // to handle input in a low-latency and accurate way! If we move the divider,
    // we'll call this again.
    top, divider_rect, bottom := compute_rects(r, state, divider_thickness_in_pixels);

    
    changed := false;
    divider_status := get_status_flags(divider_rect);
    if state.dragging  divider_status |= .OVER;
    
    if divider_status & .OVER {
        if (mouse_button_left_state & .START) && !state.dragging {
            state.dragging = true;
            changed = true;
            active_widget_add(state, true);
        }
    }


    focus := has_focus(r);
    down  := focus && (mouse_button_left_state & .DOWN);
    if state.dragging {
        if down {
            dir      := v2(mouse_delta_x_float, mouse_delta_y_float);
            moved_xy := slide_vector * dot_product(dir, slide_vector);

            // One of the coordinates of 'moved' will be 0, so let's just add them.
            moved   := moved_xy.x + moved_xy.y;
            if moved {
                denom := slide_dimension;
                if !denom denom = 1;
                state.divider_t += moved / denom;
                Clamp(*state.divider_t, 0, 1);
                
                // Recompute the rects since the divider moved!
                top, divider_rect, bottom = compute_rects(r, state, divider_thickness_in_pixels);
            }
        } else {
            state.dragging = false;
            active_widget_remove(state);
        }
    }

    if state.dragging || (divider_status & .OVER) {
        draw_procs.set_pointer_image(active_pointer, state);
    }
    
    update_production_value_button(divider_rect, changed, *state.divider_state, divider_status, *theme.divider_theme);

    state.left_or_top_rect     = top;
    state.right_or_bottom_rect = bottom;
    state.divider_rect         = divider_rect;

    state.divider_over_factor    = state.divider_state.over_factor;    // @Cleanup @Redundant
    state.divider_pressed_factor = state.divider_state.pressed_factor; // @Cleanup @Redundant


    //
    // Draw the backgrounds, then push scissor.
    //
    draw_procs.set_shader_for_color(true);

    b := *theme.first_background;
    rounded_rectangle(top, b.shape, b.color, b.frame_color);
    
    b  = *theme.second_background;
    rounded_rectangle(bottom, b.shape, b.color, b.frame_color);

    draw_procs.immediate_flush();
    
    push_scissor(state.left_or_top_rect);
    
    return state, top, bottom, divider_rect;
}

switch_to_bottom_rect :: switch_to_second_rect;
switch_to_right_rect  :: switch_to_second_rect;
switch_to_second_rect :: (state: *Slidable_Region_State)  {
    // @Robustness: Ensure this is the right scissor.
    pop_scissor();

    push_scissor(state.right_or_bottom_rect);
} 

switch_to_top_rect   :: switch_to_first_rect;
switch_to_left_rect  :: switch_to_first_rect;
switch_to_first_rect :: (state: *Slidable_Region_State)  {
    // We set this up already in slidable_region, but if for some reason you want to switch
    // back and forth between top and bottom regions, we let you do that.
    pop_scissor();
    push_scissor(state.left_or_top_rect);
}

finish :: (state: *Slidable_Region_State) {
    // @Incomplete: Assert that the clip rectangle is owned by us.

    pop_scissor();

    t := *state.theme.divider_theme;

    draw_procs.set_shader_for_color(true);
    color, frame_color, frame_thickness := get_colors_and_thickness_for_button(t, *state.divider_state);
    
    rounded_rectangle(state.divider_rect, t.rectangle_shape, color, frame_color, frame_thickness);
}


#scope_file

compute_rects :: (r: Rect, state: *Slidable_Region_State, divider_thickness_in_pixels: float) -> (top: Rect, divider: Rect, bottom: Rect) {
    half := divider_thickness_in_pixels * .5;
    theme := state.theme;

    top, middle, divider_rect, bottom: Rect = ---;
    if theme.orientation == .HORIZONTAL {
        x := r.w * state.divider_t - half;
        Clamp(*x, 0, r.w - divider_thickness_in_pixels);
        top, middle          = cut_left(r, x);
        divider_rect, bottom = cut_left(middle, divider_thickness_in_pixels);
    } else {
        y := r.h * state.divider_t - half;
        Clamp(*y, 0, r.h - divider_thickness_in_pixels);
        bottom, middle       = cut_bottom(r, y);
        divider_rect, top    = cut_bottom(middle, divider_thickness_in_pixels);
    }

    return top, divider_rect, bottom;
}

#scope_export

Slidable_Region_Theme :: struct {
    orientation: enum u8 {
        HORIZONTAL :: 0;
        VERTICAL   :: 1;
    }

    divider_theme: Button_Theme;
    divider_theme.surface_color       = .{.4, .6, .7, 1};
    divider_theme.surface_color_over  = .{.7, .8, .9, 1};
    divider_theme.surface_color_down  = .{.8, .9, .95, 1};
    divider_theme.surface_color_flash = .{.9, .87, .99, 1};

    divider_thickness_type := Size_Computation.ABSOLUTE_FROM_GLOBAL;
    divider_thickness      := .02;

    initial_divider_position_type := Size_Computation.RELATIVE_TO_HEIGHT;
    initial_divider_position      := 0.5;

    first_background:  Background_Theme;    
    second_background: Background_Theme;

    first_background.shape.frame_thickness_type  = .ABSOLUTE_FROM_GLOBAL;
    first_background.shape.rounding_flags        = Rectangle_Shape.Rounding_Flags.NORTHWEST | .SOUTHWEST;
    second_background.shape.frame_thickness_type = .ABSOLUTE_FROM_GLOBAL;
    second_background.shape.rounding_flags       = Rectangle_Shape.Rounding_Flags.NORTHEAST | .SOUTHEAST;
}

Slidable_Region_State :: struct #type_info_none {
    #as using widget: Active_Widget;
    
    divider_state:  Button_State;

    left_or_top_rect:     Rect;
    right_or_bottom_rect: Rect;
    divider_rect:         Rect;
    theme:                *Slidable_Region_Theme;

    divider_t:              float;  // Divider position as a fraction of the input rect's slide_dimension.
    divider_over_factor:    float;  // @Cleanup: Probably we should leave this stuff on Button_State and just refer to it there. It'd be more compact?
    divider_pressed_factor: float; 
    
    dragging    := false;
}

