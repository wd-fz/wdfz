shader_type canvas_item;
render_mode unshaded;
// No mip pyramid is needed for ordinary grading, distortion or colour changes.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
#include "scene_post_body.gdshaderinc"
