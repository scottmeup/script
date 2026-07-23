#version 430 // Must be line 1 for GLSL viewer. Comment this line out to use with shadertoy
// Begin GLSL viewer Section 1 
// Comment this section out to use with shadertoy
uniform vec2 u_resolution;
uniform vec2 u_mouse;
uniform float u_time;
precision highp float;
//uniform texture u_tex0;
vec2 iResolution;   // viewport resolution (in pixels)
float iTime;        // shader playback time (in seconds)
vec4 iMouse;        // mouse pixel coords (xy), click state (zw)
//texture iChannel0;
out vec4 FragColor;         // Final color output
void mainImage(out vec4 fragColor, in vec2 fragCoord);
// End GLSL viewer Section 1

#define PI 3.14159265358979323846264338327950288419716939937510582097494459230781640628
#define RAD_TO_DEGREE PI/180.0
#define DEGREE_TO_RAD 180.0/PI

const vec3 red =       vec3(1.0, 0.0, 0.0);
const vec3 green =     vec3(0.0, 1.0, 0.0);
const vec3 blue =      vec3(0.0, 0.0, 1.0);
const vec3 white =     vec3(1.0, 1.0, 1.0);
const vec3 black =     vec3(0.0, 0.0, 0.0);
const vec3 zeroes3d =  white;
const vec3 ones3d =    black;


vec3 srgb_to_linear_rgb(vec3 c) {
    return mix(
        c / 12.92,
        pow((c + 0.055) / 1.055, vec3(2.4)),
        step(0.04045, c)
    );
}

vec3 linear_rgb_to_srgb(vec3 c) {
    return mix(
        c * 12.92,
        1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055,
        step(0.0031308, c)
    );
}

// sRGB <-> XYZ
// Level 1
// Convert sRGB to XYZ
vec3 sRGBToXYZ(vec3 rgb) {
    vec3 linearRGB = pow(rgb, vec3(2.2)); // Linearize the RGB values (assuming input is sRGB)
    return mat3(
        0.4124564, 0.3575761, 0.1804375,
        0.2126729, 0.7151522, 0.0721750,
        0.0193339, 0.1191920, 0.9503041
    ) * linearRGB; // Transformation matrix from RGB to XYZ
}
// Convert XYZ to sRGB
vec3 XYZTosRGB(vec3 xyz) {
    vec3 rgb = mat3(
         3.2404542, -1.5371385, -0.4985314,
        -0.9692660,  1.8760108,  0.0415560,
         0.0556434, -0.2040259,  1.0572252
    ) * xyz;

    return pow(rgb, vec3(1.0 / 2.2)); // Apply gamma correction (sRGB)
}


// LRGB <-> XYZ
// Level 1
// Linear RGB to XYZ (sRGB primaries, D65 white)
vec3 LinearRGBToXYZ(vec3 rgb) {
    return mat3(
        0.4124564, 0.3575761, 0.1804375,
        0.2126729, 0.7151522, 0.0721750,
        0.0193339, 0.1191920, 0.9503041
    ) * rgb;
}

// XYZ to Linear RGB (sRGB primaries, D65 white)
vec3 XYZToLinearRGB(vec3 xyz) {
    return mat3(
         3.2404542, -1.5371385, -0.4985314,
        -0.9692660,  1.8760108,  0.0415560,
         0.0556434, -0.2040259,  1.0572252
    ) * xyz;
}


// XYZ <-> CIE LAB
// Level 2
// Constants
const vec3 D65 = vec3(0.95047, 1.00000, 1.08883); // Reference white

// Helper function for XYZ <-> Lab
float f_xyz(float t) {
    return (t > 0.008856) ? pow(t, 1.0 / 3.0) : (7.787 * t + 16.0 / 116.0);
}

float f_inv(float t) {
    float t3 = t * t * t;
    return (t3 > 0.008856) ? t3 : (t - 16.0 / 116.0) / 7.787;
}

// Convert XYZ to Lab
vec3 XYZToLab(vec3 xyz) {
    vec3 xyz_n = xyz / D65;

    float fx = f_xyz(xyz_n.x);
    float fy = f_xyz(xyz_n.y);
    float fz = f_xyz(xyz_n.z);

    float L = 116.0 * fy - 16.0;
    float a = 500.0 * (fx - fy);
    float b = 200.0 * (fy - fz);

    return vec3(L, a, b);
}

