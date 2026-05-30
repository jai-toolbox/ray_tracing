UNIFORM_HEMISPHERE_PDF :: cast(float) 1.0 / (cast(float) 2.0 * PI);

Light_Li_Sample :: struct {
    L: Sampled_Spectrum;
    wi: Vector3;
    pdf: float;
    p_light: Vector3;
    finite: bool;
}

Simple_Path_Integrator :: struct {
    camera: Pinhole_Camera;
    sampler: Sampler;
    film: Film;
    scene: *Scene;
    max_depth: int = 5;
    sample_lights: bool = true;
    sample_bsdf: bool = true;
    disable_pixel_jitter := false;
}

coordinate_system_from_z :: (z_axis: Vector3) -> Vector3, Vector3 {
    x_axis: Vector3;
    y_axis: Vector3;
    sign := ifx z_axis.z < 0.0 then -1.0 else 1.0;
    a := -1.0 / (sign + z_axis.z);
    b := z_axis.x * z_axis.y * a;
    x_axis = .{1.0 + sign * z_axis.x * z_axis.x * a, sign * b, -sign * z_axis.x};
    y_axis = .{b, sign + z_axis.y * z_axis.y * a, -z_axis.y};
    return x_axis, y_axis;
}

sample_uniform_hemisphere :: (u: Point2) -> Vector3 {
    z := u.x;
    r := sqrt(max(0.0, 1.0 - z*z));
    phi := 2.0 * PI * u.y;
    return .{r * cos(phi), r * sin(phi), z};
}

spherical_direction :: (sin_theta: float, cos_theta: float, phi: float) -> Vector3 {
    return .{sin_theta * cos(phi), sin_theta * sin(phi), cos_theta};
}

sample_uniform_disk_concentric :: (u: Point2) -> Point2 {
    u_offset := Point2.{2.0 * u.x - 1.0, 2.0 * u.y - 1.0};
    if u_offset.x == 0.0 && u_offset.y == 0.0 return .{};

    theta: float;
    r: float;
    if abs(u_offset.x) > abs(u_offset.y) {
        r = u_offset.x;
        theta = (PI / 4.0) * (u_offset.y / u_offset.x);
    } else {
        r = u_offset.y;
        theta = (PI / 2.0) - (PI / 4.0) * (u_offset.x / u_offset.y);
    }

    return .{r * cos(theta), r * sin(theta)};
}

sample_cosine_hemisphere :: (u: Point2) -> Vector3 {
    d := sample_uniform_disk_concentric(u);
    z := sqrt(max(0.0, 1.0 - d.x*d.x - d.y*d.y));
    return .{d.x, d.y, z};
}

local_to_world :: (local: Vector3, normal: Vector3) -> Vector3 {
    x_axis, y_axis := coordinate_system_from_z(normal);
    return local.x * x_axis + local.y * y_axis + local.z * normal;
}

bsdf_local_to_world :: (local: Vector3, intr: *Surface_Interaction) -> Vector3 {
    x_axis := normalize(intr.dpdu);
    y_axis := cross(intr.n, x_axis);
    return local.x * x_axis + local.y * y_axis + local.z * intr.n;
}

find_emissive_sphere :: (scene: *Scene) -> *Sphere {
    for *sphere: scene.spheres {
        material := scene.materials[sphere.material_index];
        if material.type == .EMISSIVE return sphere;
    }
    return null;
}

sample_emissive_sphere_light :: (scene: *Scene, intr: *Surface_Interaction, sphere: *Sphere, u: Point2) -> Light_Li_Sample, bool {
    to_center := sphere.center - intr.p;
    distance_squared := dot(to_center, to_center);
    if distance_squared <= 0.0 return .{}, false;

    distance_to_center := sqrt(distance_squared);
    if distance_squared <= sphere.radius * sphere.radius {
        local_n := sample_uniform_sphere(u);
        p_light := sphere.center + sphere.radius * local_n;
        wi := p_light - intr.p;
        wi_len_sq := dot(wi, wi);
        if wi_len_sq == 0.0 return .{}, false;
        wi_len := sqrt(wi_len_sq);
        wi /= wi_len;
        if dot(local_n, -wi) < 0.0 return .{}, false;
        abs_dot_light := abs(dot(local_n, -wi));
        if abs_dot_light == 0.0 return .{}, false;
        area_pdf := 1.0 / (4.0 * PI * sphere.radius * sphere.radius);
        pdf := area_pdf * wi_len_sq / abs_dot_light;
        material := scene.materials[sphere.material_index];
        return .{material.sampled_emission, wi, pdf, p_light, true}, true;
    }

    sin_theta_max := sphere.radius / distance_to_center;
    sin2_theta_max := sin_theta_max * sin_theta_max;
    cos_theta_max := sqrt(max(0.0, 1.0 - sin2_theta_max));
    one_minus_cos_theta_max := 1.0 - cos_theta_max;

    cos_theta := (cos_theta_max - 1.0) * u.x + 1.0;
    sin2_theta := 1.0 - cos_theta * cos_theta;
    if sin2_theta_max < cast(float) 0.00068523 {
        sin2_theta = sin2_theta_max * u.x;
        cos_theta = sqrt(max(0.0, 1.0 - sin2_theta));
        one_minus_cos_theta_max = sin2_theta_max * 0.5;
    }
    if one_minus_cos_theta_max == 0.0 return .{}, false;

    sin2_over_max := sin2_theta / sin2_theta_max;
    cos_alpha := sin2_theta / sin_theta_max + cos_theta * sqrt(max(0.0, 1.0 - sin2_over_max));
    sin_alpha := sqrt(max(0.0, 1.0 - cos_alpha * cos_alpha));
    phi := u.y * 2.0 * PI;
    w := spherical_direction(sin_alpha, cos_alpha, phi);

    z_axis := normalize(to_center);
    x_axis, y_axis := coordinate_system_from_z(z_axis);
    n := -(w.x * x_axis + w.y * y_axis + w.z * z_axis);
    p_light := sphere.center + sphere.radius * n;
    wi := normalize(p_light - intr.p);
    if dot(n, -wi) < 0.0 return .{}, false;
    pdf := 1.0 / (2.0 * PI * one_minus_cos_theta_max);
    material := scene.materials[sphere.material_index];
    return .{material.sampled_emission, wi, pdf, p_light, true}, true;
}

