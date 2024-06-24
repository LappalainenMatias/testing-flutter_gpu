#version 460 core

uniform VertexInfo {
  mat4 mvp;
  vec4 color;
} vertex_info;

in vec2 position;
out vec4 v_color;

void main() {
  v_color = vertex_info.color;
  gl_Position = vertex_info.mvp * vec4(position, 0.0, 1.0);
}