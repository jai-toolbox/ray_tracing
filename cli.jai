Command_Line :: #import "Command_Line";

Ray_Tracing_CLI_Options :: struct {
    cropwindow: string;                @"?Specify an image crop window w.r.t. [0,1]^2."
    debugstart: string;                @"?Inform the Integrator where to start rendering for faster debugging."
    disable_image_textures: bool;      @"?Always return the average value of image textures."
    disable_pixel_jitter: bool;        @"?Always sample pixels at their centers."
    disable_texture_filtering: bool;   @"?Point-sample all textures."
    disable_wavelength_jitter: bool;   @"?Always sample the same wavelengths of light."
    displacement_edge_scale: float = 1;@"?Scale target triangle edge length by given value."
    display_server: string;            @"?Connect to display server at given address and port."
    force_diffuse: bool;               @"?Convert all materials to be diffuse."
    fullscreen: bool;                  @"?Render fullscreen. Only supported with interactive rendering."
    interactive: bool;                 @"?Enable interactive rendering mode."
    mse_reference_image: string;       @"?Filename for reference image to use for MSE computation."
    mse_reference_out: string;         @"?File to write MSE error vs spp results."
    nthreads: int;                     @"?Use specified number of threads for rendering."
    outfile: string;                   @"?Write the final image to the given filename."
    pixel: string;                     @"?Render just the specified pixel."
    pixelbounds: string;               @"?Specify an image crop window w.r.t. pixel coordinates."
    pixelmaterial: string;             @"?Print information about the material visible in the center of the pixel's extent."
    pixelstats: bool;                  @"?Record per-pixel statistics and write additional images with their values."
    quick: bool;                       @"?Automatically reduce a number of quality settings to render more quickly."
    quiet: bool;                       @"?Suppress all text output other than error messages."
    render_coord_sys: string;          @"?Coordinate system to use for the scene: camera, cameraworld, or world."
    seed: int;                         @"?Set random number generator seed. Default: 0."
    spp: int;                          @"?Override number of pixel samples specified in scene description file."
    stats: bool;                       @"?Print various statistics after rendering completes."
    wavefront: bool;                   @"?Use wavefront volumetric path integrator."
    write_partial_images: bool;        @"?Periodically write the current image to disk."

    log_file: string;                  @"?Filename to write logging messages to."
    log_level: string;                 @"?Log messages at or above this level: verbose, error, or fatal."
    log_utilization: bool;             @"?Periodically print processor and memory use in verbose-level logging."

    format: bool;                      @"?Print a reformatted version of the input file(s). Does not render an image."
    toply: bool;                       @"?Print a reformatted version of the input file(s) and convert triangle meshes to PLY files."
    upgrade: bool;                     @"?Upgrade an older scene file to this renderer's current format."
}

show_ray_tracing_cli_usage :: (message: string = "") {
    if message print("tbx_raytracing: %\n\n", message);

    print(#string END
usage: tbx_raytracing [<options>] <filename...>

Rendering options:
  --cropwindow <x0,x1,y0,y1>    Specify an image crop window w.r.t. [0,1]^2.
  --debugstart <values>         Inform the Integrator where to start rendering for
                                faster debugging.
  --disable-image-textures      Always return the average value of image textures.
  --disable-pixel-jitter        Always sample pixels at their centers.
  --disable-texture-filtering   Point-sample all textures.
  --disable-wavelength-jitter   Always sample the same wavelengths of light.
  --displacement-edge-scale <s> Scale target triangle edge length by given value.
                                (Default: 1)
  --display-server <addr:port>  Connect to display server at given address and port
                                to display the image as it's being rendered.
  --force-diffuse               Convert all materials to be diffuse.
  --fullscreen                  Render fullscreen. Only supported with --interactive.
  --help                        Print this help text.
  --interactive                 Enable interactive rendering mode.
  --mse-reference-image <file>  Filename for reference image to use for MSE computation.
  --mse-reference-out <file>    File to write MSE error vs spp results.
  --nthreads <num>              Use specified number of threads for rendering.
  --outfile <filename>          Write the final image to the given filename.
  --pixel <x,y>                 Render just the specified pixel.
  --pixelbounds <x0,x1,y0,y1>   Specify an image crop window w.r.t. pixel coordinates.
  --pixelmaterial <x,y>         Print information about the material visible in the
                                center of the pixel's extent.
  --pixelstats                  Record per-pixel statistics and write additional images
                                with their values.
  --quick                       Automatically reduce a number of quality settings
                                to render more quickly.
  --quiet                       Suppress all text output other than error messages.
  --render-coord-sys <name>     Coordinate system to use for the scene: camera,
                                cameraworld, or world.
  --seed <n>                    Set random number generator seed. Default: 0.
  --stats                       Print various statistics after rendering completes.
  --spp <n>                     Override number of pixel samples specified in scene
                                description file.
  --wavefront                   Use wavefront volumetric path integrator.
  --write-partial-images        Periodically write the current image to disk.

Logging options:
  --log-file <filename>         Filename to write logging messages to.
  --log-level <level>           Log messages at or above this level: verbose, error,
                                or fatal. Default: error.
  --log-utilization             Periodically print processor and memory use in verbose-
                                level logging.

Reformatting options:
  --format                      Print a reformatted version of the input file(s).
  --toply                       Print a reformatted version of the input file(s) and
                                convert all triangle meshes to PLY files.
  --upgrade                     Upgrade an older scene file to this renderer's format.

This renderer currently maps the CLI to the built-in volumetric explosion demo scene.
END);
}

ray_tracing_cli_has_help_arg :: (args: [] string) -> bool {
    for i: 1..args.count - 1 {
        if args[i] == "--help" || args[i] == "-help" || args[i] == "-h" || args[i] == "-?" return true;
    }
    return false;
}