sample_infinite_light :: (scene: *Scene, intr: *Surface_Interaction, u: Point2) -> Light_Li_Sample, bool {
    wi := sample_uniform_sphere(u);
    return .{scene.sampled_infinite_light, wi, UNIFORM_SPHERE_PDF, intr.p + wi * cast(float) 2000000.0, false}, true;
}

spot_light_falloff :: (light: *Point_Spot_Light, w_light_to_point: Vector3) -> float {
    if !light.is_spot return 1.0;

    cos_theta := dot(light.direction, normalize(w_light_to_point));
    if cos_theta < light.cos_total_width return 0.0;
    if cos_theta > light.cos_falloff_start return 1.0;

    delta := (cos_theta - light.cos_total_width) / (light.cos_falloff_start - light.cos_total_width);
    return delta * delta * delta * delta;
}

sample_point_spot_light :: (scene: *Scene, intr: *Surface_Interaction, light: *Point_Spot_Light) -> Light_Li_Sample, bool {
    to_light := light.position - intr.p;
    distance_squared := dot(to_light, to_light);
    if distance_squared <= 0.0 return .{}, false;

    wi := normalize(to_light);
    falloff := spot_light_falloff(light, -wi);
    if falloff <= 0.0 return .{}, false;

    L := spectrum_scale(light.sampled_intensity, falloff / distance_squared);
    return .{L, wi, 1.0, light.position, true}, true;
}

direct_light_count :: (scene: *Scene, include_infinite: bool = true) -> int {
    count := scene.point_spot_lights.count;
    if find_emissive_sphere(scene) != null count += 1;
    if include_infinite && !spectrum_is_zero(scene.sampled_infinite_light) count += 1;
    return count;
}

sample_direct_light_by_index :: (scene: *Scene, intr: *Surface_Interaction, index: int, u: Point2, include_infinite: bool = true) -> Light_Li_Sample, bool {
    if index < scene.point_spot_lights.count {
        ls, ok := sample_point_spot_light(scene, intr, *scene.point_spot_lights[index]);
        return ls, ok;
    }
    index -= scene.point_spot_lights.count;

    emissive_sphere := find_emissive_sphere(scene);
    if emissive_sphere != null {
        if index == 0 {
            ls, ok := sample_emissive_sphere_light(scene, intr, emissive_sphere, u);
            return ls, ok;
        }
        index -= 1;
    }

    if include_infinite && index == 0 {
        ls, ok := sample_infinite_light(scene, intr, u);
        return ls, ok;
    }
    return .{}, false;
}

unoccluded :: (scene: *Scene, intr: *Surface_Interaction, ls: *Light_Li_Sample) -> bool {
    shadow_ray := spawn_ray(intr, ls.wi);
    t_max := cast(float) 1000000000;
    if ls.finite {
        to_light := ls.p_light - shadow_ray.origin;
        light_distance := sqrt(dot(to_light, to_light));
        t_max = max(0.0, light_distance * (1.0 - cast(float) 0.000001));
    }

    hit, si := intersect(scene, shadow_ray, t_max);
    if !hit return true;

    if ls.finite {
        material := scene.materials[si.intr.material_index];
        if material.type == .EMISSIVE return true;
    }

    return false;
}

