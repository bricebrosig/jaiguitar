SCALE :: 1;  // use this during development to quickly make the window real big.

my_window: Window_Type;
window_width : s32 = 1920 * SCALE;
window_height: s32 = 1080 * SCALE;

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

// indexes into our flats / sharps array - only supporting flats here because it is purely for convenience
A  :: 0;
Bb :: 1;
B  :: 2;
C  :: 3;
Db :: 4;
D  :: 5;
Eb :: 6;
E  :: 7;
F  :: 8;
Gb :: 9;
G  :: 10;
Ab :: 11;

//
// our definition of a pitch in this program follows the table from
// scientific pitch notation https://en.wikipedia.org/wiki/Scientific_pitch_notation
Pitch :: struct {
  note   : int;  // an index into our flats/sharps array
  octave : int;  // the octave this note is played at 
  
  // NOTE (brice): these might become useful at a later time - could also look them up from a table
  // freq   : float  // the frequency in Hz of this pitch
  // midi   : int  // the "midi number" of this pitch
}

chord :: struct {
  root  : int;
  major : bool;
  minor : bool;
  aug   : bool;
  dim   : bool;
  sus   : bool;
}

SharpsOrFlats :: enum { SHARPS; FLATS; }
sharps_or_flats : SharpsOrFlats = .SHARPS;

           // 0   1   2   3   4   5   6   7   8   9   10  11
flats : []string = .["A ", "Bb", "B ", "C ", "Db", "D ", "Eb", "E ", "F ", "Gb", "G ", "Ab"];
sharps: []string = .["A ", "A#", "B ", "C ", "C#", "D ", "D#", "E ", "F ", "F#", "G ", "G#"];

all_notes: []string;

tuning: [..]Pitch;

currently_fretted: [6]int;

get_interval_in_semitones :: (a: int, b: int) -> int {
  if a >= b {
    return 12 - (a - b);
  } else {
    return b - a;
  }
}

//
// choose between flat and sharp based on the global and then mod the semitone
// into the range of the notes
note :: (g_string: Fret, fret: int, offset: int) -> string {
  if fret >= 0 && fret == cast(int) g_string {
    return all_notes[(offset + fret) % 12];
  }
  return "  ";
}

pitch_class_to_int :: (pitch_class: []int) -> u16 {
  /*
  <0 4 5> -> 00000000 00110001
  */

  value :u16 = 1;
  for pitch_class {
    value |= cast(u16) 1 << cast(u16) it; 
  }
  return value;
}

