Path_Integrator :: struct {
    camera: Pinhole_Camera;
    sampler: Sampler;
    film: Film;
    scene: *Scene;
    max_depth: int = 5;
    disable_pixel_jitter := false;
}

spectrum_max_component :: (a: Sampled_Spectrum) -> float {
    return max(max(a.x0, a.x1), max(a.x2, a.x3));
}

power_heuristic :: (nf: int, f_pdf: float, ng: int, g_pdf: float) -> float {
    f := cast(float) nf * f_pdf;
    g := cast(float) ng * g_pdf;
    ff := f * f;
    gg := g * g;
    if ff + gg == 0.0 return 0.0;
    return ff / (ff + gg);
}

lambertian_bsdf_pdf :: (intr: *Surface_Interaction, wo: Vector3, wi: Vector3) -> float {
    if dot(wo, intr.n) * dot(wi, intr.n) <= 0.0 return 0.0;
    return abs(dot(wi, intr.n)) * INV_PI;
}

sphere_light_pdf_li :: (ctx_intr: *Surface_Interaction, sphere: *Sphere, wi: Vector3) -> float {
    to_center := sphere.center - ctx_intr.p;
    distance_squared := dot(to_center, to_center);
    if distance_squared <= 0.0 return 0.0;

    if distance_squared <= sphere.radius * sphere.radius {
        shadow_ray := spawn_ray(ctx_intr, wi);
        hit, si := intersect_sphere(sphere, shadow_ray, cast(float) 1000000000);
        if !hit return 0.0;

        wi_len_sq := si.t_hit * si.t_hit * dot(shadow_ray.direction, shadow_ray.direction);
        abs_dot_light := abs(dot(si.intr.n, -wi));
        if abs_dot_light == 0.0 return 0.0;
        area_pdf := 1.0 / (4.0 * PI * sphere.radius * sphere.radius);
        return area_pdf * wi_len_sq / abs_dot_light;
    }

    sin2_theta_max := sphere.radius * sphere.radius / distance_squared;
    cos_theta_max := sqrt(max(0.0, 1.0 - sin2_theta_max));
    one_minus_cos_theta_max := 1.0 - cos_theta_max;
    if sin2_theta_max < cast(float) 0.00068523 {
        one_minus_cos_theta_max = sin2_theta_max * 0.5;
    }
    if one_minus_cos_theta_max == 0.0 return 0.0;
    return 1.0 / (2.0 * PI * one_minus_cos_theta_max);
}

sample_path_direct_light :: (using integrator: *Path_Integrator, intr: *Surface_Interaction, wo: Vector3) -> Sampled_Spectrum {
    light_count := direct_light_count(scene, include_infinite = false);
    if light_count == 0 return .{};

    uc := get_1d(*sampler);
    u_light := get_2d(*sampler);
    index := min(cast(int) floor(uc * cast(float) light_count), light_count - 1);
    light_p := 1.0 / cast(float) light_count;

    // PBRT path tracing asks lights for an incomplete PDF. Uniform infinite
    // lights return no direct-light sample in that mode, though the samples
    // are still consumed.
    light_context_intr := intr.*;
    light_context_intr.p = spawn_ray(intr, wo).origin;
    ls, ok := sample_direct_light_by_index(scene, *light_context_intr, index, u_light, include_infinite = false);
    if !ok || ls.pdf <= 0.0 || spectrum_is_zero(ls.L) return .{};

    fcos := spectrum_scale(bsdf_f(scene, intr, wo, ls.wi), abs(dot(ls.wi, intr.n)));
    if spectrum_is_zero(fcos) return .{};
    if !unoccluded(scene, intr, *ls) return .{};

    p_l := light_p * ls.pdf;
    p_b := lambertian_bsdf_pdf(intr, wo, ls.wi);
    w_l := power_heuristic(1, p_l, 1, p_b);
    return spectrum_scale(spectrum_div(spectrum_mul(fcos, ls.L), p_l), w_l);
}

