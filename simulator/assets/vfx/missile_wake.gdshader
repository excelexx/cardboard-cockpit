shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// UV.y is distance along the wake, so a long trail never becomes a row of cards.
uniform float motor = 1.0;
varying vec4 smoke_colour;
varying float view_distance;
void vertex() {
    smoke_colour = COLOR;
    view_distance = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}
void fragment() {
    float across = abs(UV.x * 2.0 - 1.0);
    float edge = pow(max(1.0 - across * across, 0.0), 1.8);
    float curl = sin(UV.y * 0.17 + sin(UV.y * 0.057 - TIME * 1.1) * 2.4 + UV.x * 5.0);
    float billow = 0.74 + 0.16 * curl + 0.10 * sin(UV.y * 0.43 - TIME * 1.8);
    float hot = pow(clamp(UV2.x, 0.0, 1.0), 12.0) * pow(edge, 4.0) * motor;
    ALBEDO = mix(smoke_colour.rgb, vec3(1.0, 0.67, 0.27), hot * 0.75);
    EMISSION = vec3(1.0, 0.38, 0.075) * hot * 4.0;
    ALPHA = clamp(smoke_colour.a * edge * billow + hot * 0.22, 0.0, 0.95) * smoothstep(12.0, 55.0, view_distance);
}
