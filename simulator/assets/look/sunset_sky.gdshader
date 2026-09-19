shader_type sky;
// Graded photographic sky. The panorama is a real golden-hour cloudscape; this
// pass gives it the key-art mood: exposed for the clouds rather than the ground,
// steeper contrast so cloud bases go dark and their lit edges glow, warm light
// pooled around the sun and low on its side of the sky, cool shadowed blue
// elsewhere. No sun disc or shafts are added, so nothing bright sits over the view.
uniform sampler2D panorama : source_color, filter_linear, repeat_enable;
uniform vec3 sun_dir = vec3(-0.482, 0.286, 0.828);   // panorama space, toward the sun
uniform float exposure = 0.72;
uniform float contrast = 1.45;
uniform float pivot = 0.30;
uniform float saturation = 1.30;
uniform vec3 warm : source_color = vec3(1.0, 0.62, 0.30);
uniform vec3 cool : source_color = vec3(0.62, 0.78, 1.0);
uniform float warm_reach = 2.2;
void sky() {
	vec3 colour = texture(panorama, SKY_COORDS).rgb * exposure;
	float luminance = max(dot(colour, vec3(0.2126, 0.7152, 0.0722)), 1e-4);
	colour *= pow(luminance / pivot, contrast - 1.0);
	vec3 eye = normalize(EYEDIR);
	float toward = max(dot(eye, normalize(sun_dir)), 0.0);
	float low = 1.0 - smoothstep(0.0, 0.55, eye.y);
	float warmth = clamp(pow(toward, warm_reach) * 1.1 + low * toward * 0.45, 0.0, 1.0);
	// Bright pixels take the warm light; dark cloud bases keep the cool shadow colour.
	float lit = smoothstep(0.15, 1.2, luminance);
	vec3 tint = mix(cool, mix(vec3(1.0), warm * 1.55, warmth), mix(0.35, 1.0, lit));
	colour *= tint;
	colour = colour / (1.0 + colour * 0.20);          // shoulder: clouds near the sun keep their shape
	float grey = dot(colour, vec3(0.2126, 0.7152, 0.0722));
	colour = max(mix(vec3(grey), colour, saturation), vec3(0.0));
	COLOR = colour;
}