/// given the fretted chords, compute the chords and write them to a string
/// TODO (brice): this algorithm is really naive...
compute_chords :: (str: *String_Builder, fretted: []int) {
  append(str, tprint("[%, %, %, %, %, %]\n", 
    cast(int) string_6,
    cast(int) string_5, 
    cast(int) string_4, 
    cast(int) string_3, 
    cast(int) string_2, 
    cast(int) string_1
  ));

  // get the bass note
  bass: int;
  for 0..5 {
    if fretted[it] == -1  continue;  // not playing this note
    bass = tuning[it].note + fretted[it];
  }

  table: Table(u16, void);

  for i: 0..3 {
    if fretted[i] == -1  continue;
    // establish a  root
    root := tuning[i].note + fretted[i];

    // get the intervals to other notes in the chord
    push_allocator(temp);  // this will defer switching back to previous allocator

    pitch_class: [..]int;  
    defer array_free(pitch_class);
    for j: 0..fretted.count-1 {
      if fretted[j] == -1  continue;
      if i != j {
        interval := get_interval_in_semitones(
          (tuning[i].note + fretted[i]) % 12, 
          (tuning[j].note + fretted[j]) % 12
        );
        if interval != 12 
          array_add_if_unique(*pitch_class, interval);
      }
    }

    quick_sort(pitch_class, x => x);

    // check duplicates first
    // if table_contains(*table, pitch_class_to_int(pitch_class))  continue;
    // the_void: void;
    // table_add(*table, pitch_class_to_int(pitch_class), the_void);
    
    //
    // name the chord
    
    // start with root
    append(str, tprint("%", all_notes[root % 12]));

    // TODO (brice): this is very very very silly
    has_second        := array_find(pitch_class,  2);
    has_minor_third   := array_find(pitch_class,  3);
    has_major_third   := array_find(pitch_class,  4);
    has_fourth        := array_find(pitch_class,  5);
    has_dim_fifth     := array_find(pitch_class,  6);
    has_perfect_fifth := array_find(pitch_class,  7);
    has_aug_fifth     := array_find(pitch_class,  8);
    has_sixth         := array_find(pitch_class,  9);
    has_minor_seven   := array_find(pitch_class, 10);
    has_major_seven   := array_find(pitch_class, 11);
    is_sus            := false;
    modded_five       := false;
    
    if has_major_third && has_aug_fifth {
      append(str, "Aug ");
      modded_five = true;
    }
    
    if has_minor_third && has_dim_fifth {
      append(str, "Dim ");
      modded_five = true;
    }
    
    if has_major_third {
      append(str, "Major ");
    } else if has_minor_third {
      append(str, "Minor ");
    }
    
    if has_minor_seven {
      append(str, "min7 ");
    } else if has_major_seven {
      append(str, "maj7 ");
    }
    
    if !has_major_third && !has_minor_third {
      is_sus = true;
      if has_second {
        append(str, "sus2 ");
      } else if has_fourth {
        append(str, "sus4 ");
      }
    }
    
    if !is_sus {
      if has_second {
        append(str, "add2 ");
      } else if has_fourth {
        append(str, "add4 ");
      }
    }
    
    if !has_perfect_fifth && !modded_five {
      if has_aug_fifth {
        append(str, "sharp 5");
      } else if has_dim_fifth {
        append(str, "flat 5");
      } else {
        append(str, "omit 5");
      }
    }

    // add the bass if this is an inversion
    if all_notes[bass % 12] != all_notes[root % 12] {
      append(str, tprint(" / %", all_notes[bass % 12]));
    }

    // write the pitch class too
    append(str, " -- ");
    append(str, tprint("< 0 "));
    for pitch_class  append(str, tprint("% ", it));
    append(str, tprint(">\n"));
  }
}


// the strings
// TODO (brice): support for 7 strings? 8 strings?
string_1: Fret = 0;
string_2: Fret = 0;
string_3: Fret = 0;
string_4: Fret = 0;
string_5: Fret = 0;
string_6: Fret = 0;

all_strings: [] *Fret = .[*string_6, *string_5, *string_4, *string_3, *string_2, *string_1];

