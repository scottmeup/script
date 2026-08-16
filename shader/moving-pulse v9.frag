#version 430 // Must be line 1 for GLSL viewer. Comment this line out to use with shadertoy
// Begin GLSL viewer Section 1 
// Comment this section out to use with shadertoy
uniform vec2 u_resolution;
uniform vec2 u_mouse;
uniform float u_time;
vec2 iResolution;   // viewport resolution (in pixels)
float iTime;        // shader playback time (in seconds)
vec4 iMouse;        // mouse pixel coords (xy), click state (zw)
out vec4 FragColor;         // Final color output
void mainImage(out vec4 fragColor, in vec2 fragCoord);
// End GLSL viewer Section 1

// configurable color pulses
// - Additional Features to consider
// - - Inverse brightness mode
// - - Set fixed or rotated color at specific LED position
//
// To-do:
// - Fix pulse[6] device 7 configuration: head decay
// -- enabled in configuration via bool color_blend_pulse_head_with_fade_in
// -- should work similarly to pulse[4] device 5 but in the head instead of behind the pulse
// -- need to check if blended head size can be defined separately from normal head size
// - Check timing of first LED in fade_and_decay_first_and_last_led_only
// - Look into brightness as a function of RGB, consider re-working brightness calculation
// - - Especially for blending pulse head to fade-in
// - Write better variable names for get_decay_and_fade_offsets()
// - Implement head offset & head buffer column settings
// Note: work being done mainly in debug section so features can be switched on & off individually for testing




// Begin User Config Globals Section
//
//
const int size_of_display_in_columns = 11;    // how many parallel pulses to run
const bool direction_movement_horizontal = false;
const bool direction_movement_reversed = true;
//const float duration_of_pause = 5.0;   //  Time between the front of the pulse leaving the screen and the next pulse appearing
const float duration_of_pause = 0.0;   // disable pause while testing fade
const float duration_of_pulse = 3.0;    // Time taken for the front of the pulse to run across the display
const float speed_global_modifier = .01;    // When set to 1.0, cycle will play at 1 second per unit of duration
//
//
// End User Config Section


//Maths
const vec3 ones3d =      vec3(1.0, 1.0, 1.0);
const vec3 zeros3d =     vec3(0.0, 0.0, 0.0);
const float one_third =  (1.0 / 3.0);
const float two_thirds = (2.0 / 3.0);
const float pi =         3.14159265358979323;

// Colors
const vec3 red =        vec3(1.0, 0.0, 0.0);
const vec3 orange =     vec3(1.0, 0.75, 0.0);
const vec3 yellow =     vec3(1.0, 1.0, 0.0);
const vec3 green =      vec3(0.0, 1.0, 0.0);
const vec3 light_blue = vec3(0.0, 1.0, 1.0);
const vec3 blue =       vec3(0.0, 0.0, 1.0);
const vec3 purple =     vec3(0.5, 0.0, 1.0);
const vec3 pink =       vec3(1.0, 0.0, 1.0);
const vec3 white =      vec3(1.0, 1.0, 1.0);
const vec3 grey =       vec3(0.5, 0.5, 0.5);
const vec3 black =      vec3(0.0, 0.0, 0.0);

// Debug
const bool debug_master =                          true;
const bool debug_add_overlay_colorshft =           false;
//
const bool debug_background =                      true;
const bool debug_decay_and_fade_in =               false;
const bool debug_fade_in =                         false;                 // I think it looks better with this set to false
const bool debug_show_LED_map =                    false;
const bool debug_show_distance_behind_pulse =      false;
const bool debug_show_distance_in_front_of_pulse = false;
const bool debug_define_led_element =              false;
const bool debug_head =                            false;
//
const bool debug_show_intended_output =            true;
//



struct Pulse_settings 
{
    vec3 rgb_pulse;                                                 // (R, G, B) Color for pulse
    vec3 rgb_pause;                                                 // (R, G, B) Color for negative space: non-pulse area
    vec3 rgb_fade_out;                                              // (R, G, B) Color applied to fade-out behind pulse
    vec3 rgb_fade_in;                                               // (R, G, B) Color applied to fade-in in front of pulse
    vec3 rgb_background;                                            // (R, G, B) Color applied uniformly on top of others
    float size_of_display_in_leds;                                  // Set to the number of LEDs in your display in order to align other settings properly   
    float size_of_pulse_head_in_leds;                               // Non-decay area at the start of the pulse. Will run at brightness specified in rgb_pulse for the length of the number of LEDs specified
    float decay_speed_exponential;                                  // 0.0 for no exponential decay. Higher number = faster decay, shorter / darker pulse.
    float decay_speed_linear;                                       // 0.0 for no linear decay. Higher number = faster decay, shorter / darker pulse.
    float fade_in_speed_exponential;                                // 0.0 for no exponential fade-in. Generate a fade-in on the LED before the pulse. Higher number = faster = shorter.
    float fade_in_speed_linear;                                     // 0.0 for no linear fade-in. Generate a fade-in on the LED before the pulse. Higher number = faster = shorter.
    float color_brightness_cutoff;                                  // switch to non-pulse, "pause" section of cycle coloring below this brightness.
    float color_pulse_minimum_brightness_percent;                   // Minimum brightness of pulse as a percent. Will not decay below this level.
    float size_of_blending_zone_fade_in_to_head_as_percentage;      // Percentage of the pulse head used to blend fade-in colour to pulse head colour. Range: 0.0 to 1.0.
    float size_of_blending_zone_head_to_fade_out_as_percentage;     // Percentage of the pulse head used to blend head colour to fade-out colour. Range: 0.0 to 1.0.
    float offset_of_pulse_head_within_blending_zone;                // Alignment of blending zone for fade-in to head. 0.0 = align to front, 1.0 = align to back.
    float offset_of_whole_element_in_leds;                          // Advance or delay the timing of the entire element by a the specified number of LEDs
    bool color_brightness_cutoff_includes_background_brightness;    // Consider background coloring or not when determining the brightness of a pixel for cutoff to pause coloring.
    bool color_combine_background_with_pause_color;                 // Overlay the background color on top of the "pause" / negative space color.
    bool color_blend_pulse_head_with_fade_out;                      // Smooth transition between fade-out and pulse head
    bool color_blend_pulse_head_with_fade_in;                       // Smooth transition between fade-in and pulse head
    bool display_discrete_led_output;                               // Simulate LED display based on size_of_display_in_leds.
    bool fade_and_decay_first_and_last_led_only;                    // Only apply fade-in to the first LED before the pulse appears, and decay to the last LED after the pulse leaves. Requires display_discrete_led_output and either fade_in or decay.

};



