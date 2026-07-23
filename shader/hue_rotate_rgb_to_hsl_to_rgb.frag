#version 450

in vec2 fragTexCoord;  // The input texture coordinates (or position in your case)
out vec4 fragColor;    // The output color

uniform float hueShift; // The amount of hue shift (can be time or user-controlled)

vec3 rgbToHsl(vec3 rgb) {
    float maxVal = max(max(rgb.r, rgb.g), rgb.b);
    float minVal = min(min(rgb.r, rgb.g), rgb.b);
    float delta = maxVal - minVal;
    float h = 0.0;
    float s = maxVal == 0.0 ? 0.0 : delta / maxVal;
    float l = (maxVal + minVal) / 2.0;

    if (delta != 0.0) {
        if (maxVal == rgb.r) {
            h = mod((rgb.g - rgb.b) / delta, 6.0);
        } else if (maxVal == rgb.g) {
            h = (rgb.b - rgb.r) / delta + 2.0;
        } else {
            h = (rgb.r - rgb.g) / delta + 4.0;
        }
        h /= 6.0;
    }

    return vec3(h, s, l);
}

vec3 hslToRgb(vec3 hsl) {
    float h = hsl.x;
    float s = hsl.y;
    float l = hsl.z;
    float c = (1.0 - abs(2.0 * l - 1.0)) * s;
    float x = c * (1.0 - abs(mod(h * 6.0, 2.0) - 1.0));
    float m = l - c / 2.0;

    vec3 color = vec3(0.0);
    if (h >= 0.0 && h < 1.0 / 6.0) {
        color = vec3(c, x, 0.0);
    } else if (h >= 1.0 / 6.0 && h < 2.0 / 6.0) {
        color = vec3(x, c, 0.0);
    } else if (h >= 2.0 / 6.0 && h < 3.0 / 6.0) {
        color = vec3(0.0, c, x);
    } else if (h >= 3.0 / 6.0 && h < 4.0 / 6.0) {
        color = vec3(0.0, x, c);
    } else if (h >= 4.0 / 6.0 && h < 5.0 / 6.0) {
        color = vec3(x, 0.0, c);
    } else {
        color = vec3(c, 0.0, x);
    }

    return color + vec3(m);
}

void main() {
    vec3 color = texture(sampler2D(u_texture, fragTexCoord)).rgb; // Sample the input color from a texture
    vec3 hsl = rgbToHsl(color); // Convert RGB to HSL

    // Apply hue shift (wrap the hue between 0.0 and 1.0)
    hsl.x = mod(hsl.x + hueShift, 1.0);

    // Convert the modified HSL back to RGB
    vec3 rotatedColor = hslToRgb(hsl);

    fragColor = vec4(rotatedColor, 1.0); // Output the rotated color
}
