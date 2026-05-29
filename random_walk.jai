/*
Random-walk path tracing terminology used in this file:

- Li / li: incoming radiance along a ray. The li() function estimates the light
  that arrives at the camera by recursively following a path through the scene.
- Random walk: the recursive path construction in li_random_walk(). At each
  surface hit we randomly pick a new direction, trace another ray, and add that
  bounced light contribution to the current point.
- Radiance: light power per unit projected area per unit solid angle. Informally,
  it is "how much light is travelling through this point in this direction."
  This is the quantity carried by rays and returned by Li/Le. In this code it is
  stored as Sampled_Spectrum so the same math can be applied per sampled
  wavelength/RGB lane.
- Le / surface_emission: emitted radiance from a surface. Area lights contribute
  through this term when a ray hits an emissive material.
- BSDF: bidirectional scattering distribution function; the general function
  that describes how light arriving from wi scatters toward wo at a surface.
- BRDF: bidirectional reflectance distribution function; the reflective-only
  subset of a BSDF. The Lambertian material here is a BRDF with value
  albedo / pi.
- bsdf_f: evaluates the material scattering f(wo, wi). It answers "how much of
  the incoming light from wi is reflected toward wo?"
- wo: outgoing direction from the surface toward the previous path vertex, often
  the camera on the first bounce. Here it is -ray.direction.
- wi / wp: incoming or sampled direction for the next bounce. wp is sampled from
  the unit sphere in li_random_walk().
- cos term: abs(dot(wp, n)). Surface response is scaled by the projected angle
  between the sampled direction and the surface normal.
- PDF: probability density function. Because wp is randomly sampled, the
  contribution is divided by the sampling probability (UNIFORM_SPHERE_PDF) to
  keep the estimator unbiased.
- Throughput: the multiplicative path weight carried from bounce to bounce. This
  simple implementation builds it implicitly with fcos / PDF at each recursive
  return instead of storing a separate throughput variable.
- max_depth: recursion limit. When reached, the path stops and only emission at
  the current hit is returned.
*/

INV_PI :: cast(float) 1.0 / PI;
UNIFORM_SPHERE_PDF :: cast(float) 1.0 / (cast(float) 4.0 * PI);
MACHINE_EPSILON :: cast(float) 0.000000059604644775390625;
RAY_T_MIN :: cast(float) 0.0001;
SPHERE_PERROR_GAMMA_N :: cast(float) 6.1466969;

Point2 :: struct {
    x, y: float;
}

Point2i :: struct {
    x, y: int;
}

Ray :: struct {
    origin: Vector3;
    direction: Vector3;
    origin_error: Vector3;
}

Camera_Sample :: struct {
    p_film: Point2; // position on film we are looking at or something.
    filter_weight: float = 1.0;
}

Camera_Ray :: struct {
    ray: Ray;
    weight: Sampled_Spectrum = .{1, 1, 1, 1};
}

Pinhole_Camera :: struct {
    origin: Vector3;
    origin_error: Vector3;
    u, v, w: Vector3;
    focal_length: float = 1.0;
    film_width: float = 2.0;
    film_height: float = 2.0;
    frame_aspect: float = 1.0;
    tan_fov_over_2: float = 1.0;
    inv_tan_fov_over_2: float = 1.0;
}

Film :: struct {
    width, height: int;
    pixels: [] Sampled_Spectrum;
    rgb_sums: [] RGB_Sum;
    sample_weights: [] float;
}

RGB_Sum :: struct {
    r, g, b: float64;
}

Sampled_Spectrum :: struct {
    x0, x1, x2, x3: float;
}

Sampler :: struct {
    samples_per_pixel: int = 1;
    seed: int = 0;
    rng_state: u64 = 0x853c49e6748fea9b;
    rng_inc: u64 = 0xda3e39cb94b95bdb;
}

Material_Type :: enum {
    LAMBERTIAN;
    EMISSIVE;
}

Material :: struct {
    type: Material_Type = .LAMBERTIAN;
    albedo: Vector3 = .{0.8, 0.8, 0.8};
    sampled_albedo: Sampled_Spectrum = .{0.8, 0.8, 0.8, 0.8};
    emission: Vector3;
    sampled_emission: Sampled_Spectrum;
}

Sphere :: struct {
    center: Vector3;
    radius: float;
    material_index: int;
}

