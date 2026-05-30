Simple_Vol_Path_Integrator :: struct {
    camera: Pinhole_Camera;
    sampler: Sampler;
    film: Film;
    scene: *Scene;
    max_depth: int = 5;
    disable_pixel_jitter := false;
}

sample_henyey_greenstein :: (wo: Vector3, g: float, u: Point2) -> Vector3, float {
    g = min(cast(float) 0.99, max(cast(float) -0.99, g));
    cos_theta: float;
    if abs(g) < 0.001 {
        cos_theta = cast(float) 1.0 - cast(float) 2.0 * u.x;
    } else {
        sqr_term := (cast(float) 1.0 - g * g) / (cast(float) 1.0 + g - cast(float) 2.0 * g * u.x);
        cos_theta = -((cast(float) 1.0 + g * g - sqr_term * sqr_term) / (cast(float) 2.0 * g));
    }

    sin_theta := sqrt(max(cast(float) 0.0, cast(float) 1.0 - cos_theta * cos_theta));
    phi := cast(float) 2.0 * PI * u.y;

    w := normalize(wo);
    v1, v2 := coordinate_system_pbrt(w);
    wi := sin_theta * cos(phi) * v1 + sin_theta * sin(phi) * v2 + cos_theta * w;
    return normalize(wi), henyey_greenstein_pdf(dot(wo, normalize(wi)), g);
}

coordinate_system_pbrt :: (v1: Vector3) -> Vector3, Vector3 {
    sign := ifx v1.z < 0.0 then cast(float) -1.0 else cast(float) 1.0;
    a := cast(float) -1.0 / (sign + v1.z);
    b := v1.x * v1.y * a;
    v2 := Vector3.{cast(float) 1.0 + sign * v1.x * v1.x * a, sign * b, -sign * v1.x};
    v3 := Vector3.{b, sign + v1.y * v1.y * a, -v1.y};
    return v2, v3;
}

henyey_greenstein_pdf :: (cos_theta: float, g: float) -> float {
    g = min(cast(float) 0.99, max(cast(float) -0.99, g));
    denom := cast(float) 1.0 + g * g + cast(float) 2.0 * g * cos_theta;
    return (cast(float) 1.0 / (cast(float) 4.0 * PI)) * ((cast(float) 1.0 - g * g) / (denom * sqrt(denom)));
}

medium_properties_at :: (scene: *Scene, medium_index: int, p: Vector3) -> Medium_Properties {
    medium := scene.media[medium_index];
    if medium.type == .DENSE_NANOVDB {
        p_medium := explosion_render_to_medium_point(p);
        density, temperature := sample_dense_volume(*medium.volume, p_medium);
        temp := (temperature - medium.temperature_offset) * medium.temperature_scale;
        Le := Sampled_Spectrum.{};
        if temp > 100.0 {
            Le = spectrum_scale(blackbody_sampled_primary(temp), medium.Le_scale);
        }
        return .{spectrum_scale(medium.sigma_a, density), spectrum_scale(medium.sigma_s, density), Le, medium.g};
    }
    return .{medium.sigma_a, medium.sigma_s, medium.Le, medium.g};
}

sample_dense_volume :: (volume: *Dense_Volume, p_render: Vector3) -> density: float, temperature: float {
    pd := dense_volume_index_position(volume, p_render, true);
    fx := pd.x - cast(float) volume.min_x;
    fy := pd.y - cast(float) volume.min_y;
    fz := pd.z - cast(float) volume.min_z;
    d := trilinear_dense_channel(volume.density, volume, fx, fy, fz);

    pt := dense_volume_index_position(volume, p_render, false);
    fx = pt.x - cast(float) volume.min_x;
    fy = pt.y - cast(float) volume.min_y;
    fz = pt.z - cast(float) volume.min_z;
    t := trilinear_dense_channel(volume.temperature, volume, fx, fy, fz);
    return d, t;
}

