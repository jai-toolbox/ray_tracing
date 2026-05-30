Vol_Path_Integrator :: struct {
    camera: Pinhole_Camera;
    sampler: Sampler;
    film: Film;
    scene: *Scene;
    max_depth: int = 5;
    disable_pixel_jitter := false;
}

spectrum_sub :: (a: Sampled_Spectrum, b: Sampled_Spectrum) -> Sampled_Spectrum {
    return .{a.x0 - b.x0, a.x1 - b.x1, a.x2 - b.x2, a.x3 - b.x3};
}

spectrum_clamp_zero :: (a: Sampled_Spectrum) -> Sampled_Spectrum {
    return .{max(0.0, a.x0), max(0.0, a.x1), max(0.0, a.x2), max(0.0, a.x3)};
}

spectrum_exp_neg_scale :: (a: Sampled_Spectrum, s: float) -> Sampled_Spectrum {
    return .{exp(-s * a.x0), exp(-s * a.x1), exp(-s * a.x2), exp(-s * a.x3)};
}

spectrum_average :: (a: Sampled_Spectrum) -> float {
    return (a.x0 + a.x1 + a.x2 + a.x3) * 0.25;
}

spectrum_div_spectrum :: (a: Sampled_Spectrum, b: Sampled_Spectrum) -> Sampled_Spectrum {
    return .{
        ifx b.x0 != 0.0 then a.x0 / b.x0 else 0.0,
        ifx b.x1 != 0.0 then a.x1 / b.x1 else 0.0,
        ifx b.x2 != 0.0 then a.x2 / b.x2 else 0.0,
        ifx b.x3 != 0.0 then a.x3 / b.x3 else 0.0,
    };
}

vol_path_sample_exponential :: (u: float, a: float) -> float {
    u = min(cast(float) 0.99999994, max(cast(float) 0.0000001, u));
    return -log(cast(float) 1.0 - u) / a;
}

vol_path_medium_sigma_majorant :: (medium: *Medium, majorant_density: float) -> Sampled_Spectrum {
    if medium.type == .DENSE_NANOVDB {
        return spectrum_scale(spectrum_add(medium.sigma_a, medium.sigma_s), majorant_density);
    }
    return spectrum_add(medium.sigma_a, medium.sigma_s);
}

vol_path_apply_unscattered_transmittance :: (T_maj: Sampled_Spectrum,
                                               beta: *Sampled_Spectrum,
                                               r_u: *Sampled_Spectrum,
                                               r_l: *Sampled_Spectrum) {
    if T_maj.x0 == 0.0 {
        beta.* = .{};
        r_u.* = .{};
        r_l.* = .{};
        return;
    }
    ratio := spectrum_div(T_maj, T_maj.x0);
    beta.* = spectrum_mul(beta.*, ratio);
    r_u.* = spectrum_mul(r_u.*, ratio);
    r_l.* = spectrum_mul(r_l.*, ratio);
}

blackbody_sampled_visible :: (temperature: float) -> Sampled_Spectrum {
    return .{
        blackbody_normalized(cast(float) 545.903013580535, temperature),
        blackbody_normalized(cast(float) 616.856224458481, temperature),
        blackbody_normalized(cast(float) 830.000007566554, temperature),
        blackbody_normalized(cast(float) 479.154062543822, temperature),
    };
}

medium_properties_at_vol_path :: (scene: *Scene, medium_index: int, p: Vector3) -> Medium_Properties {
    medium := scene.media[medium_index];
    if medium.type == .DENSE_NANOVDB {
        p_medium := explosion_render_to_medium_point(p);
        density, temperature := sample_dense_volume(*medium.volume, p_medium);
        temp := (temperature - medium.temperature_offset) * medium.temperature_scale;
        Le := Sampled_Spectrum.{};
        if temp > 100.0 {
            Le = spectrum_scale(blackbody_sampled_visible(temp), medium.Le_scale);
        }
        return .{spectrum_scale(medium.sigma_a, density), spectrum_scale(medium.sigma_s, density), Le, medium.g};
    }
    return .{medium.sigma_a, medium.sigma_s, medium.Le, medium.g};
}

