Pbrt_Imported_Scene :: struct {
    scene: Scene;
    camera: Pinhole_Camera;
    width: int = 320;
    height: int = 180;
    samples_per_pixel: int = 1;
    max_depth: int = 5;
    output_filename: string = "jai_pbrt_import.ppm";
    integrator_name: string = "path";
}

Pbrt_Param :: struct {
    type_name: string;
    name: string;
    floats: [..] float;
    ints: [..] int;
    strings: [..] string;
    bools: [..] bool;
}

Pbrt_Named_Material :: struct {
    name: string;
    material_index: int;
}

Pbrt_Named_Texture :: struct {
    name: string;
    texture_index: int;
}

Pbrt_Import_State :: struct {
    imported: Pbrt_Imported_Scene;
    scene_directory: string;
    transform: Matrix4 = Matrix4_Identity;
    transform_stack: [..] Matrix4;
    material_index: int = 0;
    material_stack: [..] int;
    named_materials: [..] Pbrt_Named_Material;
    named_textures: [..] Pbrt_Named_Texture;
    look_from: Vector3 = .{0, 0, 5};
    look_at: Vector3 = .{0, 0, 0};
    look_up: Vector3 = .{0, 1, 0};
    fov: float = 45.0;
}

Pbrt_Tokenizer :: struct {
    data: string;
    cursor: int;
}

pbrt_load_scene :: (filename: string) -> Pbrt_Imported_Scene, bool {
    bytes, ok := read_entire_file(filename);
    if !ok {
        log_error("Failed to read PBRT scene '%'.", filename);
        return .{}, false;
    }
    defer free(bytes);

    state: Pbrt_Import_State;
    state.scene_directory = pbrt_directory_from_path(filename);

    default_material: Material;
    default_material.albedo = .{0.8, 0.8, 0.8};
    default_material.sampled_albedo = rgb_to_sampled_spectrum(default_material.albedo);
    array_add(*state.imported.scene.materials, default_material);

    tokenizer: Pbrt_Tokenizer;
    tokenizer.data = bytes;

    while true {
        directive, found := pbrt_next_token(*tokenizer);
        if !found break;

        if directive == "Film" {
            pbrt_parse_film(*tokenizer, *state);
        } else if directive == "Sampler" {
            pbrt_parse_sampler(*tokenizer, *state);
        } else if directive == "Integrator" {
            pbrt_parse_integrator(*tokenizer, *state);
        } else if directive == "LookAt" {
            pbrt_parse_look_at(*tokenizer, *state);
        } else if directive == "Camera" {
            pbrt_parse_camera(*tokenizer, *state);
        } else if directive == "WorldBegin" {
            // PBRT starts the world block here. Our importer keeps parsing into the same state.
        } else if directive == "AttributeBegin" {
            array_add(*state.transform_stack, state.transform);
            array_add(*state.material_stack, state.material_index);
        } else if directive == "AttributeEnd" {
            if state.transform_stack.count > 0 {
                state.transform = state.transform_stack[state.transform_stack.count - 1];
                array_resize(*state.transform_stack, state.transform_stack.count - 1);
            }
            if state.material_stack.count > 0 {
                state.material_index = state.material_stack[state.material_stack.count - 1];
                array_resize(*state.material_stack, state.material_stack.count - 1);
            }
        } else if directive == "Translate" {
            x := pbrt_parse_float_token(*tokenizer, 0);
            y := pbrt_parse_float_token(*tokenizer, 0);
            z := pbrt_parse_float_token(*tokenizer, 0);
            state.transform = state.transform * make_translation_matrix4(.{x, y, z});
        } else if directive == "Scale" {
            x := pbrt_parse_float_token(*tokenizer, 1);
            y := pbrt_parse_float_token(*tokenizer, 1);
            z := pbrt_parse_float_token(*tokenizer, 1);
            state.transform = state.transform * make_scale_matrix4(.{x, y, z});
        } else if directive == "Rotate" {
            angle := pbrt_parse_float_token(*tokenizer, 0);
            x := pbrt_parse_float_token(*tokenizer, 0);
            y := pbrt_parse_float_token(*tokenizer, 0);
            z := pbrt_parse_float_token(*tokenizer, 0);
            q: Quaternion;
            set_from_axis_and_angle(*q, normalize(Vector3.{x, y, z}), angle * PI / 180.0);
            state.transform = state.transform * rotation_matrix(Matrix4, q);
        } else if directive == "Transform" {
            m := pbrt_parse_matrix(*tokenizer);
            state.transform = m;
        } else if directive == "ConcatTransform" {
            m := pbrt_parse_matrix(*tokenizer);
            state.transform = state.transform * m;
        } else if directive == "Texture" {
            pbrt_parse_texture(*tokenizer, *state);
        } else if directive == "Material" {
            pbrt_parse_material(*tokenizer, *state, named = "");
        } else if directive == "MakeNamedMaterial" {
            name, ok_name := pbrt_next_token(*tokenizer);
            if ok_name pbrt_parse_material(*tokenizer, *state, name);
        } else if directive == "NamedMaterial" {
            name, ok_name := pbrt_next_token(*tokenizer);
            if ok_name state.material_index = pbrt_find_named_material(*state, name, state.material_index);
        } else if directive == "LightSource" {
            pbrt_parse_light_source(*tokenizer, *state);
        } else if directive == "Shape" {
            pbrt_parse_shape(*tokenizer, *state);
        } else if directive == "Include" {
            include_name, ok_include := pbrt_next_token(*tokenizer);
            if ok_include {
                log_error("PBRT Include '%' is not loaded by the first Jai importer yet.", include_name);
            }
        } else {
            // Unknown directives are accepted while we grow the importer.
        }
    }

    state.imported.camera = look_at_perspective_camera(state.look_from, state.look_at, state.look_up,
                                                       state.imported.width, state.imported.height,
                                                       state.fov);
    free(state.scene_directory);
    pbrt_free_import_state(*state);
    return state.imported, true;
}

