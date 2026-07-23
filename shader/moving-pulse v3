// configurable unidirectional color pulse

struct PulseSettings {
        float color_brightness_cutoff;
        bool color_brightness_cutoff_includes_background_brightness;
        float color_pulse_minimum_brightness_percent;
        bool color_combine_background_with_pause_color;
        float decay_speed_linear;
        float decay_speed_exponential;
        vec3 rgb_background;
        vec3 rgb_pause;
        vec3 rgb_pulse;
        float width_pulse_head_in_leds;
        float width_of_display_in_leds;
        bool display_discrete_led_output;
    };

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    float color_brightness_cutoff = 0.03;    // switch to non-pulse, "pause" section of cycle coloring below this brightness
    bool color_brightness_cutoff_includes_background_brightness = false;    
    float color_pulse_minimum_brightness_percent = 0.00;    // Minimum brightness of pulse as a percent.
    bool color_combine_background_with_pause_color = false;
    float decay_speed_linear = 0.0;    // 0.0 for no linear decay 
    float decay_speed_exponential = 3.0;    // 0.0 for no exponential decay
    bool direction_movement_horizontal = false;
    bool direction_movement_reversed = false;
    bool display_discrete_led_output = false; // To-do
    float duration_of_pause = 1.0;   //  Time between the front of the pulse leaving the screen and the next pulse appearing 
    float duration_of_pulse = 3.0;    // Time taken for the front of the pulse to run across the display
    vec3 rgb_background = vec3(0.0, 0.0, 0.5);    // (R, G, B) Color applied uniformly on top of others
    vec3 rgb_pause = vec3(0.2, 0.2, 0.0);     // (R, G, B) Color for negative space: non-pulse area  
    vec3 rgb_pulse = vec3(0.0, 1.0, 0.0);    // (R, G, B) Color for pulse
    float speed_global_modifier = 1.0;    // When set to 1.0, cycle will play at 1 second per unit of duration
    float size_pulse_head_in_leds = 1.0;
    float size_of_display_in_leds = 6.0;
    
    
    // Adjust the display parameters to suit the direction & size of the display
    // from fragCoord and iResolution 
    float size_display_in_pixels;
    float position_current_pixel;
    if (direction_movement_horizontal){
        size_display_in_pixels = iResolution.x;
        position_current_pixel = fragCoord.x;
        size_display_in_pixels_orthogonal = iResolution.y
        position_current_pixel_orthogonal = fragCoord.y;
        }
    else{
        size_display_in_pixels = iResolution.y;
        position_current_pixel = fragCoord.y;
        size_display_in_pixels_orthogonal = iResolution.x
        position_current_pixel_orthogonal = fragCoord.x;      
    }
    

    // Set additional parameters related to display calculation
    float position_of_current_location_as_percent_of_display = position_current_pixel / size_display_in_pixels;
    float duration_of_cycle = duration_of_pause + duration_of_pulse;
    float size_of_total_cycle_as_percent_of_display = duration_of_cycle / duration_of_pulse;
    float speed_of_movement_per_second_as_percent_of_display = 1.0 / duration_of_pulse;
    float size_of_led_as_percent_of_display = 1.0 / size_of_display_in_leds;
    float size_of_pulse_head_as_percent_of_display = size_of_led_as_percent_of_display * size_pulse_head_in_leds;
    float ratio_of_display_size_to_pulse_tail_size = 1.0 / (1.0 - size_of_pulse_head_as_percent_of_display);
    
    
    // Move beginning of pulse across the screen and calculate distance from each screen location
    float speed_reverse_modifier = 1.0;
    if(direction_movement_reversed){
        speed_reverse_modifier = -1.0;
    }
    
    
    // either or of the time setting works with the code, but at least the one with mod won't get insanely large
    float time = mod(iTime*speed_global_modifier*speed_reverse_modifier, duration_of_cycle);
    float position_of_pulse_as_percent_of_display = speed_of_movement_per_second_as_percent_of_display * time;

    
    // Set up distance from end of pulse head based on normal or reverse direction of movement
    vec3 display_output_vector;
    float distance_of_current_location_from_pulse_as_percent;
    if(direction_movement_reversed){
        distance_of_current_location_from_pulse_as_percent = mod((position_of_current_location_as_percent_of_display - position_of_pulse_as_percent_of_display), size_of_total_cycle_as_percent_of_display); // expect this to reach values over 100% if pause time is greater than 0
    }
    else{
        distance_of_current_location_from_pulse_as_percent = mod((position_of_pulse_as_percent_of_display - position_of_current_location_as_percent_of_display), size_of_total_cycle_as_percent_of_display); // expect this to reach values over 100% if pause time is greater than 0    
    }
    

    // Draw the pulse
    if ((distance_of_current_location_from_pulse_as_percent) < size_of_pulse_head_as_percent_of_display){
        // Pulse Head
        display_output_vector = rgb_pulse;
        }
    else{
        // Pulse Tail
        // Squish the decay rate into the non-head area of the pulse
        float distance_from_pulse_head_percent = (distance_of_current_location_from_pulse_as_percent - size_of_pulse_head_as_percent_of_display);
        float distance_from_pulse_head_percent_normalised = ( distance_from_pulse_head_percent / ratio_of_display_size_to_pulse_tail_size );
        float decay_linear = 1.0 - (distance_from_pulse_head_percent_normalised * decay_speed_linear);        
        float decay_exponential = exp(-distance_from_pulse_head_percent_normalised * decay_speed_exponential);
        float decay_total = decay_linear * decay_exponential;
        display_output_vector = (rgb_pulse * decay_total);
    }
    

    // enforce minimum brightness setting for pulse - do not decay below this intensity
    vec3 ones3d = vec3(1.0, 1.0, 1.0);
    float color_brightness_of_display_output_vector_mean_percent = dot(ones3d, display_output_vector)/3.0;
    
    if( color_brightness_of_display_output_vector_mean_percent < color_pulse_minimum_brightness_percent){
        float rgb_pulse_brightness_sum = rgb_pulse.x + rgb_pulse.y + rgb_pulse.z;
        vec3 rgb_ratio = vec3((rgb_pulse.x / rgb_pulse_brightness_sum), (rgb_pulse.y / rgb_pulse_brightness_sum), (rgb_pulse.z / rgb_pulse_brightness_sum));
        display_output_vector = (rgb_ratio * color_pulse_minimum_brightness_percent * 3.0);
    }
    

    // Establish cutoff location for pause section coloring
    float color_brightness_intensity;
    if( color_brightness_cutoff_includes_background_brightness){
        color_brightness_intensity = (dot(ones3d, display_output_vector) + dot(ones3d, rgb_background)) / 3.0;
    }
    else{
        color_brightness_intensity = dot(ones3d, display_output_vector) / 3.0;
    }


    // Switch to pause-section coloring
    if (color_brightness_intensity < color_brightness_cutoff){
         display_output_vector = rgb_pause;
         
         // Add the optional background color
         if(color_combine_background_with_pause_color){
             display_output_vector = display_output_vector + rgb_background;
         }
    }


    // Apply background to pulse section
    else{
        display_output_vector = display_output_vector + rgb_background;
    }
    

    // Display final output
    fragColor = vec4(display_output_vector.x, display_output_vector.y, display_output_vector.z, 1.0);
}