trilinear_dense_channel :: (values: [] float, volume: *Dense_Volume, fx: float, fy: float, fz: float) -> float {
    if fx < 0.0 || fy < 0.0 || fz < 0.0 return 0.0;
    if fx >= cast(float) (volume.nx - 1) || fy >= cast(float) (volume.ny - 1) || fz >= cast(float) (volume.nz - 1) return 0.0;

    x0 := cast(int) floor(fx);
    y0 := cast(int) floor(fy);
    z0 := cast(int) floor(fz);
    tx := fx - cast(float) x0;
    ty := fy - cast(float) y0;
    tz := fz - cast(float) z0;

    return trilinear_volume_value(values, volume.nx, volume.ny, x0, y0, z0, tx, ty, tz);
}

trilinear_volume_value :: (values: [] float, nx: int, ny: int, x: int, y: int, z: int,
                             tx: float, ty: float, tz: float) -> float {
    i000 := x + nx * (y + ny * z);
    i100 := i000 + 1;
    i010 := i000 + nx;
    i110 := i010 + 1;
    i001 := i000 + nx * ny;
    i101 := i001 + 1;
    i011 := i001 + nx;
    i111 := i011 + 1;

    c00 := values[i000] * (1.0 - tx) + values[i100] * tx;
    c10 := values[i010] * (1.0 - tx) + values[i110] * tx;
    c01 := values[i001] * (1.0 - tx) + values[i101] * tx;
    c11 := values[i011] * (1.0 - tx) + values[i111] * tx;
    c0 := c00 * (1.0 - ty) + c10 * ty;
    c1 := c01 * (1.0 - ty) + c11 * ty;
    return c0 * (1.0 - tz) + c1 * tz;
}

blackbody_sampled_primary :: (temperature: float) -> Sampled_Spectrum {
    lambda_primary_nm :: cast(float) 540.716;
    intensity := blackbody_normalized(lambda_primary_nm, temperature);
    return .{intensity, 0.0, 0.0, 0.0};
}

blackbody_normalized :: (lambda_nm: float, temperature: float) -> float {
    if temperature <= 0.0 return 0.0;
    lambda_max_nm := cast(float) 2.8977721e6 / temperature;
    peak := blackbody_radiance(lambda_max_nm, temperature);
    if peak <= 0.0 return 0.0;
    return blackbody_radiance(lambda_nm, temperature) / peak;
}

blackbody_radiance :: (lambda_nm: float, temperature: float) -> float {
    c :: cast(float64) 299792458.0;
    h :: cast(float64) 6.62606957e-34;
    kb :: cast(float64) 1.3806488e-23;
    l := cast(float64) lambda_nm * cast(float64) 0.000000001;
    T := cast(float64) temperature;
    denom := pow(l, 5.0) * (exp((h * c) / (l * kb * T)) - 1.0);
    if denom <= 0.0 return 0.0;
    return cast(float) ((2.0 * h * c * c) / denom);
}

dense_volume_index_position :: (volume: *Dense_Volume, p_render: Vector3, density_grid: bool = true) -> Vector3 {
    wmin := ifx density_grid then volume.density_world_min else volume.temperature_world_min;
    wmax := ifx density_grid then volume.density_world_max else volume.temperature_world_max;
    min_x := ifx density_grid then volume.density_min_x else volume.temperature_min_x;
    min_y := ifx density_grid then volume.density_min_y else volume.temperature_min_y;
    min_z := ifx density_grid then volume.density_min_z else volume.temperature_min_z;
    max_x := ifx density_grid then volume.density_max_x else volume.temperature_max_x;
    max_y := ifx density_grid then volume.density_max_y else volume.temperature_max_y;
    max_z := ifx density_grid then volume.density_max_z else volume.temperature_max_z;
    return .{
        ((p_render.x - wmin.x) / (wmax.x - wmin.x)) * cast(float) (max_x - min_x + 1) + cast(float) min_x,
        ((p_render.y - wmin.y) / (wmax.y - wmin.y)) * cast(float) (max_y - min_y + 1) + cast(float) min_y,
        ((p_render.z - wmin.z) / (wmax.z - wmin.z)) * cast(float) (max_z - min_z + 1) + cast(float) min_z,
    };
}