// Begin User Config Pulse / Example Settings Section
//
//
void Initialize_pulse_settings_array(inout Pulse_settings pulse[size_of_display_in_columns]){
    // Use order of variables listed above in "struct Pulse_settings"
    //                                                                                                                                   | LEDs in | Pulse | Decay | Decay | Fade | Fade | Bright | Min    | blend     | blend      | blending | element  | Cufoff | BG +  | Head+   | Head+    | LED    | 1st+ 
    //                              Pulse-color  |  Pause-color          | Fade-out colour     | Fade-in colour      | Background-color  | Display | Head  |  Exp  |  Lin  | Exp  | Lin  | Cutoff | Bright | size f-in | size f-out | offset   | offset   | BG     | Pause | fade-in | fade-out | Output | last
    pulse[0]  = Pulse_settings(vec3(1.0, 0.0, 0.0 ), vec3(0.0, 0.0, 0.05), vec3(1.0, 0.0, 0.0 ), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0), 5.0,      1.0,     3.0,    0.0,   0.0,   0.0,   0.025,   0.0,     0.0,        0.0,         0.0,         0.0,     false,   true,   false,    false,     false,   false );     // Device 1
    pulse[1]  = Pulse_settings(vec3(1.0, 0.75, 0.0), vec3(0.0, 0.0, 0.05), vec3(1.0, 0.75, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0), 3.0,      1.0,     3.0,    0.0,   0.0,   0.0,   0.025,   0.0,     0.0,        0.0,         0.0,         0.0,     false,   true,   false,    false,     false,   false );     // Device 2
    pulse[2]  = Pulse_settings(vec3(1.0, 1.0, 0.0 ), vec3(0.0, 0.0, 0.1 ), vec3(1.0, 1.0, 0.0 ), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0), 3.0,      2.0,     3.0,    0.0,   0.0,   0.0,   0.025,   0.0,     0.0,        0.0,         0.0,         0.0,     false,   true,   false,    false,     false,   false );     // Device 3
    pulse[3]  = Pulse_settings(vec3(0.0, 1.0, 0.0 ), vec3(0.0, 0.0, 0.0 ), vec3(0.0, 1.0, 0.0 ), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0), 14.0,     1.0,     3.0,    0.0,  14.0,   0.0,   0.025,   0.0,     0.0,        0.0,         0.0,         1.0,     false,   true,   false,    false,     false,   false );     // Device 4
    pulse[4]  = Pulse_settings(vec3(0.0, 0.0, 1.0 ), vec3(0.0, 0.0, 0.0 ), vec3(0.0, 1.0, 0.0 ), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), 8.0,      1.0,     3.0,    0.0,   0.0,   0.0,   0.025,   0.0,     0.0,        0.0,         0.0,         2.0,     false,   true,   false,    false,     false,   false );     // Device 5
    pulse[5]  = Pulse_settings(vec3(0.0, 1.0, 1.0 ), vec3(0.0, 0.0, 0.5 ), vec3(0.0, 0.0, 1.0 ), vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), 8.0,      1.0,     3.0,    0.0,   0.0,   0.0,   0.1,     0.0,     0.0,        0.0,         0.0,         3.0,     false,   true,   false,    false,     false,   false );     // Device 6
    pulse[6]  = Pulse_settings(vec3(0.0, 0.0, 1.0 ), vec3(0.0, 0.0, 0.0 ), vec3(0.0, 0.0, 1.0 ), vec3(0.5, 0.0, 1.0), vec3(0.0, 0.0, 0.0), 8.0,      1.0,     3.0,    0.0,  64.0,   0.0,   0.025,   0.0,     0.0,        0.0,         0.0,         4.0,     false,   true,   true,     false,     false,   false );     // Device 7
//    pulse[7]  = Pulse_settings(vec3(1.0, 0.0, 1.0 ), vec3(0.0, 0.0, 0.0 ), vec3(1.0, 0.0, 1.0), vec3(0.0, 0.0, 0.0), 3.0,      1.0,   3.0,  0.0,  1.0,   3.0,  0.025,   0.0,   0.0,    false,  true,  false,  true,   true );     // Device 8
//    pulse[8]  = Pulse_settings(vec3(0.5, 0.0, 1.0 ), vec3(0.0, 0.0, 0.0 ), vec3(0.5, 0.0, 1.0), vec3(0.0, 0.0, 0.0), 4.0,      0.0,   0.0,  1.0,  0.0,   1.0,  0.025,   0.0,   0.0,    false,  true,  false,  true,   false );    // Device 9
    pulse[7]  = Pulse_settings(vec3(1.0, 0.0, 1.0 ), vec3(0.0, 0.0, 0.0 ), vec3(1.0, 0.0, 1.0 ), vec3(1.0, 0.0, 1.0), vec3(0.0, 0.0, 0.0), 2.0,      1.0,     3.0,    0.0,   1.0,   3.0,   0.025,   0.0,     0.0,         0.0,        0.0,         0.0,     false,   true,   false,    false,      false,   true  );     // Device 8
    pulse[8]  = Pulse_settings(vec3(1.0, 0.0, 1.0 ), vec3(0.0, 0.0, 0.0 ), vec3(1.0, 0.0, 1.0 ), vec3(1.0, 0.0, 1.0), vec3(0.0, 0.0, 0.0), 2.0,      1.0,     3.0,    0.0,   1.0,   3.0,   0.025,   0.0,     0.0,         0.0,        0.0,         0.0,     false,   true,   false,    false,      false,   false );    // Device 9
    pulse[9]  = Pulse_settings(vec3(1.0, 1.0, 1.0 ), vec3(0.0, 0.0, 0.0 ), vec3(1.0, 1.0, 1.0 ), vec3(1.0, 1.0, 1.0), vec3(0.0, 0.0, 0.0), 4.0,      0.0,     9.0,    0.0,   9.0,   0.0,   0.025,   0.0,     0.0,         0.0,        0.0,         0.0,     false,   true,   false,    false,      false,   false );    // Device 10
    pulse[10] = Pulse_settings(vec3(1.0, 1.0, 1.0 ), vec3(0.0, 0.0, 0.0 ), vec3(1.0, 1.0, 1.0 ), vec3(1.0, 1.0, 1.0), vec3(0.0, 0.0, 0.0), 4.0,      0.0,     0.0,    1.5,   0.0,   0.0,   0.025,   0.3,     0.0,         0.0,        0.0,         0.0,     false,   true,   false,    false,      false,   false );    // Device 11


    /*

    // Alternative way to initialize a pulse:
    // Does the same thing as the examples above.
    pulse[0].rgb_pulse = vec3(0.0, 1.0, 0.0);
    pulse[0].rgb_pause = vec3(0.0, 0.0, 0.05);
    pulse[0].rgb_fade_in = vec3(0.0, 0.0, 1.0);
    pulse[0].rgb_background = vec3(0.0, 0.0, 0.0);
    pulse[0].size_of_display_in_leds = 8.0; 
    pulse[0].size_of_pulse_head_in_leds = 1.0;   
    pulse[0].decay_speed_exponential = 3.0;  
    pulse[0].decay_speed_linear = 0.0;   
    pulse[0].fade_in_speed_exponential = 16.0;  
    pulse[0].fade_in_speed_linear = 0.0;   
    pulse[0].color_brightness_cutoff = 0.025;  
    pulse[0].color_pulse_minimum_brightness_percent = 0.0;  
    pulse[0].color_brightness_cutoff_includes_background_brightness = false;
    pulse[0].color_combine_background_with_pause_color = false;   
    pulse[0].color_blend_pulse_head_with_fade_in = true;   
    pulse[0].display_discrete_led_output = true;
    pulse[0].fade_and_decay_first_and_last_led_only = false;
    
    */

}
//
//
// End User Config Section


bool close_to(
    float value_variable, 
    float value_comparison, 
    float tolerance){
    if(value_variable > (value_comparison - (tolerance/2.0)) && (value_variable < (value_comparison + (tolerance/2.0)))){
        return true;
    }
    else{
        return false;
    }
} 


float invert_value(float value, float range){
    return range - value;
}

float restrict_float_from_0_to_1(float var){
// Return a float with value between 0.0 and 1.0
    var = min(var, 1.0);
    var = max(var, 0.0);
    return var;
}


