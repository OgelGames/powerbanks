
-- Translation support
local S = minetest.get_translator("powerbanks")

local charge_time = 1

local function is_owner(pos, player)
	local name = ""
	if player then
		name = player:get_player_name()
	end
	local owner = minetest.get_meta(pos):get_string("owner")
	if owner == "" or owner == name or minetest.check_player_privs(name, "protection_bypass") then
		return true
	end
	return false
end

local function is_chargeable(stack)
	local name = stack:get_name()
	if not technic.power_tools[name] or name:find("powerbanks:powerbank") then
		return false
	end
	return true
end

local base_formspec =
	"size[8,7.25]"..
	"list[context;main;0,1.25;4,1;]"..
	"list[current_player;main;0,3.5;8,4;]"..
	"listring[context;main]"..
	"listring[current_player;main]"..
	"image[5.4,1.2;3,1;powerbanks_battery_bg.png]"..
	"label[0,2.25;"..S("Charging Slots").."]"

local function update_formspec(pos, charge, data)
	local fraction = charge / data.max_charge
	local red = math.min(510 - (510 * fraction), 255)
	local green = math.min(510 * fraction, 255)
	local color = string.format("#%02X%02X00FF", red, green)

	local new_formspec = base_formspec..
		"label[0,0;"..S("Powerbank Mk@1", data.mark).."]"..
		"label[5.4,2.25;"..S("Power Remaining: @1", technic.pretty_num(charge)).."EU]"..
		"box[5.45,1.25;"..(fraction * 2.12)..",0.8;"..color.."]"

	minetest.get_meta(pos):set_string("formspec", new_formspec)
end

local function update_infotext(pos, is_charging, data)
	local meta = minetest.get_meta(pos)
	local current_charge = technic.pretty_num(meta:get_int("charge")).."EU"
	local max_charge = technic.pretty_num(data.max_charge).."EU"
	local status = is_charging and S("Charging") or S("Idle")

	local infotext = S("Powerbank Mk@1: @2 / @3 @4", data.mark, current_charge, max_charge, status)

	meta:set_string("infotext", infotext)
end

local function set_charge(stack, charge)
	local meta = stack:get_meta()
	local metadata = minetest.deserialize(meta:get_string("")) or {}
	metadata.charge = charge
	meta:set_string("", minetest.serialize(metadata))
	technic.set_RE_wear(stack, charge, technic.power_tools[stack:get_name()])
end

local function get_charge(stack)
	local meta = stack:get_meta()
	local metadata = minetest.deserialize(meta:get_string("")) or {}
	return metadata.charge or 0
end

if technic.plus then
	set_charge = technic.set_RE_charge
	get_charge = technic.get_RE_charge
end

local function charge_item(stack, powerbank_charge, charge_step)
	if not is_chargeable(stack) then
		return powerbank_charge, true
	end
	local item_max_charge = technic.power_tools[stack:get_name()]
	local item_charge = get_charge(stack)

	charge_step = math.min(charge_step, item_max_charge - item_charge, powerbank_charge)
	item_charge = item_charge + charge_step
	powerbank_charge = powerbank_charge - charge_step
	set_charge(stack, item_charge)

	return powerbank_charge, (item_charge == item_max_charge)
end

local function do_charging(pos, charge_step, data)
	local meta = minetest.get_meta(pos)
	local current_charge = meta:get_int("charge")
	local inv = meta:get_inventory()
	local still_charging = false

	for i=1, inv:get_size("main") do
		local stack = inv:get_stack("main", i)
		local item_fully_charged
		if current_charge > 0 and not stack:is_empty() then
			current_charge, item_fully_charged = charge_item(stack, current_charge, charge_step)
			inv:set_stack("main", i, stack)

			if not item_fully_charged then
				still_charging = true
			end
		end
	end

	meta:set_int("charge", current_charge)
	update_formspec(pos, current_charge, data)
	update_infotext(pos, still_charging, data)

	return still_charging and current_charge > 0
end