Surface_Interaction :: struct {
    p: Vector3; 
    p_error: Vector3;
    n: Vector3;
    material_index: int;
}

Shape_Intersection :: struct {
    t_hit: float;
    intr: Surface_Interaction; // todo rename to surface_interaction
}

Interval :: struct {
    low, high: float;
}

Scene :: struct {
    spheres: [..] Sphere;
    materials: [..] Material;
    infinite_light: Vector3 = .{0.02, 0.025, 0.04};
    sampled_infinite_light: Sampled_Spectrum = .{0.02, 0.025, 0.04, 0.04};
}

Random_Walk_Integrator :: struct {
    camera: Pinhole_Camera;
    sampler: Sampler;
    film: Film;
    scene: *Scene;
    max_depth: int = 5;
    disable_pixel_jitter := false;
}

v3 :: (x: float, y: float, z: float) -> Vector3 {
    return .{x, y, z};
}

hadamard :: (a: Vector3, b: Vector3) -> Vector3 {
    return .{a.x * b.x, a.y * b.y, a.z * b.z};
}

spectrum_zero :: () -> Sampled_Spectrum {
    return .{};
}

spectrum_add :: (a: Sampled_Spectrum, b: Sampled_Spectrum) -> Sampled_Spectrum {
    return .{a.x0 + b.x0, a.x1 + b.x1, a.x2 + b.x2, a.x3 + b.x3};
}

spectrum_mul :: (a: Sampled_Spectrum, b: Sampled_Spectrum) -> Sampled_Spectrum {
    return .{a.x0 * b.x0, a.x1 * b.x1, a.x2 * b.x2, a.x3 * b.x3};
}

spectrum_scale :: (a: Sampled_Spectrum, s: float) -> Sampled_Spectrum {
    return .{a.x0 * s, a.x1 * s, a.x2 * s, a.x3 * s};
}

spectrum_div :: (a: Sampled_Spectrum, s: float) -> Sampled_Spectrum {
    return .{a.x0 / s, a.x1 / s, a.x2 / s, a.x3 / s};
}

spectrum_is_zero :: (a: Sampled_Spectrum) -> bool {
    return a.x0 == 0.0 && a.x1 == 0.0 && a.x2 == 0.0 && a.x3 == 0.0;
}

spectrum_to_preview_rgb :: (s: Sampled_Spectrum) -> Vector3 {
    r := s.x0 * cast(float) -19.5195503 + s.x1 * cast(float) 198.160538 + s.x2 * cast(float) 0.00367876096 + s.x3 * cast(float) -22.2260914;
    g := s.x0 * cast(float)  94.4784241 + s.x1 * cast(float) -8.36080456 + s.x2 * cast(float) -0.00039975351 + s.x3 * cast(float) 13.9654284;
    b := s.x0 * cast(float) -10.6283808 + s.x1 * cast(float) -2.96292305 + s.x2 * cast(float) -0.0000247055796 + s.x3 * cast(float) 66.7974014;
    return .{r, g, b};
}

clamp01 :: (x: float) -> float {
    return max(0.0, min(1.0, x));
}

fma :: (a: float, b: float, c: float) -> float {
    return cast(float) (cast(float64) a * cast(float64) b + cast(float64) c);
}

evaluate_polynomial6 :: (t: float, c0: float, c1: float, c2: float, c3: float, c4: float, c5: float) -> float {
    return fma(t, fma(t, fma(t, fma(t, fma(t, c5, c4), c3), c2), c1), c0);
}

length64 :: (v: Vector3) -> float {
    x := cast(float64) v.x;
    y := cast(float64) v.y;
    z := cast(float64) v.z;
    return cast(float) sqrt(x*x + y*y + z*z);
}

length_pbrt :: (v: Vector3) -> float {
    sx := round_float(v.x * v.x);
    sy := round_float(v.y * v.y);
    sz := round_float(v.z * v.z);
    sxy := round_float(sx + sy);
    sum := round_float(sxy + sz);
    return sqrt(sum);
}

linear_to_srgb :: (value: float) -> float {
    if value <= 0.0031308 return 12.92 * value;

    sqrt_value := sqrt(value);
    p := evaluate_polynomial6(sqrt_value,
                                 cast(float) -0.0016829072605308378,
                                 cast(float)  0.03453868659826638,
                                 cast(float)  0.7642611304733891,
                                 cast(float)  2.0041169284241644,
                                 cast(float)  0.7551545191665577,
                                 cast(float) -0.016202083165206348);
    q := evaluate_polynomial6(sqrt_value,
                                 cast(float)  4.178892964897981e-7,
                                 cast(float) -0.00004375359692957097,
                                 cast(float)  0.03467195408529984,
                                 cast(float)  0.6085338522168684,
                                 cast(float)  1.8970238036421054,
                                 cast(float)  1.0);
    return p / q * value;
}

