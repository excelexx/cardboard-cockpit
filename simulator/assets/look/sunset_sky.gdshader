shader_type sky;
// Graded photographic sky, pushed toward the key art: exposed for the clouds
// rather than the ground, steep contrast so cloud BASES go dark slate and only
// their lit edges glow, a concentrated warm band low on the horizon, and a cool
// shadowed blue everywhere else. A soft shoulder keeps the sun side from
// clipping to white. No sun disc and no shafts are added.
//
// The panorama has real crepuscular rays photographed into it, and they fan 60
// to 90 degrees out from the sun. Contrast turns them into hard shafts over the
// view, which the brief forbids, and a flatten kernel keyed on pow(toward, 2.5)
// only reaches ~30 degrees - the shafts' ORIGIN, not their bodies. So the sun
// side is softened toward an angular blur of itself, weighted to the bright
// pixels: a shaft is a bright streak between clouds and dissolves, while a dark
// cloud base keeps its edge. The horizon band is backed off on the sun side,
// where sky and water are already the same gold and the band was the thing
// making the horizon line disappear.
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
uniform float shaft_reach = 0.75;    // exponent on cos(angle to sun): lower reaches further
uniform float shaft_softness = 0.88; // how far a bright sun-side pixel goes to the blur
uniform float shaft_radius = 0.0046; // blur radius in panorama u; 1 degree = 0.00278
// --- Storm mass, away from the light -----------------------------------------
// The panorama is a clear blue afternoon everywhere except around its own sun,
// so a frame looking across the light read as two different times of day: gold
// on one side, a summer cumulus sky on the other. The key art's weather is a
// dark low bank AWAY from the light, and that belongs here rather than in more
// fog sheets on the water.
//
// It is slate, not black, and it is held under about sixteen degrees of
// elevation. The geese are read against this sky and the playability rule
// forbids making them harder to see, so the bank stays well above a goose
// silhouette in value and leaves the upper sky alone.
uniform vec3 storm : source_color = vec3(0.090, 0.104, 0.134);
uniform float storm_amount = 0.95;   // how much of the anti-sun horizon it owns
uniform float storm_top = 0.46;      // eye.y the bank's top edge sits around

// Angular blur of the panorama. Twelve taps on two rings; v is scaled by two
// because an equirectangular v spans 180 degrees against u's 360.
vec3 soften(vec2 uv) {
	vec3 sum = texture(panorama, uv).rgb;
	for (int i = 0; i < 6; i++) {
		float t = float(i) * 1.0471976;
		vec2 o = vec2(cos(t), sin(t) * 2.0) * shaft_radius;
		sum += texture(panorama, uv + o).rgb;
		sum += texture(panorama, uv - o * 2.1).rgb;
	}
	return sum / 13.0;
}

void sky() {
	vec3 eye = normalize(EYEDIR);
	float toward = max(dot(eye, normalize(sun_dir)), 0.0);
	// pow(x, 0.75) still reads 0.45 at 70 degrees off the sun, which is where
	// the shafts actually are.
	float fan = pow(toward, shaft_reach);
	vec3 raw = texture(panorama, SKY_COORDS).rgb;
	vec3 colour = raw;
	if (fan > 0.06 && !AT_CUBEMAP_PASS) {
		float bright = smoothstep(0.30, 1.30, dot(raw, vec3(0.2126, 0.7152, 0.0722)) / pivot);
		colour = mix(raw, soften(SKY_COORDS), clamp(fan * bright * shaft_softness, 0.0, 0.9));
	}
	colour *= exposure;
	float luminance = max(dot(colour, vec3(0.2126, 0.7152, 0.0722)), 1e-4);
	// Flatten the grade across the whole sun side, not just around the disc.
	float local_contrast = mix(contrast, 1.06, clamp(fan * 1.15, 0.0, 1.0));
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
	// Away from the light the panorama is a bright summer afternoon - blue sky,
	// white cumulus - and next to the gold side of the same frame that reads as
	// two times of day. Cool it and settle it, hardest on the cloud TOPS, which
	// are lit by a sun that is almost on the horizon and have no business being
	// white. Restrained on purpose: the geese are read against this sky.
	float away = smoothstep(0.30, -0.35, toward);
	colour *= mix(vec3(1.0), vec3(0.50, 0.58, 0.74), away * mix(0.42, 0.92, lit));
	// A narrow band of gold on the horizon - on the FLANKS of the sun, falling
	// away as the view turns into it.
	float horizon = smoothstep(0.26, 0.0, abs(eye.y)) * smoothstep(0.0, 0.35, eye.y + 0.18);
	float flank = smoothstep(-0.25, 0.45, toward) * (1.0 - 0.80 * smoothstep(0.50, 0.95, toward));
	// The band is ADDITIVE, so where there is no warm light to justify it the
	// gold landed on a cool blue sky and mixed to the flat dusty maroon wash that
	// sat under the cumulus. Desaturate it and back it off as the warmth runs out.
	float justified = clamp(warmth * 2.1, 0.0, 1.0);
	vec3 band_tint = mix(vec3(dot(band, vec3(0.2126, 0.7152, 0.0722))), band, justified);
	colour += band_tint * horizon * flank * 0.42 * mix(0.26, 1.0, justified);

	// --- The storm mass ------------------------------------------------------
	// A lumpy field lifted from a distant part of the panorama itself: free, and
	// it carries real cloud shape instead of a procedural wobble. The panorama is
	// HDR and most of it sits well above one, so compress before thresholding -
	// against a raw luma every sample reads as "bright" and the mass comes out
	// flat, which is what the first pass at this got wrong.
	vec3 lump = texture(panorama, SKY_COORDS * vec2(0.63, 0.34) + vec2(0.37, 0.41)).rgb;
	float lump_l = dot(lump, vec3(0.2126, 0.7152, 0.0722));
	float mass = smoothstep(0.30, 0.78, lump_l / (1.0 + lump_l));
	float top = storm_top * (0.45 + 0.90 * mass);
	float bank = smoothstep(top, top - 0.15, eye.y) * smoothstep(-0.17, -0.02, eye.y);
	float shelf = bank * away * storm_amount;
	// Bases go furthest toward slate; the denser lumps keep a little more of
	// their own body so the mass has volume rather than reading as a grey wash.
	colour = mix(colour, storm * (0.55 + 1.45 * mass), shelf * mix(0.52, 0.94, 1.0 - mass));
	// A thin warm rim where the top edge of the mass catches the light, so the
	// bank has an edge the eye can find and the horizon stays a line.
	colour += warm * 0.13 * away * storm_amount * bank * (1.0 - bank) * 4.0 * smoothstep(0.35, 0.90, mass);
	// Shoulder: clouds near the sun keep their shape. It tightens inside the last
	// few degrees around the sun itself, because that core is the one thing in
	// the frame bright enough to bloom a veil down over the coast - which the
	// brief forbids - and it is already reading as "the sun" at half the value.
	float knee = mix(0.26, 0.46, smoothstep(0.90, 0.9975, toward));
	colour = colour / (1.0 + colour * knee);
	float grey = dot(colour, vec3(0.2126, 0.7152, 0.0722));
	colour = max(mix(vec3(grey), colour, saturation), vec3(0.0));
	COLOR = colour;
}
