BLENDER_GLTF_WATTS_TO_LUMENS :: 683.0;
BLENDER_WORLD_COLOR :: Vector3.{0.050876, 0.050876, 0.050876};

PBRT_LIGHT_MODE_ALL        :: 0;
PBRT_LIGHT_MODE_SUN_ONLY   :: 1;
PBRT_LIGHT_MODE_POINT_ONLY :: 2;
PBRT_LIGHT_MODE_SPOT_ONLY  :: 3;

Pbrt_Export_Options :: struct {
    output_image_name: string;
    xresolution: int;
    yresolution: int;
    light_mode: int;
}

Pbrt_Mesh_Instance :: struct {
    mesh_index: int;
    world_transform: Matrix4;
}

make_default_pbrt_export_options :: (output_image_name: string = "scene.exr") -> Pbrt_Export_Options {
    return .{
        output_image_name = output_image_name,
        xresolution = 1024,
        yresolution = 768,
        light_mode = PBRT_LIGHT_MODE_ALL,
    };
}

export_gltf_to_pbrt :: (gltf: *Gltf_Data, source_scene_path: string, output_path: string, options: Pbrt_Export_Options) -> bool {
    builder: String_Builder;

    print_to_builder(*builder, "# Generated from %\n", source_scene_path);
    print_to_builder(*builder, "# First-pass glTF -> PBRT v4 export.\n");
    print_to_builder(*builder, "# Material policy: obvious metal/rust names -> conductor, otherwise coateddiffuse.\n");
    print_to_builder(*builder, "# Metallic-roughness texture channel unpacking and alpha modes are not translated yet.\n\n");

    write_pbrt_camera_and_render_settings(*builder, options);
    print_to_builder(*builder, "WorldBegin\n\n");

    write_pbrt_materials(*builder, gltf);
    write_pbrt_lights(*builder, gltf, options.light_mode);
    write_pbrt_meshes(*builder, gltf);

    output := builder_to_string(*builder);
    return write_entire_file(output_path, output);
}

write_pbrt_camera_and_render_settings :: (builder: *String_Builder, options: Pbrt_Export_Options) {
    print_to_builder(builder, "Film \"rgb\"\n");
    print_to_builder(builder, "    \"integer xresolution\" [%]\n", options.xresolution);
    print_to_builder(builder, "    \"integer yresolution\" [%]\n", options.yresolution);
    print_to_builder(builder, "    \"string filename\" [\"%\"]\n", options.output_image_name);
    print_to_builder(builder, "Sampler \"independent\" \"integer pixelsamples\" [16]\n");
    print_to_builder(builder, "Integrator \"path\" \"integer maxdepth\" [6]\n");
    print_to_builder(builder, "LookAt 12 8 14   0 0 0   0 1 0\n");
    print_to_builder(builder, "Camera \"perspective\" \"float fov\" [45]\n\n");
}

write_pbrt_materials :: (builder: *String_Builder, gltf: *Gltf_Data) {
    print_to_builder(builder, "# Materials\n");
    if gltf.all_materials.count == 0 {
        print_to_builder(builder, "MakeNamedMaterial \"mat_default\" \"string type\" [\"coateddiffuse\"] \"rgb reflectance\" [0.8 0.8 0.8] \"float roughness\" [0.5]\n\n");
        return;
    }

    for * mat, mat_index: gltf.all_materials {
        base_texture_name := tprint("mat_%_base_color", mat_index);
        normal_path := resolve_gltf_image_path(gltf, mat.normal_texture.texture_index);
        base_path := resolve_gltf_image_path(gltf, mat.pbr_metallic_roughness.base_color_texture.texture_index);
        has_base_texture := base_path.count > 0;

        if has_base_texture {
            print_to_builder(builder, "Texture \"%\" \"spectrum\" \"imagemap\" \"string filename\" [\"%\"]\n", base_texture_name, pbrt_path(base_path));
        }

        material_type := choose_pbrt_material_type(mat);
        c := mat.pbr_metallic_roughness.base_color_factor;
        roughness := choose_pbrt_roughness(mat);

        print_to_builder(builder, "MakeNamedMaterial \"mat_%\" \"string type\" [\"%\"]", mat_index, material_type);
        if has_base_texture {
            print_to_builder(builder, " \"texture reflectance\" [\"%\"]", base_texture_name);
        } else {
            print_to_builder(builder, " \"rgb reflectance\" [% % %]", c.x, c.y, c.z);
        }
        print_to_builder(builder, " \"float roughness\" [%]", roughness);
        if normal_path.count > 0 {
            print_to_builder(builder, " \"string normalmap\" [\"%\"]", pbrt_path(normal_path));
        }
        print_to_builder(builder, "\n");
    }
    print_to_builder(builder, "\n");
}