dense_volume_majorant_at :: (volume: *Dense_Volume, p_render: Vector3) -> float {
    p := dense_volume_index_position(volume, p_render);
    if p.x < cast(float) volume.min_x || p.y < cast(float) volume.min_y || p.z < cast(float) volume.min_z return 0.0;
    if p.x > cast(float) volume.max_x || p.y > cast(float) volume.max_y || p.z > cast(float) volume.max_z return 0.0;

    fx := (p.x - cast(float) volume.min_x) / cast(float) max(1, volume.nx - 1);
    fy := (p.y - cast(float) volume.min_y) / cast(float) max(1, volume.ny - 1);
    fz := (p.z - cast(float) volume.min_z) / cast(float) max(1, volume.nz - 1);
    mx := min(volume.majorant_res - 1, max(0, cast(int) floor(fx * cast(float) volume.majorant_res)));
    my := min(volume.majorant_res - 1, max(0, cast(int) floor(fy * cast(float) volume.majorant_res)));
    mz := min(volume.majorant_res - 1, max(0, cast(int) floor(fz * cast(float) volume.majorant_res)));
    return volume.majorants[mx + volume.majorant_res * (my + volume.majorant_res * mz)];
}

Majorant_Segment :: struct {
    t_min, t_max: float;
    majorant: float;
}

DDA_Majorant_Iterator :: struct {
    valid: bool;
    volume: *Dense_Volume;
    t_min, t_max: float;
    next_crossing_t: [3] float;
    delta_t: [3] float;
    step: [3] int;
    voxel_limit: [3] int;
    voxel: [3] int;
}

explosion_render_to_medium_point :: (p: Vector3) -> Vector3 {
    // PBRT transform stack for the explosion medium is:
    //   Scale 1 1 1.6
    //   Rotate 90 1 0 0
    // The accumulated renderFromMedium transform maps NanoVDB medium/world
    // space into the render-space sphere boundary; this is the inverse used by
    // PBRT before sampling the dense grid.
    return .{p.x, p.z / cast(float) 1.6, -p.y};
}

explosion_render_to_medium_direction :: (d: Vector3) -> Vector3 {
    return .{d.x, d.z / cast(float) 1.6, -d.y};
}

explosion_render_to_medium_point_error :: (p: Vector3) -> Vector3 {
    p_medium := explosion_render_to_medium_point(p);
    return gamma(3) * abs_v3(p_medium);
}

dense_volume_bounds_min :: (volume: *Dense_Volume) -> Vector3 {
    return volume.world_min;
}

dense_volume_bounds_max :: (volume: *Dense_Volume) -> Vector3 {
    return volume.world_max;
}

vector_axis :: (v: Vector3, axis: int) -> float {
    if axis == 0 return v.x;
    if axis == 1 return v.y;
    return v.z;
}

intersect_dense_volume_bounds :: (volume: *Dense_Volume, ray: Ray, ray_t_max: float) -> t_min: float, t_max: float, hit: bool {
    bmin := dense_volume_bounds_min(volume);
    bmax := dense_volume_bounds_max(volume);
    t0 := cast(float) 0.0;
    t1 := ray_t_max;

    for axis: 0..2 {
        o := vector_axis(ray.origin, axis);
        d := vector_axis(ray.direction, axis);
        min_a := vector_axis(bmin, axis);
        max_a := vector_axis(bmax, axis);

        if abs(d) < cast(float) 0.00000001 {
            if o < min_a || o > max_a return 0.0, 0.0, false;
            continue;
        }

        inv_d := cast(float) 1.0 / d;
        t_near := (min_a - o) * inv_d;
        t_far := (max_a - o) * inv_d;
        if t_near > t_far {
            tmp := t_near;
            t_near = t_far;
            t_far = tmp;
        }

        t0 = max(t0, t_near);
        t1 = min(t1, t_far);
        if t0 > t1 return 0.0, 0.0, false;
    }

    return t0, t1, true;
}