li_path :: (using integrator: *Path_Integrator, ray_: Ray) -> Sampled_Spectrum {
    ray := ray_;
    l := spectrum_zero();
    beta: Sampled_Spectrum = .{1, 1, 1, 1};
    depth := 0;

    p_b: float = 0.0;
    eta_scale: float = 1.0;
    specular_bounce := false;
    any_non_specular_bounces := false;
    prev_intr: Surface_Interaction;
    has_prev_intr := false;

    while true {
        hit, shape_intersection := intersect(scene, ray);
        if !hit {
            le := scene.sampled_infinite_light;
            if depth == 0 || specular_bounce {
                l = spectrum_add(l, spectrum_mul(beta, le));
            } else {
                // UniformInfiniteLight::PDF_Li(..., allowIncompletePDF=true) is zero.
                w_b := power_heuristic(1, p_b, 1, 0.0);
                l = spectrum_add(l, spectrum_scale(spectrum_mul(beta, le), w_b));
            }
            break;
        }

        curr_to_prev_hit := -ray.direction;
        emitted := surface_emission(scene, *shape_intersection.intr, curr_to_prev_hit);
        if !spectrum_is_zero(emitted) {
            if depth == 0 || specular_bounce || !has_prev_intr {
                l = spectrum_add(l, spectrum_mul(beta, emitted));
            } else {
                emissive_sphere := find_emissive_sphere(scene);
                p_l := cast(float) 0.0;
                if emissive_sphere != null {
                    p_l = 0.5 * sphere_light_pdf_li(*prev_intr, emissive_sphere, ray.direction);
                }
                w_l := power_heuristic(1, p_b, 1, p_l);
                l = spectrum_add(l, spectrum_scale(spectrum_mul(beta, emitted), w_l));
            }
        }

        if depth == max_depth break;
        depth += 1;

        l = spectrum_add(l, spectrum_mul(beta, sample_path_direct_light(integrator, *shape_intersection.intr, curr_to_prev_hit)));

        get_1d(*sampler);
        next_ray_direction, f, pdf, specular := sample_lambertian_bsdf(scene, *shape_intersection.intr, curr_to_prev_hit, get_2d(*sampler));
        if pdf <= 0.0 || spectrum_is_zero(f) break;

        fcos := spectrum_scale(f, abs(dot(next_ray_direction, shape_intersection.intr.n)));
        beta = spectrum_mul(beta, spectrum_div(fcos, pdf));
        p_b = lambertian_bsdf_pdf(*shape_intersection.intr, curr_to_prev_hit, next_ray_direction);
        specular_bounce = specular;
        any_non_specular_bounces = any_non_specular_bounces || !specular;
        prev_intr = shape_intersection.intr;
        has_prev_intr = true;

        ray = spawn_ray(*shape_intersection.intr, next_ray_direction);

        rr_beta := spectrum_scale(beta, eta_scale);
        rr_max := spectrum_max_component(rr_beta);
        if rr_max < 1.0 && depth > 1 {
            q := max(0.0, 1.0 - rr_max);
            if get_1d(*sampler) < q break;
            beta = spectrum_div(beta, 1.0 - q);
        }
    }

    return l;
}

li :: (using integrator: *Path_Integrator, ray: Ray) -> Sampled_Spectrum {
    return li_path(integrator, ray);
}

evaluate_pixel_sample :: (using integrator: *Path_Integrator, p_pixel: Point2i, sample_index: int) {
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

render :: (using integrator: *Path_Integrator) {
    for sample_index: 0..sampler.samples_per_pixel-1 {
        for y: 0..film.height-1 {
            for x: 0..film.width-1 {
                evaluate_pixel_sample(integrator, .{x, y}, sample_index);
            }
        }
    }
}

make_path_integrator :: (scene: *Scene, camera: Pinhole_Camera,
                           width: int, height: int, samples_per_pixel: int = 1,
                           max_depth: int = 5,
                           disable_pixel_jitter := false) -> Path_Integrator {
    integrator: Path_Integrator;
    integrator.scene = scene;
    integrator.camera = camera;
    integrator.film = make_film(width, height);
    integrator.sampler = make_sampler(samples_per_pixel);
    integrator.max_depth = max_depth;
    integrator.disable_pixel_jitter = disable_pixel_jitter;
    return integrator;
}