write_pbrt_lights :: (builder: *String_Builder, gltf: *Gltf_Data, light_mode: int) {
    print_to_builder(builder, "# Lights\n");
    print_to_builder(builder, "LightSource \"infinite\" \"rgb L\" [% % %]\n",
        BLENDER_WORLD_COLOR.x, BLENDER_WORLD_COLOR.y, BLENDER_WORLD_COLOR.z);

    if gltf.all_lights.count == 0 {
        print_to_builder(builder, "LightSource \"distant\" \"rgb L\" [1 1 1] \"float illuminance\" [250]\n\n");
        return;
    }

    write_pbrt_lights_recursive(builder, gltf, get_pbrt_scene_roots(gltf), Matrix4_Identity, light_mode);
    print_to_builder(builder, "\n");
}

write_pbrt_lights_recursive :: (builder: *String_Builder, gltf: *Gltf_Data, nodes: [] int, parent_transform: Matrix4, light_mode: int) {
    for node_index: nodes {
        if node_index < 0 || node_index >= gltf.all_nodes.count continue;
        node := *gltf.all_nodes[node_index];
        world_transform := parent_transform * compute_pbrt_node_local_transform(node);

        if node.light_index >= 0 && node.light_index < gltf.all_lights.count {
            light := *gltf.all_lights[node.light_index];
            color := light.color;
            intensity := max(light.intensity / BLENDER_GLTF_WATTS_TO_LUMENS, 0.001);
            position := transform_point(world_transform, .{0, 0, 0});
            direction := normalize(transform_vector(world_transform, .{0, 0, -1}));
            target := position + direction;

            if light.light_type == {
                case .POINT;
                    if light_mode != PBRT_LIGHT_MODE_ALL && light_mode != PBRT_LIGHT_MODE_POINT_ONLY break;
                    print_to_builder(builder, "LightSource \"point\" \"point3 from\" [% % %] \"rgb I\" [% % %] \"float scale\" [%]\n",
                        position.x, position.y, position.z, color.x, color.y, color.z, intensity);
                case .SPOT;
                    if light_mode != PBRT_LIGHT_MODE_ALL && light_mode != PBRT_LIGHT_MODE_SPOT_ONLY break;
                    outer_deg := light.outer_cone_angle * 180.0 / PI;
                    delta_deg := max((light.outer_cone_angle - light.inner_cone_angle) * 180.0 / PI, 0.0);
                    print_to_builder(builder, "LightSource \"spot\" \"point3 from\" [% % %] \"point3 to\" [% % %] \"rgb I\" [% % %] \"float scale\" [%] \"float coneangle\" [%] \"float conedeltaangle\" [%]\n",
                        position.x, position.y, position.z, target.x, target.y, target.z,
                        color.x, color.y, color.z, intensity, outer_deg, delta_deg);
                case .DIRECTIONAL;
                    if light_mode != PBRT_LIGHT_MODE_ALL && light_mode != PBRT_LIGHT_MODE_SUN_ONLY break;
                    from := -direction * 10.0;
                    to := direction * 10.0;
                    print_to_builder(builder, "LightSource \"distant\" \"point3 from\" [% % %] \"point3 to\" [% % %] \"rgb L\" [% % %] \"float scale\" [%]\n",
                        from.x, from.y, from.z, to.x, to.y, to.z, color.x, color.y, color.z, intensity);
            }
        }

        write_pbrt_lights_recursive(builder, gltf, node.children, world_transform, light_mode);
    }
}

write_pbrt_meshes :: (builder: *String_Builder, gltf: *Gltf_Data) {
    instances := collect_pbrt_mesh_instances(gltf);
    print_to_builder(builder, "# Geometry\n");
    print_to_builder(builder, "# % mesh instances\n\n", instances.count);

    primitive_count := 0;
    for instance: instances {
        if instance.mesh_index < 0 || instance.mesh_index >= gltf.all_meshes.count continue;
        mesh := *gltf.all_meshes[instance.mesh_index];

        for * prim: mesh.primitives {
            if prim.mode != .TRIANGLES continue;
            if prim.position_accessor < 0 continue;

            positions := read_accessor_as_vector3_array(gltf, prim.position_accessor);
            if positions.count == 0 continue;

            normals := read_accessor_as_vector3_array(gltf, prim.normal_accessor);
            texcoords := read_primitive_texcoords(gltf, prim, 0);
            indices := read_accessor_as_index_array(gltf, prim.indices_accessor);

            if normals.count != positions.count {
                array_resize(*normals, positions.count);
                for * normals it.* = .{0, 1, 0};
            }

            if texcoords.count != positions.count {
                array_resize(*texcoords, positions.count);
                for * texcoords it.* = .{0, 0};
            }

            if indices.count == 0 {
                array_reserve(*indices, positions.count);
                for i: 0..positions.count - 1 array_add(*indices, cast(u32) i);
            }

            mat_name := ifx prim.material_index >= 0 then tprint("mat_%", prim.material_index) else "mat_default";
            print_to_builder(builder, "AttributeBegin\n");
            print_to_builder(builder, "    NamedMaterial \"%\"\n", mat_name);
            print_to_builder(builder, "    Shape \"trianglemesh\"\n");

            print_to_builder(builder, "        \"point3 P\" [");
            for p, i: positions {
                wp := transform_point(instance.world_transform, p);
                print_to_builder(builder, "% % %", wp.x, wp.y, wp.z);
                if i < positions.count - 1 print_to_builder(builder, " ");
            }
            print_to_builder(builder, "]\n");

            print_to_builder(builder, "        \"normal N\" [");
            for n, i: normals {
                wn := normalize(transform_vector(instance.world_transform, n));
                print_to_builder(builder, "% % %", wn.x, wn.y, wn.z);
                if i < normals.count - 1 print_to_builder(builder, " ");
            }
            print_to_builder(builder, "]\n");

            print_to_builder(builder, "        \"point2 uv\" [");
            for uv, i: texcoords {
                print_to_builder(builder, "% %", uv.x, 1.0 - uv.y);
                if i < texcoords.count - 1 print_to_builder(builder, " ");
            }
            print_to_builder(builder, "]\n");

            print_to_builder(builder, "        \"integer indices\" [");
            for idx, i: indices {
                print_to_builder(builder, "%", idx);
                if i < indices.count - 1 print_to_builder(builder, " ");
            }
            print_to_builder(builder, "]\n");
            print_to_builder(builder, "AttributeEnd\n\n");

            primitive_count += 1;
        }
    }

    print("Exported % mesh instances, % trianglemesh primitives\n", instances.count, primitive_count);
}