ray_tracing_cli_normalize_arg :: (arg: string) -> string {
    if arg.count < 2 || arg[0] != #char "-" return copy_string(arg);

    builder: String_Builder;
    for i: 0..arg.count - 1 {
        c := arg[i];
        if i >= 2 && c == #char "-" {
            append(*builder, "_");
        } else {
            append(*builder, c);
        }
    }

    return builder_to_string(*builder);
}

ray_tracing_cli_normalize_args :: (raw_args: [] string) -> [..] string {
    result: [..] string;
    for i: 1..raw_args.count - 1 array_add(*result, ray_tracing_cli_normalize_arg(raw_args[i]));
    return result;
}

ray_tracing_cli_warn_if_unsupported_options_are_set :: (is_set: Command_Line.Is_Set(Ray_Tracing_CLI_Options), free_arguments: [] string, quiet: bool) {
    if quiet return;

    if free_arguments.count {
        print("Scene-file parsing is not wired up yet; rendering the built-in demo scene instead.\n");
    }

    if is_set.cropwindow || is_set.debugstart || is_set.disable_image_textures ||
       is_set.disable_texture_filtering || is_set.disable_wavelength_jitter ||
       is_set.displacement_edge_scale || is_set.force_diffuse || is_set.fullscreen ||
       is_set.interactive || is_set.mse_reference_image || is_set.mse_reference_out ||
       is_set.nthreads || is_set.pixel || is_set.pixelbounds || is_set.pixelmaterial ||
       is_set.pixelstats || is_set.quick || is_set.render_coord_sys || is_set.seed ||
       is_set.stats || is_set.wavefront || is_set.write_partial_images ||
       is_set.log_file || is_set.log_level || is_set.log_utilization ||
       is_set.format || is_set.toply || is_set.upgrade {
        print("Some parsed CLI options are accepted for compatibility but are not implemented yet.\n");
    }
}

render_cli_vol_path_explosion_ppm :: (filename: string, width: int = 320, height: int = 180,
                                      samples_per_pixel: int = 1, max_depth: int = 5,
                                      disable_pixel_jitter := false) {
    scene := make_simple_vol_explosion_reference_scene();
    camera := make_simple_vol_explosion_camera(width, height);
    integrator := make_vol_path_integrator(*scene, camera, width, height, samples_per_pixel,
                                           max_depth, disable_pixel_jitter);
    render(*integrator);

    ok := write_ppm(*integrator.film, filename);
    assert(ok, "Failed to write image '%'.", filename);
}

render_cli_vol_path_explosion_tev :: (title: string = "jai_vol_path_explosion.exr",
                                      address: string = TEV_DEFAULT_ADDRESS,
                                      width: int = 320, height: int = 180,
                                      samples_per_pixel: int = 1, max_depth: int = 5,
                                      disable_pixel_jitter := false) -> bool {
    scene := make_simple_vol_explosion_reference_scene();
    camera := make_simple_vol_explosion_camera(width, height);
    integrator := make_vol_path_integrator(*scene, camera, width, height, samples_per_pixel,
                                           max_depth, disable_pixel_jitter);

    connection := tev_connect(address);
    if !connection.connected return false;
    defer tev_disconnect(*connection);

    display_item := make_tev_display_item(title, width, height);
    defer free_tev_display_item(*display_item);

    if !tev_display_item_display(*display_item, *connection, *integrator.film) return false;

    for sample_index: 0..integrator.sampler.samples_per_pixel-1 {
        for y: 0..integrator.film.height-1 {
            for x: 0..integrator.film.width-1 {
                evaluate_pixel_sample(*integrator, .{x, y}, sample_index);
            }

            if !tev_display_item_display(*display_item, *connection, *integrator.film) return false;
        }
    }

    return tev_display_item_display(*display_item, *connection, *integrator.film);
}

run_ray_tracing_cli :: () {
    raw_args := get_command_line_arguments();
    defer array_reset(*raw_args);

    run_ray_tracing_cli(raw_args);
}

run_ray_tracing_cli :: (raw_args: [] string) {
    if ray_tracing_cli_has_help_arg(raw_args) {
        show_ray_tracing_cli_usage();
        return;
    }

    normalized_args := ray_tracing_cli_normalize_args(raw_args);
    defer {
        for normalized_args free(it);
        array_free(normalized_args);
    }

    success, options, is_set, free_arguments := Command_Line.parse_arguments(
        Ray_Tracing_CLI_Options,
        flags = .FREE_ARGUMENTS_ALLOWED | .DOUBLE_DASH_REQUIRED,
        help_triggers = .[],
        args = normalized_args);
    defer array_free(free_arguments);

    if !success {
        show_ray_tracing_cli_usage("Invalid command-line arguments.");
        return;
    }

    ray_tracing_cli_warn_if_unsupported_options_are_set(is_set, free_arguments, options.quiet);

    width := 320;
    height := 180;
    samples_per_pixel := ifx is_set.spp then max(1, options.spp) else 1;

    if options.display_server {
        ok := render_cli_vol_path_explosion_tev("jai_vol_path_explosion.exr", options.display_server,
                                                width, height, samples_per_pixel, 5,
                                                options.disable_pixel_jitter);
        assert(ok, "Failed to send render to display server at '%'.", options.display_server);
        return;
    }

    output := ifx options.outfile then options.outfile else "bin/jai_vol_path_explosion.ppm";
    render_cli_vol_path_explosion_ppm(output, width, height, samples_per_pixel, 5,
                                      options.disable_pixel_jitter);

    if !options.quiet print("Wrote %\n", output);
}