vec3 restrict_vec3_from_0_to_1(vec3 var){
// Return a 3D vector with values between 0.0 and 1.0
    var = min(var, 1.0);
    var = max(var, 0.0);
    return var;
}

float distance_with_mod(
    float position_initial, 
    float position_final, 
    float size_of_space){
    // Always returns a positive value: the remainder of (pos_final - pos_initial) / size_of_space
    return mod((position_final - position_initial), size_of_space);
}


float get_offset_of_whole_element(
    float current_location,
    float size_to_offset_by, 
    float size_of_cycle){
// Takes current location of element, the amount to offset it by, and the size of the cycle.
// +ive size_to_offset_by delays the position
// -ive size_to_offset_by advances the position

    float offset_position = mod(current_location-size_to_offset_by, size_of_cycle);
    return offset_position;
}

vec2 get_decay_and_fade_offsets(
    float head_buffer_leds, 
    float head_buffer_alignment, 
    float size_of_led_as_percent_of_display, 
    float size_of_pulse_head_in_leds){
    // Alighment & buffer space between full-intensity section and fade-in / decay start for calculations.
    // Takes number of LEDs as inputs and returns percent of display
    //
    // head_buffer_leds: amount of space to extend / retract the fade & decay areas
    // head_buffer_alignment: shift the fade & decay areas forward or backward by this amount of LEDs
    // size_of_led_as_percent_of_display: number of LED elements in the display
    // size_of_pulse_head_in_leds: size of full intensity area as a multiple of LEDs
    //
    // head_buffer_leds = 0.0, head_buffer_alignment = 0.5 : full illumination to exactly 1 LED element at a time and aligns LEDs to index of pulse
    // 
    // Probably best managed as part of Pulse_settings or with additional logic: doesn't always play nice with continuous display mode
    vec2 offset;
    //
    // Adjust default behavior to align start of calculation at the pulse index, trailing the pulse.
    // offset.x = trailing edge, offset.y = leading edge
    //
    offset.x = ( (head_buffer_leds) / 2.0 ) + head_buffer_alignment + size_of_pulse_head_in_leds;
    offset.y = ( (head_buffer_leds) / 2.0 ) - head_buffer_alignment;
    offset = offset * size_of_led_as_percent_of_display;
    return offset;
}


bool define_led_element_at_offset_from_pulse_index(
    float offset_from_pulse_in_leds, 
    float size_of_defined_element_in_leds, float size_of_display_in_leds, 
    float distance_of_current_location_in_front_of_pulse_as_percent_of_display, 
    float distance_of_current_location_behind_pulse_as_percent_of_display){
    // # Clean this up #
    
    float size_of_single_led_as_percent_of_display = 1.0 / size_of_display_in_leds;
    float size_of_defined_element_as_percent_of_display = size_of_single_led_as_percent_of_display * size_of_defined_element_in_leds;
    
    // Center element on pulse index
    // + moves backward
    // - moves forward
    float size_forward =  ((-offset_from_pulse_in_leds)                                     * size_of_single_led_as_percent_of_display);
    float size_backward = (  offset_from_pulse_in_leds  + size_of_defined_element_in_leds ) * size_of_single_led_as_percent_of_display;
    
    bool element_is_defined = false;
    
    if (size_forward > size_of_defined_element_as_percent_of_display){
        // Entire head is in front of the pulse and not touching it
        if(distance_of_current_location_in_front_of_pulse_as_percent_of_display < (size_forward - size_of_defined_element_as_percent_of_display) ){
            element_is_defined = false;
        }
        else if(distance_of_current_location_in_front_of_pulse_as_percent_of_display < size_forward){
            element_is_defined = true;
        }
        else{
            element_is_defined = false;
        }
    }
    else if (size_backward > size_of_defined_element_as_percent_of_display){
        // Entire head is behind the pulse and not touching it
        if(distance_of_current_location_behind_pulse_as_percent_of_display < (size_backward - size_of_defined_element_as_percent_of_display) ){
            element_is_defined = false;
        }
        else if(distance_of_current_location_behind_pulse_as_percent_of_display < size_backward){
            element_is_defined = true;
        }
        else{
            element_is_defined = false;
        }
    }
    //Head spans the pulse index if neither of the above two options applies
    else if(distance_of_current_location_in_front_of_pulse_as_percent_of_display < size_forward ){
        element_is_defined = true;
    }
    else if(distance_of_current_location_behind_pulse_as_percent_of_display < size_backward ){
        element_is_defined = true;
    }
    
    return element_is_defined;
}


float get_led_offset_as_percent_of_display(
    float offset_in_leds, 
    float size_of_led_as_percent_of_display
    ){
    // Return the display distance for a given number of LED elements as a percentage of the display size
    float offset = offset_in_leds * size_of_led_as_percent_of_display;
    return offset;
}

vec2 get_distance_of_current_location_from_pulse_as_percent_of_display(
    float pulse_location_as_percent_of_display, 
    float current_location_on_y_axis_of_display_as_percent_of_display, 
    float size_of_cycle_as_percent_of_display
    ){
    // Get the the distance of the current location behind (vec2.x) and in front of (vec2.y) the pulse index
    
    float distance_of_current_location_in_front_of_pulse_as_percent_of_display;
    float distance_of_current_location_behind_pulse_as_percent_of_display;
    if(direction_movement_reversed){
        distance_of_current_location_in_front_of_pulse_as_percent_of_display = mod( 
            (pulse_location_as_percent_of_display - current_location_on_y_axis_of_display_as_percent_of_display), 
            size_of_cycle_as_percent_of_display);
        distance_of_current_location_behind_pulse_as_percent_of_display = invert_value(
            distance_of_current_location_in_front_of_pulse_as_percent_of_display, 
            size_of_cycle_as_percent_of_display);
    }
    else{
        distance_of_current_location_behind_pulse_as_percent_of_display = mod(
            (pulse_location_as_percent_of_display - current_location_on_y_axis_of_display_as_percent_of_display), 
            size_of_cycle_as_percent_of_display);
        distance_of_current_location_in_front_of_pulse_as_percent_of_display = invert_value(
            distance_of_current_location_behind_pulse_as_percent_of_display, 
            size_of_cycle_as_percent_of_display);
    }
    return vec2(distance_of_current_location_behind_pulse_as_percent_of_display, distance_of_current_location_in_front_of_pulse_as_percent_of_display);
}

vec2 get_display_location_as_percent_of_display_size(vec2 fragCoord){
    // Generate (x,y) coordinates of display location adjusted for horizontal / vertical direction of movement
    float size_display_width_in_pixels;
    float size_display_height_in_pixels;
    float position_current_pixel_x;
    float position_current_pixel_y;
    if (direction_movement_horizontal){
        size_display_width_in_pixels = iResolution.y;
        size_display_height_in_pixels = iResolution.x;
        position_current_pixel_x = fragCoord.y;
        position_current_pixel_y = fragCoord.x;   
    }else{
        size_display_width_in_pixels = iResolution.x;
        size_display_height_in_pixels = iResolution.y;
        position_current_pixel_x = fragCoord.x;
        position_current_pixel_y = fragCoord.y;   
    }
    vec2 display_location_as_percent_of_display = vec2(position_current_pixel_x/size_display_width_in_pixels, position_current_pixel_y/size_display_height_in_pixels);
    return display_location_as_percent_of_display;
}

