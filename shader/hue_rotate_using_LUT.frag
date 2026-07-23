#version 450

in vec2 fragTexCoord;  // Texture coordinates for the fragment
out vec4 fragColor;    // The output color

uniform sampler3D uLUT;      // 3D LUT texture (for example, 256x256x256)
uniform float hueShift;      // Hue shift value (can be time-based or user-controlled)
uniform float time;

vec3 rotateHue(vec3 color, float shift) {
    // Convert RGB to HSL
    float maxVal = max(max(color.r, color.g), color.b);
    float minVal = min(min(color.r, color.g), color.b);
    float delta = maxVal - minVal;

    float h = 0.0;
    float s = (maxVal == 0.0) ? 0.0 : (delta / maxVal);
    float l = (maxVal + minVal) / 2.0;

    if (delta != 0.0) {
        if (maxVal == color.r) {
            h = mod((color.g - color.b) / delta, 6.0);
        } else if (maxVal == color.g) {
            h = (color.b - color.r) / delta + 2.0;
        } else {
            h = (color.r - color.g) / delta + 4.0;
        }
        h /= 6.0;
    }

    // Apply hue shift
    h = mod(h + shift, 1.0);  // Hue is normalized between 0 and 1

    // Convert back to RGB from modified HSL
    float c = (1.0 - abs(2.0 * l - 1.0)) * s;
    float x = c * (1.0 - abs(mod(h * 6.0, 2.0) - 1.0));
    float m = l - c / 2.0;

    vec3 newColor = vec3(0.0);
    if (h < 1.0 / 6.0) {
        newColor = vec3(c, x, 0.0);
    } else if (h < 2.0 / 6.0) {
        newColor = vec3(x, c, 0.0);
    } else if (h < 3.0 / 6.0) {
        newColor = vec3(0.0, c, x);
    } else if (h < 4.0 / 6.0) {
        newColor = vec3(0.0, x, c);
    } else if (h < 5.0 / 6.0) {
        newColor = vec3(x, 0.0, c);
    } else {
        newColor = vec3(c, 0.0, x);
    }

    return newColor + vec3(m);
}

void main() {
    // Sample the input color (from a LUT texture, for example)
    vec3 color = texture(uLUT, fragTexCoord).rgb;  // Assume fragTexCoord maps to the 3D LUT coordinates

    hueShift = mod(time * 0.1, 1.0);  // Rotate by a factor depending on time

    // Rotate the hue by the desired amount
    vec3 rotatedColor = rotateHue(color, hueShift);

    // Output the rotated color
    fragColor = vec4(rotatedColor, 1.0);
}