blue_noise :: (channel: int, x: int, y: int) -> float {
    texture_index := channel % 3;
    bx := x % BLUE_NOISE_RESOLUTION;
    by := y % BLUE_NOISE_RESOLUTION;
    index := texture_index * BLUE_NOISE_RESOLUTION * BLUE_NOISE_RESOLUTION +
             bx * BLUE_NOISE_RESOLUTION + by;
    return cast(float) BLUE_NOISE_RGB[index] / cast(float) 65535.0;
}

linear_to_srgb8 :: (value: float, dither: float = 0.0) -> int {
    if value <= 0.0 return 0;
    if value >= 1.0 return 255;

    return clamp(cast(int) floor(255.0 * linear_to_srgb(value) + dither + 0.5), 0, 255);
}

abs_v3 :: (v: Vector3) -> Vector3 {
    return .{abs(v.x), abs(v.y), abs(v.z)};
}

make_interval :: (value: float) -> Interval {
    return .{value, value};
}

interval_from_value_error :: (value: float, error: float) -> Interval {
    if error == 0.0 return .{value, value};
    return .{next_float_down(value - error), next_float_up(value + error)};
}

interval_midpoint :: (i: Interval) -> float {
    return (i.low + i.high) * cast(float) 0.5;
}

interval_add :: (a: Interval, b: Interval) -> Interval {
    return .{next_float_down(a.low + b.low), next_float_up(a.high + b.high)};
}

interval_sub :: (a: Interval, b: Interval) -> Interval {
    return .{next_float_down(a.low - b.high), next_float_up(a.high - b.low)};
}

interval_mul :: (a: Interval, b: Interval) -> Interval {
    p0 := a.low * b.low;
    p1 := a.high * b.low;
    p2 := a.low * b.high;
    p3 := a.high * b.high;
    lo := min(min(p0, p1), min(p2, p3));
    hi := max(max(p0, p1), max(p2, p3));
    return .{next_float_down(lo), next_float_up(hi)};
}

interval_scale :: (a: Interval, s: float) -> Interval {
    if s >= 0.0 return .{next_float_down(a.low * s), next_float_up(a.high * s)};
    return .{next_float_down(a.high * s), next_float_up(a.low * s)};
}

interval_div :: (a: Interval, b: Interval) -> Interval {
    if b.low <= 0.0 && b.high >= 0.0 return .{cast(float) -1000000000, cast(float) 1000000000};
    p0 := a.low / b.low;
    p1 := a.high / b.low;
    p2 := a.low / b.high;
    p3 := a.high / b.high;
    lo := min(min(p0, p1), min(p2, p3));
    hi := max(max(p0, p1), max(p2, p3));
    return .{next_float_down(lo), next_float_up(hi)};
}

interval_sqrt :: (a: Interval) -> Interval {
    return .{next_float_down(sqrt(max(cast(float) 0.0, a.low))),
             next_float_up(sqrt(max(cast(float) 0.0, a.high)))};
}

interval_sqr :: (a: Interval) -> Interval {
    return interval_mul(a, a);
}

gamma :: (n: int) -> float {
    nf := cast(float) n;
    return (nf * MACHINE_EPSILON) / (1.0 - nf * MACHINE_EPSILON);
}

gamma_fractional :: (n: float) -> float {
    return (n * MACHINE_EPSILON) / (1.0 - n * MACHINE_EPSILON);
}

float_bits :: (value: float) -> u32 {
    return (.*) cast(*u32) *value;
}

round_float :: (value: float) -> float {
    return bits_to_float(float_bits(value));
}

float_hex :: (value: float) -> string {
    return tprint("0x%", formatInt(float_bits(value), base=16));
}

bits_to_float :: (bits: u32) -> float {
    return (.*) cast(*float) *bits;
}

