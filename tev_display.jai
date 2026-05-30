TEV_DEFAULT_ADDRESS :: "127.0.0.1:14158";
TEV_TILE_SIZE :: 128;

#if OS == .WINDOWS {
    GetCurrentThreadId :: () -> u32 #foreign kernel32;
}

Tev_Display_Directive :: enum u8 {
    Open_Image   :: 0;
    Reload_Image :: 1;
    Close_Image  :: 2;
    Update_Image :: 3;
    Create_Image :: 4;
}

Tev_Display_Connection :: struct {
    socket: Socket = INVALID_SOCKET;
    connected: bool;
}

Tev_Display_Item :: struct {
    title: string;
    width, height: int;
    opened_image: bool;
    tile_hashes: [] u64;
}

tev_connect :: (address: string = TEV_DEFAULT_ADDRESS) -> Tev_Display_Connection {
    result: Tev_Display_Connection;

    if !socket_init() {
        log_error("tev: failed to initialize sockets.");
        return result;
    }

    split := find_index_from_right(address, ":");
    if split < 0 {
        log_error("tev: expected display address as host:port, got '%'.", address);
        return result;
    }

    host := slice(address, 0, split);
    port := slice(address, split + 1, address.count - split - 1);

    c_host := to_c_string(host);
    c_port := to_c_string(port);
    defer free(c_host);
    defer free(c_port);

    hints: addrinfo;
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = .STREAM;
    hints.ai_protocol = .TCP;

    resolved: *addrinfo;
    err := getaddrinfo(c_host, c_port, *hints, *resolved);
    if err != 0 {
        log_error("tev: getaddrinfo failed for '%'.", address);
        return result;
    }
    defer freeaddrinfo(resolved);

    info := resolved;
    while info != null {
        s := socket(info.ai_family, info.ai_socktype, info.ai_protocol);
        if s == INVALID_SOCKET {
            info = info.ai_next;
            continue;
        }

        #if OS == .WINDOWS {
            connect_result := connect(s, info.ai_addr, cast(s32) info.ai_addrlen);
        } else {
            connect_result := connect(s, info.ai_addr, cast(socklen_t) info.ai_addrlen);
        }

        if connect_result == SOCKET_ERROR {
            close_and_reset(*s);
            info = info.ai_next;
            continue;
        }

        result.socket = s;
        result.connected = true;
        return result;
    }

    log_error("tev: could not connect to display server at '%'.", address);
    return result;
}

tev_disconnect :: (connection: *Tev_Display_Connection) {
    close_and_reset(*connection.socket);
    connection.connected = false;
}

tev_write_u8 :: (ptr: *u8, value: u8) -> *u8 {
    ptr.* = value;
    return ptr + 1;
}

tev_write_s32 :: (ptr: *u8, value: s32) -> *u8 {
    memcpy(ptr, *value, size_of(s32));
    return ptr + size_of(s32);
}

tev_write_float :: (ptr: *u8, value: float) -> *u8 {
    memcpy(ptr, *value, size_of(float));
    return ptr + size_of(float);
}

tev_write_string :: (ptr: *u8, value: string) -> *u8 {
    memcpy(ptr, value.data, value.count);
    ptr += value.count;
    ptr.* = 0;
    return ptr + 1;
}

tev_send :: (connection: *Tev_Display_Connection, message: [] u8) -> bool {
    if !connection.connected return false;

    message_size := cast(s32) message.count;
    memcpy(message.data, *message_size, size_of(s32));

    sent_total := 0;
    while sent_total < message.count {
        ptr := message.data + sent_total;
        remaining := message.count - sent_total;

        #if OS == .WINDOWS {
            sent := send(connection.socket, ptr, cast(s32) remaining, cast(MSG) 0);
        } else {
            sent := send(connection.socket, ptr, cast(u64) remaining, cast(MSG) 0);
        }

        if sent <= 0 {
            log_error("tev: send failed.");
            tev_disconnect(connection);
            return false;
        }

        sent_total += sent;
    }

    return true;
}

