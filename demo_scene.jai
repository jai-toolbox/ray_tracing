make_demo_scene_variant :: (scene_index: int = 0) -> Scene {
    scene: Scene;
    scene.infinite_light = .{0.55, 0.65, 0.8};
    scene.sampled_infinite_light = .{cast(float) 0.00638226513, cast(float) 0.00481029693, cast(float) 0.00284382002, cast(float) 0.00810805522};

    diffuse_red: Material;
    diffuse_red.albedo = .{0.8, 0.15, 0.1};
    diffuse_red.sampled_albedo = .{cast(float) 0.159395633, cast(float) 0.719455662, cast(float) 0.997910677, cast(float) 0.100214483};
    array_add(*scene.materials, diffuse_red);

    diffuse_gray: Material;
    diffuse_gray.albedo = .{0.75, 0.75, 0.72};
    diffuse_gray.sampled_albedo = .{cast(float) 0.749664729, cast(float) 0.749848393, cast(float) 0.635725513, cast(float) 0.73441398};
    array_add(*scene.materials, diffuse_gray);

    light: Material;
    light.type = .EMISSIVE;
    light.emission = .{8, 7, 5};
    light.sampled_albedo = .{0.5, 0.5, 0.5, 0.5};
    light.sampled_emission = .{cast(float) 0.0692663491, cast(float) 0.064553, cast(float) 0.0330325924, cast(float) 0.0635709763};
    array_add(*scene.materials, light);

    if scene_index == 1 {
        array_add(*scene.spheres, .{.{cast(float) -0.45, cast(float) -0.05, cast(float) -3.1}, cast(float) 0.85, 0});
        array_add(*scene.spheres, .{.{0, cast(float) -1001.1, cast(float) -3.25}, 1000.0, 1});
        array_add(*scene.spheres, .{.{cast(float) 1.1, cast(float) 4.8, cast(float) -2.4}, cast(float) 0.8, 2});
    } else if scene_index == 2 {
        array_add(*scene.spheres, .{.{cast(float) 0.55, cast(float) -0.12, cast(float) -2.75}, cast(float) 0.65, 0});
        array_add(*scene.spheres, .{.{cast(float) -0.7, cast(float) -0.32, cast(float) -3.55}, cast(float) 0.42, 1});
        array_add(*scene.spheres, .{.{0, cast(float) -1001.25, cast(float) -3.1}, 1000.0, 1});
        array_add(*scene.spheres, .{.{cast(float) -1.35, cast(float) 3.9, cast(float) -2.05}, cast(float) 0.55, 2});
    } else if scene_index == 3 {
        array_add(*scene.spheres, .{.{cast(float) -0.75, cast(float) 0.18, cast(float) -2.65}, cast(float) 0.58, 0});
        array_add(*scene.spheres, .{.{cast(float) 0.62, cast(float) -0.38, cast(float) -3.35}, cast(float) 0.35, 1});
        array_add(*scene.spheres, .{.{0, cast(float) -1001.35, cast(float) -3.35}, 1000.0, 1});
        array_add(*scene.spheres, .{.{cast(float) 0.8, cast(float) 3.6, cast(float) -1.85}, cast(float) 0.48, 2});
    } else if scene_index == 4 {
        array_add(*scene.spheres, .{.{cast(float) 0.1, cast(float) 0.05, cast(float) -2.35}, cast(float) 0.5, 0});
        array_add(*scene.spheres, .{.{cast(float) -0.95, cast(float) -0.22, cast(float) -3.05}, cast(float) 0.55, 1});
        array_add(*scene.spheres, .{.{cast(float) 0.95, cast(float) -0.48, cast(float) -3.8}, cast(float) 0.32, 0});
        array_add(*scene.spheres, .{.{0, cast(float) -1001.2, cast(float) -3.0}, 1000.0, 1});
        array_add(*scene.spheres, .{.{cast(float) 1.55, cast(float) 4.2, cast(float) -2.6}, cast(float) 0.65, 2});
    } else if scene_index == 5 {
        array_add(*scene.spheres, .{.{cast(float) -0.25, cast(float) -0.18, cast(float) -2.2}, cast(float) 0.42, 0});
        array_add(*scene.spheres, .{.{cast(float) 0.72, cast(float) 0.06, cast(float) -3.0}, cast(float) 0.62, 1});
        array_add(*scene.spheres, .{.{cast(float) -1.1, cast(float) -0.45, cast(float) -4.0}, cast(float) 0.4, 0});
        array_add(*scene.spheres, .{.{0, cast(float) -1001.05, cast(float) -3.4}, 1000.0, 1});
        array_add(*scene.spheres, .{.{cast(float) -1.25, cast(float) 4.6, cast(float) -2.9}, cast(float) 0.75, 2});
    } else if scene_index == 6 {
        array_add(*scene.spheres, .{.{cast(float) 0.82, cast(float) -0.05, cast(float) -2.55}, cast(float) 0.45, 0});
        array_add(*scene.spheres, .{.{cast(float) -0.42, cast(float) -0.16, cast(float) -3.15}, cast(float) 0.72, 1});
        array_add(*scene.spheres, .{.{cast(float) 0.05, cast(float) -1001.4, cast(float) -3.2}, 1000.0, 1});
        array_add(*scene.spheres, .{.{cast(float) 0.05, cast(float) 5.2, cast(float) -3.15}, cast(float) 0.9, 2});
    } else if scene_index == 7 {
        array_add(*scene.spheres, .{.{cast(float) -0.62, cast(float) -0.28, cast(float) -2.45}, cast(float) 0.36, 0});
        array_add(*scene.spheres, .{.{cast(float) 0.18, cast(float) 0.22, cast(float) -3.25}, cast(float) 0.82, 0});
        array_add(*scene.spheres, .{.{cast(float) 1.1, cast(float) -0.38, cast(float) -3.75}, cast(float) 0.38, 1});
        array_add(*scene.spheres, .{.{0, cast(float) -1001.18, cast(float) -3.15}, 1000.0, 1});
        array_add(*scene.spheres, .{.{cast(float) -0.7, cast(float) 3.4, cast(float) -1.75}, cast(float) 0.45, 2});
    } else if scene_index == 8 {
        array_add(*scene.spheres, .{.{cast(float) -0.98, cast(float) 0.0, cast(float) -3.0}, cast(float) 0.5, 0});
        array_add(*scene.spheres, .{.{cast(float) 0.0, cast(float) -0.3, cast(float) -2.45}, cast(float) 0.38, 1});
        array_add(*scene.spheres, .{.{cast(float) 0.92, cast(float) 0.02, cast(float) -3.3}, cast(float) 0.52, 0});
        array_add(*scene.spheres, .{.{0, cast(float) -1001.0, cast(float) -3.35}, 1000.0, 1});
        array_add(*scene.spheres, .{.{cast(float) 1.35, cast(float) 3.7, cast(float) -1.95}, cast(float) 0.5, 2});
    } else if scene_index == 9 {
        array_add(*scene.spheres, .{.{cast(float) 0.0, cast(float) 0.38, cast(float) -3.35}, cast(float) 0.72, 0});
        array_add(*scene.spheres, .{.{cast(float) -0.9, cast(float) -0.42, cast(float) -2.8}, cast(float) 0.3, 1});
        array_add(*scene.spheres, .{.{cast(float) 0.85, cast(float) -0.5, cast(float) -2.7}, cast(float) 0.28, 1});
        array_add(*scene.spheres, .{.{0, cast(float) -1001.3, cast(float) -3.2}, 1000.0, 1});
        array_add(*scene.spheres, .{.{cast(float) -1.55, cast(float) 4.4, cast(float) -2.35}, cast(float) 0.62, 2});
    } else {
        array_add(*scene.spheres, .{.{0, 0, -3}, 1.0, 0});
        array_add(*scene.spheres, .{.{0, -1001, -3}, 1000.0, 1});
        array_add(*scene.spheres, .{.{0, 5, -3}, 1.0, 2});
    }

    return scene;
}