pbrt_free_import_state :: (state: *Pbrt_Import_State) {
    for named: state.named_materials {
        free(named.name);
    }
    for named: state.named_textures {
        free(named.name);
    }

    array_free(state.transform_stack);
    array_free(state.material_stack);
    array_free(state.named_materials);
    array_free(state.named_textures);
}

pbrt_next_token :: (tokenizer: *Pbrt_Tokenizer) -> string, bool {
    data := tokenizer.data;
    i := tokenizer.cursor;

    while i < data.count {
        c := data[i];
        if c == #char "#" {
            while i < data.count && data[i] != #char "\n" i += 1;
            continue;
        }
        if c == #char " " || c == #char "\t" || c == #char "\r" || c == #char "\n" {
            i += 1;
            continue;
        }
        break;
    }

    if i >= data.count {
        tokenizer.cursor = i;
        return "", false;
    }

    if data[i] == #char "[" || data[i] == #char "]" {
        tokenizer.cursor = i + 1;
        return slice(data, i, 1), true;
    }

    if data[i] == #char "\"" {
        i += 1;
        start := i;
        while i < data.count && data[i] != #char "\"" i += 1;
        token := slice(data, start, i - start);
        if i < data.count i += 1;
        tokenizer.cursor = i;
        return token, true;
    }

    start := i;
    while i < data.count {
        c := data[i];
        if c == #char " " || c == #char "\t" || c == #char "\r" || c == #char "\n" ||
           c == #char "[" || c == #char "]" || c == #char "#" {
            break;
        }
        i += 1;
    }

    tokenizer.cursor = i;
    return slice(data, start, i - start), true;
}