tev_send_create_image :: (connection: *Tev_Display_Connection, title: string,
                          width: int, height: int, grab_focus := true) -> bool {
    channels := string.["R", "G", "B"];
    channel_name_bytes := 0;
    for channels channel_name_bytes += it.count + 1;

    message_size := size_of(s32) + size_of(u8) + size_of(u8) + title.count + 1
                  + 3 * size_of(s32) + channel_name_bytes;
    message := NewArray(message_size, u8);
    defer array_free(message);

    ptr := message.data;
    ptr = tev_write_s32(ptr, 0);
    ptr = tev_write_u8(ptr, cast(u8) Tev_Display_Directive.Create_Image);
    ptr = tev_write_u8(ptr, ifx grab_focus then cast(u8) 1 else cast(u8) 0);
    ptr = tev_write_string(ptr, title);
    ptr = tev_write_s32(ptr, cast(s32) width);
    ptr = tev_write_s32(ptr, cast(s32) height);
    ptr = tev_write_s32(ptr, cast(s32) channels.count);
    for channels ptr = tev_write_string(ptr, it);

    return tev_send(connection, message);
}

tev_film_rgb :: (film: *Film, x: int, y: int) -> Vector3 {
    index := x + y * film.width;
    weight := film.sample_weights[index];
    if weight <= 0.0 return .{};

    rgb := Vector3.{
        cast(float) (film.rgb_sums[index].r / cast(float64) weight),
        cast(float) (film.rgb_sums[index].g / cast(float64) weight),
        cast(float) (film.rgb_sums[index].b / cast(float64) weight),
    };

    rgb.x = to_image_half(rgb.x);
    rgb.y = to_image_half(rgb.y);
    rgb.z = to_image_half(rgb.z);
    return rgb;
}

tev_channel_value :: (rgb: Vector3, channel_index: int) -> float {
    if channel_index == 0 return rgb.x;
    if channel_index == 1 return rgb.y;
    return rgb.z;
}

tev_display_title :: (base_title: string) -> string {
    #if OS == .WINDOWS {
        return tprint("% (%)", base_title, GetCurrentThreadId());
    } else {
        return tprint("% (%)", base_title, 0);
    }
}

tev_tile_count :: (width: int, height: int) -> int {
    tiles_x := (width + TEV_TILE_SIZE - 1) / TEV_TILE_SIZE;
    tiles_y := (height + TEV_TILE_SIZE - 1) / TEV_TILE_SIZE;
    return tiles_x * tiles_y;
}

tev_murmur_hash64a :: (key: *u8, len: int, seed: u64 = 0) -> u64 {
    m :: cast(u64) 0xc6a4a7935bd1e995;
    r :: 47;

    h := seed ~ (cast(u64) len * m);

    cursor := key;
    chunks := len / 8;
    for 0..chunks - 1 {
        k: u64;
        memcpy(*k, cursor, size_of(u64));
        cursor += 8;

        k *= m;
        k ^= k >> r;
        k *= m;

        h ^= k;
        h *= m;
    }

    tail_count := len & 7;
    if tail_count >= 7 h ^= cast(u64) cursor[6] << 48;
    if tail_count >= 6 h ^= cast(u64) cursor[5] << 40;
    if tail_count >= 5 h ^= cast(u64) cursor[4] << 32;
    if tail_count >= 4 h ^= cast(u64) cursor[3] << 24;
    if tail_count >= 3 h ^= cast(u64) cursor[2] << 16;
    if tail_count >= 2 h ^= cast(u64) cursor[1] << 8;
    if tail_count >= 1 {
        h ^= cast(u64) cursor[0];
        h *= m;
    }

    h ^= h >> r;
    h *= m;
    h ^= h >> r;

    return h;
}

tev_hash_float_buffer :: (values: [] float) -> u64 {
    return tev_murmur_hash64a(cast(*u8) values.data, values.count * size_of(float));
}

tev_zero_tile_hash :: () -> u64 {
    values := NewArray(TEV_TILE_SIZE * TEV_TILE_SIZE, float);
    defer array_free(values);
    return tev_hash_float_buffer(values);
}

tev_hash_tile :: (film: *Film, channel_index: int,
                  tile_x: int, tile_y: int, tile_width: int, tile_height: int) -> u64 {
    values := NewArray(TEV_TILE_SIZE * TEV_TILE_SIZE, float);
    defer array_free(values);

    offset := 0;
    for y: tile_y..tile_y + tile_height - 1 {
        for x: tile_x..tile_x + tile_width - 1 {
            rgb := tev_film_rgb(film, x, y);
            values[offset] = tev_channel_value(rgb, channel_index);
            offset += 1;
        }
    }

    return tev_hash_float_buffer(values);
}

