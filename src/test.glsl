vf vec3 color;

#ifdef STAGE_VERTEX
void main() {
    gl_Position = vec4(v_position.xy, 0, 1);
    color = v_color;
}
#endif

#ifdef STAGE_FRAGMENT
void main() {
    f_color = vec4(color, 1);
}
#endif