float get_pulse_location_as_percent_of_display(){
    float duration_of_cycle = duration_of_pause + duration_of_pulse;
    float size_of_cycle_as_percent_of_screen = duration_of_cycle / duration_of_pulse;
    float speed_of_movement_per_second_as_percent_of_display = 1.0 / duration_of_pulse;

    
    // Move beginning of pulse across the screen and calculate distance from each screen location
    float speed_reverse_modifier = 1.0;
    if(direction_movement_reversed){
        speed_reverse_modifier = -1.0;
    }
    float time = mod(iTime*speed_global_modifier*speed_reverse_modifier, duration_of_cycle);
    float location_of_pulse_as_percent_of_display = speed_of_movement_per_second_as_percent_of_display * time;
    return location_of_pulse_as_percent_of_display;
}


/*
float get_distance_of_current_location_behind_pulse_as_percent(float current_location_on_y_axis_of_display_as_percent_of_display, float position_of_pulse_as_percent_of_display, float size_of_cycle_as_percent_of_screen, bool direction_movement_reversed){
    // Set up distance from end of pulse head based on normal or reverse direction of movement
    vec3 display_output_vector;
    float distance_of_current_location_behind_pulse_as_percent;
    if(direction_movement_reversed){
        distance_of_current_location_behind_pulse_as_percent = mod((current_location_on_y_axis_of_display_as_percent_of_display - position_of_pulse_as_percent_of_display), size_of_cycle_as_percent_of_screen); 
    }
    else{
        distance_of_current_location_behind_pulse_as_percent = mod((position_of_pulse_as_percent_of_display - current_location_on_y_axis_of_display_as_percent_of_display), size_of_cycle_as_percent_of_screen);  
    }
    return distance_of_current_location_behind_pulse_as_percent;
}


float get_size_of_LED_as_percent_of_display(float number_of_leds_in_display){
    float size_of_LED = 1.0/(number_of_leds_in_display);
    return size_of_LED;
}
*/

/*
float get_distance_of_current_location_from_pulse_as_percent_of_display(float pulse_location_as_percent_of_display, float current_location_on_y_axis_of_display_as_percent_of_display, float size_of_cycle_as_percent_of_display, bool behind_pulse){
    // For the purposes of this function, behind_pulse refers to the screen coordinate of interest being a lower index with regard to the display device:
    // ie. to the left of, or below the pulse location.
    float direction_modifier = 1.0;
    if(!behind_pulse){
        direction_modifier = -1.0;
    }
    float distance_of_current_location_behind_pulse_as_percent_of_display = mod( ( ( pulse_location_as_percent_of_display * direction_modifier) - (current_location_on_y_axis_of_display_as_percent_of_display * direction_modifier)), size_of_cycle_as_percent_of_display);
    return distance_of_current_location_behind_pulse_as_percent_of_display;
}

*/

float discrete_LED_output(
    float distance_of_current_location_behind_start_of_led_as_percent_of_display, 
    float distance_of_current_location_behind_pulse_as_percent, 
    float size_of_led_as_percent_of_display, 
    float size_of_cycle_as_percent_of_screen, bool
    ){
// Align distance to the end of the LED segment that the pulse index is inside

    // Keeps illuminated LED betweeen 0 and 1 LED width ahead of the pulse index with regard to the direction of movement
    // Illuminated LED will always be at a higher screen position otherwise
    // Update: something changed, now this isn't needed?
    if(direction_movement_reversed){
        //distance_of_current_location_behind_start_of_led_as_percent_of_display -= size_of_led_as_percent_of_display;
    }
    
    // Add current distance behind pulse to current distance behind start of LED and wrap around at the size of the whole cycle
    distance_of_current_location_behind_pulse_as_percent = distance_of_current_location_behind_pulse_as_percent + distance_of_current_location_behind_start_of_led_as_percent_of_display;
    distance_of_current_location_behind_pulse_as_percent = mod(
        distance_of_current_location_behind_pulse_as_percent, 
        size_of_cycle_as_percent_of_screen);
    return distance_of_current_location_behind_pulse_as_percent;
}


/*
vec3 generate_fade_in(float current_location_on_y_axis_of_display_as_percent_of_display, float pulse_location_as_percent_of_display, float size_of_cycle_as_percent_of_screen, Pulse_settings pulse){
    // Generate fade-in:
    // Calculate distance of current screen position in front of pulse
    bool flag_generate_fade_in_exponential = (pulse.fade_in_speed_exponential > 0.0);
    bool flag_generate_fade_in_linear = (pulse.fade_in_speed_linear > 0.0); 
    float fade_in_linear = 1.0;
    float fade_in_exponential = 1.0;
    float size_of_led_as_percent_of_display = get_size_of_LED_as_percent_of_display(pulse.size_of_display_in_leds);
    float distance_of_current_location_in_front_of_pulse_as_percent = mod( (size_of_cycle_as_percent_of_screen - pulse_location_as_percent_of_display + current_location_on_y_axis_of_display_as_percent_of_display), size_of_cycle_as_percent_of_screen);    
    float distance_of_current_location_in_front_of_pulse_in_leds = ceil(distance_of_current_location_in_front_of_pulse_as_percent/size_of_led_as_percent_of_display);
    /*
    if(fade_and_decay_first_and_last_led_only && (position_current_led_in_display == 0.0)){
        // Delay the timing of fade-in generation if fade_and_decay_first_and_last_led_only is set
        //distance_of_current_location_in_front_of_pulse_as_percent += (1.0 * size_of_led_as_percent_of_display);
        //return vec3(0.25, 0.25, 0.25);
    }
    */
    /*
    if( distance_of_current_location_in_front_of_pulse_in_leds < 1.0 ){
        // Do nothing if current location is less than 1 LED in front of the pulse as measured in number of discrete LEDs rounded up.
        // It shouldn't be possible for this branch to execute if things are working properly.
        return vec3(1.0, 1.0, 1.0);
    }
    else{
        float distance_of_current_location_in_front_of_pulse_adjusted_for_direction = distance_of_current_location_in_front_of_pulse_as_percent;
        if(pulse.display_discrete_led_output && (pulse.size_of_pulse_head_in_leds <= 0.0)){
            // Shift calculated distance for intensity one LED toward the back of the pulse if discrete LED output is used and pulse has no head
            // I think it looks better without this option enabled
            if(debug_fade_in){
                distance_of_current_location_in_front_of_pulse_as_percent -= size_of_led_as_percent_of_display;
            }
        }
        // Generate fade-in if current location is more than 1 LED in front of the pulse;
        if (flag_generate_fade_in_linear){
            fade_in_linear = 1.0 - (distance_of_current_location_in_front_of_pulse_as_percent * pulse.fade_in_speed_linear);
        }
        if(flag_generate_fade_in_exponential){
            fade_in_exponential = exp((-distance_of_current_location_in_front_of_pulse_as_percent) * pulse.fade_in_speed_exponential);
        }
    }
}
*/