image_half_to_float :: (half: u16) -> float {
    sign := (cast(u32) half & 0x8000) << 16;
    exp := (cast(u32) half >> 10) & 0x1f;
    mant := cast(u32) half & 0x3ff;

    if exp == 0 {
        if mant == 0 return bits_to_float(sign);
        while (mant & 0x400) == 0 {
            mant <<= 1;
            exp -= 1;
        }
        exp += 1;
        mant &= 0x3ff;
    } else if exp == 31 {
        return bits_to_float(sign | 0x7f800000 | (mant << 13));
    }

    exp = exp + (127 - 15);
    return bits_to_float(sign | (exp << 23) | (mant << 13));
}

float_to_image_half :: (value: float) -> u16 {
    bits := float_bits(value);
    sign := (bits >> 16) & 0x8000;
    exp := cast(int) ((bits >> 23) & 0xff) - 127 + 15;
    mant := bits & 0x7fffff;

    if exp <= 0 {
        if exp < -10 return cast(u16) sign;
        mant |= 0x800000;
        shift := 14 - exp;
        rounded := (mant + (1 << (shift - 1))) >> shift;
        return cast(u16) (sign | rounded);
    }

    if exp >= 31 return cast(u16) (sign | 0x7c00);

    rounded_mant := mant + 0x1000;
    if (rounded_mant & 0x800000) != 0 {
        rounded_mant = 0;
        exp += 1;
        if exp >= 31 return cast(u16) (sign | 0x7c00);
    }

    return cast(u16) (sign | (cast(u32) exp << 10) | (rounded_mant >> 13));
}

to_image_half :: (value: float) -> float {
    if value > 65504.0 return 65504.0;
    return image_half_to_float(float_to_image_half(value));
}

next_float_up :: (v: float) -> float {
    value := v;
    if value == -0.0 value = 0.0;

    bits := float_bits(value);
    if value >= 0.0 {
        bits += 1;
    } else {
        bits -= 1;
    }

    return bits_to_float(bits);
}

next_float_down :: (v: float) -> float {
    value := v;
    if value == 0.0 value = -0.0;

    bits := float_bits(value);
    if value > 0.0 {
        bits -= 1;
    } else {
        bits += 1;
    }

    return bits_to_float(bits);
}

make_film :: (width: int, height: int) -> Film {
    film: Film;
    film.width = width;
    film.height = height;
    film.pixels = NewArray(width * height, Sampled_Spectrum);
    film.rgb_sums = NewArray(width * height, RGB_Sum);
    film.sample_weights = NewArray(width * height, float);
    return film;
}

add_sample :: (using film: *Film, p_pixel: Point2i, l: Sampled_Spectrum, filter_weight: float = 1.0) {
    index := p_pixel.x + p_pixel.y * width;
    pixels[index] = spectrum_add(pixels[index], spectrum_scale(l, filter_weight));
    rgb := spectrum_to_preview_rgb(l);
    rgb_sums[index].r += cast(float64) (filter_weight * rgb.x);
    rgb_sums[index].g += cast(float64) (filter_weight * rgb.y);
    rgb_sums[index].b += cast(float64) (filter_weight * rgb.z);
    sample_weights[index] += filter_weight;
}

write_ppm :: (using film: *Film, filename: string) -> bool {
    builder: String_Builder;
    append(*builder, "P3\n");
    print_to_builder(*builder, "% %\n255", width, height);

    for y: 0..height-1 {
        append(*builder, "\n");
        for x: 0..width-1 {
            index := x + y * width;
            weight := sample_weights[index];
            spectrum := ifx weight > 0.0 then spectrum_div(pixels[index], weight) else Sampled_Spectrum.{};
            rgb := ifx weight > 0.0 then Vector3.{
                cast(float) (rgb_sums[index].r / cast(float64) weight),
                cast(float) (rgb_sums[index].g / cast(float64) weight),
                cast(float) (rgb_sums[index].b / cast(float64) weight),
            } else Vector3.{};
            rgb.x = to_image_half(rgb.x);
            rgb.y = to_image_half(rgb.y);
            rgb.z = to_image_half(rgb.z);

            r := linear_to_srgb8(rgb.x, -0.5 + blue_noise(0, x, y));
            g := linear_to_srgb8(rgb.y, -0.5 + blue_noise(1, x, y));
            b := linear_to_srgb8(rgb.z, -0.5 + blue_noise(2, x, y));
            print_to_builder(*builder, "% % % ", r, g, b);
        }
    }

    return write_entire_file(filename, *builder);
}

