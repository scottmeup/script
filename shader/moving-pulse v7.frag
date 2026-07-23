// configurable color pulses


// To-do
// - Fix bug with fade-in: Currently fade-in gives 1 LED at full intensity behind the LED that is actively fading in
// - - Added a debug switch to see if I like it better with or without that
// - Check timing of first LED in fade_and_decay_first_and_last_led_only
// - Inverse brightness mode?
// - Look into brightness as a function of RGB, consider re-working brightness calculation
// - - Especially for blending pulse head to fade-in
// - Consider separating image generation function into separate functions
// - Consider duplicating variables from pulse struct into local scope



// Begin User Config Globals Section
//
//
const int size_of_display_in_columns = 11;    // how many parallel pulses to run
const bool direction_movement_horizontal = false;
const bool direction_movement_reversed = true;
const float duration_of_pause = 3.0;   //  Time between the front of the pulse leaving the screen and the next pulse appearing 
const float duration_of_pulse = 3.0;    // Time taken for the front of the pulse to run across the display
const float speed_global_modifier = 1.0;    // When set to 1.0, cycle will play at 1 second per unit of duration
//
//
// End User Config Section



const vec3 ones3d = vec3(1.0, 1.0, 1.0);
const vec3 zeros3d = vec3(0.0, 0.0, 0.0);
const bool debug_fade_in = false;                 // I think it looks better with this set to false

struct Pulse_settings 
{
    vec3 rgb_pulse;    // (R, G, B) Color for pulse
    vec3 rgb_pause;     // (R, G, B) Color for negative space: non-pulse area
    vec3 rgb_fade_in;    // (R, G, B) Color applied to fade-in in front of pulse
    vec3 rgb_background;    // (R, G, B) Color applied uniformly on top of others
    float size_of_display_in_leds;    // Set to the number of LEDs in your display in order to align other settings properly   
    float size_pulse_head_in_leds;    // Non-decay area at the start of the pulse. Will run at brightness specified in rgb_pulse for the length of the number of LEDs specified
    float decay_speed_exponential;    // 0.0 for no exponential decay. Higher number = faster decay, shorter / darker pulse.
    float decay_speed_linear;    // 0.0 for no linear decay. Higher number = faster decay, shorter / darker pulse.
    float fade_in_speed_exponential;    // 0.0 for no exponential fade-in. Generate a fade-in on the LED before the pulse. Higher number = faster = shorter.
    float fade_in_speed_linear;    // 0.0 for no linear fade-in. Generate a fade-in on the LED before the pulse. Higher number = faster = shorter.
    float color_brightness_cutoff;    // switch to non-pulse, "pause" section of cycle coloring below this brightness.
    float color_pulse_minimum_brightness_percent;    // Minimum brightness of pulse as a percent. Will not decay below this level.
    bool color_brightness_cutoff_includes_background_brightness;    // Consider background coloring or not when determining the brightness of a pixel for cutoff to pause coloring.
    bool color_combine_background_with_pause_color;    // Overlay the background color on top of the "pause" / negative space color.
    bool color_combine_pulse_head_with_fade_in;    // Smooth transition between fade-in and pulse head
    bool display_discrete_led_output;   // Simulate LED display based on size_of_display_in_leds.
    bool fade_and_decay_first_and_last_led_only;    // Only apply fade-in to the first LED before the pulse appears, and to the last LED after the pulse leaves. Requires display_discrete_led_output and either fade_in or decay.

};



