shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;
uniform sampler2D sheet : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D ink : filter_linear_mipmap, repeat_disable;
uniform bool register_sheet = false;
uniform bool forecast = false;
uniform vec4 clock_digits = vec4(0.0);
uniform float student_row = 0.0;
uniform float written : hint_range(0.0,1.0) = 0.0;
uniform float erased : hint_range(0.0,1.0) = 0.0;

float glyph(vec2 cell, float index) {
	return texture(ink, (vec2(index,0.0)+clamp(cell,0.003,0.997))/vec2(14.0,5.0)).r;
}

void fragment() {
	vec3 page = texture(sheet, UV).rgb;
	if (register_sheet) {
		vec2 name_uv = (UV-vec2(.222,.569))/vec2(.34,.074);
		if (all(greaterThanEqual(name_uv,vec2(0.0))) && all(lessThan(name_uv,vec2(1.0)))) {
			float name = texture(ink, vec2(name_uv.x/7.0,(1.0+student_row+name_uv.y)/5.0)).r;
			page = mix(page, vec3(.041,.051,.044), name);
		}
		float x = (UV.x-.185)/.54;
		float stroke = 1.0-smoothstep(.002,.006,abs(UV.y-(.622-.028*x+.003*sin(x*18.0))));
		if (x>=0.0 && x<=written) page = mix(page,vec3(.23,.027,.021),stroke);
	} else {
		vec2 line = (UV-vec2(.12,.37))/vec2(.095,.33);
		float cell = floor(line.x);
		float index = 11.0 + cell;
		if (cell==3.0) index = clock_digits.x;
		if (cell==4.0) index = clock_digits.y;
		if (cell==5.0) index = 10.0;
		if (cell==6.0) index = clock_digits.z;
		if (cell==7.0) index = clock_digits.w;
		float count = forecast ? 8.0 : 3.0;
		if (line.y>=0.0 && line.y<1.0 && cell>=0.0 && cell<count) {
			float reveal = 1.0-smoothstep(written*count-.08,written*count+.08,line.x);
			page = mix(page,vec3(.72,.76,.66),glyph(vec2(fract(line.x),line.y),index)*reveal*(1.0-erased));
		}
	}
	ALBEDO = page;
}
