#import "GetRect";

SCALE :: 1;  // use this during development to quickly make the window real big.

my_window: Window_Type;
window_width : s32 = 1920*SCALE;
window_height: s32 = 1080*SCALE;

current_time: float64;
last\  _time: float64;

current_theme: s32 = xx Default_Themes.Default;
my_theme: Overall_Theme;  // This gets filled out by calling the Theme_Proc for current_theme.

// we are using an enum here mostly because we have to have an enum to use the radio button
// and that makes things very easy
Fret :: enum s32 {
    NONE :: -1; 
    ZERO :: 0;
    ONE; TWO; THREE; FOUR; FIVE; SIX; SEVEN; EIGHT; NINE; TEN;
    ELEVEN; TWELVE; THIRTEEN; FOURTEEN; FIFTEEN; SIXTEEN; SEVENTEEN;
    EIGHTEEN; NINETEEN; TWENTY; TWENTY_ONE;
}

SharpsOrFlats :: enum { SHARPS; FLATS; }
sharps_or_flats : SharpsOrFlats = .SHARPS;

                   // 0     1     2     3     4     5     6     7     8     9     10    11
flats : []string = .["A ", "Bb", "B ", "C ", "Db", "D ", "Eb", "E ", "F ", "Gb", "G ", "Ab"];
sharps: []string = .["A ", "A#", "B ", "C ", "C#", "D ", "D#", "E ", "F ", "F#", "G ", "G#"];

tuning: []int = .[7, 2, 10, 5, 0, 7];  // tuning of the strings, BACKWARDS

get_note :: (g_string: Fret, fret: int, offset: int) -> string {
    if fret >= 0 && fret == cast(int) g_string {
        if sharps_or_flats == {
            case .FLATS ;  return flats[(offset + fret) % 12];
            case .SHARPS;  #through;
            case; return sharps[(offset + fret) % 12];
        }
    }
    return "  ";
}


// the strings
// TODO (brice): support for 7 strings? 8 strings?
string_1: Fret = 0;
string_2: Fret = 0;
string_3: Fret = 0;
string_4: Fret = 0;
string_5: Fret = 0;
string_6: Fret = 0;

main :: () {
    #if OS == .WINDOWS {
        Windows :: #import "Windows";
        Windows.SetProcessDPIAware();

        // Windows is very bad at thread-switching by default unless you do this. Sad.
        Windows.timeBeginPeriod(1);
    }

    my_window = create_window(window_width, window_height, "Guitar");
    #if OS == .WINDOWS {
        // @Feature: Add user-specific typelist support.
        Windows.DragAcceptFiles(my_window, cast(Windows.BOOL) true);
    } else #if OS == .LINUX {
        X11 :: #import "X11";
        typelist := string.["url/url", "text/uri-list", "text/plain", "application/octet-stream"];
        X11.enable_drag_and_drop(my_window, typelist);
    } else #if OS == .MACOS {
        #import "Objective_C";
        #import "Objective_C/AppKit";
        types := NSArray(NSPasteboardType).arrayWithObject(NSPasteboardTypeFileURL);
        NSView.registerForDraggedTypes(my_window, types);
    }

    Simp.set_render_target(my_window);

    init_fonts();
    ui_init();
    
    quit := false;
    while !quit {
        current_time = get_time();
        dt := cast(float)(current_time - last_time);
        Clamp(*dt, 0, 0.1);
        last_time = current_time;

        Input.update_window_events();

        for Input.get_window_resizes() {
            Simp.update_window(it.window);

            if it.window == my_window {
                should_reinit := (it.width != window_width) || (it.height != window_height);

                window_width  = it.width;
                window_height = it.height;

                if should_reinit init_fonts();  // Resize the font for the new window size.
            }
        }

        for event: Input.events_this_frame {
            if event.type == .QUIT then quit = true;

            getrect_handle_event(event);

            if event.type == {
              case .KEYBOARD;
                if event.key_pressed && event.key_code == .ESCAPE {
                    active_widget_deactivate_all();
                }
            }
        }

        draw_one_frame(dt);

        reset_temporary_storage();
        sleep_milliseconds(10);
    }
}