// Begin User Config Pulse / Example Settings Section
//
//
void Initialize_pulse_settings_array(inout Pulse_settings pulse[size_of_display_in_columns]){
    // Use order of variables listed above in "struct Pulse_settings"
    //                                                                                                              LEDs in |Pulse |Decay|Decay|Fade |Fade | Bright | Min    | Cufoff| BG + | Head+| LED   | 1st+ 
    //                              Pulse-color  |  Pause-color         | Fade-in color       | Background-color  | Display | Head | Exp | Lin | Exp | Lin | Cutoff | Bright | BG    | Pause| Fade | Output| last
    /*
    pulse[0]  = Pulse_settings(vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.05), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0), 5.0,      1.0,   3.0,  0.0,  0.0,  0.0,  0.025,   0.0,     false,  false, true,  true,   false);    // Mouse bottom
    pulse[1]  = Pulse_settings(vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.05), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0), 3.0,      1.0,   3.0,  0.0,  0.0,  0.0,  0.025,   0.0,     false,  false, true,  true,   false);    // Mouse scroll wheel
    pulse[2]  = Pulse_settings(vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.1 ), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0), 3.0,      1.0,   3.0,  0.0,  0.0,  0.0,  0.025,   0.0,     false,  false, true,  true,   false);    // Mouse logo
    pulse[3]  = Pulse_settings(vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0 ), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0), 14.0,     1.0,   3.0,  0.0,  0.0,  0.0,  0.025,   0.0,     false,  false, true,  true,   false);    // Case Front
    pulse[4]  = Pulse_settings(vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0 ), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0), 10.0,     1.0,   3.0,  0.0,  0.0,  0.0,  0.025,   0.0,     false,  false, true,  true,   false);    // Case Top
    pulse[5]  = Pulse_settings(vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0 ), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0), 8.0,      1.0,   3.0,  0.0,  0.0,  0.0,  0.025,   0.0,     false,  false, true,  true,   false);    // Motherboard - Z490D
    pulse[6]  = Pulse_settings(vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0 ), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0), 8.0,      1.0,   3.0,  0.0,  0.0,  0.0,  0.025,   0.0,     false,  false, true,  true,   false);    // Motherboard - Asus Aura
    pulse[7]  = Pulse_settings(vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0 ), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0), 4.0,      1.0,   3.0,  0.0,  1.0,  3.0,  0.025,   0.0,     false,  false, false,  true,   true );    // Graphics Card
    pulse[8]  = Pulse_settings(vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0 ), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0), 4.0,      1.0,   3.0,  0.0,  1.0,  3.0,  0.025,   0.0,     false,  false, true,  true,   true );    // Test
    */
    pulse[0]  = Pulse_settings(vec3(1.0, 0.0, 0.0 ), vec3(0.0, 0.0, 0.05), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0), 5.0,      1.0,   3.0,  0.0,  0.0,   0.0,  0.025,   0.0,     false,  true, false,  true,   false);     // Device 1
    pulse[1]  = Pulse_settings(vec3(1.0, 0.75, 0.0), vec3(0.0, 0.0, 0.05), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0), 3.0,      1.0,   3.0,  0.0,  0.0,   0.0,  0.025,   0.0,     false,  true, false,  true,   false);     // Device 2
    pulse[2]  = Pulse_settings(vec3(1.0, 1.0, 0.0 ), vec3(0.0, 0.0, 0.1 ), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0), 3.0,      2.0,   3.0,  0.0,  0.0,   0.0,  0.025,   0.0,     false,  true, false,  true,   false);     // Device 3
    pulse[3]  = Pulse_settings(vec3(0.0, 1.0, 0.0 ), vec3(0.0, 0.0, 0.0 ), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0), 14.0,     1.0,   3.0,  0.0,  14.0,  0.0,  0.025,   0.0,     false,  true, false,  true,   false);     // Device 4
    pulse[4]  = Pulse_settings(vec3(0.0, 0.0, 1.0 ), vec3(0.0, 0.0, 0.0 ), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), 8.0,      1.0,   3.0,  0.0,  0.0,   0.0,  0.025,   0.0,     false,  true, false,  true,   false);     // Device 5
    pulse[5]  = Pulse_settings(vec3(0.0, 1.0, 1.0 ), vec3(0.0, 0.0, 0.5 ), vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), 8.0,      1.0,   3.0,  0.0,  0.0,   0.0,  0.1,     0.0,     false,  true, false,  true,   false);     // Device 6
    pulse[6]  = Pulse_settings(vec3(0.0, 0.0, 1.0 ), vec3(0.0, 0.0, 0.0 ), vec3(0.5, 0.0, 1.0), vec3(0.0, 0.0, 0.0), 8.0,      1.0,   3.0,  0.0, 64.0,   0.0,  0.025,   0.0,     false,  true, true,   true,   false);     // Device 7
