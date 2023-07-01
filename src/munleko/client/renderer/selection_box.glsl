#ifdef STAGE_VERTEX
void main() {
    vec3 padding = (v_position * 2 - 1) * u_padding;
    vec3 world_position = (u_position + v_position * u_size) + padding;
    gl_Position = u_proj * u_view * vec4(world_position, 1);
}
#endif

#ifdef STAGE_FRAGMENT
void main() {
    f_color = vec4(u_color, 1);
}
#endif