make_demo_camera :: (width: int, height: int) -> Pinhole_Camera {
    return look_at_perspective_camera(.{0, cast(float) 0.5, cast(float) 1.5},
                                      .{0, 0, -3},
                                      .{0, 1, 0},
                                      width, height);
}

make_simple_vol_demo_scene_variant :: (scene_index: int = 0) -> Scene {
    source := make_demo_scene_variant(scene_index);
    scene: Scene;
    scene.infinite_light = source.infinite_light;
    scene.sampled_infinite_light = source.sampled_infinite_light;

    light_material := source.materials[2];
    array_add(*scene.materials, light_material);

    for sphere: source.spheres {
        material := source.materials[sphere.material_index];
        if material.type == .EMISSIVE {
            array_add(*scene.spheres, .{sphere.center, sphere.radius, 0});
        }
    }

    return scene;
}

make_simple_vol_explosion_reference_scene :: () -> Scene {
    scene: Scene;
    scene.infinite_light = .{0, 0, 0};
    scene.sampled_infinite_light = .{0, 0, 0, 0};

    volume := load_dense_nanovdb_volume("bin/fire.tbxnvdb");
    medium: Medium;
    medium.type = .DENSE_NANOVDB;
    medium.sigma_a = .{10, 10, 10, 10};
    medium.sigma_s = .{10, 10, 10, 10};
    medium.Le_scale = 5.0;
    medium.temperature_offset = 1.0;
    medium.temperature_scale = 100.0;
    medium.volume = volume;
    array_add(*scene.media, medium);

    interface_material: Material;
    interface_material.type = .INTERFACE;
    interface_material.inside_medium_index = 0;
    interface_material.outside_medium_index = -1;
    array_add(*scene.materials, interface_material);

    array_add(*scene.spheres, .{.{0, 40, 0}, 80.0, 0});
    return scene;
}

