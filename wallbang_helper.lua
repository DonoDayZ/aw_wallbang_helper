-- Wallbang Helper by ShadyRetard
local WALLBANG_STAND_RADIUS = 20;
local WALK_SPEED = 100;
local WB_ACTION_COOLDOWN = 30;
local GAME_COMMAND_COOLDOWN = 40;
local WALLBANG_SAVE_FILE_NAME = "wallbang_helper_data.dat";

local maps = {}

local WB_WINDOW_ACTIVE = gui.Checkbox(gui.Reference("VISUALS", "MISC", "Assistance"), "WB_WINDOW_ACTIVE", "Wallbang Helper", false);
local WB_WINDOW = gui.Window("WB_WINDOW", "Wallbang Helper", 200, 200, 450, 200);
local WB_NEW_WALLBANG_GB = gui.Groupbox(WB_WINDOW, "Add wallbang", 15, 15, 200, 150);
local WB_ENABLE_KEYBINDS = gui.Checkbox(WB_NEW_WALLBANG_GB, "WB_ENABLE_KEYBINDS", "Enable Add Keybinds", false);
local WB_ADD_KB = gui.Keybox(WB_NEW_WALLBANG_GB, "WB_ADD_KB", "Add key", "");
local WB_DEL_KB = gui.Keybox(WB_NEW_WALLBANG_GB, "WB_DEL_KB", "Remove key", "");

local WB_SETTINGS_GB = gui.Groupbox(WB_WINDOW, "Settings", 230, 15, 200, 150);
local WB_HELPER_ENABLED = gui.Checkbox(WB_SETTINGS_GB, "WB_HELPER_ENABLED", "Enable Wallbang Helper", false);
local WB_VISUALS_DISTANCE_SL = gui.Slider(WB_SETTINGS_GB, "WB_VISUALS_DISTANCE_SL", "Display Distance", 800, 1, 9999);
local WB_VISUALS_MARKER_DISTANCE_SL = gui.Slider(WB_SETTINGS_GB, "WB_VISUALS_MARKER_DISTANCE_SL", "Marker Distance", 200, 1, 9999);

local window_show = false;
local window_cb_pressed = true;
local last_action = globals.TickCount();
local my_last_load = globals.TickCount();
local screen_w, screen_h = 0, 0;

-- Just open up the file in append mode, should create the file if it doesn't exist and won't override anything if it does
local my_file = file.Open(WALLBANG_SAVE_FILE_NAME, "a");
my_file:Close();

local current_map_name;

function drawEventHandler()
    showWindow();

    if (WB_HELPER_ENABLED:GetValue() == false) then
        return;
    end

    screen_w, screen_h = draw.GetScreenSize();
    if (my_last_load ~= nil and my_last_load > globals.TickCount()) then
        my_last_load = globals.TickCount();
    end

    if (globals.TickCount() - my_last_load > 150) then
        loadData();
    end

    local active_map_name = engine.GetMapName();

    -- If we don't have an active map, stop
    if (active_map_name == nil or maps == nil) then
        return;
    end

    if (maps[active_map_name] == nil) then
        maps[active_map_name] = {};
    end

    if (current_map_name ~= active_map_name) then
        current_map_name = active_map_name;
    end

    if (maps[current_map_name] == nil) then
        return;
    end

    showWallbangSpots();
end

function moveEventHandler(cmd)
    if (WB_HELPER_ENABLED:GetValue() == false) then
        return;
    end

    local me = entities.GetLocalPlayer();
    if (current_map_name == nil or maps == nil or maps[current_map_name] == nil or me == nil or not me:IsAlive()) then
        return;
    end

    local add_keybind = WB_ADD_KB:GetValue();
    local del_keybind = WB_DEL_KB:GetValue();
    if (WB_ENABLE_KEYBINDS:GetValue() == false or (add_keybind == 0 and del_keybind == 0)) then
        return;
    end

    if (last_action ~= nil and last_action > globals.TickCount()) then
        last_action = globals.TickCount();
    end

    if (add_keybind ~= 0 and input.IsButtonDown(add_keybind) and globals.TickCount() - last_action > WB_ACTION_COOLDOWN) then
        last_action = globals.TickCount();
        return doAdd(cmd);
    end

    local closest_wallbang, distance = getClosestWallbangSpot(maps[current_map_name], me, cmd);
    if (closest_wallbang == nil or distance > WALLBANG_STAND_RADIUS) then
        return;
    end

    if (del_keybind ~= 0 and input.IsButtonDown(del_keybind) and globals.TickCount() - last_action > WB_ACTION_COOLDOWN) then
        last_action = globals.TickCount();
        return doDel(closest_wallbang);
    end
end

function showWindow()
    window_show = WB_WINDOW_ACTIVE:GetValue();

    if input.IsButtonPressed(gui.GetValue("msc_menutoggle")) then
        window_cb_pressed = not window_cb_pressed;
    end

    if (window_show and window_cb_pressed) then
        WB_WINDOW:SetActive(1);
    else
        WB_WINDOW:SetActive(0);
    end