vol_path_sample_medium_segment :: (using integrator: *Vol_Path_Integrator, ray: *Ray, t_max: float,
                                    medium_index: int, beta: *Sampled_Spectrum,
                                    r_u: *Sampled_Spectrum, r_l: *Sampled_Spectrum,
                                    L: *Sampled_Spectrum, depth: *int,
                                    rng: *Sampler, initial_u: float,
                                    trace: *String_Builder = null) -> scattered: bool, terminated: bool {
    medium := scene.media[medium_index];
    sample_ray := ray.*;
    ray_length := sqrt(dot(sample_ray.direction, sample_ray.direction));
    if ray_length > 0.0 {
        t_max *= ray_length;
        sample_ray.direction /= ray_length;
    }
    T_maj: Sampled_Spectrum = .{1, 1, 1, 1};
    u := initial_u;
    if trace != null {
        print_to_builder(trace, "vp_medium_begin t_max % medium % depth % beta % % % % r_u % % % % r_l % % % % initial_u %\n",
                         t_max, medium_index, depth.*, beta.x0, beta.x1, beta.x2, beta.x3,
                         r_u.x0, r_u.x1, r_u.x2, r_u.x3, r_l.x0, r_l.x1, r_l.x2, r_l.x3, initial_u);
    }

    iter := make_dda_majorant_iterator(*medium.volume, sample_ray, t_max);
    if medium.type != .DENSE_NANOVDB {
        // Homogeneous media are represented as a single ray segment.
        iter.valid = true;
        iter.t_min = 0.0;
        iter.t_max = t_max;
        iter.volume = null;
    }

    while true {
        seg: Majorant_Segment;
        ok := false;
        if medium.type == .DENSE_NANOVDB {
            seg, ok = dda_next_majorant_segment(*iter);
        } else {
            if !iter.valid return false, false;
            seg = .{iter.t_min, iter.t_max, 1.0};
            iter.valid = false;
            ok = true;
        }
        if !ok {
            if trace != null {
                print_to_builder(trace, "vp_medium_end_unscattered T_maj % % % %\n", T_maj.x0, T_maj.x1, T_maj.x2, T_maj.x3);
            }
            vol_path_apply_unscattered_transmittance(T_maj, beta, r_u, r_l);
            if trace != null {
                print_to_builder(trace, "vp_medium_after_unscattered beta % % % % r_u % % % % r_l % % % %\n",
                                 beta.x0, beta.x1, beta.x2, beta.x3, r_u.x0, r_u.x1, r_u.x2, r_u.x3,
                                 r_l.x0, r_l.x1, r_l.x2, r_l.x3);
            }
            return false, false;
        }

        sigma_maj := vol_path_medium_sigma_majorant(*medium, seg.majorant);
        sigma_maj_0 := spectrum_first_component(sigma_maj);
        if trace != null {
            print_to_builder(trace, "vp_segment t_min % t_max % majorant % sigma_maj % % % %\n",
                             seg.t_min, seg.t_max, seg.majorant, sigma_maj.x0, sigma_maj.x1, sigma_maj.x2, sigma_maj.x3);
        }
        if sigma_maj_0 == 0.0 {
            T_maj = spectrum_mul(T_maj, spectrum_exp_neg_scale(sigma_maj, seg.t_max - seg.t_min));
            continue;
        }

        t_min := seg.t_min;
        while true {
            t := t_min + vol_path_sample_exponential(u, sigma_maj_0);
            u = get_1d(rng);
            if t > seg.t_max {
                T_maj = spectrum_mul(T_maj, spectrum_exp_neg_scale(sigma_maj, seg.t_max - t_min));
                if trace != null {
                    print_to_builder(trace, "vp_sample_past t % next_u % T_maj % % % %\n",
                                     t, u, T_maj.x0, T_maj.x1, T_maj.x2, T_maj.x3);
                }
                break;
            }

            T_maj = spectrum_mul(T_maj, spectrum_exp_neg_scale(sigma_maj, t - t_min));
            p := sample_ray.origin + sample_ray.direction * t;
            mp := medium_properties_at_vol_path(scene, medium_index, p);
            if trace != null {
                print_to_builder(trace, "vp_sample t % next_u % p % % % T_maj % % % %\n",
                                 t, u, p.x, p.y, p.z, T_maj.x0, T_maj.x1, T_maj.x2, T_maj.x3);
                print_to_builder(trace, "vp_mp sigma_a % % % % sigma_s % % % % Le % % % % g %\n",
                                 mp.sigma_a.x0, mp.sigma_a.x1, mp.sigma_a.x2, mp.sigma_a.x3,
                                 mp.sigma_s.x0, mp.sigma_s.x1, mp.sigma_s.x2, mp.sigma_s.x3,
                                 mp.Le.x0, mp.Le.x1, mp.Le.x2, mp.Le.x3, mp.g);
            }

            if depth.* < max_depth && !spectrum_is_zero(mp.Le) {
                pdf := sigma_maj_0 * T_maj.x0;
                if pdf != 0.0 {
                    betap := spectrum_div(spectrum_mul(beta.*, T_maj), pdf);
                    r_e := spectrum_div(spectrum_mul(spectrum_mul(r_u.*, sigma_maj), T_maj), pdf);
                    r_e_avg := spectrum_average(r_e);
                    if r_e_avg != 0.0 {
                        emitted := spectrum_div(spectrum_mul(spectrum_mul(betap, mp.sigma_a), mp.Le), r_e_avg);
                        L.* = spectrum_add(L.*, emitted);
                        if trace != null {
                            print_to_builder(trace, "vp_emit pdf % r_e_avg % emitted % % % % L % % % %\n",
                                             pdf, r_e_avg, emitted.x0, emitted.x1, emitted.x2, emitted.x3,
                                             L.x0, L.x1, L.x2, L.x3);
                        }
                    }
                }
            }

            p_absorb := mp.sigma_a.x0 / sigma_maj_0;
            p_scatter := mp.sigma_s.x0 / sigma_maj_0;
            p_null := max(cast(float) 0.0, cast(float) 1.0 - p_absorb - p_scatter);
            um := get_1d(rng);
            mode_sample := um * (p_absorb + p_scatter + p_null);
            if trace != null {
                print_to_builder(trace, "vp_mode um % mode_sample % p_absorb % p_scatter % p_null %\n",
                                 um, mode_sample, p_absorb, p_scatter, p_null);
            }

            if mode_sample < p_absorb {
                if trace != null print_to_builder(trace, "vp_absorb\n");
                return false, true;
            } else if mode_sample < p_absorb + p_scatter {
                if depth.* >= max_depth return false, true;
                depth.* += 1;

                pdf := T_maj.x0 * mp.sigma_s.x0;
                if pdf == 0.0 return false, true;
                beta.* = spectrum_div(spectrum_mul(spectrum_mul(beta.*, T_maj), mp.sigma_s), pdf);
                r_u.* = spectrum_div(spectrum_mul(spectrum_mul(r_u.*, T_maj), mp.sigma_s), pdf);
                if spectrum_is_zero(beta.*) || spectrum_is_zero(r_u.*) return false, true;
                if trace != null {
                    print_to_builder(trace, "vp_scatter pdf % beta % % % % r_u % % % %\n",
                                     pdf, beta.x0, beta.x1, beta.x2, beta.x3, r_u.x0, r_u.x1, r_u.x2, r_u.x3);
                }

                // VolPathIntegrator samples direct lighting at real medium
                // scatters even when the selected light contributes black.
                // Keep the sampler stream aligned with PBRT before phase sampling.
                get_1d(*sampler);
                get_2d(*sampler);

                wi, phase_pdf := sample_henyey_greenstein(-ray.direction, mp.g, .{get_1d(*sampler), get_1d(*sampler)});
                if phase_pdf == 0.0 return false, true;
                beta.* = spectrum_scale(beta.*, henyey_greenstein_pdf(dot(-ray.direction, wi), mp.g) / phase_pdf);
                r_l.* = spectrum_div(r_u.*, phase_pdf);
                if trace != null {
                    print_to_builder(trace, "vp_phase wi % % % phase_pdf % beta % % % % r_l % % % %\n",
                                     wi.x, wi.y, wi.z, phase_pdf, beta.x0, beta.x1, beta.x2, beta.x3,
                                     r_l.x0, r_l.x1, r_l.x2, r_l.x3);
                }

                ray.origin = p;
                ray.direction = wi;
                ray.medium_index = medium_index;
                return true, false;
            } else {
                sigma_n := spectrum_clamp_zero(spectrum_sub(sigma_maj, spectrum_add(mp.sigma_a, mp.sigma_s)));
                pdf := T_maj.x0 * sigma_n.x0;
                if pdf == 0.0 {
                    beta.* = .{};
                    return false, true;
                }
                beta.* = spectrum_div(spectrum_mul(spectrum_mul(beta.*, T_maj), sigma_n), pdf);
                r_u.* = spectrum_div(spectrum_mul(spectrum_mul(r_u.*, T_maj), sigma_n), pdf);
                r_l.* = spectrum_div(spectrum_mul(spectrum_mul(r_l.*, T_maj), sigma_maj), pdf);
                if spectrum_is_zero(beta.*) || spectrum_is_zero(r_u.*) return false, true;
                if trace != null {
                    print_to_builder(trace, "vp_null pdf % sigma_n % % % % beta % % % % r_u % % % % r_l % % % %\n",
                                     pdf, sigma_n.x0, sigma_n.x1, sigma_n.x2, sigma_n.x3,
                                     beta.x0, beta.x1, beta.x2, beta.x3, r_u.x0, r_u.x1, r_u.x2, r_u.x3,
                                     r_l.x0, r_l.x1, r_l.x2, r_l.x3);
                }
                T_maj = .{1, 1, 1, 1};
                t_min = t;
            }
        }
    }

    return false, false;
}