make_tev_display_item :: (title: string, width: int, height: int) -> Tev_Display_Item {
    item: Tev_Display_Item;
    item.title = tev_display_title(title);
    item.width = width;
    item.height = height;

    n_tiles := tev_tile_count(width, height);
    item.tile_hashes = NewArray(n_tiles * 3, u64);

    zero_hash := tev_zero_tile_hash();
    for i: 0..item.tile_hashes.count - 1 item.tile_hashes[i] = zero_hash;

    return item;
}

free_tev_display_item :: (item: *Tev_Display_Item) {
    array_free(item.tile_hashes);
    item.tile_hashes = .[];
    item.opened_image = false;
}

tev_send_update_tile :: (connection: *Tev_Display_Connection, film: *Film, title: string,
                         channel_name: string, channel_index: int,
                         tile_x: int, tile_y: int, tile_width: int, tile_height: int) -> bool {
    value_count := tile_width * tile_height;
    message_size := size_of(s32) + size_of(u8) + size_of(u8) + title.count + 1
                  + channel_name.count + 1 + 4 * size_of(s32)
                  + value_count * size_of(float);
    message := NewArray(message_size, u8);
    defer array_free(message);

    ptr := message.data;
    ptr = tev_write_s32(ptr, 0);
    ptr = tev_write_u8(ptr, cast(u8) Tev_Display_Directive.Update_Image);
    ptr = tev_write_u8(ptr, cast(u8) 0);
    ptr = tev_write_string(ptr, title);
    ptr = tev_write_string(ptr, channel_name);
    ptr = tev_write_s32(ptr, cast(s32) tile_x);
    ptr = tev_write_s32(ptr, cast(s32) tile_y);
    ptr = tev_write_s32(ptr, cast(s32) tile_width);
    ptr = tev_write_s32(ptr, cast(s32) tile_height);

    for y: tile_y..tile_y + tile_height - 1 {
        for x: tile_x..tile_x + tile_width - 1 {
            rgb := tev_film_rgb(film, x, y);
            ptr = tev_write_float(ptr, tev_channel_value(rgb, channel_index));
        }
    }

    return tev_send(connection, message);
}

tev_display_item_display :: (item: *Tev_Display_Item, connection: *Tev_Display_Connection,
                             film: *Film) -> bool {
    if !item.opened_image {
        if !tev_send_create_image(connection, item.title, item.width, item.height) return false;
        item.opened_image = true;
    }

    channels := string.["R", "G", "B"];
    tile_index := 0;
    tile_y := 0;
    while tile_y < item.height {
        tile_height := min(TEV_TILE_SIZE, item.height - tile_y);
        tile_x := 0;
        while tile_x < item.width {
            tile_width := min(TEV_TILE_SIZE, item.width - tile_x);
            for channel_index: 0..channels.count - 1 {
                hash_index := tile_index * channels.count + channel_index;
                hash := tev_hash_tile(film, channel_index, tile_x, tile_y, tile_width, tile_height);
                if hash != item.tile_hashes[hash_index] {
                    if !tev_send_update_tile(connection, film, item.title, channels[channel_index],
                                             channel_index, tile_x, tile_y, tile_width, tile_height) {
                        item.opened_image = false;
                        return false;
                    }
                    item.tile_hashes[hash_index] = hash;
                }
            }
            tile_x += TEV_TILE_SIZE;
            tile_index += 1;
        }
        tile_y += TEV_TILE_SIZE;
    }

    return true;
}

display_film_in_tev :: (film: *Film, title: string = "Jai Render",
                        address: string = TEV_DEFAULT_ADDRESS, grab_focus := true) -> bool {
    connection := tev_connect(address);
    if !connection.connected return false;
    defer tev_disconnect(*connection);

    item := make_tev_display_item(title, film.width, film.height);
    defer free_tev_display_item(*item);

    if grab_focus {
        if !tev_send_create_image(*connection, title, film.width, film.height, true) return false;
        item.opened_image = true;
    }

    return tev_display_item_display(*item, *connection, film);
}