make_sampler :: (samples_per_pixel: int, seed_low: u64 = 0, seed_high: u64 = 2) -> Sampler {
    sampler: Sampler;
    sampler.samples_per_pixel = max(1, samples_per_pixel);
    sampler.seed = cast(int) seed_low;
    return sampler;
}

murmur_hash64a_p2_seed :: (p: Point2i, seed: int) -> u64 {
    m :: cast(u64) 0xc6a4a7935bd1e995;
    r :: 47;

    h: u64 = cast(u64) 12 * m;

    px := cast(u64) (cast(u32) p.x);
    py := cast(u64) (cast(u32) p.y);
    k := px | (py << 32);
    k *= m;
    k ^= k >> r;
    k *= m;

    h ^= k;
    h *= m;

    tail := cast(u64)(cast(u32) seed);
    h ^= tail;
    h *= m;

    h ^= h >> r;
    h *= m;
    h ^= h >> r;

    return h;
}

mix_bits :: (v: u64) -> u64 {
    v ^= v >> 31;
    v *= cast(u64) 0x7fb5d329728ea185;
    v ^= v >> 27;
    v *= cast(u64) 0x81dadef4bc2dd44d;
    v ^= v >> 33;
    return v;
}

pcg_uniform_u32 :: (using sampler: *Sampler) -> u32 {
    oldstate := rng_state;
    rng_state = oldstate * cast(u64) 0x5851f42d4c957f2d + rng_inc;
    xorshifted := cast,no_check(u32) (((oldstate >> 18) ^ oldstate) >> 27);
    rot := cast(u32) (oldstate >> 59);
    return (xorshifted >> rot) | (xorshifted << ((~rot + 1) & 31));
}

pcg_set_sequence :: (using sampler: *Sampler, sequence_index: u64, offset: u64) {
    rng_state = 0;
    rng_inc = (sequence_index << 1) | 1;
    pcg_uniform_u32(sampler);
    rng_state += offset;
    pcg_uniform_u32(sampler);
}

pcg_advance :: (using sampler: *Sampler, delta: u64) {
    cur_mult := cast(u64) 0x5851f42d4c957f2d;
    cur_plus := rng_inc;
    acc_mult: u64 = 1;
    acc_plus: u64 = 0;

    while delta > 0 {
        if delta & 1 {
            acc_mult *= cur_mult;
            acc_plus = acc_plus * cur_mult + cur_plus;
        }
        cur_plus = (cur_mult + 1) * cur_plus;
        cur_mult *= cur_mult;
        delta /= 2;
    }

    rng_state = acc_mult * rng_state + acc_plus;
}

// what does start even mean here?
start_pixel_sample :: (using sampler: *Sampler, p_pixel: Point2i, sample_index: int) {
    sequence := murmur_hash64a_p2_seed(p_pixel, seed);
    pcg_set_sequence(sampler, sequence, mix_bits(sequence));
    pcg_advance(sampler, cast(u64) sample_index * 65536);
}

// bad function name?
get_1d :: (using sampler: *Sampler) -> float {
    ONE_MINUS_EPSILON :: cast(float) 0.99999994;
    UINT32_TO_FLOAT :: cast(float) 2.3283064e-10;
    return min(ONE_MINUS_EPSILON, cast(float) pcg_uniform_u32(sampler) * UINT32_TO_FLOAT);
}

get_2d :: (using sampler: *Sampler) -> Point2 {
    return .{get_1d(sampler), get_1d(sampler)};
}

get_camera_sample :: (sampler: *Sampler, p_pixel: Point2i) -> Camera_Sample {
    jitter := get_2d(sampler);
    return .{.{cast(float) p_pixel.x + jitter.x, cast(float) p_pixel.y + jitter.y}, 1.0};
}

get_center_camera_sample :: (p_pixel: Point2i) -> Camera_Sample {
    return .{.{cast(float) p_pixel.x + 0.5, cast(float) p_pixel.y + 0.5}, 1.0};
}