compute_pbrt_node_local_transform :: (node: *Gltf_Node) -> Matrix4 {
    if node.has_matrix return node.matrix;

    rotation := rotation_matrix(Matrix4, node.rotation);
    scale_matrix := Matrix4_Identity;
    scale_matrix._11 = node.scale.x;
    scale_matrix._22 = node.scale.y;
    scale_matrix._33 = node.scale.z;

    translation_matrix := Matrix4_Identity;
    translation_matrix._14 = node.translation.x;
    translation_matrix._24 = node.translation.y;
    translation_matrix._34 = node.translation.z;

    return translation_matrix * rotation * scale_matrix;
}

collect_pbrt_mesh_instances :: (gltf: *Gltf_Data) -> [..] Pbrt_Mesh_Instance {
    result: [..] Pbrt_Mesh_Instance;
    roots := get_pbrt_scene_roots(gltf);
    collect_pbrt_mesh_instances_recursive(gltf, roots, Matrix4_Identity, *result);
    return result;
}

collect_pbrt_mesh_instances_recursive :: (gltf: *Gltf_Data, nodes: [] int, parent_transform: Matrix4, result: *[..] Pbrt_Mesh_Instance) {
    for node_index: nodes {
        if node_index < 0 || node_index >= gltf.all_nodes.count continue;
        node := *gltf.all_nodes[node_index];
        world_transform := parent_transform * compute_pbrt_node_local_transform(node);

        if node.mesh_index >= 0 {
            array_add(result, .{mesh_index = node.mesh_index, world_transform = world_transform});
        }

        collect_pbrt_mesh_instances_recursive(gltf, node.children, world_transform, result);
    }
}

get_pbrt_scene_roots :: (gltf: *Gltf_Data) -> [] int {
    scene := get_default_scene(gltf);
    if scene != null return scene.nodes;

    roots: [..] int;
    array_reserve(*roots, gltf.all_nodes.count);
    for i: 0..gltf.all_nodes.count - 1 array_add(*roots, i);
    return roots;
}

pbrt_path :: (path: string) -> string {
    result: String_Builder;
    for ch: path {
        if ch == #char "\\" {
            append(*result, "/");
        } else {
            append(*result, cast(u8) ch);
        }
    }
    return builder_to_string(*result);
}

clamp_float :: (v: float, lo: float, hi: float) -> float {
    if v < lo return lo;
    if v > hi return hi;
    return v;
}

choose_pbrt_material_type :: (mat: *Gltf_Material) -> string {
    if material_name_suggests_metal(mat.name) return "conductor";
    return "coateddiffuse";
}

choose_pbrt_roughness :: (mat: *Gltf_Material) -> float {
    roughness := mat.pbr_metallic_roughness.roughness_factor;

    // Blender's glTF export commonly puts roughness only in the packed texture.
    // Until we unpack that image, avoid making every textured material fully rough.
    if mat.pbr_metallic_roughness.metallic_roughness_texture.texture_index >= 0 && roughness == 1.0 {
        roughness = 0.5;
    }

    return clamp_float(roughness, 0.02, 1.0);
}

material_name_suggests_metal :: (name: string) -> bool {
    return contains_ascii_case_insensitive(name, "metal") || contains_ascii_case_insensitive(name, "rust");
}

contains_ascii_case_insensitive :: (haystack: string, needle: string) -> bool {
    if needle.count == 0 return true;
    if haystack.count < needle.count return false;

    for start: 0..haystack.count - needle.count {
        matched := true;
        for offset: 0..needle.count - 1 {
            if ascii_lower(cast(u8) haystack[start + offset]) != ascii_lower(cast(u8) needle[offset]) {
                matched = false;
                break;
            }
        }

        if matched return true;
    }

    return false;
}

ascii_lower :: (ch: u8) -> u8 {
    if ch >= cast(u8) #char "A" && ch <= cast(u8) #char "Z" return ch + 32;
    return ch;
}