load_dense_nanovdb_volume :: (filename: string) -> Dense_Volume {
    data, ok := read_entire_file(filename);
    assert(ok, "Failed to read dense NanoVDB dump '%'. Run tools/dump_nanovdb_volume first.", filename);

    base := cast(*u8) data.data;
    assert(data.count >= 32, "Dense NanoVDB dump '%' is truncated.", filename);
    volume: Dense_Volume;
    volume.nx = (cast(*s32)(base + 8)).*;
    volume.ny = (cast(*s32)(base + 12)).*;
    volume.nz = (cast(*s32)(base + 16)).*;
    volume.min_x = (cast(*s32)(base + 20)).*;
    volume.min_y = (cast(*s32)(base + 24)).*;
    volume.min_z = (cast(*s32)(base + 28)).*;
    volume.max_x = (cast(*s32)(base + 32)).*;
    volume.max_y = (cast(*s32)(base + 36)).*;
    volume.max_z = (cast(*s32)(base + 40)).*;

    legacy_header_size :: 44;
    header_size := 164;
    if data.count < header_size || base[7] != cast(u8) 51 {
        header_size = legacy_header_size;
        volume.world_min = .{cast(float) volume.min_x, cast(float) volume.min_y, cast(float) volume.min_z};
        volume.world_max = .{cast(float) volume.max_x, cast(float) volume.max_y, cast(float) volume.max_z};
        volume.density_min_x = volume.min_x;
        volume.density_min_y = volume.min_y;
        volume.density_min_z = volume.min_z;
        volume.density_max_x = volume.max_x;
        volume.density_max_y = volume.max_y;
        volume.density_max_z = volume.max_z;
        volume.temperature_min_x = volume.min_x;
        volume.temperature_min_y = volume.min_y;
        volume.temperature_min_z = volume.min_z;
        volume.temperature_max_x = volume.max_x;
        volume.temperature_max_y = volume.max_y;
        volume.temperature_max_z = volume.max_z;
        volume.density_world_min = volume.world_min;
        volume.density_world_max = volume.world_max;
        volume.temperature_world_min = volume.world_min;
        volume.temperature_world_max = volume.world_max;
    } else {
        volume.world_min = .{
            (cast(*float)(base + 44)).*,
            (cast(*float)(base + 48)).*,
            (cast(*float)(base + 52)).*,
        };
        volume.world_max = .{
            (cast(*float)(base + 56)).*,
            (cast(*float)(base + 60)).*,
            (cast(*float)(base + 64)).*,
        };
        volume.density_min_x = (cast(*s32)(base + 68)).*;
        volume.density_min_y = (cast(*s32)(base + 72)).*;
        volume.density_min_z = (cast(*s32)(base + 76)).*;
        volume.density_max_x = (cast(*s32)(base + 80)).*;
        volume.density_max_y = (cast(*s32)(base + 84)).*;
        volume.density_max_z = (cast(*s32)(base + 88)).*;
        volume.temperature_min_x = (cast(*s32)(base + 92)).*;
        volume.temperature_min_y = (cast(*s32)(base + 96)).*;
        volume.temperature_min_z = (cast(*s32)(base + 100)).*;
        volume.temperature_max_x = (cast(*s32)(base + 104)).*;
        volume.temperature_max_y = (cast(*s32)(base + 108)).*;
        volume.temperature_max_z = (cast(*s32)(base + 112)).*;
        volume.density_world_min = .{
            (cast(*float)(base + 116)).*,
            (cast(*float)(base + 120)).*,
            (cast(*float)(base + 124)).*,
        };
        volume.density_world_max = .{
            (cast(*float)(base + 128)).*,
            (cast(*float)(base + 132)).*,
            (cast(*float)(base + 136)).*,
        };
        volume.temperature_world_min = .{
            (cast(*float)(base + 140)).*,
            (cast(*float)(base + 144)).*,
            (cast(*float)(base + 148)).*,
        };
        volume.temperature_world_max = .{
            (cast(*float)(base + 152)).*,
            (cast(*float)(base + 156)).*,
            (cast(*float)(base + 160)).*,
        };
    }
    count := volume.nx * volume.ny * volume.nz;
    assert(data.count >= header_size + count * 8, "Dense NanoVDB dump '%' is truncated.", filename);
    volume.density = NewArray(count, float);
    volume.temperature = NewArray(count, float);
    majorant_count := volume.majorant_res * volume.majorant_res * volume.majorant_res;
    volume.majorants = NewArray(majorant_count, float);
    p := base + header_size;
    for i: 0..count-1 {
        volume.density[i] = (cast(*float) p).*;
        volume.max_density = max(volume.max_density, volume.density[i]);
        p += 4;
        volume.temperature[i] = (cast(*float) p).*;
        p += 4;
    }

    for mz: 0..volume.majorant_res-1 {
        z0w := volume.world_min.z + (volume.world_max.z - volume.world_min.z) * cast(float) mz / cast(float) volume.majorant_res;
        z1w := volume.world_min.z + (volume.world_max.z - volume.world_min.z) * cast(float) (mz + 1) / cast(float) volume.majorant_res;
        fz0 := ((z0w - volume.density_world_min.z) / (volume.density_world_max.z - volume.density_world_min.z)) * cast(float) (volume.density_max_z - volume.density_min_z + 1) + cast(float) volume.density_min_z;
        fz1 := ((z1w - volume.density_world_min.z) / (volume.density_world_max.z - volume.density_world_min.z)) * cast(float) (volume.density_max_z - volume.density_min_z + 1) + cast(float) volume.density_min_z;
        nz0 := max(volume.density_min_z, cast(int) (fz0 - 1.0));
        nz1 := min(volume.density_max_z, cast(int) (fz1 + 1.0));

        for my: 0..volume.majorant_res-1 {
            y0w := volume.world_min.y + (volume.world_max.y - volume.world_min.y) * cast(float) my / cast(float) volume.majorant_res;
            y1w := volume.world_min.y + (volume.world_max.y - volume.world_min.y) * cast(float) (my + 1) / cast(float) volume.majorant_res;
            fy0 := ((y0w - volume.density_world_min.y) / (volume.density_world_max.y - volume.density_world_min.y)) * cast(float) (volume.density_max_y - volume.density_min_y + 1) + cast(float) volume.density_min_y;
            fy1 := ((y1w - volume.density_world_min.y) / (volume.density_world_max.y - volume.density_world_min.y)) * cast(float) (volume.density_max_y - volume.density_min_y + 1) + cast(float) volume.density_min_y;
            ny0 := max(volume.density_min_y, cast(int) (fy0 - 1.0));
            ny1 := min(volume.density_max_y, cast(int) (fy1 + 1.0));

            for mx: 0..volume.majorant_res-1 {
                x0w := volume.world_min.x + (volume.world_max.x - volume.world_min.x) * cast(float) mx / cast(float) volume.majorant_res;
                x1w := volume.world_min.x + (volume.world_max.x - volume.world_min.x) * cast(float) (mx + 1) / cast(float) volume.majorant_res;
                fx0 := ((x0w - volume.density_world_min.x) / (volume.density_world_max.x - volume.density_world_min.x)) * cast(float) (volume.density_max_x - volume.density_min_x + 1) + cast(float) volume.density_min_x;
                fx1 := ((x1w - volume.density_world_min.x) / (volume.density_world_max.x - volume.density_world_min.x)) * cast(float) (volume.density_max_x - volume.density_min_x + 1) + cast(float) volume.density_min_x;
                nx0 := max(volume.density_min_x, cast(int) (fx0 - 1.0));
                nx1 := min(volume.density_max_x, cast(int) (fx1 + 1.0));

                dst := mx + volume.majorant_res * (my + volume.majorant_res * mz);
                for z_abs: nz0..nz1 {
                    z := z_abs - volume.min_z;
                    for y_abs: ny0..ny1 {
                        y := y_abs - volume.min_y;
                        for x_abs: nx0..nx1 {
                            x := x_abs - volume.min_x;
                            if x < 0 || y < 0 || z < 0 continue;
                            if x >= volume.nx || y >= volume.ny || z >= volume.nz continue;
                            src := x + volume.nx * (y + volume.ny * z);
                            volume.majorants[dst] = max(volume.majorants[dst], volume.density[src]);
                        }
                    }
                }
            }
        }
    }

    return volume;
}

make_simple_vol_explosion_camera :: (width: int, height: int) -> Pinhole_Camera {
    return look_at_perspective_camera(.{0, 120, 20},
                                      .{cast(float) -0.5, 0, 30},
                                      .{0, 0, 1},
                                      width, height,
                                      37.0);
}
