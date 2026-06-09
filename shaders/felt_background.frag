#version 460 core
#include <flutter/runtime_effect.glsl>

// Premium casino felt backdrop. This shader is generative (no input texture):
// it starts from uFeltColor and layers a slowly-breathing centre spotlight,
// faint fabric grain, and a slow-drifting darkening vignette. Kept low-contrast
// — it is a backdrop, not the star. Uniform order is consumed by
// _FeltShaderLayer (felt_table_background.dart):
//   setFloat 0..1 -> uSize, 2 -> uTime, 3 -> uIntensity, 4..6 -> uFeltColor.
uniform vec2 uSize;
uniform float uTime;
uniform float uIntensity;
uniform vec3 uFeltColor;

out vec4 fragColor;

// Cheap 2D hash — no texture lookups, no loops.
float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

// Bilinearly-smoothed value noise for soft fabric grain.
float valueNoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 uv = fragCoord / uSize;

  // Aspect-corrected, centre-origin coords so the spotlight stays circular.
  float aspect = uSize.x / max(uSize.y, 1.0);
  vec2 centred = (uv - 0.5) * vec2(aspect, 1.0);
  float dist = length(centred);

  vec3 color = uFeltColor;

  // 1. Soft radial spotlight over the table centre / discard area, slowly
  //    breathing over time. Brightens in the felt's own hue so it stays subtle.
  float breath = 0.5 + 0.5 * sin(uTime * 0.6);
  float spotRadius = mix(0.42, 0.52, breath);
  float spot = smoothstep(spotRadius, 0.0, dist);
  color += uFeltColor * spot * (0.16 + 0.06 * breath) * uIntensity;

  // 2. Faint fabric grain (time-independent) so the felt never looks flat.
  float grain = valueNoise(uv * uSize.y * 0.18) - 0.5;
  color += grain * 0.025 * uIntensity;

  // 3. Very slow-drifting darkening vignette toward the edges.
  float drift = 0.5 + 0.5 * sin(uTime * 0.08);
  float vignette = smoothstep(0.46, 0.96, dist);
  color -= color * vignette * (0.26 + 0.06 * drift) * uIntensity;

  fragColor = vec4(color, 1.0);
}