make_dda_majorant_iterator :: (volume: *Dense_Volume, ray: Ray, ray_t_max: float) -> DDA_Majorant_Iterator {
    medium_ray := ray;
    medium_ray.origin = explosion_render_to_medium_point(ray.origin);
    medium_ray.direction = explosion_render_to_medium_direction(ray.direction);
    origin_error := explosion_render_to_medium_point_error(ray.origin);
    length_squared := dot(medium_ray.direction, medium_ray.direction);
    if length_squared > 0.0 {
        dt := dot(abs_v3(medium_ray.direction), origin_error) / length_squared;
        medium_ray.origin += medium_ray.direction * dt;
        ray_t_max -= dt;
    }

    t_min, t_max, hit := intersect_dense_volume_bounds(volume, medium_ray, ray_t_max);
    if !hit return .{};

    it: DDA_Majorant_Iterator;
    it.valid = true;
    it.volume = volume;
    it.t_min = t_min;
    it.t_max = t_max;

    bounds_min := dense_volume_bounds_min(volume);
    bounds_max := dense_volume_bounds_max(volume);
    diag := bounds_max - bounds_min;
    grid_intersect := medium_ray.origin + medium_ray.direction * t_min;
    res := volume.majorant_res;

    for axis: 0..2 {
        offset := (vector_axis(grid_intersect, axis) - vector_axis(bounds_min, axis)) / vector_axis(diag, axis);
        v := cast(int) clamp(cast(int) floor(offset * cast(float) res), 0, res - 1);
        it.voxel[axis] = v;

        ray_grid_d := vector_axis(medium_ray.direction, axis) / vector_axis(diag, axis);
        if ray_grid_d == 0.0 {
            it.delta_t[axis] = cast(float) 1.0e30;
            it.next_crossing_t[axis] = cast(float) 1.0e30;
            it.step[axis] = 1;
            it.voxel_limit[axis] = res;
        } else {
            it.delta_t[axis] = cast(float) 1.0 / (abs(ray_grid_d) * cast(float) res);
            if ray_grid_d > 0.0 {
                next_voxel_pos := cast(float) (v + 1) / cast(float) res;
                it.next_crossing_t[axis] = t_min + (next_voxel_pos - offset) / ray_grid_d;
                it.step[axis] = 1;
                it.voxel_limit[axis] = res;
            } else {
                next_voxel_pos := cast(float) v / cast(float) res;
                it.next_crossing_t[axis] = t_min + (next_voxel_pos - offset) / ray_grid_d;
                it.step[axis] = -1;
                it.voxel_limit[axis] = -1;
            }
        }
    }

    return it;
}

dda_next_majorant_segment :: (it: *DDA_Majorant_Iterator) -> segment: Majorant_Segment, ok: bool {
    if !it.valid || it.t_min >= it.t_max return .{}, false;

    bits := 0;
    if it.next_crossing_t[0] < it.next_crossing_t[1] bits += 4;
    if it.next_crossing_t[0] < it.next_crossing_t[2] bits += 2;
    if it.next_crossing_t[1] < it.next_crossing_t[2] bits += 1;
    cmp_to_axis: [8] int = .[2, 1, 2, 1, 2, 2, 0, 0];
    step_axis := cmp_to_axis[bits];

    t_voxel_exit := min(it.t_max, it.next_crossing_t[step_axis]);
    majorant := it.volume.majorants[it.voxel[0] + it.volume.majorant_res * (it.voxel[1] + it.volume.majorant_res * it.voxel[2])];
    seg := Majorant_Segment.{it.t_min, t_voxel_exit, majorant};

    it.t_min = t_voxel_exit;
    if it.next_crossing_t[step_axis] > it.t_max it.t_min = it.t_max;
    it.voxel[step_axis] += it.step[step_axis];
    if it.voxel[step_axis] == it.voxel_limit[step_axis] it.t_min = it.t_max;
    it.next_crossing_t[step_axis] += it.delta_t[step_axis];

    return seg, true;
}