draw_one_frame :: (dt: float) {
    proc := default_theme_procs[current_theme];
    my_theme = proc();
    set_default_theme(my_theme);  // Just in case we don't explicitly pass themes sometimes...!

    bg_col := my_theme.background_color;
    Simp.clear_render_target(bg_col.x, bg_col.y, bg_col.z, 1);

    x, y, width, height := get_dimensions(my_window, true);
    ui_per_frame_update(my_window, width, height, current_time);

    // TODO (brice): cleanup the theme stuff
    radio_theme := my_theme.checkbox_theme;
    radio_theme.font = button_font; // @Cleanup: We have to manually set a font for now.
    radio_theme.is_radio_button = true;
    
    ch    := cast(float) button_font.character_height;  // TODO (brice): chose size not based on the font size
    cw    := cast(float) button_font.em_width;
    h_mid := cast(float) (window_height / 2);
    
    fret_width  := cast(float) (window_width * .8) / 22;
    fret_height := cast(float) (window_height / 18);
    
    //
    // sharps or flats toggle
    //
    
    r := get_rect(window_width * .8, h_mid + 4 * fret_height, 7 * cw, ch);
    radio_button(r, "Sharps", *sharps_or_flats, .SHARPS, *radio_theme);
    r.x += r.w;
    radio_button(r, "Flats",  *sharps_or_flats,  .FLATS, *radio_theme);
    
    //
    // draw "strings"
    //

    r1 := get_rect(window_width * .1, h_mid,                 fret_width, fret_height);
    r2 := get_rect(window_width * .1, h_mid -   fret_height, fret_width, fret_height);
    r3 := get_rect(window_width * .1, h_mid - 2*fret_height, fret_width, fret_height);
    r4 := get_rect(window_width * .1, h_mid - 3*fret_height, fret_width, fret_height);
    r5 := get_rect(window_width * .1, h_mid - 4*fret_height, fret_width, fret_height);
    r6 := get_rect(window_width * .1, h_mid - 5*fret_height, fret_width, fret_height);

    text_x := cast(s64) (window_width * .1);
    text_y := cast(s64) (h_mid + fret_height / 4);
    text_color: Vector4 = .{200, 200, 220, 255};
    
    characters_to_draw := string.["e","B","G","D","A","E"];
    for char: characters_to_draw {
        text_width := Simp.prepare_text(my_font, char);
        Simp.draw_prepared_text(my_font, text_x - cast(s64) (3 * cw), text_y, color=text_color);
        text_y -= cast(s64) fret_height;
    }
    
    text_y = cast(s64) (h_mid - 6 * fret_height);
    
    radio_button(r1, get_note(string_1, -1, tuning[0]), *string_1, cast(Fret) -1, *radio_theme);
    radio_button(r2, get_note(string_2, -1, tuning[1]), *string_2, cast(Fret) -1, *radio_theme);
    radio_button(r3, get_note(string_3, -1, tuning[2]), *string_3, cast(Fret) -1, *radio_theme);
    radio_button(r4, get_note(string_4, -1, tuning[3]), *string_4, cast(Fret) -1, *radio_theme);
    radio_button(r5, get_note(string_5, -1, tuning[4]), *string_5, cast(Fret) -1, *radio_theme);
    radio_button(r6, get_note(string_6, -1, tuning[5]), *string_6, cast(Fret) -1, *radio_theme);
    
    text_width := Simp.prepare_text(my_font, "x  ");
    Simp.draw_prepared_text(my_font, cast(s64) r1.x, text_y, color=text_color);
    
    r1.x += r1.w;
    r2.x += r2.w;
    r3.x += r3.w;
    r4.x += r4.w;
    r5.x += r5.w;
    r6.x += r6.w;
    text_x = cast(s64) r6.x;
    
    for 0..21 {
        radio_button(r1, get_note(string_1, it, tuning[0]), *string_1, cast(Fret) it, *radio_theme, it);
        radio_button(r2, get_note(string_2, it, tuning[1]), *string_2, cast(Fret) it, *radio_theme, it);
        radio_button(r3, get_note(string_3, it, tuning[2]), *string_3, cast(Fret) it, *radio_theme, it);
        radio_button(r4, get_note(string_4, it, tuning[3]), *string_4, cast(Fret) it, *radio_theme, it);
        radio_button(r5, get_note(string_5, it, tuning[4]), *string_5, cast(Fret) it, *radio_theme, it);
        radio_button(r6, get_note(string_6, it, tuning[5]), *string_6, cast(Fret) it, *radio_theme, it);
        
        // TODO (brice): make a quick draw_text function
        text_width := Simp.prepare_text(my_font, tprint("%", formatInt(it, padding=3)));
        Simp.draw_prepared_text(my_font, text_x, text_y, color=text_color);
         
        r1.x += r1.w;
        r2.x += r2.w;
        r3.x += r3.w;
        r4.x += r4.w;
        r5.x += r5.w;
        r6.x += r6.w;
        text_x = cast(s64) r6.x;
    }
    
    //
    // draw chords
    //
    
    // r = get_rect(window_width * .1, window_height * .1, cast(float) title_font.em_width, cast(float) title_font.character_height)
    Simp.prepare_text(title_font, "Cmaj7add9");
    Simp.draw_prepared_text(title_font, cast(s64) (window_width * .1), cast(s64) (window_height * .8), color=text_color);

    Simp.swap_buffers(my_window);
}  // draw_one_frame

init_fonts :: () {
    if !working_directory_set {
        // So that we can load our font, set to path of running executable.
        path := path_strip_filename(get_path_of_running_executable());
        set_working_directory(path);

        working_directory_set = true;
    }

    pixel_height := window_height / 24;
    my_font = Simp.get_font_at_size("data", "OpenSans-BoldItalic.ttf", pixel_height);
    assert(my_font != null);

    pixel_height /= 2;
    button_font = Simp.get_font_at_size("data", "OpenSans-BoldItalic.ttf", pixel_height);
    assert(button_font != null);

    pixel_height = window_height / 7;
    title_font = Simp.get_font_at_size("data", "OpenSans-BoldItalic.ttf", pixel_height);
}

Font :: Simp.Dynamic_Font;

my_font:     *Font;
button_font: *Font;
title_font:  *Font;

working_directory_set := false;

Simp  :: #import "Simp";
Input :: #import "Input";

#import "Window_Creation";

#import "Basic";
Basic :: #import "Basic"; // :CompilerBug  We need this to resolve to_lower for some reason?!
#import "Math";
#import "System";  // For get_path_of_running_executable. @Cleanup.
#import "String";  // For path_strip_filename. @Cleanup.

modify_string :: (ps: *string, new_value: string) {
    free(ps.*);
    ps.* = copy_string(new_value);
}