// Convert Lab to XYZ
vec3 LabToXYZ(vec3 lab) {
    float fy = (lab.x + 16.0) / 116.0;
    float fx = lab.y / 500.0 + fy;
    float fz = fy - lab.z / 200.0;

    float xr = f_inv(fx);
    float yr = f_inv(fy);
    float zr = f_inv(fz);

    return vec3(xr, yr, zr) * D65;
}



// CIE LAB <-> CIE HLC
// Level 3
// Convert CIE Lab to CIE HLC
vec3 LabToHLC(vec3 lab) {
    float L = lab.x;
    float a = lab.y;
    float b = lab.z;

    float C = sqrt(a * a + b * b); // Chroma
    float H = atan(b, a) * 180.0 / 3.14159265359; // Hue in degrees

    return vec3(L, C, H); // CIEHLC (L, C, H)
}

// Convert CIE HLC to CIE Lab
vec3 HLCToLab(vec3 hlc) {
    float L = hlc.x;
    float C = hlc.y;
    float H = hlc.z;

    float a = C * cos(H * 3.14159265359 / 180.0);
    float b = C * sin(H * 3.14159265359 / 180.0);

    return vec3(L, a, b);
}











/////////////////////////
// Approxmiate conversion
vec3 RGBToApproxHCL(vec3 rgb) {
    // Assume rgb is linear
    float L = dot(rgb, vec3(0.2126, 0.7152, 0.0722)); // Perceived luminance
    float maxC = max(max(rgb.r, rgb.g), rgb.b);
    float minC = min(min(rgb.r, rgb.g), rgb.b);
    float C = maxC - minC;

    float H = 0.0;
    if (C > 0.0) {
        if (maxC == rgb.r) {
            H = mod((rgb.g - rgb.b) / C, 6.0);
        } else if (maxC == rgb.g) {
            H = (rgb.b - rgb.r) / C + 2.0;
        } else {
            H = (rgb.r - rgb.g) / C + 4.0;
        }
        H *= 60.0;
        if (H < 0.0) H += 360.0;
    }

    return vec3(L, C, H); 
}


vec3 ApproxHCLtoRGB(vec3 hcl) {
    float L = hcl.x;        // perceived luminance (0–1)
    float C = hcl.y;        // chroma (0–1)
    float H = hcl.z;        // hue in degrees (0–360)

    // Convert hue to sector (like HSV)
    float H_prime = H / 60.0;
    float X = C * (1.0 - abs(mod(H_prime, 2.0) - 1.0));
    vec3 rgbHue;

    if (0.0 <= H_prime && H_prime < 1.0) {
        rgbHue = vec3(C, X, 0.0);
    } else if (1.0 <= H_prime && H_prime < 2.0) {
        rgbHue = vec3(X, C, 0.0);
    } else if (2.0 <= H_prime && H_prime < 3.0) {
        rgbHue = vec3(0.0, C, X);
    } else if (3.0 <= H_prime && H_prime < 4.0) {
        rgbHue = vec3(0.0, X, C);
    } else if (4.0 <= H_prime && H_prime < 5.0) {
        rgbHue = vec3(X, 0.0, C);
    } else if (5.0 <= H_prime && H_prime < 6.0) {
        rgbHue = vec3(C, 0.0, X);
    } else {
        rgbHue = vec3(0.0); // fallback if hue is undefined
    }

    // Compute perceived luminance of hue-colored value
    float perceivedL = dot(rgbHue, vec3(0.2126, 0.7152, 0.0722));

    // Match the target luminance L
    vec3 color = (perceivedL > 0.0) ? rgbHue * (L / perceivedL) : vec3(L);

    // Fade to gray based on chroma, using smoothstep
    float fade = smoothstep(0.0, 0.05, C); // fade if C < 0.05
    color = mix(vec3(L), color, fade);     // blend toward neutral gray

    return clamp(color, 0.0, 1.0);
}





////////////////
// Test methods