li_vol_path :: (using integrator: *Vol_Path_Integrator, ray_: Ray, trace: *String_Builder = null) -> Sampled_Spectrum {
    ray := ray_;
    L := spectrum_zero();
    beta: Sampled_Spectrum = .{1, 1, 1, 1};
    r_u: Sampled_Spectrum = .{1, 1, 1, 1};
    r_l: Sampled_Spectrum = .{1, 1, 1, 1};
    depth := 0;
    specular_bounce := false;

    while true {
        if trace != null {
            print_to_builder(trace, "vp_loop depth % ray_o % % % ray_d % % % medium % L % % % % beta % % % % r_u % % % % r_l % % % %\n",
                             depth, ray.origin.x, ray.origin.y, ray.origin.z, ray.direction.x, ray.direction.y, ray.direction.z,
                             ray.medium_index, L.x0, L.x1, L.x2, L.x3, beta.x0, beta.x1, beta.x2, beta.x3,
                             r_u.x0, r_u.x1, r_u.x2, r_u.x3, r_l.x0, r_l.x1, r_l.x2, r_l.x3);
        }
        hit, si := intersect(scene, ray);
        if trace != null {
            print_to_builder(trace, "vp_intersect hit %", hit);
            if hit print_to_builder(trace, " t_hit % p % % % n % % %", si.t_hit, si.intr.p.x, si.intr.p.y, si.intr.p.z, si.intr.n.x, si.intr.n.y, si.intr.n.z);
            append(trace, "\n");
        }
        if ray.medium_index >= 0 {
            hash_u0 := get_1d(*sampler);
            hash_u1 := get_1d(*sampler);
            hash0 := hash_float_pbrt(hash_u0);
            hash1 := hash_float_pbrt(hash_u1);
            medium_rng := make_sampler(1);
            pcg_set_sequence(*medium_rng, hash0, hash1);
            t_max := ifx hit then si.t_hit else cast(float) 1000000000;
            initial_u := get_1d(*sampler);
            if trace != null {
                print_to_builder(trace, "vp_medium_rng hash_u % % hash % % rng_state % % initial_u %\n",
                                 hash_u0, hash_u1, hash0, hash1, medium_rng.rng_state, medium_rng.rng_inc, initial_u);
            }
            scattered, terminated := vol_path_sample_medium_segment(integrator, *ray, t_max, ray.medium_index,
                                                                     *beta, *r_u, *r_l, *L, *depth,
                                                                     *medium_rng, initial_u, trace);
            if trace != null print_to_builder(trace, "vp_medium_result scattered % terminated %\n", scattered, terminated);
            if terminated || spectrum_is_zero(beta) || spectrum_is_zero(r_u) return L;
            if scattered {
                specular_bounce = false;
                continue;
            }
        }

        if !hit {
            le := scene.sampled_infinite_light;
            if !spectrum_is_zero(le) {
                r_avg := spectrum_average(r_u);
                if depth == 0 || specular_bounce {
                    if r_avg != 0.0 L = spectrum_add(L, spectrum_div(spectrum_mul(beta, le), r_avg));
                }
            }
            if trace != null print_to_builder(trace, "vp_miss_return L % % % %\n", L.x0, L.x1, L.x2, L.x3);
            break;
        }

        emitted := surface_emission(scene, *si.intr, -ray.direction);
        if !spectrum_is_zero(emitted) {
            r_avg := spectrum_average(r_u);
            if depth == 0 || specular_bounce {
                if r_avg != 0.0 L = spectrum_add(L, spectrum_div(spectrum_mul(beta, emitted), r_avg));
            }
        }

        material := scene.materials[si.intr.material_index];
        if material.type == .INTERFACE {
            entering := dot(ray.direction, si.intr.n) < 0.0;
            next_medium := ifx entering then material.inside_medium_index else material.outside_medium_index;
            ray = spawn_ray(*si.intr, ray.direction);
            ray.medium_index = next_medium;
            continue;
        }

        if depth >= max_depth break;
        depth += 1;

        get_1d(*sampler);
        wo := -ray.direction;
        wi, f, pdf, specular := sample_lambertian_bsdf(scene, *si.intr, wo, get_2d(*sampler));
        if pdf <= 0.0 || spectrum_is_zero(f) break;

        fcos := spectrum_scale(f, abs(dot(wi, si.intr.n)));
        beta = spectrum_mul(beta, spectrum_div(fcos, pdf));
        r_l = spectrum_div(r_u, pdf);
        specular_bounce = specular;
        ray = spawn_ray(*si.intr, wi);

        rr_beta := spectrum_div(beta, spectrum_average(r_u));
        rr_max := spectrum_max_component(rr_beta);
        if rr_max < 1.0 && depth > 1 {
            q := max(0.0, 1.0 - rr_max);
            if get_1d(*sampler) < q break;
            beta = spectrum_div(beta, 1.0 - q);
        }
    }

    return L;
}

li :: (using integrator: *Vol_Path_Integrator, ray: Ray) -> Sampled_Spectrum {
    return li_vol_path(integrator, ray);
}

evaluate_pixel_sample :: (using integrator: *Vol_Path_Integrator, p_pixel: Point2i, sample_index: int) {
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

render :: (using integrator: *Vol_Path_Integrator) {
    for sample_index: 0..sampler.samples_per_pixel-1 {
        for y: 0..film.height-1 {
            for x: 0..film.width-1 {
                evaluate_pixel_sample(integrator, .{x, y}, sample_index);
            }
        }
    }
}

make_vol_path_integrator :: (scene: *Scene, camera: Pinhole_Camera,
                               width: int, height: int, samples_per_pixel: int = 1,
                               max_depth: int = 5,
                               disable_pixel_jitter := false) -> Vol_Path_Integrator {
    integrator: Vol_Path_Integrator;
    integrator.scene = scene;
    integrator.camera = camera;
    integrator.film = make_film(width, height);
    integrator.sampler = make_sampler(samples_per_pixel);
    integrator.max_depth = max_depth;
    integrator.disable_pixel_jitter = disable_pixel_jitter;
    return integrator;
}