end

function loadData()
    local data_file = file.Open(WALLBANG_SAVE_FILE_NAME, "r");
    if (data_file == nil) then
        return;
    end

    local wallbang_data = data_file:Read();
    data_file:Close();
    if (wallbang_data ~= nil and wallbang_data ~= "") then
        maps = parseStringifiedTable(wallbang_data);
    end
end

function doAdd(cmd)
    local me = entities.GetLocalPlayer();
    if (current_map_name == nil or maps[current_map_name] == nil or me == nil or not me:IsAlive()) then
        return;
    end

    local my_x, my_y, my_z = me:GetAbsOrigin();
    local ax, ay, az = cmd:GetViewAngles();

    table.insert(maps[current_map_name], {
        x = my_x,
        y = my_y,
        z = my_z,
        ax = ax,
        ay = ay
    });

    local value = convertTableToDataString(maps);
    local data_file = file.Open(WALLBANG_SAVE_FILE_NAME, "w");
    if (data_file ~= nil) then
        data_file:Write(value);
        data_file:Close();
    end
end

function doDel(wallbang)
    if (current_map_name == nil or maps[current_map_name] == nil) then
        return;
    end

    removeFirstWallbang(wallbang);

    local value = convertTableToDataString(maps);
    local data_file = file.Open(WALLBANG_SAVE_FILE_NAME, "w");
    if (data_file ~= nil) then
        data_file:Write(value);
        data_file:Close();
    end
end

function showWallbangSpots()
    local me = entities:GetLocalPlayer();

    if (me == nil) then
        return;
    end

    local wallbangs_to_show, within_distance = getActiveWallbangs(maps[current_map_name], me);

    for i = 1, #wallbangs_to_show do
        local wallbang = wallbangs_to_show[i];
        local cx, cy = client.WorldToScreen(wallbang.x, wallbang.y, wallbang.z);
        local clr_esp_skeleton_r, clr_esp_skeleton_g, clr_esp_skeleton_b, clr_esp_skeleton_a = gui.GetValue('clr_esp_skeleton');
        local clr_esp_box_t_vis_r, clr_esp_box_t_vis_g, clr_esp_box_t_vis_b, clr_esp_box_t_vis_a = gui.GetValue('clr_esp_box_t_vis');
        local esp_box_t_invis_r, esp_box_t_invis_g, esp_box_t_invis_b, esp_box_t_invis_a = gui.GetValue('clr_esp_box_t_invis');

        if (within_distance) then
            local z_offset = 64;
            if (wallbang.type == "crouch") then
                z_offset = 46;
            end

            local t_x, t_y, t_z = getWallbangPosition(wallbang.x, wallbang.y, wallbang.z, wallbang.ax, wallbang.ay, z_offset);
            local draw_x, draw_y = client.WorldToScreen(t_x, t_y, t_z);
            if (draw_x ~= nil and draw_y ~= nil) then
                draw.Color(esp_box_t_invis_r, esp_box_t_invis_g, esp_box_t_invis_b, esp_box_t_invis_a);
                draw.RoundedRect(draw_x - 10, draw_y - 10, draw_x + 10, draw_y + 10);

                -- Draw a line from the center of our screen to the wallbang position
                draw.Color(clr_esp_skeleton_r, clr_esp_skeleton_g, clr_esp_skeleton_b, clr_esp_skeleton_a);
                draw.Line(draw_x, draw_y, screen_w / 2, screen_h / 2);
            end
        end

        local ulx, uly = client.WorldToScreen(wallbang.x - WALLBANG_STAND_RADIUS / 2, wallbang.y - WALLBANG_STAND_RADIUS / 2, wallbang.z);
        local blx, bly = client.WorldToScreen(wallbang.x - WALLBANG_STAND_RADIUS / 2, wallbang.y + WALLBANG_STAND_RADIUS / 2, wallbang.z);
        local urx, ury = client.WorldToScreen(wallbang.x + WALLBANG_STAND_RADIUS / 2, wallbang.y - WALLBANG_STAND_RADIUS / 2, wallbang.z);
        local brx, bry = client.WorldToScreen(wallbang.x + WALLBANG_STAND_RADIUS / 2, wallbang.y + WALLBANG_STAND_RADIUS / 2, wallbang.z);

        if (cx ~= nil and cy ~= nil and ulx ~= nil and uly ~= nil and blx ~= nil and bly ~= nil and urx ~= nil and ury ~= nil and brx ~= nil and bry ~= nil) then
            local alpha = 0;
            if (wallbang.distance < WB_VISUALS_DISTANCE_SL:GetValue()) then
                alpha = (1 - wallbang.distance / WB_VISUALS_DISTANCE_SL:GetValue()) * esp_box_t_invis_a;
            end

            -- Show radius as green when in distance, blue otherwise
            if (within_distance) then
                draw.Color(esp_box_t_invis_r, esp_box_t_invis_g, esp_box_t_invis_b, esp_box_t_invis_a);
            else
                draw.Color(clr_esp_box_t_vis_r, clr_esp_box_t_vis_g, clr_esp_box_t_vis_b, alpha);
            end

            -- Top left to rest
            draw.Line(ulx, uly, blx, bly);
            draw.Line(ulx, uly, urx, ury);
            draw.Line(ulx, uly, brx, bry);

            -- Bottom right to rest
            draw.Line(brx, bry, blx, bly);
            draw.Line(brx, bry, urx, ury);

            -- Diagonal
            draw.Line(blx, bly, urx, ury);
        end
    end