pbrt_peek_token :: (tokenizer: *Pbrt_Tokenizer) -> string, bool {
    old := tokenizer.cursor;
    token, ok := pbrt_next_token(tokenizer);
    tokenizer.cursor = old;
    return token, ok;
}

pbrt_is_param_decl :: (token: string) -> bool {
    split := find_index_from_left(token, " ");
    if split < 0 return false;
    type_name := slice(token, 0, split);
    return type_name == "float" || type_name == "integer" || type_name == "bool" ||
           type_name == "string" || type_name == "rgb" || type_name == "spectrum" ||
           type_name == "point2" || type_name == "point3" || type_name == "vector3" ||
           type_name == "normal" || type_name == "normal3" || type_name == "texture";
}

pbrt_parse_params :: (tokenizer: *Pbrt_Tokenizer) -> [..] Pbrt_Param {
    params: [..] Pbrt_Param;
    while true {
        token, ok := pbrt_peek_token(tokenizer);
        if !ok || !pbrt_is_param_decl(token) break;

        decl, _ := pbrt_next_token(tokenizer);
        split := find_index_from_left(decl, " ");
        param: Pbrt_Param;
        param.type_name = slice(decl, 0, split);
        param.name = slice(decl, split + 1, decl.count - split - 1);

        next, has_next := pbrt_peek_token(tokenizer);
        if has_next && next == "[" {
            pbrt_next_token(tokenizer);
            while true {
                value_token, value_ok := pbrt_next_token(tokenizer);
                if !value_ok || value_token == "]" break;
                pbrt_add_param_value(*param, value_token);
            }
        } else {
            value_token, value_ok := pbrt_next_token(tokenizer);
            if value_ok pbrt_add_param_value(*param, value_token);
        }

        array_add(*params, param);
    }
    return params;
}

pbrt_add_param_value :: (param: *Pbrt_Param, token: string) {
    if param.type_name == "integer" {
        v, ok, _ := string_to_int(token);
        if ok array_add(*param.ints, v);
    } else if param.type_name == "string" || param.type_name == "texture" {
        array_add(*param.strings, token);
    } else if param.type_name == "bool" {
        array_add(*param.bools, token == "true" || token == "1");
    } else {
        v64, ok, _ := string_to_float64(token);
        if ok array_add(*param.floats, cast(float) v64);
    }
}

pbrt_free_params :: (params: *[..] Pbrt_Param) {
    for *param: params.* {
        array_free(param.floats);
        array_free(param.ints);
        array_free(param.strings);
        array_free(param.bools);
    }
    array_free(params.*);
}

pbrt_parse_float_token :: (tokenizer: *Pbrt_Tokenizer, default_value: float) -> float {
    token, ok := pbrt_next_token(tokenizer);
    if !ok return default_value;
    v64, parse_ok, _ := string_to_float64(token);
    if !parse_ok return default_value;
    return cast(float) v64;
}

pbrt_parse_int_token :: (tokenizer: *Pbrt_Tokenizer, default_value: int) -> int {
    token, ok := pbrt_next_token(tokenizer);
    if !ok return default_value;
    value, parse_ok, _ := string_to_int(token);
    if !parse_ok return default_value;
    return value;
}

pbrt_parse_matrix :: (tokenizer: *Pbrt_Tokenizer) -> Matrix4 {
    token, ok := pbrt_next_token(tokenizer);
    values: [16] float;
    if ok && token == "[" {
        for i: 0..15 values[i] = pbrt_parse_float_token(tokenizer, ifx (i % 5) == 0 then cast(float) 1 else cast(float) 0);
        pbrt_next_token(tokenizer); // ]
    }
    return Matrix4.{
        values[0], values[1], values[2], values[3],
        values[4], values[5], values[6], values[7],
        values[8], values[9], values[10], values[11],
        values[12], values[13], values[14], values[15],
    };
}