look_at_camera :: (origin: Vector3, look_at: Vector3, up: Vector3,
                     film_width: float, film_height: float, focal_length: float = 1.0,
                     frame_aspect: float = 1.0, tan_fov_over_2: float = 1.0,
                     inv_tan_fov_over_2: float = 1.0) -> Pinhole_Camera {
    camera: Pinhole_Camera;
    camera.origin = origin;
    camera.origin_error = .{0, gamma(3) * abs(origin.y), gamma(3) * abs(origin.z)};
    dir := normalize(look_at - origin);
    camera.u = normalize(cross(normalize(up), dir));
    camera.v = cross(dir, camera.u);
    camera.w = -dir;
    camera.film_width = film_width;
    camera.film_height = film_height;
    camera.focal_length = focal_length;
    camera.frame_aspect = frame_aspect;
    camera.tan_fov_over_2 = tan_fov_over_2;
    camera.inv_tan_fov_over_2 = inv_tan_fov_over_2;
    return camera;
}

look_at_perspective_camera :: (origin: Vector3, look_at: Vector3, up: Vector3,
                                 image_width: int, image_height: int,
                                 fov_degrees: float = 58.7) -> Pinhole_Camera {
    tan_fov_over_2 := tan((fov_degrees * PI / cast(float) 180.0) * cast(float) 0.5);
    inv_tan_fov_over_2 := cast(float) 1.0 / tan_fov_over_2;
    film_height := cast(float) 2.0 * tan_fov_over_2;
    frame_aspect := cast(float) image_width / cast(float) image_height;
    film_width := film_height * frame_aspect;
    return look_at_camera(origin, look_at, up, film_width, film_height, 1.0, frame_aspect, tan_fov_over_2, inv_tan_fov_over_2);
}

generate_ray :: (using camera: *Pinhole_Camera, sample: Camera_Sample, film: *Film) -> Camera_Ray {

    ndc_x := sample.p_film.x / cast(float) film.width;
    ndc_y := sample.p_film.y / -cast(float) film.height;

    screen_x := ndc_x * (cast(float) 2.0 * frame_aspect) - frame_aspect;
    screen_y := ndc_y * cast(float) 2.0 + cast(float) 1.0;

    z_near := cast(float) 0.01;
    x := (screen_x / inv_tan_fov_over_2) * z_near;
    y := (screen_y / inv_tan_fov_over_2) * z_near;

    camera_direction := normalize(Vector3.{x, y, z_near});

    direction := camera_direction.z * -w + camera_direction.x * u + camera_direction.y * v;

    ray_origin := origin;
    length_squared := dot(direction, direction);
    if length_squared > 0.0 {
        dt := dot(abs_v3(direction), origin_error) / length_squared;
        ray_origin += direction * dt;
    }

    return .{.{ray_origin, direction, origin_error}, .{1, 1, 1, 1}};
}


/*
Map two uniform random numbers in [0, 1) onto a direction on the unit sphere.

Think of u as a point on a unit square:
- u.x chooses z, the vertical height on the sphere, from +1 down to -1.
  Sampling z directly gives equal-area horizontal bands, which is what makes
  the result uniform over the sphere surface. Sampling the polar angle
  directly would crowd samples near the poles.
- u.y chooses phi, the angle around that horizontal band, from 0 to 2*pi.

Once z is chosen, the point must satisfy x*x + y*y + z*z = 1. The radius of
the horizontal circle at that z is therefore sqrt(1 - z*z). We then use the
usual polar-to-Cartesian conversion for x and y:

    x = r * cos(phi)
    y = r * sin(phi)

The corresponding probability density is 1 / (4*pi), since a unit sphere has
surface area 4*pi.
*/

sample_uniform_sphere :: (u: Point2) -> Vector3 {
    z := 1.0 - 2.0 * u.x;
    r := sqrt(max(0.0, 1.0 - z*z));
    phi := 2.0 * PI * u.y;
    return .{r * cos(phi), r * sin(phi), z};
}

spawn_ray :: (intr: *Surface_Interaction, direction: Vector3) -> Ray {
    d := dot(abs_v3(intr.n), intr.p_error);
    offset := intr.n * d;
    if dot(direction, intr.n) < 0.0 offset = -offset;

    origin := intr.p + offset;
    if offset.x > 0.0      origin.x = next_float_up(origin.x);
    else if offset.x < 0.0 origin.x = next_float_down(origin.x);
    if offset.y > 0.0      origin.y = next_float_up(origin.y);
    else if offset.y < 0.0 origin.y = next_float_down(origin.y);
    if offset.z > 0.0      origin.z = next_float_up(origin.z);
    else if offset.z < 0.0 origin.z = next_float_down(origin.z);

    origin_error := intr.p_error + abs_v3(offset);
    return .{origin, normalize(direction), origin_error};
}