end

function getWallbangPosition(pos_x, pos_y, pos_z, ax, ay, z_offset)
    return pos_x - WB_VISUALS_MARKER_DISTANCE_SL:GetValue() * math.cos(math.rad(ay + 180)), pos_y - WB_VISUALS_MARKER_DISTANCE_SL:GetValue() * math.sin(math.rad(ay + 180)), pos_z - WB_VISUALS_MARKER_DISTANCE_SL:GetValue() * math.tan(math.rad(ax)) + z_offset;
end

function getDistanceToTarget(my_x, my_y, my_z, t_x, t_y, t_z)
    local dx = my_x - t_x;
    local dy = my_y - t_y;
    local dz = my_z - t_z;
    return math.sqrt(dx ^ 2 + dy ^ 2 + dz ^ 2);
end

function getActiveWallbangs(map, me)
    local wallbangs = {};
    local wallbangs_in_distance = {};
    -- Determine if any are within range, we should only show those if that's the case
    for i = 1, #map do
        local wallbang = map[i];
        local my_x, my_y, my_z = me:GetAbsOrigin();
        local distance = getDistanceToTarget(my_x, my_y, wallbang.z, wallbang.x, wallbang.y, wallbang.z);
        wallbang.distance = distance;
        if (distance < WALLBANG_STAND_RADIUS) then
            table.insert(wallbangs_in_distance, wallbang);
        else
            table.insert(wallbangs, wallbang);
        end
    end

    if (#wallbangs_in_distance > 0) then
        return wallbangs_in_distance, true;
    end

    return wallbangs, false;
end

function getClosestWallbangSpot(map, me, cmd)
    local closest_wallbang;
    local closest_distance;
    local closest_distance_from_center;
    local my_x, my_y, my_z = me:GetAbsOrigin();
    for i = 1, #map do
        local wallbang = map[i];
        local distance = getDistanceToTarget(my_x, my_y, wallbang.z, wallbang.x, wallbang.y, wallbang.z);
        local z_offset = 64;
        local pos_x, pos_y, pos_z = getWallbangPosition(wallbang.x, wallbang.y, wallbang.z, wallbang.ax, wallbang.ay, z_offset);
        local draw_x, draw_y = client.WorldToScreen(pos_x, pos_y, pos_z);
        local distance_from_center;

        if (draw_x ~= nil and draw_y ~= nil) then
            distance_from_center = math.abs(screen_w / 2 - draw_x + screen_h / 2 - draw_y);
        end

        if (closest_distance == nil
                or (distance <= WALLBANG_STAND_RADIUS
                and (closest_distance_from_center == nil
                or (closest_distance_from_center ~= nil and distance_from_center ~= nil and distance_from_center < closest_distance_from_center)))
                or ((closest_distance_from_center == nil and distance < closest_distance))) then
            closest_wallbang = wallbang;
            closest_distance = distance;
            closest_distance_from_center = distance_from_center;
        end
    end

    return closest_wallbang, closest_distance;
end

function parseStringifiedTable(stringified_table)
    local new_map = {};
    for i in string.gmatch(stringified_table, "([^;]*);") do
        local matches = {};
        string.gmatch(i, "(.*),")

        for word in string.gmatch(i, "([^,]*)") do
            table.insert(matches, word);
        end

        local map_name = matches[1];
        if new_map[map_name] == nil then
            new_map[map_name] = {};
        end

        table.insert(new_map[map_name], {
            x = tonumber(matches[2]),
            y = tonumber(matches[3]),
            z = tonumber(matches[4]),
            ax = tonumber(matches[5]),
            ay = tonumber(matches[6])
        });
    end
    return new_map;
end

function convertTableToDataString(object)
    local converted = "";
    for map_name, map in pairs(object) do
        for i, wallbang in ipairs(map) do
            if (wallbang ~= nil) then
                converted = converted .. map_name .. ',' .. wallbang.x .. ',' .. wallbang.y .. ',' .. wallbang.z .. ',' .. wallbang.ax .. ',' .. wallbang.ay .. ';'
            end
        end
    end

    return converted;
end

function hasValue(tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end

function removeFirstWallbang(wallbang)
    for i, v in ipairs(maps[current_map_name]) do
        if (v.x == wallbang.x and v.y == wallbang.y and v.z == wallbang.z and v.ax == wallbang.ax and v.ay == wallbang.ay) then
            return table.remove(maps[current_map_name], i);
        end
    end
end

callbacks.Register("CreateMove", "WB_MOVE", moveEventHandler);
callbacks.Register("Draw", "WB_DRAW", drawEventHandler);