sample_homogeneous_medium :: (scene: *Scene, rng: *Sampler, ray: Ray, t_max: float,
                                medium_index: int, beta: *float, L: *Sampled_Spectrum,
                                depth: *int, max_depth: int, initial_u: float, initial_mode_u: float) -> scattered: bool, terminated: bool, scattered_ray: Ray {
    medium := scene.media[medium_index];
    sigma_maj := spectrum_add(medium.sigma_a, medium.sigma_s);
    sigma_maj_0 := max(cast(float) 0.0, spectrum_first_component(sigma_maj));
    if sigma_maj_0 <= 0.0 && medium.type != .DENSE_NANOVDB return false, false, ray;

    u := initial_u;
    mode_u := initial_mode_u;

    if medium.type == .DENSE_NANOVDB {
        iter := make_dda_majorant_iterator(*medium.volume, ray, t_max);
        while true {
            seg, ok := dda_next_majorant_segment(*iter);
            if !ok return false, false, ray;
            if seg.majorant <= 0.0 continue;

            sigma_maj = spectrum_scale(spectrum_add(medium.sigma_a, medium.sigma_s), seg.majorant);
            sigma_maj_0 = max(cast(float) 0.0, spectrum_first_component(sigma_maj));
            if sigma_maj_0 <= 0.0 continue;

            t_min := seg.t_min;
            while true {
                u = max(cast(float) 0.0000001, u);
                t := t_min + -log(cast(float) 1.0 - u) / sigma_maj_0;
                u = get_1d(rng);
                if t >= seg.t_max break;

                p := ray.origin + ray.direction * t;
                mp := medium_properties_at(scene, medium_index, p);
                p_absorb := max(cast(float) 0.0, mp.sigma_a.x0 / sigma_maj_0);
                p_scatter := max(cast(float) 0.0, mp.sigma_s.x0 / sigma_maj_0);

                if mode_u < p_absorb {
                    L.* = spectrum_add(L.*, spectrum_scale(terminate_secondary_wavelengths(mp.Le), beta.*));
                    return false, true, ray;
                }

                if mode_u < p_absorb + p_scatter {
                    if depth.* >= max_depth return false, true, ray;
                    depth.* += 1;

                    wi, pdf := sample_henyey_greenstein(-ray.direction, mp.g, .{get_1d(rng), get_1d(rng)});
                    if pdf <= 0.0 return false, true, ray;

                    return true, false, .{p, wi, .{}, medium_index};
                }

                mode_u = get_1d(rng);
                t_min = t;
            }
        }
    }

    current_ray := ray;
    remaining_t := t_max;
    while true {
        u = max(cast(float) 0.0000001, u);
        t := -log(cast(float) 1.0 - u) / sigma_maj_0;
        u = get_1d(rng);
        if t >= remaining_t return false, false, ray;

        p := current_ray.origin + current_ray.direction * t;
        mp := medium_properties_at(scene, medium_index, p);
        p_absorb := max(cast(float) 0.0, mp.sigma_a.x0 / sigma_maj_0);
        p_scatter := max(cast(float) 0.0, mp.sigma_s.x0 / sigma_maj_0);

        if mode_u < p_absorb {
            L.* = spectrum_add(L.*, spectrum_scale(terminate_secondary_wavelengths(mp.Le), beta.*));
            return false, true, ray;
        }

        if mode_u < p_absorb + p_scatter {
            if depth.* >= max_depth return false, true, ray;
            depth.* += 1;

            wi, pdf := sample_henyey_greenstein(-current_ray.direction, mp.g, .{get_1d(rng), get_1d(rng)});
            if pdf <= 0.0 return false, true, ray;

            return true, false, .{p, wi, .{}, medium_index};
        }

        mode_u = get_1d(rng);
        current_ray.origin = p;
        remaining_t -= t;
    }

    return false, true, ray;
}