intersect_sphere :: (sphere: *Sphere, ray: Ray, t_max: float) -> hit: bool, si: Shape_Intersection {
    oc := ray.origin - sphere.center;
    a := dot(ray.direction, ray.direction);
    half_b := dot(oc, ray.direction);
    c := dot(oc, oc) - sphere.radius * sphere.radius;
    discriminant := half_b * half_b - a * c;
    if discriminant < 0.0 return false, .{};

    object_origin_error := gamma(3) * (abs_v3(ray.origin) + abs_v3(sphere.center));
    closest_object_point := oc - (half_b / a) * ray.direction;
    closest_distance := length(closest_object_point);
    if closest_distance > 0.0 {
        closest_distance_error := dot(abs_v3(closest_object_point), object_origin_error) / closest_distance;
        closest_distance_upper := closest_distance + closest_distance_error + gamma(3) * closest_distance;
        if sphere.radius - closest_distance_upper < 0.0 return false, .{};
    }

    oi_x := interval_from_value_error(oc.x, object_origin_error.x);
    oi_y := interval_from_value_error(oc.y, object_origin_error.y);
    oi_z := interval_from_value_error(oc.z, object_origin_error.z);
    di_x := make_interval(ray.direction.x);
    di_y := make_interval(ray.direction.y);
    di_z := make_interval(ray.direction.z);

    ia := interval_add(interval_add(interval_sqr(di_x), interval_sqr(di_y)), interval_sqr(di_z));
    ib := interval_scale(interval_add(interval_add(interval_mul(di_x, oi_x), interval_mul(di_y, oi_y)), interval_mul(di_z, oi_z)), cast(float) 2.0);
    ic := interval_sub(interval_add(interval_add(interval_sqr(oi_x), interval_sqr(oi_y)), interval_sqr(oi_z)), make_interval(sphere.radius * sphere.radius));

    iv_x := interval_sub(oi_x, interval_mul(interval_div(ib, interval_scale(ia, cast(float) 2.0)), di_x));
    iv_y := interval_sub(oi_y, interval_mul(interval_div(ib, interval_scale(ia, cast(float) 2.0)), di_y));
    iv_z := interval_sub(oi_z, interval_mul(interval_div(ib, interval_scale(ia, cast(float) 2.0)), di_z));
    ilength := interval_sqrt(interval_add(interval_add(interval_sqr(iv_x), interval_sqr(iv_y)), interval_sqr(iv_z)));
    idiscriminant := interval_scale(interval_mul(interval_mul(ia,
                                      interval_add(make_interval(sphere.radius), ilength)),
                                      interval_sub(make_interval(sphere.radius), ilength)), cast(float) 4.0);
    if idiscriminant.low < 0.0 return false, .{};

    root_discriminant := interval_sqrt(idiscriminant);
    q: Interval;
    if interval_midpoint(ib) < 0.0 {
        q = interval_scale(interval_sub(ib, root_discriminant), cast(float) -0.5);
    } else {
        q = interval_scale(interval_add(ib, root_discriminant), cast(float) -0.5);
    }
    t0i := interval_div(q, ia);
    t1i := interval_div(ic, q);
    if t0i.low > t1i.low {
        temp := t0i;
        t0i = t1i;
        t1i = temp;
    }

    if t0i.high > t_max || t1i.low <= RAY_T_MIN return false, .{};
    root_i := t0i;
    if root_i.low <= RAY_T_MIN {
        root_i = t1i;
        if root_i.high > t_max return false, .{};
    }
    root := interval_midpoint(root_i);

    oi_mid := Vector3.{interval_midpoint(oi_x), interval_midpoint(oi_y), interval_midpoint(oi_z)};
    local_p := Vector3.{
        oi_mid.x + root * ray.direction.x,
        oi_mid.y + root * ray.direction.y,
        oi_mid.z + root * ray.direction.z,
    };
    local_length := length_pbrt(local_p);
    local_length_bits := float_bits(local_length);
    local_length = bits_to_float(local_length_bits);
    local_scale := sphere.radius / local_length;
    local_p *= local_scale;
    p := sphere.center + local_p;
    p_error := gamma_fractional(SPHERE_PERROR_GAMMA_N) * abs_v3(local_p) + gamma(3) * (abs_v3(local_p) + abs_v3(sphere.center));
    return true, .{
        root,
        .{
            p,
            p_error,
            normalize(local_p),
            sphere.material_index,
        },
    };
}