pbrt_parse_film :: (tokenizer: *Pbrt_Tokenizer, state: *Pbrt_Import_State) {
    film_type, _ := pbrt_next_token(tokenizer);
    params := pbrt_parse_params(tokenizer);
    defer pbrt_free_params(*params);
    state.imported.width = pbrt_get_one_int(params, "xresolution", state.imported.width);
    state.imported.height = pbrt_get_one_int(params, "yresolution", state.imported.height);
    output_filename := pbrt_get_one_string(params, "filename", "");
    if output_filename state.imported.output_filename = copy_string(output_filename);
}

pbrt_parse_sampler :: (tokenizer: *Pbrt_Tokenizer, state: *Pbrt_Import_State) {
    sampler_type, _ := pbrt_next_token(tokenizer);
    params := pbrt_parse_params(tokenizer);
    defer pbrt_free_params(*params);
    state.imported.samples_per_pixel = pbrt_get_one_int(params, "pixelsamples", state.imported.samples_per_pixel);
}

pbrt_parse_integrator :: (tokenizer: *Pbrt_Tokenizer, state: *Pbrt_Import_State) {
    name, ok := pbrt_next_token(tokenizer);
    if ok state.imported.integrator_name = copy_string(name);
    params := pbrt_parse_params(tokenizer);
    defer pbrt_free_params(*params);
    state.imported.max_depth = pbrt_get_one_int(params, "maxdepth", state.imported.max_depth);
}

pbrt_parse_look_at :: (tokenizer: *Pbrt_Tokenizer, state: *Pbrt_Import_State) {
    state.look_from = .{pbrt_parse_float_token(tokenizer, 0), pbrt_parse_float_token(tokenizer, 0), pbrt_parse_float_token(tokenizer, 0)};
    state.look_at = .{pbrt_parse_float_token(tokenizer, 0), pbrt_parse_float_token(tokenizer, 0), pbrt_parse_float_token(tokenizer, 0)};
    state.look_up = .{pbrt_parse_float_token(tokenizer, 0), pbrt_parse_float_token(tokenizer, 1), pbrt_parse_float_token(tokenizer, 0)};
}

pbrt_parse_camera :: (tokenizer: *Pbrt_Tokenizer, state: *Pbrt_Import_State) {
    camera_type, _ := pbrt_next_token(tokenizer);
    params := pbrt_parse_params(tokenizer);
    defer pbrt_free_params(*params);
    state.fov = pbrt_get_one_float(params, "fov", state.fov);
}

pbrt_parse_material :: (tokenizer: *Pbrt_Tokenizer, state: *Pbrt_Import_State, named: string) {
    material_type := "diffuse";
    token, ok := pbrt_peek_token(tokenizer);
    if ok && !pbrt_is_param_decl(token) {
        material_type, _ = pbrt_next_token(tokenizer);
    }

    params := pbrt_parse_params(tokenizer);
    defer pbrt_free_params(*params);

    mat: Material;
    mat.type = .LAMBERTIAN;
    mat.albedo = pbrt_get_one_rgb(params, "reflectance", .{0.8, 0.8, 0.8});
    mat.sampled_albedo = rgb_to_sampled_spectrum(mat.albedo);
    reflectance_texture := pbrt_get_one_texture(params, "reflectance", "");
    if reflectance_texture {
        mat.reflectance_texture_index = pbrt_find_named_texture(state, reflectance_texture, -1);
    }
    normalmap := pbrt_get_one_string(params, "normalmap", "");
    if normalmap {
        mat.normalmap_texture_index = pbrt_find_or_load_texture(state, normalmap, normalmap);
    }

    idx := state.imported.scene.materials.count;
    array_add(*state.imported.scene.materials, mat);

    if named {
        array_add(*state.named_materials, .{copy_string(named), idx});
    } else {
        state.material_index = idx;
    }
}