sample_direct_light :: (using integrator: *Simple_Path_Integrator, intr: *Surface_Interaction, wo: Vector3, beta: Sampled_Spectrum) -> Sampled_Spectrum {
    light_count := direct_light_count(scene, include_infinite = true);
    if light_count == 0 return .{};

    uc := get_1d(*sampler);
    u := get_2d(*sampler);
    index := min(cast(int) floor(uc * cast(float) light_count), light_count - 1);
    light_p := 1.0 / cast(float) light_count;

    ls, ok := sample_direct_light_by_index(scene, intr, index, u, include_infinite = true);
    if !ok || ls.pdf <= 0.0 || spectrum_is_zero(ls.L) return .{};

    fcos := spectrum_scale(bsdf_f(scene, intr, wo, ls.wi), abs(dot(ls.wi, intr.n)));
    if spectrum_is_zero(fcos) return .{};
    if !unoccluded(scene, intr, *ls) return .{};

    return spectrum_mul(beta, spectrum_div(spectrum_mul(fcos, ls.L), light_p * ls.pdf));
}

sample_lambertian_bsdf :: (scene: *Scene, intr: *Surface_Interaction, wo: Vector3, u: Point2) -> Vector3, Sampled_Spectrum, float, bool {
    wi: Vector3;
    f: Sampled_Spectrum;
    pdf: float;
    specular: bool;
    local_wi := sample_cosine_hemisphere(u);
    if dot(wo, intr.n) < 0.0 local_wi.z *= -1.0;
    wi = bsdf_local_to_world(local_wi, intr);
    pdf = abs(dot(wi, intr.n)) * INV_PI;
    f = bsdf_f(scene, intr, wo, wi);
    specular = false;
    return wi, f, pdf, specular;
}

li_simple_path :: (using integrator: *Simple_Path_Integrator, ray_: Ray) -> Sampled_Spectrum {
    ray := ray_;
    l := spectrum_zero();
    beta: Sampled_Spectrum = .{1, 1, 1, 1};
    specular_bounce := true;
    depth := 0;

    while !spectrum_is_zero(beta) {
        hit, shape_intersection := intersect(scene, ray);
        if !hit {
            if !sample_lights || specular_bounce {
                l = spectrum_add(l, spectrum_mul(beta, scene.sampled_infinite_light));
            }
            break;
        }

        curr_to_prev_hit := -ray.direction;
        if !sample_lights || specular_bounce {
            emitted := surface_emission(scene, *shape_intersection.intr, curr_to_prev_hit);
            l = spectrum_add(l, spectrum_mul(beta, emitted));
        }

        if depth == max_depth break;
        depth += 1;

        if sample_lights {
            l = spectrum_add(l, sample_direct_light(integrator, *shape_intersection.intr, curr_to_prev_hit, beta));
        }

        next_ray_direction: Vector3;
        f: Sampled_Spectrum;
        pdf: float;

        if sample_bsdf {
            get_1d(*sampler); // PBRT consumes a component-selection sample before the 2D BSDF sample.
            specular: bool;
            next_ray_direction, f, pdf, specular = sample_lambertian_bsdf(scene, *shape_intersection.intr, curr_to_prev_hit, get_2d(*sampler));
            specular_bounce = specular;
        } else {
            next_ray_direction = sample_uniform_hemisphere(get_2d(*sampler));
            if dot(curr_to_prev_hit, shape_intersection.intr.n) * dot(next_ray_direction, shape_intersection.intr.n) < 0.0 {
                next_ray_direction = -next_ray_direction;
            }
            pdf = UNIFORM_HEMISPHERE_PDF;
            f = bsdf_f(scene, *shape_intersection.intr, curr_to_prev_hit, next_ray_direction);
            specular_bounce = false;
        }

        if pdf <= 0.0 || spectrum_is_zero(f) break;

        fcos := spectrum_scale(f, abs(dot(next_ray_direction, shape_intersection.intr.n)));
        beta = spectrum_mul(beta, spectrum_div(fcos, pdf));
        ray = spawn_ray(*shape_intersection.intr, next_ray_direction);
    }

    return l;
}

li :: (using integrator: *Simple_Path_Integrator, ray: Ray) -> Sampled_Spectrum {
    return li_simple_path(integrator, ray);
}

evaluate_pixel_sample :: (using integrator: *Simple_Path_Integrator, p_pixel: Point2i, sample_index: int) {
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

render :: (using integrator: *Simple_Path_Integrator) {
    for sample_index: 0..sampler.samples_per_pixel-1 {
        for y: 0..film.height-1 {
            for x: 0..film.width-1 {
                evaluate_pixel_sample(integrator, .{x, y}, sample_index);
            }
        }
    }
}

make_simple_path_integrator :: (scene: *Scene, camera: Pinhole_Camera,
                                  width: int, height: int, samples_per_pixel: int = 1,
                                  max_depth: int = 5,
                                  sample_lights: bool = true,
                                  sample_bsdf: bool = true,
                                  disable_pixel_jitter := false) -> Simple_Path_Integrator {
    integrator: Simple_Path_Integrator;
    integrator.scene = scene;
    integrator.camera = camera;
    integrator.film = make_film(width, height);
    integrator.sampler = make_sampler(samples_per_pixel);
    integrator.max_depth = max_depth;
    integrator.sample_lights = sample_lights;
    integrator.sample_bsdf = sample_bsdf;
    integrator.disable_pixel_jitter = disable_pixel_jitter;
    return integrator;
}
