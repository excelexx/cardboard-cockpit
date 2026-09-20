shader_type sky;
// Graded photographic sky, pushed toward the key art: exposed for the clouds
// rather than the ground, steep contrast so cloud BASES go dark slate and only
// their lit edges glow, a concentrated warm band low on the sun side, and a
// cool shadowed blue everywhere else. A soft shoulder keeps the sun side from
// clipping to white. No sun disc and no shafts are added, so nothing bright
// ever sits over the view.
uniform sampler2D panorama : source_color, filter_linear, repeat_enable;
uniform vec3 sun_dir = vec3(-0.482, 0.286, 0.828);   // panorama space, toward the sun
uniform float exposure = 0.62;
uniform float contrast = 1.62;
uniform float pivot = 0.34;
uniform float saturation = 1.26;
uniform vec3 warm : source_color = vec3(1.0, 0.60, 0.26);
uniform vec3 cool : source_color = vec3(0.57, 0.69, 0.90);
uniform vec3 band : source_color = vec3(1.0, 0.52, 0.17);
uniform float warm_reach = 2.2;
uniform float base_shadow = 0.62;    // how far the dark cloud bases are pushed down
void sky() {
	vec3 colour = texture(panorama, SKY_COORDS).rgb * exposure;
	float luminance = max(dot(colour, vec3(0.2126, 0.7152, 0.0722)), 1e-4);
	vec3 eye = normalize(EYEDIR);
	float toward = max(dot(eye, normalize(sun_dir)), 0.0);
	// Flatten the grade close to the sun. The panorama has real crepuscular rays
	// baked into it and a steep curve turns them into hard shafts over the view.
	float local_contrast = mix(contrast, 1.12, pow(toward, 2.5));
	colour *= pow(luminance / pivot, local_contrast - 1.0);
	float low = 1.0 - smoothstep(0.0, 0.55, eye.y);
	float warmth = clamp(pow(toward, warm_reach) * 1.1 + low * toward * 0.45, 0.0, 1.0);
	// Bright pixels take the warm light; dark cloud bases keep the cool shadow colour.
	float lit = smoothstep(0.18, 1.1, luminance);
	vec3 tint = mix(cool, mix(vec3(1.0), warm * 1.6, warmth), mix(0.30, 1.0, lit));
	colour *= tint;
	// Cloud bases: everything unlit goes further down and further toward slate,
	// which is what separates the key art's sky from a postcard.
	colour *= mix(1.0 - base_shadow * (1.0 - warmth * 0.45), 1.0, lit);
	// A narrow, rich band of gold sitting on the horizon on the sun side only.
	float horizon = smoothstep(0.26, 0.0, abs(eye.y)) * smoothstep(0.0, 0.35, eye.y + 0.18);
	colour += band * horizon * pow(toward * 0.5 + 0.5, 5.0) * 0.55;
	colour = colour / (1.0 + colour * 0.26);          // shoulder: clouds near the sun keep their shape
	float grey = dot(colour, vec3(0.2126, 0.7152, 0.0722));
	colour = max(mix(vec3(grey), colour, saturation), vec3(0.0));
	COLOR = colour;
}