float generate_pulse_decay(
    float distance_of_current_location_behind_pulse_as_percent_of_display, 
    float pulse_location_as_percent_of_display, 
    float size_of_cycle_as_percent_of_display, 
    float offset_from_pulse_index, 
    Pulse_settings pulse){
    // Generate decay pulse
    
    // Positive offsets move the beginning of calculations behind the pulse
    // Negative offsets move the beginning of calculations in front of the pulse 
    // mod(distance) is better left for debug - it creates a gap between the head and the decay section
    float distance_plus_offset_behind_pulse_as_percent_of_display = (distance_of_current_location_behind_pulse_as_percent_of_display - offset_from_pulse_index);
    //distance_plus_offset_behind_pulse_as_percent_of_display = mod(distance_plus_offset_behind_pulse_as_percent_of_display, size_of_cycle_as_percent_of_display);
    
    float decay_speed_exponential = pulse.decay_speed_exponential;
    float decay_speed_linear = pulse.decay_speed_linear;
    float size_of_display_in_leds = pulse.size_of_display_in_leds;
    float size_of_pulse_head_in_leds = pulse.size_of_pulse_head_in_leds;
    
    bool flag_generate_decay_linear = (decay_speed_linear > 0.0);
    bool flag_generate_decay_exponential = (decay_speed_exponential > 0.0);
    
    float size_of_pulse_head_as_percent_of_display = (size_of_pulse_head_in_leds / size_of_display_in_leds);
    float decay_total;


    //float distance_of_current_location_behind_pulse_as_percent_of_display = get_distance_of_current_location_from_pulse_as_percent_of_display(pulse_location_as_percent_of_display, current_location_on_y_axis_of_display_as_percent_of_display, size_of_cycle_as_percent_of_display, behind_pulse);
    /*
    if ((distance_of_current_location_behind_pulse_as_percent_of_display) < size_of_pulse_head_as_percent_of_display){
    
        // Pulse Head
        if(pulse.color_blend_pulse_head_with_fade_in && flag_generate_fade_in){
            // Draw head blended with fade-in
            distance_of_pulse_from_front_of_current_led_as_percent_of_led = ((distance_of_current_location_behind_pulse_as_percent) / size_of_led_as_percent_of_display);
            distance_of_pulse_from_back_of_current_led_as_percent_of_led = ( 1.0 - distance_of_pulse_from_front_of_current_led_as_percent_of_led );
            vec3 color_head_scaled_to_pulse_position_in_led = ( pulse.rgb_pulse * (distance_of_pulse_from_front_of_current_led_as_percent_of_led));
            vec3 color_fade_in_scaled_to_pulse_position_in_led = ( pulse.rgb_fade_in * (distance_of_pulse_from_back_of_current_led_as_percent_of_led));
            // x2.0 is a bit of a hack to reach colors in the middle. Look into trig functions, color gradients... 
            color_head_scaled_to_pulse_position_in_led = min(2.0 * color_head_scaled_to_pulse_position_in_led, pulse.rgb_pulse);
            color_fade_in_scaled_to_pulse_position_in_led = min(2.0 * color_fade_in_scaled_to_pulse_position_in_led, pulse.rgb_fade_in);
            display_output_vector_column = (color_head_scaled_to_pulse_position_in_led + color_fade_in_scaled_to_pulse_position_in_led);
        }
        else if(fade_and_decay_first_and_last_led_only && (position_current_led_in_display<=0.0)){
            // Really want to be generating fade-in here

            //return vec3(0.6, 0.6, 0.6);
            display_output_vector_column = pulse.rgb_pulse;
        }
        else{
            // Draw head without blending fade-in
            display_output_vector_column = pulse.rgb_pulse;
        }
    }
    */
    //else if(( flag_generate_decay_linear || flag_generate_decay_exponential ) != false ){
    if(( flag_generate_decay_linear || flag_generate_decay_exponential ) != false ){
    /*
        // Pulse Tail
        // Squish the decay rate into the non-head area of the pulse
        float distance_of_current_location_behind_pulse_as_percent_of_display =- size_of_pulse_head_as_percent_of_display;
        float distance_behind_pulse_head_as_percent_of_display_normalised = ( distance_behind_pulse_head_as_percent_of_display * ratio_of_display_size_to_pulse_tail_size );
        float decay_linear = 1.0 - (distance_behind_pulse_head_as_percent_of_display_normalised * pulse.decay_speed_linear);        
        float decay_exponential = exp(-distance_behind_pulse_head_as_percent_of_display_normalised * pulse.decay_speed_exponential);
        float decay_total = ( decay_linear * decay_exponential );
        /*
        if ( ( position_current_led_in_display != (pulse.size_of_display_in_leds-1.0) ) && fade_and_decay_first_and_last_led_only){
            // fade_and_decay_first_and_last_led_only is set but this isn't the last LED in the display.
            // Do nothing.
        }
        else{
            // Otherwise, generate pulse decay tail
            display_output_vector_column = ( pulse.rgb_pulse * decay_total );
        }
        */
        float decay_linear = 1.0 - (distance_plus_offset_behind_pulse_as_percent_of_display * pulse.decay_speed_linear);
        float decay_exponential = exp(-distance_plus_offset_behind_pulse_as_percent_of_display * pulse.decay_speed_exponential);
        decay_total = ( decay_linear * decay_exponential );
        
        /*
        //if(distance_of_current_location_behind_pulse_as_percent_of_display < mod(-offset_from_pulse_index, size_of_cycle_as_percent_of_display)){
        if(distance_of_current_location_behind_pulse_as_percent_of_display < -offset_from_pulse_index){
            decay_total = 0.0;
        }
        else{
            float decay_linear = 1.0 - (distance_plus_offset_behind_pulse_as_percent_of_display * pulse.decay_speed_linear);
            float decay_exponential = exp(-distance_plus_offset_behind_pulse_as_percent_of_display * pulse.decay_speed_exponential);
            decay_total = ( decay_linear * decay_exponential );
        }
        */

    }
    return decay_total;
}


float generate_head(
    float pulse_location_as_percent_of_display, 
    float current_location_on_y_axis_of_display_as_percent_of_display, 
    float distance_of_current_location_behind_pulse_as_percent_of_display, 
    float distance_of_current_location_in_front_of_pulse_as_percent_of_display, 
    float head_offset_as_percent_of_display, 
    Pulse_settings pulse){
    float size_of_display_in_leds = pulse.size_of_display_in_leds;
    float size_of_pulse_head_in_leds = pulse.size_of_pulse_head_in_leds;
    float size_of_led_as_percent_of_display = (1.0 / size_of_display_in_leds);
    float size_pulse_head_as_percent_of_display = size_of_led_as_percent_of_display * size_of_pulse_head_in_leds;
    float head_factor = 0.0;        // Brightness intensity from 0.0 to 1.0


    // Good idea to make this it's own separate function.
    // Can definitely clean it up a bit
    //
    // Center head on pulse index
    //float size_forward = ((size_pulse_head_as_percent_of_display)/2.0) - head_offset_as_percent_of_display;
    //float size_backward = ((size_pulse_head_as_percent_of_display)/2.0) + head_offset_as_percent_of_display;
    // Align head behind pulse index
    float size_forward = head_offset_as_percent_of_display;
    float size_backward = size_pulse_head_as_percent_of_display - head_offset_as_percent_of_display;
    
    if (size_forward > size_pulse_head_as_percent_of_display){
        // Entire head is in front of the pulse and not touching it
        if(distance_of_current_location_in_front_of_pulse_as_percent_of_display < (size_forward - size_pulse_head_as_percent_of_display) ){
            head_factor = 0.0;
        }
        else if(distance_of_current_location_in_front_of_pulse_as_percent_of_display < size_forward){
            head_factor = 1.0;
        }
        else{
            head_factor = 0.0;
        }
    }
    else if (size_backward > size_pulse_head_as_percent_of_display){
        // Entire head is behind the pulse and not touching it
        if(distance_of_current_location_behind_pulse_as_percent_of_display < (size_backward + size_pulse_head_as_percent_of_display) ){
            head_factor = 0.0;
        }
        else if(distance_of_current_location_behind_pulse_as_percent_of_display < size_backward){
            head_factor = 1.0;
        }
        else{
            head_factor = 0.0;
        }
    }
    //Head spans the pulse index if neither of the above two options applies
    else if(distance_of_current_location_in_front_of_pulse_as_percent_of_display < size_forward ){
        head_factor = 1.0;
    }
    else if(distance_of_current_location_behind_pulse_as_percent_of_display < size_backward ){
        head_factor = 1.0;
    }
    
    return head_factor;
}