pbrt_parse_texture :: (tokenizer: *Pbrt_Tokenizer, state: *Pbrt_Import_State) {
    texture_name, ok_name := pbrt_next_token(tokenizer);
    texture_class, ok_class := pbrt_next_token(tokenizer);
    texture_type, ok_type := pbrt_next_token(tokenizer);
    if !ok_name || !ok_class || !ok_type return;

    params := pbrt_parse_params(tokenizer);
    defer pbrt_free_params(*params);

    if texture_type != "imagemap" return;

    filename := pbrt_get_one_string(params, "filename", "");
    if !filename return;

    idx := pbrt_find_or_load_texture(state, texture_name, filename);
    if idx >= 0 {
        scale := pbrt_get_one_rgb(params, "scale", .{1, 1, 1});
        state.imported.scene.textures[idx].scale = scale;
    }
}

pbrt_parse_light_source :: (tokenizer: *Pbrt_Tokenizer, state: *Pbrt_Import_State) {
    light_type, ok := pbrt_next_token(tokenizer);
    if !ok return;
    params := pbrt_parse_params(tokenizer);
    defer pbrt_free_params(*params);

    if light_type == "infinite" || light_type == "distant" {
        l := pbrt_get_one_rgb(params, "L", .{1, 1, 1});
        scale := pbrt_get_one_float(params, "scale", 1.0);
        illuminance := pbrt_get_one_float(params, "illuminance", 0.0);
        if illuminance > 0.0 l = l * (illuminance / 683.0);
        state.imported.scene.infinite_light = l * scale;
        state.imported.scene.sampled_infinite_light = rgb_to_sampled_spectrum(state.imported.scene.infinite_light);
    } else if light_type == "point" || light_type == "spot" {
        from := pbrt_get_one_point3(params, "from", transform_point(state.transform, .{0, 0, 0}));
        to := pbrt_get_one_point3(params, "to", from + transform_vector(state.transform, .{0, 0, -1}));
        i := pbrt_get_one_rgb(params, "I", .{1, 1, 1});
        scale := pbrt_get_one_float(params, "scale", 1.0);

        light: Point_Spot_Light;
        light.position = from;
        light.direction = normalize(to - from);
        if length(light.direction) == 0.0 light.direction = .{0, 0, -1};
        light.intensity = i * scale;
        light.sampled_intensity = rgb_to_sampled_spectrum(light.intensity);
        light.is_spot = light_type == "spot";
        if light.is_spot {
            cone_angle := pbrt_get_one_float(params, "coneangle", 30.0);
            cone_delta_angle := pbrt_get_one_float(params, "conedeltaangle", 5.0);
            light.cos_total_width = cos(cone_angle * PI / 180.0);
            light.cos_falloff_start = cos(max(0.0, cone_angle - cone_delta_angle) * PI / 180.0);
        }
        array_add(*state.imported.scene.point_spot_lights, light);
    }
}

pbrt_parse_shape :: (tokenizer: *Pbrt_Tokenizer, state: *Pbrt_Import_State) {
    shape_type, ok := pbrt_next_token(tokenizer);
    if !ok return;

    params := pbrt_parse_params(tokenizer);
    defer pbrt_free_params(*params);

    if shape_type == "sphere" {
        radius := pbrt_get_one_float(params, "radius", 1.0);
        center := transform_point(state.transform, .{0, 0, 0});
        scaled_x := transform_point(state.transform, .{radius, 0, 0});
        world_radius := length(scaled_x - center);
        array_add(*state.imported.scene.spheres, .{center, world_radius, state.material_index});
    } else if shape_type == "trianglemesh" {
        p := pbrt_get_float_array(params, "P");
        indices := pbrt_get_int_array(params, "indices");
        normals := pbrt_get_float_array(params, "N");
        uvs := pbrt_get_float_array(params, "uv");

        if p.count >= 9 && indices.count >= 3 {
            mesh: Triangle_Mesh;
            mesh.material_index = state.material_index;
            mesh.positions = NewArray(p.count / 3, Vector3);
            for i: 0..mesh.positions.count - 1 {
                local := Vector3.{p[i * 3 + 0], p[i * 3 + 1], p[i * 3 + 2]};
                mesh.positions[i] = transform_point(state.transform, local);
            }

            if normals.count == p.count {
                mesh.normals = NewArray(normals.count / 3, Vector3);
                for i: 0..mesh.normals.count - 1 {
                    n := Vector3.{normals[i * 3 + 0], normals[i * 3 + 1], normals[i * 3 + 2]};
                    mesh.normals[i] = normalize(transform_vector(state.transform, n));
                }
            }

            if uvs.count >= mesh.positions.count * 2 {
                mesh.texcoords = NewArray(mesh.positions.count, Vector2);
                for i: 0..mesh.texcoords.count - 1 {
                    mesh.texcoords[i] = .{uvs[i * 2 + 0], uvs[i * 2 + 1]};
                }
            }

            mesh.indices = NewArray(indices.count, int);
            for i: 0..indices.count - 1 mesh.indices[i] = indices[i];
            array_add(*state.imported.scene.triangle_meshes, mesh);
        }
    }
}