output_buffer: String_Builder;

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

  //
  // init some state
  //

  all_notes = sharps;  // a view onto either sharps or flats that we will toggle between the two
  
  // we are going to write our chords into the string builder every frame
  // and then display them from that buffer as well.
  init_string_builder(*output_buffer);
  
  array_add(*tuning, .{E, 2});
  array_add(*tuning, .{A, 2});
  array_add(*tuning, .{D, 3});
  array_add(*tuning, .{G, 3});
  array_add(*tuning, .{B, 3});
  array_add(*tuning, .{E, 4});
  
  //
  // get rect stuff
  set_global_rounding_radius_in_pixels(0);
  set_global_frame_thickness_in_pixels(2);
  set_global_divider_thickness_in_pixels(4);
  
  quit := false;
  while !quit {
    // time
    current_time = seconds_since_init();
    dt := cast(float)(current_time - last_time);
    Clamp(*dt, 0, 0.1);
    last_time = current_time;

    // window events
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

        if event.key_pressed && event.key_code == .SPACEBAR {
          string_1 = -1;
          string_2 = -1;
          string_3 = -1;
          string_4 = -1;
          string_5 = -1;
          string_6 = -1;
        }
      }
    }

    //
    // my stuff
    //
    
    if sharps_or_flats == {
      case .FLATS ;  all_notes = flats;
      case .SHARPS;  #through;
      case; all_notes = sharps;
    }
    
    for all_strings  currently_fretted[it_index] = xx it.*;
    
    reset(*output_buffer);
    compute_chords(*output_buffer, currently_fretted);
    
    // draw call
    draw_one_frame(dt);

    reset_temporary_storage();
    sleep_milliseconds(10);
  }  // while true
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
  
  ch  := cast(float) button_font.character_height;  // TODO (brice): chose size not based on the font size
  cw  := cast(float) button_font.em_width;
  h_mid := cast(float) (window_height / 2);
  
  fret_width  := cast(float) (window_width * .8) / 22;
  fret_height := cast(float) (window_height / 20);

  whole_window := get_rect(0, 0, xx width, xx height);
  sr_theme: Slidable_Region_Theme;  // default for now
  sr_theme.orientation = .VERTICAL;
  sr_theme.first_background.shape.roundedness = 0.0;
  sr_theme.second_background = sr_theme.first_background;
  sr_state, top, bottom, divider := slidable_region(whole_window, *sr_theme);
  {
    // draw chords
    font  := button_font;
    text  := builder_to_string(*output_buffer,, allocator = temp);
    lines := split(text, "\n");

    K :: .5;
    color := Vector4.{K, K, K, 1};

    xpad := floor(font.default_line_spacing * .5 + .5);

    tx := window_width * .1;
    ty := window_height * .8;
    for lines {
      trimmed := trim_right(it, " \t\r\n");
      Simp.draw_text(font, xx tx, xx ty, trimmed, color);
      ty -= cast(float) font.default_line_spacing;
    }
  }
  
  switch_to_bottom_rect(sr_state);
  
  {
    r: Rect;

    // draw save button

    // sharps or flats toggle
    w := 5 * cw;
    pad := cw;
    r = get_rect(bottom.w - 3 * (w + pad), bottom.h - 1.5 * ch, w, ch);
    button(r, "add");
    r.x += r.w + pad;
    radio_button(r, "Sharps", *sharps_or_flats, .SHARPS, *radio_theme);
    r.x += r.w + pad;
    radio_button(r, "Flats",  *sharps_or_flats,  .FLATS, *radio_theme);
    
    fx := window_width  * .1;
    fy := window_height * .1;

    r1 := get_rect(fx, fy + 5 * fret_height, fret_width, fret_height);
    r2 := get_rect(fx, fy + 4 * fret_height, fret_width, fret_height);
    r3 := get_rect(fx, fy + 3 * fret_height, fret_width, fret_height);
    r4 := get_rect(fx, fy + 2 * fret_height, fret_width, fret_height);
    r5 := get_rect(fx, fy + 1 * fret_height, fret_width, fret_height);
    r6 := get_rect(fx, fy          , fret_width, fret_height);
    
    ddx := window_width * .1;
    ddy := r6.y;
    text_color: Vector4 = .{200, 200, 220, 255};
    
    // draw tuning selection
    picker_height := fret_height * .75;
    r = get_rect(ddx - 6 * cw, ddy, cw * 5, picker_height);
    for tuning {
      dropdown(r, all_notes, xx *it.note, identifier = it_index);
      r.y += fret_height;
    }
    
    text_y := cast(s64) (r6.y - fret_height);

    // draw strings
    radio_button(r1, note(string_1, -1, tuning[5].note), *string_1, cast(Fret) -1, *radio_theme);
    radio_button(r2, note(string_2, -1, tuning[4].note), *string_2, cast(Fret) -1, *radio_theme);
    radio_button(r3, note(string_3, -1, tuning[3].note), *string_3, cast(Fret) -1, *radio_theme);
    radio_button(r4, note(string_4, -1, tuning[2].note), *string_4, cast(Fret) -1, *radio_theme);
    radio_button(r5, note(string_5, -1, tuning[1].note), *string_5, cast(Fret) -1, *radio_theme);
    radio_button(r6, note(string_6, -1, tuning[0].note), *string_6, cast(Fret) -1, *radio_theme);
    
    text_width := Simp.prepare_text(my_font, "x  ");
    Simp.draw_prepared_text(my_font, cast(s64) r1.x, text_y, color=text_color);

    r1.x += r1.w;
    r2.x += r2.w;
    r3.x += r3.w;
    r4.x += r4.w;
    r5.x += r5.w;
    r6.x += r6.w;
    text_x := cast(s64) r6.x;

    prev: Fret;
    pressed: bool;
    
    for 0..21 {
      prev = string_1;
      pressed = radio_button(r1, note(string_1, it, tuning[5].note), *string_1, xx it, *radio_theme, it);
      if pressed && prev == string_1  string_1 = .NONE;
      
      prev = string_2;
      pressed = radio_button(r2, note(string_2, it, tuning[4].note), *string_2, xx it, *radio_theme, it);
      if pressed && prev == string_2  string_2 = .NONE;

      prev = string_3;
      pressed = radio_button(r3, note(string_3, it, tuning[3].note), *string_3, xx it, *radio_theme, it);
      if pressed && prev == string_3  string_3 = .NONE;

      prev = string_4;
      pressed = radio_button(r4, note(string_4, it, tuning[2].note), *string_4, xx it, *radio_theme, it);
      if pressed && prev == string_4  string_4 = .NONE;

      prev = string_5;
      pressed = radio_button(r5, note(string_5, it, tuning[1].note), *string_5, xx it, *radio_theme, it);
      if pressed && prev == string_5  string_5 = .NONE;
      
      prev = string_6;
      pressed = radio_button(r6, note(string_6, it, tuning[0].note), *string_6, xx it, *radio_theme, it);
      if pressed && prev == string_6  string_6 = .NONE;
      
      draw_text(tprint("%", formatInt(it, padding=3)), text_x, text_y, text_color, my_font);
      
      r1.x += r1.w;
      r2.x += r2.w;
      r3.x += r3.w;
      r4.x += r4.w;
      r5.x += r5.w;
      r6.x += r6.w;
      if it < 9
        text_x = xx r6.x;
      else
        text_x = xx (r6.x - cw / 2);
    }
  }

  finish(sr_state);
  
  draw_popups();
  Simp.swap_buffers(my_window);
}  // draw_one_frame