vec3 apply_minimum_brightness(
    vec3 color_at_current_location, 
    Pulse_settings pulse
    ){
    //enforce minimum brightness setting for pulse - do not decay below this intensity
    vec3 minimum_brightness_color;
    float brightness = dot(ones3d, color_at_current_location)/3.0;
    
    if( brightness < pulse.color_pulse_minimum_brightness_percent)
    {
        float rgb_pulse_brightness_sum = pulse.rgb_pulse.x + pulse.rgb_pulse.y + pulse.rgb_pulse.z;
        vec3 rgb_ratio = vec3((pulse.rgb_pulse.x / rgb_pulse_brightness_sum), (pulse.rgb_pulse.y / rgb_pulse_brightness_sum), (pulse.rgb_pulse.z / rgb_pulse_brightness_sum));
        minimum_brightness_color = (rgb_ratio * pulse.color_pulse_minimum_brightness_percent * 3.0);
    }
    return minimum_brightness_color;
}


float get_brightness_of_color(vec3 color){
    // Generate a value for the brightness of a given color
    // Current implementation just returns the average value of the vector
    return (dot(ones3d, color) / 3.0);
}


vec3 get_blended_color(
    vec3 color1,
    vec3 color2,
    float color2_percent)
{
    // placeholder value for return
    return zeros3d;
}

/*
vec3 generate_rgb_output_column(Pulse_settings pulse, vec2 screen_location_adjusted_for_alignment_as_percent_of_display, float position_of_pulse_as_percent_of_display){

    // Draw the current pulse
    vec3 display_output_vector_column;
    
    // Set up some values to manage the logic
    //float distance_of_current_location_behind_pulse_as_percent = Distance_of_current_location_behind_pulse_as_percent();
    distance_of_current_location_behind_pulse_as_percent = 0.0;
    
    float distance_of_current_location_behind_start_of_led_in_percent;

    float size_of_pulse_head_in_leds = pulse.size_of_pulse_head_in_leds;
    float size_of_display_in_leds = pulse.size_of_display_in_leds;
    float size_of_led_as_percent_of_display = ( 1.0 / size_of_display_in_leds );
    float size_of_pulse_head_as_percent_of_display = size_of_led_as_percent_of_display * size_of_pulse_head_in_leds;
    float ratio_of_display_size_to_pulse_tail_size = 1.0 / (1.0 - size_of_pulse_head_as_percent_of_display);
    float distance_of_pulse_from_front_of_current_led_as_percent_of_led;
    float distance_of_pulse_from_back_of_current_led_as_percent_of_led;
    bool flag_generate_fade_in_linear = (pulse.fade_in_speed_linear > 0.0);
    bool flag_generate_fade_in_exponential = (pulse.fade_in_speed_exponential > 0.0);
    bool flag_generate_fade_in = (flag_generate_fade_in_linear || flag_generate_fade_in_exponential);
    bool flag_generate_decay_linear = (pulse.decay_speed_linear > 0.0);
    bool flag_generate_decay_exponential = (pulse.decay_speed_exponential > 0.0);
    bool flag_generate_decay = (flag_generate_fade_in_linear || flag_generate_fade_in_exponential);
    bool fade_and_decay_first_and_last_led_only = false;
    // Calculate cycle size as a multiple of screen size.
    // The result should also be the duration in seconds of the whole cycle when global speed = 1.0 
    float size_of_cycle_as_percent_of_screen = ( ( duration_of_pause + duration_of_pulse ) / duration_of_pulse );
    float position_current_led_in_display = floor( screen_location_adjusted_for_alignment_as_percent_of_display.y / size_of_led_as_percent_of_display );
    
    if(direction_movement_reversed){
        // Hmm... i thought this code was already being passed a direction-adjusted position
        position_current_led_in_display = ( (pulse.size_of_display_in_leds - 1.0) - position_current_led_in_display );
    }
    


    // Set up fade_and_decay_first_and_last_led_only mod.
    // Should result in only 1 LED having any illumination at a time, fade-in at the start and / or decay at the end.
    if( pulse.fade_and_decay_first_and_last_led_only && ( flag_generate_decay || flag_generate_fade_in ) ){
        size_of_pulse_head_in_leds = 0.0;
        fade_and_decay_first_and_last_led_only = true;
    }


 
    
    // Combine output with fade-in vectors
    if(flag_generate_fade_in){
        float fade_in_total = fade_in_linear * fade_in_exponential;

        vec3 display_fade_in_colored_vector_column = (pulse.rgb_fade_in * fade_in_total);

        // Keep fade-in values in sensible range
        display_fade_in_colored_vector_column = max(display_fade_in_colored_vector_column, zeros3d);
        display_fade_in_colored_vector_column = min(display_fade_in_colored_vector_column, ones3d);

        if ( ( position_current_led_in_display != 0.0 ) && fade_and_decay_first_and_last_led_only){
            // fade_and_decay_first_and_last_led_only is set but this isn't the first LED in the display.
            // Do nothing.
        }
        else{
            // Otherwise, apply the fade-in
            display_output_vector_column  = display_output_vector_column + display_fade_in_colored_vector_column;

        }
    }



    
    // Keep display values in sensible range
    display_output_vector_column = max(display_output_vector_column, zeros3d);
    display_output_vector_column = min(display_output_vector_column, ones3d);

    


    // leftover from the minimum color section
    if(false){
    }
    // Apply background to pulse section
    else{
        display_output_vector_column = display_output_vector_column + pulse.rgb_background;
    }
    return display_output_vector_column;
}
*/