local function register_powerbank(data)
	local node_def =  {
		description = S("Powerbank Mk@1 Node", data.mark),
		tiles = {
			"powerbanks_base.png",
			"powerbanks_base.png",
			"powerbanks_base.png^powerbanks_overlay_mk"..data.mark..".png",
			"powerbanks_base.png^powerbanks_overlay_mk"..data.mark..".png",
			"powerbanks_base.png^powerbanks_overlay_mk"..data.mark..".png",
			"powerbanks_base.png^powerbanks_overlay_mk"..data.mark..".png"
		},
		groups = {not_in_creative_inventory = 1},
		is_ground_content = false,
		drop = "powerbanks:powerbank_mk"..data.mark,
		diggable = false,
		can_dig = function(pos, digger)
			return false
		end,
		allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
			if is_owner(pos, player) then
				return count
			end
			return 0
		end,
		allow_metadata_inventory_put = function(pos, listname, index, stack, player)
			if is_owner(pos, player) and is_chargeable(stack) then
				return stack:get_count()
			end
			return 0
		end,
		allow_metadata_inventory_take = function(pos, listname, index, stack, player)
			if is_owner(pos, player) then
				return stack:get_count()
			end
			return 0
		end,
		after_place_node = function(pos, player, stack, pointed)
			local meta = minetest.get_meta(pos)
			local charge = stack:get_meta():get_int("charge")

			meta:get_inventory():set_size("main", data.charging_slots)
			meta:set_string("owner", player:get_player_name())
			meta:set_int("charge", charge)

			update_formspec(pos, charge, data)
			update_infotext(pos, false, data)

			minetest.sound_play({name = "default_place_node_hard"}, {pos = pos})
		end,
		on_metadata_inventory_put = function(pos, listname, index, stack, player)
			local timer = minetest.get_node_timer(pos)
			if not timer:is_started() then
				timer:start(charge_time)  -- Start charging item
			end
		end,
		on_timer = function(pos, elapsed)
			local steps = math.floor((elapsed / charge_time) + 0.5)
			return do_charging(pos, steps * data.charge_step, data)
		end,
		on_punch = function(pos, node, player)
			if not player then return end
			local meta = minetest.get_meta(pos)

			if not is_owner(pos, player) then
				minetest.chat_send_player(player:get_player_name(),
					S("Powerbank is owned by @1", meta:get_string("owner"))
				)
				return
			end

			local node_inv = meta:get_inventory()
			if not node_inv:is_empty("main") then
				minetest.chat_send_player(player:get_player_name(),
					S("Powerbank cannot be removed because it is not empty")
				)
				return
			end

			-- Create item to give player
			local stack = ItemStack("powerbanks:powerbank_mk"..data.mark)
			set_charge(stack, meta:get_int("charge"))

			-- Give the item, or drop if inventory is full
			local player_inv = player:get_inventory()
			if player_inv:room_for_item("main", stack) then
				player_inv:add_item("main", stack)
			else
				minetest.add_item(pos, stack)
			end

			minetest.sound_play({name = "default_dug_node"}, {pos = pos})
			minetest.remove_node(pos)
		end
	}

	local tool_def = {
		description = S("Powerbank Mk@1", data.mark),
		inventory_image = minetest.inventorycube(
			"powerbanks_base.png",
			"powerbanks_base.png^powerbanks_overlay_mk"..data.mark..".png",
			"powerbanks_base.png^powerbanks_overlay_mk"..data.mark..".png"
		),
		max_charge = data.max_charge,
		on_place = function(stack, player, pointed)
			-- Check for on_rightclick if player is not holding sneak
			if pointed.type == "node" and player and not player:get_player_control().sneak then
				local node = minetest.get_node(pointed.under)
				local def = minetest.registered_nodes[node.name]
				if def and def.on_rightclick then
					return def.on_rightclick(pointed.under, node, player, stack, pointed) or stack, false
				end
			end

			-- Create fake node itemstack and place like player
			local node_stack = ItemStack("powerbanks:powerbank_mk"..data.mark.."_node")
			node_stack:get_meta():set_int("charge", get_charge(stack))
			local new_stack, placed = minetest.item_place_node(node_stack, player, pointed)

			if placed or new_stack:is_empty() then
				stack:clear()
			end
			return stack, placed
		end
	}

	minetest.register_node("powerbanks:powerbank_mk"..data.mark.."_node", node_def)

	if technic.plus then
		technic.register_power_tool("powerbanks:powerbank_mk"..data.mark, tool_def)
	else
		tool_def.wear_represents = "technic_RE_charge"
		tool_def.on_refill = technic.refill_RE_charge
		minetest.register_tool("powerbanks:powerbank_mk"..data.mark, tool_def)
		technic.register_power_tool("powerbanks:powerbank_mk"..data.mark, data.max_charge)
	end

	minetest.register_craft({
		output = "powerbanks:powerbank_mk"..data.mark,
		recipe = {
			{"technic:battery", "technic:battery", "technic:battery"},
			{"technic:stainless_steel_ingot", data.craft_base, "technic:stainless_steel_ingot"},
			{"", data.craft_crystal, ""},
		}
	})
end

register_powerbank({  -- Powerbank Mk1
	mark = 1,
	max_charge = 300000,
	charge_step = 3000,
	charging_slots = 1,
	craft_base = "technic:machine_casing",
	craft_crystal = "technic:red_energy_crystal",
})

register_powerbank({  -- Powerbank Mk2
	mark = 2,
	max_charge = 600000,
	charge_step = 6000,
	charging_slots = 2,
	craft_base = "powerbanks:powerbank_mk1",
	craft_crystal = "technic:green_energy_crystal"
})

register_powerbank({  -- Powerbank Mk3
	mark = 3,
	max_charge = 1200000,
	charge_step = 12000,
	charging_slots = 3,
	craft_base = "powerbanks:powerbank_mk2",
	craft_crystal = "technic:blue_energy_crystal"
})