//    pulse[7]  = Pulse_settings(vec3(1.0, 0.0, 1.0 ), vec3(0.0, 0.0, 0.0 ), vec3(1.0, 0.0, 1.0), vec3(0.0, 0.0, 0.0), 3.0,      1.0,   3.0,  0.0,  1.0,   3.0,  0.025,   0.0,     false,  true, false,  true,   true );     // Device 8
//    pulse[8]  = Pulse_settings(vec3(0.5, 0.0, 1.0 ), vec3(0.0, 0.0, 0.0 ), vec3(0.5, 0.0, 1.0), vec3(0.0, 0.0, 0.0), 4.0,      0.0,   0.0,  1.0,  0.0,   1.0,  0.025,   0.0,     false,  true, false,  true,   false );    // Device 9
    pulse[9]  = Pulse_settings(vec3(1.0, 1.0, 1.0 ), vec3(0.0, 0.0, 0.0 ), vec3(1.0, 1.0, 1.0), vec3(0.0, 0.0, 0.0), 4.0,      0.0,   9.0,  0.0,  9.0,   0.0,  0.025,   0.0,     false,  true, false,  false,  false );    // Device 10
    pulse[10] = Pulse_settings(vec3(1.0, 1.0, 1.0 ), vec3(0.0, 0.0, 0.0 ), vec3(1.0, 1.0, 1.0), vec3(0.0, 0.0, 0.0), 4.0,      0.0,   0.0,  1.5,  0.0,   0.0,  0.025,   0.3,     false,  true, false,  false,  false );    // Device 11
    pulse[7]  = Pulse_settings(vec3(1.0, 0.0, 1.0 ), vec3(0.0, 0.0, 0.0 ), vec3(1.0, 0.0, 1.0), vec3(0.0, 0.0, 0.0), 2.0,      1.0,   3.0,  0.0,  1.0,   3.0,  0.025,   0.0,     false,  true, false,  true,   true );     // Device 8
    pulse[8]  = Pulse_settings(vec3(1.0, 0.0, 1.0 ), vec3(0.0, 0.0, 0.0 ), vec3(1.0, 0.0, 1.0), vec3(0.0, 0.0, 0.0), 2.0,      1.0,   3.0,  0.0,  1.0,   3.0,  0.025,   0.0,     false,  true, false,  false,   false );     // Device 8


    /*

    // Alternative way to initialize a pulse:
    // Does the same thing as the examples above.
    pulse[0].rgb_pulse = vec3(0.0, 1.0, 0.0);
    pulse[0].rgb_pause = vec3(0.0, 0.0, 0.05);
    pulse[0].rgb_fade_in = vec3(0.0, 0.0, 1.0);
    pulse[0].rgb_background = vec3(0.0, 0.0, 0.0);
    pulse[0].size_of_display_in_leds = 8.0; 
    pulse[0].size_pulse_head_in_leds = 1.0;   
    pulse[0].decay_speed_exponential = 3.0;  
    pulse[0].decay_speed_linear = 0.0;   
    pulse[0].fade_in_speed_exponential = 16.0;  
    pulse[0].fade_in_speed_linear = 0.0;   
    pulse[0].color_brightness_cutoff = 0.025;  
    pulse[0].color_pulse_minimum_brightness_percent = 0.0;  
    pulse[0].color_brightness_cutoff_includes_background_brightness = false;
    pulse[0].color_combine_background_with_pause_color = false;   
    pulse[0].color_combine_pulse_head_with_fade_in = true;   
    pulse[0].display_discrete_led_output = true;
    pulse[0].fade_and_decay_first_and_last_led_only = false;
    
    */

}
//
//
// End User Config Section



