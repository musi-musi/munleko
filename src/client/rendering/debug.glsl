vf float light;

#ifdef STAGE_VERTEX
void main() {
    vec4 pos = vec4((v_position.xyz * u_radius) + u_position, 1);
    light = abs(dot(v_normal, u_light));
    gl_Position = u_proj * u_view * pos;
}
#endif

#ifdef STAGE_FRAGMENT
void main() {
    f_color = vec4(1);
    f_color.xyz = light * u_color;
    f_color.w = 1;
}
#endif