pbrt_find_named_material :: (state: *Pbrt_Import_State, name: string, fallback: int) -> int {
    for nm: state.named_materials {
        if nm.name == name return nm.material_index;
    }
    return fallback;
}

pbrt_find_named_texture :: (state: *Pbrt_Import_State, name: string, fallback: int) -> int {
    for nt: state.named_textures {
        if nt.name == name return nt.texture_index;
    }
    return fallback;
}

pbrt_find_or_load_texture :: (state: *Pbrt_Import_State, name: string, filename: string) -> int {
    existing := pbrt_find_named_texture(state, name, -1);
    if existing >= 0 return existing;

    path := pbrt_resolve_path(state.scene_directory, filename);
    defer free(path);

    texture, ok := pbrt_load_image_texture(name, path);
    if !ok {
        log_error("Failed to load PBRT imagemap texture '%' from '%'.", name, path);
        return -1;
    }

    idx := state.imported.scene.textures.count;
    array_add(*state.imported.scene.textures, texture);
    array_add(*state.named_textures, .{copy_string(name), idx});
    return idx;
}

pbrt_load_image_texture :: (name: string, filename: string) -> Image_Texture, bool {
    w: s32;
    h: s32;
    channels: s32;
    c_filename := to_c_string(filename);
    defer free(c_filename);

    pixels := stbi_load(c_filename, *w, *h, *channels, 4);
    if pixels == null {
        texture, ok := pbrt_load_ppm_texture(name, filename);
        return texture, ok;
    }
    defer stbi_image_free(pixels);

    count := cast(int) w * cast(int) h * 4;
    texture: Image_Texture;
    texture.name = copy_string(name);
    texture.filename = copy_string(filename);
    texture.width = cast(int) w;
    texture.height = cast(int) h;
    texture.pixels = NewArray(count, u8);
    memcpy(texture.pixels.data, pixels, count);
    texture.scale = .{1, 1, 1};
    return texture, true;
}

pbrt_load_ppm_texture :: (name: string, filename: string) -> Image_Texture, bool {
    bytes, ok := read_entire_file(filename);
    if !ok return .{}, false;
    defer free(bytes);

    tokenizer: Pbrt_Tokenizer;
    tokenizer.data = bytes;

    magic, ok_magic := pbrt_next_token(*tokenizer);
    if !ok_magic || magic != "P3" return .{}, false;

    width := pbrt_parse_int_token(*tokenizer, 0);
    height := pbrt_parse_int_token(*tokenizer, 0);
    max_value := pbrt_parse_int_token(*tokenizer, 255);
    if width <= 0 || height <= 0 || max_value <= 0 return .{}, false;

    texture: Image_Texture;
    texture.name = copy_string(name);
    texture.filename = copy_string(filename);
    texture.width = width;
    texture.height = height;
    texture.pixels = NewArray(width * height * 4, u8);
    texture.scale = .{1, 1, 1};

    for i: 0..width * height - 1 {
        r := pbrt_parse_int_token(*tokenizer, 0);
        g := pbrt_parse_int_token(*tokenizer, 0);
        b := pbrt_parse_int_token(*tokenizer, 0);
        texture.pixels[i * 4 + 0] = cast(u8) clamp((r * 255) / max_value, 0, 255);
        texture.pixels[i * 4 + 1] = cast(u8) clamp((g * 255) / max_value, 0, 255);
        texture.pixels[i * 4 + 2] = cast(u8) clamp((b * 255) / max_value, 0, 255);
        texture.pixels[i * 4 + 3] = 255;
    }

    return texture, true;
}