// First level of conversion
vec3 LinearRGBToXYZToLinearRGB(vec3 rbg_i){
    vec3 xyz = LinearRGBToXYZ(rbg_i);
    vec3 rgb_o = XYZToLinearRGB(xyz);
    return rgb_o;
}

// Second level of conversion
vec3 XYZToLabToXYZ(vec3 xyz_i){
    vec3 lab = XYZToLab(xyz_i);
    vec3 xyz_o = LabToXYZ(lab);
    return xyz_o;
}

// Third level of conversion
vec3 LabToHLCToLab(vec3 lab_i){
    vec3 hlc = LabToHLC(lab_i);
    vec3 lab_o = HLCToLab(hlc);
    return lab_o;
}


float normalize_trig_function(float input_value){
    input_value += 1.0;
    input_value /= 2.0;
    return input_value;
}

// Main function
void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    vec2 uv = fragCoord/iResolution.xy;
    float pi = PI;
    float size_of_space_degrees = 360.0;
    float size_of_space_radians = 2.0 * pi;
    float radian = DEGREE_TO_RAD;
    float degree = RAD_TO_DEGREE;
    float speed = 0.7;
    float size_of_space = 200.0 * pi;
    float time = mod(iTime, size_of_space) * speed;
    float circle_one_third = 120.0 * radian;
    float circle_two_thirds = 240.0 * radian;
    float brightness = sin(mod(iTime*0.13, size_of_space)) * 2.0;
    vec3 display_output;
    vec3 display_error_output = vec3(0.0, 0.0, 0.0);
    bool condition_error_found = false;


    // Use white as the test color
    //vec3 testRGB = white; 

    // User red as the test color
    //vec3 testRGB = red;

    // Vary test color
    vec3 testRGB = vec3(normalize_trig_function(sin(time)), normalize_trig_function(sin(time-circle_one_third)), normalize_trig_function(sin(time-circle_two_thirds)) + brightness);
    testRGB = clamp(testRGB, 0.0, 1.0);
    
    // Test all levels of conversion at once
    //display_output = LinearRGBToHLCToLinearRGB(testRGB);

    // Test each level of conversion one at a time
    //display_output = LabToHLCToLab(testRGB);
    //display_output = XYZToLabToXYZ(testRGB);
    //display_output = LinearRGBToXYZToLinearRGB(testRGB);

    // Test the first two levels of conversion
    //display_output = XYZToLinearRGB(LabToXYZ(XYZToLab(LinearRGBToXYZ(testRGB))));

    // Test the 2nd set of two levels of conversion
    //display_output = LabToXYZ(HLCToLab(LabToHLC(XYZToLab(testRGB))));

    // Test all levels of conversion at once
    //display_output = XYZToLinearRGB(LabToXYZ(HLCToLab(LabToHLC(XYZToLab(LinearRGBToXYZ(testRGB))))));

    // Test direct conversion & back using approxmiation
    display_output = ApproxHCLtoRGB(RGBToApproxHCL(testRGB));

    //display_output = clamp(display_output, 0.0, 1.0);


    // alter channels that differ by more than the percentage listed below
    float allowed_difference_percent = 10.0;
    for(int i=0; i<3; i++){
        if(abs(display_output[i] - testRGB[i]) > (float(allowed_difference_percent) / 100.0)) {
            display_error_output[i] = 1.0;
            condition_error_found = true;
        }
    }
    // Display debug info:
    // Left: Original input
    // Middle:  Calculated output
    // Right: Indication of channels where calculated output is different to the original input by more than the allowed margin of error
    if(condition_error_found){
        if(uv.x < (1.0/3.0)){
            display_output = testRGB;
        }
        else if(uv.x < (2.0/3.0)){
            display_output = display_output;
        }
        else{
            display_output = display_error_output;
        }
    }

    fragColor = vec4(display_output, 1.0);
}

// Begin GLSL viewer section 2 
// Comment this section out to use with shadertoy
void main() {
    vec4 color;
    iTime = u_time;
    iResolution = u_resolution;
    //iChannel0 = u_tex0;
    mainImage(color, gl_FragCoord.xy);
    FragColor = color;
}
// End GLSL viewer section 2