terminate_secondary_wavelengths :: (s: Sampled_Spectrum) -> Sampled_Spectrum {
    return .{s.x0 * 4.0, 0.0, 0.0, 0.0};
}

li_simple_vol_path :: (using integrator: *Simple_Vol_Path_Integrator, ray_: Ray) -> Sampled_Spectrum {
    ray := ray_;
    l := spectrum_zero();
    beta := cast(float) 1.0;
    depth := 0;

    while true {
        hit, si := intersect(scene, ray);
        t_max := ifx hit then si.t_hit else cast(float) 1000000000;

        if ray.medium_index >= 0 {
            hash0 := hash_float_pbrt(get_1d(*sampler));
            hash1 := hash_float_pbrt(get_1d(*sampler));
            medium_rng := make_sampler(1);
            pcg_set_sequence(*medium_rng, hash0, hash1);
            initial_u := get_1d(*sampler);
            initial_mode_u := get_1d(*sampler);
            scattered, terminated, scattered_ray := sample_homogeneous_medium(scene, *medium_rng, ray, t_max,
                                                                              ray.medium_index, *beta, *l,
                                                                              *depth, max_depth, initial_u, initial_mode_u);
            if terminated return l;
            if scattered {
                ray = scattered_ray;
                continue;
            }
        }

        if hit {
            emitted := terminate_secondary_wavelengths(surface_emission(scene, *si.intr, -ray.direction));
            l = spectrum_add(l, spectrum_scale(emitted, beta));

            material := scene.materials[si.intr.material_index];
            if material.type == .INTERFACE {
                entering := dot(ray.direction, si.intr.n) < 0.0;
                next_medium := ifx entering then material.inside_medium_index else material.outside_medium_index;
                ray = spawn_ray(*si.intr, ray.direction);
                ray.medium_index = next_medium;
                continue;
            }

            return l;
        }

        return spectrum_scale(terminate_secondary_wavelengths(scene.sampled_infinite_light), beta);
    }

    return l;
}

li :: (using integrator: *Simple_Vol_Path_Integrator, ray: Ray) -> Sampled_Spectrum {
    return li_simple_vol_path(integrator, ray);
}

evaluate_pixel_sample :: (using integrator: *Simple_Vol_Path_Integrator, p_pixel: Point2i, sample_index: int) {
    start_pixel_sample(*sampler, p_pixel, sample_index);

    get_1d(*sampler);
    camera_sample := ifx disable_pixel_jitter then get_center_camera_sample(p_pixel) else get_camera_sample(*sampler, p_pixel);
    if disable_pixel_jitter {
        get_2d(*sampler);
        get_1d(*sampler);
        get_2d(*sampler);
    }
    camera_ray := generate_ray(*camera, camera_sample, *film);
    l := spectrum_mul(camera_ray.weight, li(integrator, camera_ray.ray));

    add_sample(*film, p_pixel, l, camera_sample.filter_weight);
}

render :: (using integrator: *Simple_Vol_Path_Integrator) {
    for sample_index: 0..sampler.samples_per_pixel-1 {
        for y: 0..film.height-1 {
            for x: 0..film.width-1 {
                evaluate_pixel_sample(integrator, .{x, y}, sample_index);
            }
        }
    }
}

make_simple_vol_path_integrator :: (scene: *Scene, camera: Pinhole_Camera,
                                      width: int, height: int, samples_per_pixel: int = 1,
                                      max_depth: int = 5,
                                      disable_pixel_jitter := false) -> Simple_Vol_Path_Integrator {
    integrator: Simple_Vol_Path_Integrator;
    integrator.scene = scene;
    integrator.camera = camera;
    integrator.film = make_film(width, height);
    integrator.sampler = make_sampler(samples_per_pixel);
    integrator.max_depth = max_depth;
    integrator.disable_pixel_jitter = disable_pixel_jitter;
    return integrator;
}
