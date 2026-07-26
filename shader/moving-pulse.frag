vec3 map_viewport_coords (in vec2 frag_coord){
    // some test code to establish values.
    // black = 0%, white = 100%
    
    vec3 display_output_vector;
    float location_percent_x = frag_coord.x / iResolution.x;
    float location_percent_y = frag_coord.y / iResolution.y;
    float pixel_brightness_intensity = ( (location_percent_x/2.0) + (location_percent_y/2.0) );
    vec3 intensity_map = vec3(pixel_brightness_intensity, pixel_brightness_intensity, pixel_brightness_intensity);
    return intensity_map;
}

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    float color_pause_cutoff = 0.0;
    bool color_pause_cutoff_includes_uniform_level = false;    
    float color_pulse_minimum_brightness = 0.0;
    bool color_combine_background_with_pause = true;
    float decay_speed_linear = 0.0;    // 0.0 for no linear decay 
    float decay_speed_exponential = 3.0;    // 0.0 for no exponential decay
    bool direction_movement_horizontal = true;
    bool direction_movement_reversed = true;
    bool display_discrete_led_output = false;
    float duration_of_pause = 3.0;   //  Time between the front of the pulse leaving the screen and the next pulse appearing 
    float duration_of_pulse = 2.0;    // Time taken for the front of the pulse to run across the display
    vec3 rgb_background = vec3(0.0, 0.0, 1.0);    // Color applied uniformly on top of others
    vec3 rgb_pause = vec3(1.0, 0.0, 0.0);     // Color for negative space: non-pulse area  
    vec3 rgb_pulse = vec3(0.0, 1.0, 0.0);    // Color for pulse
    float speed_modifier_global = 1.0;    // When set to 1.0, cycle will play at 1 second per unit of duration
    float width_pulse_head_in_leds = 1.0;
    float width_of_display_in_leds = 12.0;
    
    
    // Get the resolution from Shadertoy
    // vec2 resolution_viewport = iResolution.xy;
    
    // Adjust the display parameters to suit the direction & size of the display
    // from fragCoord and iResolution 
    float width_display_in_pixels;
    float position_current_pixel;
    if (direction_movement_horizontal){
        width_display_in_pixels = iResolution.x;
        position_current_pixel = fragCoord.x;    
        }
    else{
        width_display_in_pixels = iResolution.y;
        position_current_pixel = fragCoord.y;        
    }
    
    // Set additional parameters related to display calculation
    float position_of_current_location_as_percent_of_display = position_current_pixel / width_display_in_pixels;
    float duration_of_cycle = duration_of_pause + duration_of_pulse;
    float width_of_total_cycle_as_percent_of_display = duration_of_cycle / duration_of_pulse;
    float speed_of_movement_per_second_as_percent_of_display = 1.0 / duration_of_pulse;
    //float speed_global = speed_of_movement_per_second_as_percent_of_display * speed_modifier_global; //not using this apparently?

    float width_of_led_as_percent_of_display = 1.0 / width_of_display_in_leds;
    float width_of_pulse_head_as_percent_of_display = width_of_led_as_percent_of_display * width_pulse_head_in_leds;
    float ratio_of_display_width_to_pulse_tail_width = 1.0 / (1.0 - width_of_pulse_head_as_percent_of_display);
    
    // Move beginning of pulse across the screen and calculate distance from each screen location
    float speed_reverse_modifier = 1.0;
    if(direction_movement_reversed){
        speed_reverse_modifier = -1.0;
    }
    float time = mod(iTime*speed_modifier_global, duration_of_cycle); 
    float position_of_pulse_as_percent_of_display = speed_of_movement_per_second_as_percent_of_display * time;
    float distance_of_current_location_from_pulse_as_percent = mod((position_of_pulse_as_percent_of_display - position_of_current_location_as_percent_of_display), width_of_total_cycle_as_percent_of_display); // expect this to reach values over 100% if pause time is greater than 0
   

    // display the pulse
    vec3 display_output_vector;
    if(direction_movement_reversed){
        if (distance_of_current_location_from_pulse_as_percent < width_of_pulse_head_as_percent_of_display){
            // Pulse Head
            display_output_vector = rgb_pulse;
        }
        else{
            // Pulse Tail
            // Squish the decay rate into the non-head area of the pulse
            float distance_from_pulse_head_percent = distance_of_current_location_from_pulse_as_percent - width_of_pulse_head_as_percent_of_display;
            float distance_from_pulse_head_percent_normalised = ( distance_from_pulse_head_percent / ratio_of_display_width_to_pulse_tail_width );
            float decay_linear = 1.0 - (distance_from_pulse_head_percent_normalised * decay_speed_linear);        
            float decay_exponential = exp(-distance_from_pulse_head_percent_normalised * decay_speed_exponential);
            float decay_total = decay_linear * decay_exponential;
            display_output_vector = (rgb_pulse * decay_total);
        }
    
    }
    else{
        if (distance_of_current_location_from_pulse_as_percent < width_of_pulse_head_as_percent_of_display){
            // Pulse Head
            display_output_vector = rgb_pulse;
        }
        else{
            // Pulse Tail
            // Squish the decay rate into the non-head area of the pulse
            float distance_from_pulse_head_percent = distance_of_current_location_from_pulse_as_percent - width_of_pulse_head_as_percent_of_display;
            float distance_from_pulse_head_percent_normalised = ( distance_from_pulse_head_percent / ratio_of_display_width_to_pulse_tail_width );
            float decay_linear = 1.0 - (distance_from_pulse_head_percent_normalised * decay_speed_linear);        
            float decay_exponential = exp(-distance_from_pulse_head_percent_normalised * decay_speed_exponential);
            float decay_total = decay_linear * decay_exponential;
            display_output_vector = (rgb_pulse * decay_total);

        }
    }
    
    // debug line to test viewport coordinates
    //display_output_vector = map_viewport_coords(fragCoord);
    
    fragColor = vec4(display_output_vector.x, display_output_vector.y, display_output_vector.z, 1.0);
}