intersect :: (scene: *Scene, ray: Ray, t_max: float = cast(float) 1000000000) -> hit: bool, si: Shape_Intersection {
    closest := t_max;
    closest_si: Shape_Intersection;
    found := false;

    for *sphere: scene.spheres {
        h, candidate := intersect_sphere(sphere, ray, closest);
        if h {
            found = true;
            closest = candidate.t_hit;
            closest_si = candidate;
        }
    }

    return found, closest_si;
}

surface_emission :: (scene: *Scene, intr: *Surface_Interaction, wo: Vector3) -> Sampled_Spectrum {
    material := scene.materials[intr.material_index];
    if material.type == .EMISSIVE return material.sampled_emission;
    return .{};
}

bsdf_f :: (scene: *Scene, intr: *Surface_Interaction, wo: Vector3, wi: Vector3) -> Sampled_Spectrum {
    if dot(wi, intr.n) <= 0.0 return .{};

    material := scene.materials[intr.material_index];
    if material.type == .LAMBERTIAN return spectrum_scale(material.sampled_albedo, INV_PI);
    if material.type == .EMISSIVE return spectrum_scale(material.sampled_albedo, INV_PI);

    return .{};
}

li_random_walk :: (using integrator: *Random_Walk_Integrator, ray: Ray, depth: int) -> Sampled_Spectrum {
    hit, shape_intsection := intersect(scene, ray); // si
    if !hit return scene.sampled_infinite_light;

    curr_to_prev_hit := -ray.direction; // wo
    emitted_radiance_towards_prev_hit := surface_emission(scene, *shape_intsection.intr, curr_to_prev_hit); // Le
    if depth == max_depth return emitted_radiance_towards_prev_hit;

    // random direction on unit sphere
    next_ray_direction := sample_uniform_sphere(get_2d(*sampler)); // wp
    fcos := spectrum_scale(
        bsdf_f(scene, *shape_intsection.intr, curr_to_prev_hit, next_ray_direction),
        abs(dot(next_ray_direction, shape_intsection.intr.n))
    );

    if spectrum_is_zero(fcos) return emitted_radiance_towards_prev_hit;

    next_ray := spawn_ray(*shape_intsection.intr, next_ray_direction);
    incoming := li_random_walk(integrator, next_ray, depth + 1);
    return spectrum_add(
        emitted_radiance_towards_prev_hit,
        spectrum_div(spectrum_mul(fcos, incoming), UNIFORM_SPHERE_PDF)
    );
}

li :: (using integrator: *Random_Walk_Integrator, ray: Ray) -> Sampled_Spectrum {
    return li_random_walk(integrator, ray, 0);
}

evaluate_pixel_sample :: (using integrator: *Random_Walk_Integrator, p_pixel: Point2i, sample_index: int) {
    start_pixel_sample(*sampler, p_pixel, sample_index);

    get_1d(*sampler); // wavelength sample
    camera_sample := ifx disable_pixel_jitter then get_center_camera_sample(p_pixel) else get_camera_sample(*sampler, p_pixel);
    if disable_pixel_jitter {
        get_2d(*sampler); // filter sample consumed before PBRT overrides pFilm
        get_1d(*sampler); // time
        get_2d(*sampler); // lens
    }
    camera_ray := generate_ray(*camera, camera_sample, *film);
    l := spectrum_mul(camera_ray.weight, li(integrator, camera_ray.ray));

    add_sample(*film, p_pixel, l, camera_sample.filter_weight);
}

render :: (using integrator: *Random_Walk_Integrator) {
    for sample_index: 0..sampler.samples_per_pixel-1 {
        for y: 0..film.height-1 {
            for x: 0..film.width-1 {
                evaluate_pixel_sample(integrator, .{x, y}, sample_index);
            }
        }
    }
}

make_random_walk_integrator :: (scene: *Scene, camera: Pinhole_Camera,
                                  width: int, height: int, samples_per_pixel: int = 1,
                                  max_depth: int = 5,
                                  disable_pixel_jitter := false) -> Random_Walk_Integrator {
    integrator: Random_Walk_Integrator;
    integrator.scene = scene;
    integrator.camera = camera;
    integrator.film = make_film(width, height);
    integrator.sampler = make_sampler(samples_per_pixel);
    integrator.max_depth = max_depth;
    integrator.disable_pixel_jitter = disable_pixel_jitter;
    return integrator;
}