pbrt_resolve_path :: (directory: string, filename: string) -> string {
    if pbrt_path_is_absolute(filename) return copy_string(filename);
    return copy_string(tprint("%1%2", directory, filename));
}

pbrt_path_is_absolute :: (path: string) -> bool {
    if path.count >= 1 && (path[0] == #char "/" || path[0] == #char "\\") return true;
    if path.count >= 2 && path[1] == #char ":" return true;
    return false;
}

pbrt_directory_from_path :: (path: string) -> string {
    slash := find_index_from_right(path, #char "/");
    backslash := find_index_from_right(path, #char "\\");
    last := max(slash, backslash);
    if last < 0 return copy_string("");
    return copy_string(slice(path, 0, last + 1));
}

pbrt_get_param :: (params: [] Pbrt_Param, name: string) -> *Pbrt_Param {
    for *param: params {
        if param.name == name return param;
    }
    return null;
}

pbrt_get_one_texture :: (params: [] Pbrt_Param, name: string, default_value: string) -> string {
    param := pbrt_get_param(params, name);
    if param != null && param.type_name == "texture" && param.strings.count > 0 return param.strings[0];
    return default_value;
}

pbrt_get_one_int :: (params: [] Pbrt_Param, name: string, default_value: int) -> int {
    param := pbrt_get_param(params, name);
    if param != null && param.ints.count > 0 return param.ints[0];
    return default_value;
}

pbrt_get_one_float :: (params: [] Pbrt_Param, name: string, default_value: float) -> float {
    param := pbrt_get_param(params, name);
    if param != null && param.floats.count > 0 return param.floats[0];
    return default_value;
}

pbrt_get_one_string :: (params: [] Pbrt_Param, name: string, default_value: string) -> string {
    param := pbrt_get_param(params, name);
    if param != null && param.strings.count > 0 return param.strings[0];
    return default_value;
}

pbrt_get_one_point3 :: (params: [] Pbrt_Param, name: string, default_value: Vector3) -> Vector3 {
    param := pbrt_get_param(params, name);
    if param != null && param.floats.count >= 3 return .{param.floats[0], param.floats[1], param.floats[2]};
    return default_value;
}

pbrt_get_one_rgb :: (params: [] Pbrt_Param, name: string, default_value: Vector3) -> Vector3 {
    param := pbrt_get_param(params, name);
    if param != null && param.floats.count >= 3 return .{param.floats[0], param.floats[1], param.floats[2]};
    return default_value;
}

pbrt_get_float_array :: (params: [] Pbrt_Param, name: string) -> [] float {
    param := pbrt_get_param(params, name);
    if param != null return param.floats;
    return .[];
}

pbrt_get_int_array :: (params: [] Pbrt_Param, name: string) -> [] int {
    param := pbrt_get_param(params, name);
    if param != null return param.ints;
    return .[];
}

rgb_to_sampled_spectrum :: (rgb: Vector3) -> Sampled_Spectrum {
    average := (rgb.x + rgb.y + rgb.z) / 3.0;
    return .{rgb.x, rgb.y, rgb.z, average};
}