vec3 generate_rgb_output_column(Pulse_settings pulse, float distance_of_current_location_behind_pulse_as_percent, float distance_of_current_location_behind_start_of_led_in_percent, vec2 position_current_location_adjusted_as_percent){

    // Draw the current pulse
    vec3 display_output_vector_column;
    
    // Set up some values to manage the logic
    float size_pulse_head_in_leds = pulse.size_pulse_head_in_leds;
    float size_of_display_in_leds = pulse.size_of_display_in_leds;
    float size_of_led_as_percent_of_display = ( 1.0 / size_of_display_in_leds );
    float size_of_pulse_head_as_percent_of_display = size_of_led_as_percent_of_display * size_pulse_head_in_leds;
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
    float ratio_of_total_cycle_to_display = ( ( duration_of_pause + duration_of_pulse ) / duration_of_pulse );
    float position_current_led_in_display = floor( position_current_location_adjusted_as_percent.y / size_of_led_as_percent_of_display );
    if(direction_movement_reversed){
        // Hmm... i thought this code was already being passed a direction-adjusted position
        position_current_led_in_display = ( (pulse.size_of_display_in_leds - 1.0) - position_current_led_in_display );
    }
    
    // Discrete LED output
    if(pulse.display_discrete_led_output){        
        if ( (distance_of_current_location_behind_pulse_as_percent + distance_of_current_location_behind_start_of_led_in_percent) > (ratio_of_total_cycle_to_display) ){
            // Black magic.
            // As the distance from the current location from the index of the pulse location approaches the full cycle width,
            // If adding the distance from the current location from the beginning position of it's LED is greater than one cycle width,
            // Then subtract the distance of one full cycle width from the current location.
            //
            // Generate the entire first LED in the pulse as soon as the pulse index enters it's boundaries... I hope.
            distance_of_current_location_behind_pulse_as_percent = distance_of_current_location_behind_pulse_as_percent - ratio_of_total_cycle_to_display;
            distance_of_current_location_behind_pulse_as_percent = distance_of_current_location_behind_pulse_as_percent + distance_of_current_location_behind_start_of_led_in_percent;        }
        else{
            // Any other position should have it's distance value set to the beginning of the LED that it is a member of
            distance_of_current_location_behind_pulse_as_percent = distance_of_current_location_behind_pulse_as_percent + distance_of_current_location_behind_start_of_led_in_percent;
        }
    }

    // Set up special mode: fade_and_decay_first_and_last_led_only.
    // Should result in only 1 LED having any illumination at a time, fade-in at the start and / or decay at the end.
    if( pulse.fade_and_decay_first_and_last_led_only && ( flag_generate_decay || flag_generate_fade_in ) ){
        size_pulse_head_in_leds = 0.0;
        
        fade_and_decay_first_and_last_led_only = true;
    }


    // Generate fade-in:
    // Calculate distance of current screen position in front of pulse
    float fade_in_linear = 1.0;
    float fade_in_exponential = 1.0;
    float distance_of_current_location_in_front_of_pulse_as_percent = (ratio_of_total_cycle_to_display - distance_of_current_location_behind_pulse_as_percent);    
    float distance_of_current_location_in_front_of_pulse_in_leds = ceil(distance_of_current_location_in_front_of_pulse_as_percent/size_of_led_as_percent_of_display);
    
    if(fade_and_decay_first_and_last_led_only && (position_current_led_in_display == 0.0)){
        // Delay the timing of fade-in generation if fade_and_decay_first_and_last_led_only is set
        //distance_of_current_location_in_front_of_pulse_as_percent += (1.0 * size_of_led_as_percent_of_display);
        //return vec3(0.25, 0.25, 0.25);
    }
    if( distance_of_current_location_in_front_of_pulse_in_leds < 1.0 ){
        // Do nothing if current location is less than 1 LED in front of the pulse as measured in number of discrete LEDs rounded up.
        // It shouldn't be possible for this branch to execute if things are working properly.
        return vec3(1.0, 1.0, 1.0);
    }
    else{
        float distance_of_current_location_in_front_of_pulse_adjusted_for_direction = distance_of_current_location_in_front_of_pulse_as_percent;
        if(pulse.display_discrete_led_output && (pulse.size_pulse_head_in_leds <= 0.0)){
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


    // Generate pulse
    if ((distance_of_current_location_behind_pulse_as_percent) < size_of_pulse_head_as_percent_of_display){
        // Pulse Head
        if(pulse.color_combine_pulse_head_with_fade_in && flag_generate_fade_in){
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
    else if(( flag_generate_decay_linear || flag_generate_decay_exponential ) != false ){
        // Pulse Tail
        // Squish the decay rate into the non-head area of the pulse
        float distance_behind_pulse_head_as_percent_of_display = (distance_of_current_location_behind_pulse_as_percent - size_of_pulse_head_as_percent_of_display);
        float distance_behind_pulse_head_as_percent_of_display_normalised = ( distance_behind_pulse_head_as_percent_of_display * ratio_of_display_size_to_pulse_tail_size );
        float decay_linear = 1.0 - (distance_behind_pulse_head_as_percent_of_display_normalised * pulse.decay_speed_linear);        
        float decay_exponential = exp(-distance_behind_pulse_head_as_percent_of_display_normalised * pulse.decay_speed_exponential);
        float decay_total = ( decay_linear * decay_exponential );
        if ( ( position_current_led_in_display != (pulse.size_of_display_in_leds-1.0) ) && fade_and_decay_first_and_last_led_only){
            // fade_and_decay_first_and_last_led_only is set but this isn't the last LED in the display.
            // Do nothing.
        }
        else{
            // Otherwise, generate pulse decay tail
            display_output_vector_column = ( pulse.rgb_pulse * decay_total );
        }
    }
    
    // Keep display values in sensible range
    display_output_vector_column = max(display_output_vector_column, zeros3d);
    display_output_vector_column = min(display_output_vector_column, ones3d);
  
    
    
    
    
    
    

    // enforce minimum brightness setting for pulse - do not decay below this intensity
    float color_brightness_of_display_output_vector_mean_percent = dot(ones3d, display_output_vector_column)/3.0;
    
    if( color_brightness_of_display_output_vector_mean_percent < pulse.color_pulse_minimum_brightness_percent){
        float rgb_pulse_brightness_sum = pulse.rgb_pulse.x + pulse.rgb_pulse.y + pulse.rgb_pulse.z;
        vec3 rgb_ratio = vec3((pulse.rgb_pulse.x / rgb_pulse_brightness_sum), (pulse.rgb_pulse.y / rgb_pulse_brightness_sum), (pulse.rgb_pulse.z / rgb_pulse_brightness_sum));
        display_output_vector_column = (rgb_ratio * pulse.color_pulse_minimum_brightness_percent * 3.0);
    }
    

    // Establish cutoff location for pause section coloring
    float color_brightness_intensity;
    if( pulse.color_brightness_cutoff_includes_background_brightness){
        color_brightness_intensity = (dot(ones3d, display_output_vector_column) + dot(ones3d, pulse.rgb_background)) / 3.0;
    }
    else{
        color_brightness_intensity = dot(ones3d, display_output_vector_column) / 3.0;
    }


    // Switch to pause-section coloring when brightness drops off below the set cutoff level
    if (color_brightness_intensity < pulse.color_brightness_cutoff){
         display_output_vector_column = pulse.rgb_pause;
         
         // Add the optional background color
         if(pulse.color_combine_background_with_pause_color){
             display_output_vector_column = display_output_vector_column + pulse.rgb_background;
         }
    }
    // Apply background to pulse section
    else{
        display_output_vector_column = display_output_vector_column + pulse.rgb_background;
    }
    return display_output_vector_column;
}


void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    // Begin User Config / Example Settings Section
    //
    // Create array with number of parallel pulses
    Pulse_settings[size_of_display_in_columns] pulse;
    Initialize_pulse_settings_array(pulse);
    // End User Config / Example Settings Section


    // Adjust the display parameters to suit the direction & size of the display
    // from fragCoord and iResolution 
    float size_display_width_in_pixels;
    float size_display_height_in_pixels;
    float position_current_pixel_x;
    float position_current_pixel_y;
    if (direction_movement_horizontal){
        size_display_width_in_pixels = iResolution.y;
        size_display_height_in_pixels = iResolution.x;
        position_current_pixel_x = fragCoord.y;
        position_current_pixel_y = fragCoord.x;
        }
    else{
        size_display_width_in_pixels = iResolution.x;
        size_display_height_in_pixels = iResolution.y;
        position_current_pixel_x = fragCoord.x;
        position_current_pixel_y = fragCoord.y;   
    }
    vec2 position_current_location_adjusted_as_percent = vec2(position_current_pixel_x/size_display_width_in_pixels, position_current_pixel_y/size_display_height_in_pixels);

    // Set additional parameters related to display calculation
    float position_of_current_location_y_as_percent_of_display = position_current_pixel_y / size_display_height_in_pixels;
    float duration_of_cycle = duration_of_pause + duration_of_pulse;
    float ratio_of_total_cycle_to_display = duration_of_cycle / duration_of_pulse;
    float speed_of_movement_per_second_as_percent_of_display = 1.0 / duration_of_pulse;

    
    // Move beginning of pulse across the screen and calculate distance from each screen location
    float speed_reverse_modifier = 1.0;
    if(direction_movement_reversed){
        speed_reverse_modifier = -1.0;
    }
    float time = mod(iTime*speed_global_modifier*speed_reverse_modifier, duration_of_cycle);
    float position_of_pulse_as_percent_of_display = speed_of_movement_per_second_as_percent_of_display * time;

    
    // Set up distance from end of pulse head based on normal or reverse direction of movement
    vec3 display_output_vector;
    float distance_of_current_location_behind_pulse_as_percent;
    if(direction_movement_reversed){
        distance_of_current_location_behind_pulse_as_percent = mod((position_of_current_location_y_as_percent_of_display - position_of_pulse_as_percent_of_display), ratio_of_total_cycle_to_display); // expect this to reach values over 100% if pause time is greater than 0
    }
    else{
        distance_of_current_location_behind_pulse_as_percent = mod((position_of_pulse_as_percent_of_display - position_of_current_location_y_as_percent_of_display), ratio_of_total_cycle_to_display); // expect this to reach values over 100% if pause time is greater than 0    
    }
        

    // Calculate the column index of the current screen location
    float position_of_current_location_x_as_percent_of_display = (position_current_pixel_x / size_display_width_in_pixels);
    int index_current_pulse = int(floor(position_of_current_location_x_as_percent_of_display * float(size_of_display_in_columns)));
    
    
    // Get the number of LED elements for the current column
    float size_of_current_pulse_display_in_leds = pulse[index_current_pulse].size_of_display_in_leds;
    float size_of_current_pulse_led_in_screen_percent = ( 1.0 / size_of_current_pulse_display_in_leds );
    
    
    // Set up distance of screen location from beginning of LED
    float distance_of_current_screen_position_behind_start_of_led_in_percent;
    if(direction_movement_reversed){
        distance_of_current_screen_position_behind_start_of_led_in_percent = size_of_current_pulse_led_in_screen_percent - mod(position_of_current_location_y_as_percent_of_display, size_of_current_pulse_led_in_screen_percent);
    }
    else{
        distance_of_current_screen_position_behind_start_of_led_in_percent = mod(position_of_current_location_y_as_percent_of_display, size_of_current_pulse_led_in_screen_percent);
    }
    
    
    // Call function to generate column output
    display_output_vector = generate_rgb_output_column(pulse[index_current_pulse], distance_of_current_location_behind_pulse_as_percent, distance_of_current_screen_position_behind_start_of_led_in_percent, position_current_location_adjusted_as_percent);


    // Display final output
    fragColor = vec4(display_output_vector.x, display_output_vector.y, display_output_vector.z, 1.0);
}