void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    // Create array with number of parallel pulses. 
    Pulse_settings[size_of_display_in_columns] pulse_array;
    // Call method to populate the array with saved settings.
    Initialize_pulse_settings_array(pulse_array);


    // Set parameters related to display calculation.
    // y-axis is the direction of motion
    // x-axis is the columns for different element definitions
    float size_of_cycle_as_percent_of_display = (duration_of_pause + duration_of_pulse) / duration_of_pulse;
    vec2 screen_location_adjusted_for_alignment_as_percent_of_display = get_display_location_as_percent_of_display_size(fragCoord);
    float current_location_on_y_axis_of_display_as_percent_of_display = screen_location_adjusted_for_alignment_as_percent_of_display.y;
    float pulse_location_as_percent_of_display = get_pulse_location_as_percent_of_display();
    vec2 distance_from_pulse = get_distance_of_current_location_from_pulse_as_percent_of_display(
        pulse_location_as_percent_of_display, 
        current_location_on_y_axis_of_display_as_percent_of_display, 
        size_of_cycle_as_percent_of_display);
    float distance_of_current_location_behind_pulse_as_percent_of_display = distance_from_pulse.x;
    float distance_of_current_location_in_front_of_pulse_as_percent_of_display = distance_from_pulse.y;
    vec3 display_output_vector = zeros3d;
    
    
    // Calculate the column index of the current screen location
    int index_current_pulse = int(floor(screen_location_adjusted_for_alignment_as_percent_of_display.x * float(size_of_display_in_columns)));
    
    
    // Copy some variables from the current pulse into local scope
    Pulse_settings pulse = pulse_array[index_current_pulse];
    bool display_discrete_led_output = pulse.display_discrete_led_output;
    bool color_brightness_cutoff_includes_background_brightness = pulse.color_brightness_cutoff_includes_background_brightness;
    bool color_blend_pulse_head_with_fade_in = pulse.color_blend_pulse_head_with_fade_in;
    float color_brightness_cutoff = pulse.color_brightness_cutoff;
    float color_pulse_minimum_brightness_percent = pulse.color_pulse_minimum_brightness_percent;
    float size_of_display_in_leds = pulse.size_of_display_in_leds;
    float size_of_pulse_head_in_leds = pulse.size_of_pulse_head_in_leds;
    float offset_of_whole_element_in_leds = pulse.offset_of_whole_element_in_leds;

    // Assign local variable for colours of different parts of the cycle
    vec3 rgb_background = pulse.rgb_background;
    vec3 rgb_pause = pulse.rgb_pause;
    vec3 rgb_pulse = pulse.rgb_pulse;
    vec3 rgb_fade_in = pulse.rgb_fade_in;
    vec3 rgb_fade_out = pulse.rgb_fade_out;
    
    // Set up some variables related to display
    float size_of_led_as_percent_of_display = (1.0 / size_of_display_in_leds);
    float size_pulse_head_as_percent_of_display = size_of_led_as_percent_of_display * size_of_pulse_head_in_leds;

    // Generate LED map and distance from each screen location behind the start of the LED it is a part of,
    // adjusted for the direction of movement
    float distance_of_current_location_behind_start_of_led_as_percent_of_display = mod(
        current_location_on_y_axis_of_display_as_percent_of_display, 
        size_of_led_as_percent_of_display);
    if(direction_movement_reversed){
            distance_of_current_location_behind_start_of_led_as_percent_of_display = invert_value(
                distance_of_current_location_behind_start_of_led_as_percent_of_display, 
                size_of_led_as_percent_of_display);
    }

    // Call discrete LED output method
    if(display_discrete_led_output){
        distance_of_current_location_behind_pulse_as_percent_of_display = discrete_LED_output(
            distance_of_current_location_behind_start_of_led_as_percent_of_display, 
            distance_of_current_location_behind_pulse_as_percent_of_display, 
            size_of_led_as_percent_of_display, size_of_cycle_as_percent_of_display, 
            direction_movement_reversed);
    }


    // Shift whole element by an offset
    distance_of_current_location_behind_pulse_as_percent_of_display = get_offset_of_whole_element(
        distance_of_current_location_behind_pulse_as_percent_of_display,
        offset_of_whole_element_in_leds*size_of_led_as_percent_of_display,
        size_of_cycle_as_percent_of_display);

    distance_of_current_location_in_front_of_pulse_as_percent_of_display = invert_value(
        distance_of_current_location_behind_pulse_as_percent_of_display, 
        size_of_cycle_as_percent_of_display);

    
    // Shift head as a multiple of a full LED. +ive is behind pulse, -ive is in front of pulse.
    // 0.0 is the original behaviour: align start of head behind pulse index. 
    float head_offset_in_leds = 0.0;    
    
    // Generate offsets of decay from head location
    //
    // head_buffer_leds = 0.0 results in full illumination of exactly 1 LED at a time with fade_in + decay pulse
    // head_buffer_leds > 0.0 will increase the area on either side of the pulse boundary that is at full brightness by the number of LED elements specified 
    float head_buffer_leds = 0.0;

    // 0.0 is original behaviour: align with head beginning at pulse index and trailing pulse
    // > 0.0 shifts the decay regions behind the pulse boundary
    // < 0.0 shifts the decay regions ahead of the pulse boundary
    float head_buffer_alignment = 0.0;
    
    if(!display_discrete_led_output){
        // Center head on pulse index in contiuous output mode
        //
        //head_offset_as_percent_of_display = get_led_offset_as_percent_of_display(head_offset_as_percent_of_display, size_of_led_as_percent_of_display);
        
        /*
        head_offset_in_leds -= 0.5;
        head_buffer_alignment -= 0.5;
        */
    }
    vec2 decay_and_fade_offset = get_decay_and_fade_offsets(
        head_buffer_leds, 
        head_buffer_alignment, 
        size_of_led_as_percent_of_display, 
        size_of_pulse_head_in_leds);
    


    

    
 
    // Generate head
    if(color_blend_pulse_head_with_fade_in){
        // Adjust head placement when combining head with fade-in colours.
        //head_offset_in_leds -= size_of_pulse_head_in_leds;
    }

    bool head_is_defined = define_led_element_at_offset_from_pulse_index(
        head_offset_in_leds, 
        size_of_pulse_head_in_leds, 
        size_of_display_in_leds, 
        distance_of_current_location_in_front_of_pulse_as_percent_of_display, 
        distance_of_current_location_behind_pulse_as_percent_of_display
    );

    //head_factor defines the brightness of areas that are defined as the head of the pulse, from 0.0 to 1.0
    float head_factor = 0.0;        
    if(head_is_defined && color_blend_pulse_head_with_fade_in){
        // Not working as intended - probably need to offset area that head is defined, either negative to the current offset or one screen length minus the size of the head
        head_factor =  (distance_of_current_location_behind_pulse_as_percent_of_display / size_pulse_head_as_percent_of_display);
    }
    else if(head_is_defined){
        head_factor = 1.0;
    }

    
    // Generate decay tail + fade-in
    // Direction controlled by sending either distance_of_current_location_behind_pulse_as_percent_of_display or distance_of_current_location_in_front_of_pulse_as_percent_of_display
    // decay_and_fade_offset.x (decay) and decay_and_fade_offset.y (fade-in) are the distance from pulse index to use as the start of calculations
    float decay_factor =   generate_pulse_decay(
        distance_of_current_location_behind_pulse_as_percent_of_display, 
        pulse_location_as_percent_of_display, size_of_cycle_as_percent_of_display,
        decay_and_fade_offset.x, 
        pulse);
    float fade_in_factor = generate_pulse_decay(
        distance_of_current_location_in_front_of_pulse_as_percent_of_display, 
        pulse_location_as_percent_of_display, size_of_cycle_as_percent_of_display, 
        decay_and_fade_offset.y, 
        pulse);
    
    // Keep values in a sensible range: between 0.0 and 1.0
    decay_factor = restrict_float_from_0_to_1(decay_factor);
    fade_in_factor = restrict_float_from_0_to_1(fade_in_factor);
    head_factor = restrict_float_from_0_to_1(head_factor);
    
 
    
    
    
    
    
    // Debug section
    if(debug_master){
        if(debug_add_overlay_colorshft){
            display_output_vector = vec3(sin(iTime), sin(iTime - (pi*two_thirds)), sin(iTime - (2.0*pi*two_thirds)));
        }
        // intended output
        if(debug_show_intended_output){
            // head section
            if(head_factor > 0.0){
                // Apply head
                display_output_vector = restrict_vec3_from_0_to_1((display_output_vector + (head_factor * rgb_pulse)));
            }
            // the rest
            else{
                // Apply fade-in
                display_output_vector = restrict_vec3_from_0_to_1(display_output_vector + (fade_in_factor * rgb_fade_in));
                // Apply decay trail
                display_output_vector = restrict_vec3_from_0_to_1(display_output_vector + (max((decay_factor * rgb_pulse), (color_pulse_minimum_brightness_percent * rgb_pulse))));
                
                float brightness = 0.0;
                // Calculate brightness before, or after applying background
                if(color_brightness_cutoff_includes_background_brightness){
                    display_output_vector = restrict_vec3_from_0_to_1(display_output_vector + rgb_background);
                    brightness = get_brightness_of_color(display_output_vector);
                }
                else{
                    brightness = get_brightness_of_color(display_output_vector);
                    display_output_vector = restrict_vec3_from_0_to_1(display_output_vector + rgb_background);
                }
                
                // Apply alternate color if calculated brightness is below the minimum specified
                if(brightness < color_brightness_cutoff){
                    display_output_vector = rgb_pause;
                }
  
            }
            display_output_vector = restrict_vec3_from_0_to_1(display_output_vector);
        }
        
        if(debug_background){
            display_output_vector += rgb_background;
        }


        if(debug_define_led_element){
            float offset_from_pulse_in_leds = 1.0;
            float size_of_defined_element_in_leds = 1.0;
            bool defined_led_element = define_led_element_at_offset_from_pulse_index(offset_from_pulse_in_leds, size_of_defined_element_in_leds, size_of_display_in_leds, distance_of_current_location_in_front_of_pulse_as_percent_of_display, distance_of_current_location_behind_pulse_as_percent_of_display);
            if(defined_led_element){
                display_output_vector += vec3(0.0, 1.0, 0.0);
            }
            if((distance_of_current_location_behind_pulse_as_percent_of_display < 0.001) || (distance_of_current_location_in_front_of_pulse_as_percent_of_display < 0.001)){
                display_output_vector += vec3(1.0, 0.0, 0.0);
            }
            display_output_vector = restrict_vec3_from_0_to_1(display_output_vector);
        }

        if(debug_show_distance_behind_pulse){
            // Show distance on screen behind pulse location
            // Brighter = Closer
            // Darker = Further away
            display_output_vector += ( 1.0 - (distance_of_current_location_behind_pulse_as_percent_of_display ) ) * rgb_pulse;
            display_output_vector = restrict_vec3_from_0_to_1(display_output_vector);
        }


        if(debug_show_distance_in_front_of_pulse){
            // Show distance on screen behind pulse location
            // Brighter = Closer
            // Darker = Further away
            display_output_vector +=  ( 1.0 - (distance_of_current_location_in_front_of_pulse_as_percent_of_display ) ) * rgb_pulse;
            display_output_vector = restrict_vec3_from_0_to_1(display_output_vector);
        }

        if(debug_show_distance_behind_pulse && debug_show_distance_in_front_of_pulse){
            vec3 backward_output_vector = ( 1.0 - (distance_of_current_location_behind_pulse_as_percent_of_display ) ) * rgb_pulse;
            vec3 forward_output_vector =  ( 1.0 - (distance_of_current_location_in_front_of_pulse_as_percent_of_display ) ) * rgb_pulse;
            backward_output_vector = restrict_vec3_from_0_to_1(backward_output_vector);
            forward_output_vector = restrict_vec3_from_0_to_1(forward_output_vector);
            display_output_vector += (backward_output_vector + forward_output_vector);
            display_output_vector = restrict_vec3_from_0_to_1(display_output_vector);
        }


        if(debug_show_LED_map){
            // Show distance on screen from beginning of the current LED element
            // Brighter = Closer
            // Darker = Further away
            display_output_vector += ( 1.0 - distance_of_current_location_behind_start_of_led_as_percent_of_display * size_of_display_in_leds ) * rgb_pulse;
            display_output_vector = restrict_vec3_from_0_to_1(display_output_vector);
        }



        if(debug_head && debug_decay_and_fade_in){
            float decay_border;
            float fade_in_border;
            float decay_or_head_border;

            if(decay_factor == 1.0){
                decay_border = 1.0;
            }
            if(fade_in_factor == 1.0){
                fade_in_border = 1.0;
            }
            if((decay_factor == 1.0) || (fade_in_factor==1.0)){
                decay_or_head_border = 1.0;
            }
            //display_output_vector = (green * head_factor) + (red * ((decay_factor * two_thirds) + (fade_in_factor * one_third)) + (blue * ((decay_factor*one_third) + (fade_in_factor*two_thirds))));
            display_output_vector += (green * head_factor) + (red * (decay_factor + fade_in_factor) + (blue * decay_or_head_border));
            display_output_vector = restrict_vec3_from_0_to_1(display_output_vector);
        }
        else if(debug_head){
            display_output_vector += ones3d * head_factor;
            display_output_vector = restrict_vec3_from_0_to_1(display_output_vector);
        }
        else if(debug_decay_and_fade_in){
            //display_output_vector = ones3d * (decay_factor + fade_in_factor);

            float border_fade_in;
            float border_decay;
            float offset_area;
            float pulse_index;
            vec3 debug_vector = vec3(0.0, 0.0, 0.0);
            if(decay_factor == 1.0){
                decay_factor = 0.0;
            }
            if(fade_in_factor == 1.0){
                fade_in_factor = 0.0;
            }

            if(fade_in_factor > 0.99){
                border_fade_in = 1.0;
                fade_in_factor = 0.0;
            }
            if(decay_factor > 0.99){
                border_decay = 1.0;
                decay_factor = 0.0;
            }                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    
            /*
            // Kind-of working. Doesn't handle overflow.
            if((distance_of_current_location_behind_pulse_as_percent_of_display < decay_and_fade_offset.x ) || (distance_of_current_location_in_front_of_pulse_as_percent_of_display < decay_and_fade_offset.y)){

            if((distance_of_current_location_behind_pulse_as_percent_of_display < decay_and_fade_offset.x ) || (distance_of_current_location_in_front_of_pulse_as_percent_of_display < decay_and_fade_offset.y)){
                offset_area = 1.0;
            }
            */
            // size_pulse_head_as_percent_of_display


            if(close_to(distance_of_current_location_behind_pulse_as_percent_of_display, decay_and_fade_offset.x, 0.01)){
                offset_area = 1.0;
            }
            if(close_to(distance_of_current_location_in_front_of_pulse_as_percent_of_display, decay_and_fade_offset.y, 0.01)){
                offset_area = 1.0;
            }

            /*
            if((distance_of_current_location_in_front_of_pulse_as_percent_of_display < 0.002) || (distance_of_current_location_behind_pulse_as_percent_of_display < 0.002)){
                pulse_index = 1.0;
            }
            */

            if(close_to(distance_of_current_location_in_front_of_pulse_as_percent_of_display, 0.01, 0.01)){
                pulse_index = 1.0;
            }

            display_output_vector += ((border_fade_in * blue) + (border_decay * blue) + ((fade_in_factor + decay_factor) * red) + (offset_area * green) + (pulse_index) ) * ones3d;
            display_output_vector = restrict_vec3_from_0_to_1(display_output_vector);
        }
    }

    // Display final output
    fragColor = vec4(display_output_vector.x, display_output_vector.y, display_output_vector.z, 1.0);
}


// Begin GLSL viewer section 2 
// Comment this section out to use with shadertoy
void main() {
    vec4 color;
    iTime = u_time;
    iResolution = u_resolution;
    mainImage(color, gl_FragCoord.xy);
    FragColor = color;
}
// End GLSL viewer section 2