#scope_file
init_fonts :: () {
  if !working_directory_set {
    // So that we can load our font, set to path of running executable.
    path := path_strip_filename(get_path_of_running_executable());
    set_working_directory(path);

    working_directory_set = true;
  }

  pixel_height := window_height / 22;
  my_font = Simp.get_font_at_size("data", "OpenSans-BoldItalic.ttf", pixel_height);
  assert(my_font != null);
  
  pixel_height /= 2;
  button_font = Simp.get_font_at_size("data", "OpenSans-BoldItalic.ttf", pixel_height);
  assert(button_font != null);

  pixel_height = window_height / 7;
  title_font = Simp.get_font_at_size("data", "OpenSans-BoldItalic.ttf", pixel_height);
}

/// calls prepare text followed by draw_prepared text
draw_text :: (text: string, x: int, y: int, color: Vector4, font: *Font) {
  text_width := Simp.prepare_text(font, text);
  Simp.draw_prepared_text(font, x, y, color);
}

Font :: Simp.Dynamic_Font;

my_font:   *Font;
button_font: *Font;
title_font:  *Font;

working_directory_set := false;

Simp  :: #import "Simp";
Input :: #import "Input";

#import "Window_Creation";
#import "GetRect";

#import "Basic";
Basic :: #import "Basic"; // :CompilerBug  We need this to resolve to_lower for some reason?!
#import "Math";
#import "System";  // For get_path_of_running_executable. @Cleanup.
#import "String";  // For path_strip_filename. @Cleanup.

#import "Sort";
#import "Hash_Table";