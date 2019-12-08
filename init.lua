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
	local item_name = stack:get_name()
	if not technic.power_tools[item_name] then
		return false
	end
	if item_name:find("powerbanks:powerbank") then
		return false
	end
	return true
end

local function register_powerbank(data)

	local formspec =
		"size[8,6]" ..
		"list[current_name;main;0,0.25;4,1;]" ..
		"list[current_player;main;0,2;8,4;]" ..
		"listring[current_name;main]" ..
		"listring[current_player;main]" ..
		"image[5.4,0.2;3,1;powerbanks_battery_bg.png]"

	local function update_formspec(pos, charge)
		local fraction = charge / data.max_charge

		local red = math.min(510 - (510 * fraction), 255)
		local green = math.min(510 * fraction, 255)
		local color = "#"..string.format("%02X", red)..string.format("%02X", green).."00FF"

		local new_formspec = formspec..
			"box[5.45,0.25;"..(fraction * 2.12)..",0.8;"..color.."]"

		minetest.get_meta(pos):set_string("formspec", new_formspec)
		return true
	end

	local function update_infotext(pos, is_charging)
		local meta = minetest.get_meta(pos)
		local current_charge = technic.EU_string(meta:get_int("charge"))
		local max_charge = technic.EU_string(data.max_charge)
		local status = "Idle"
		if is_charging then
			status = "Charging"
		end
		local infotext = "Powerbank Mk"..data.mark..": "..current_charge.." / "..max_charge.." "..status
		meta:set_string("infotext", infotext)
	end

	local function charge_item(item, powerbank_charge, charge_step)
		local item_meta = minetest.deserialize(item:get_metadata()) or {}
		if not item_meta.charge then
			item_meta.charge = 0
		end
		local item_max_charge = technic.power_tools[item:get_name()]
		local item_charge = item_meta.charge

		charge_step = math.min(charge_step, item_max_charge - item_charge, powerbank_charge)
		item_charge = item_charge + charge_step
		powerbank_charge = powerbank_charge - charge_step

		technic.set_RE_wear(item, item_charge, item_max_charge)
		item_meta.charge = item_charge
		item:set_metadata(minetest.serialize(item_meta))

		return item, powerbank_charge, (item_charge == item_max_charge)
	end

	local function do_charging(pos, charge_step)
		local meta = minetest.get_meta(pos)
		local current_charge = meta:get_int("charge")
		local inv = meta:get_inventory()
		local still_charging = false

		for i = 1, inv:get_size("main") do
			local stack = inv:get_stack("main", i)
			local item_fully_charged
			if (not stack:is_empty()) and (current_charge > 0) then
				stack, current_charge, item_fully_charged = charge_item(stack, current_charge, charge_step)
				inv:set_stack("main", i, stack)

				if not item_fully_charged then
					still_charging = true
				end
			end
		end

		meta:set_int("charge", current_charge)
		update_infotext(pos, still_charging)
		update_formspec(pos, current_charge)

		return still_charging and (current_charge > 0)
	end

	local function create_itemstack(metadata, is_node)
		if not metadata.charge then
			metadata.charge = 0
		end

		local extension = ""
		if is_node then
			extension = "_node"
		end

		local itemstack = ItemStack({
			name = "powerbanks:powerbank_mk"..data.mark..extension,
			count = 1,
			metadata = minetest.serialize({charge = metadata.charge})
		})

		if not is_node then
			technic.set_RE_wear(itemstack, metadata.charge, data.max_charge)
		end

		return itemstack
	end

	minetest.register_node("powerbanks:powerbank_mk"..data.mark.."_node", {
		description = "Powerbank Mk"..data.mark.." Node",
		tiles = {
			"powerbanks_base.png", -- y+ top
			"powerbanks_base.png", -- y- bottom
			"powerbanks_base.png^powerbanks_overlay_mk"..data.mark..".png", -- x+ right
			"powerbanks_base.png^powerbanks_overlay_mk"..data.mark..".png", -- x- left
			"powerbanks_base.png^powerbanks_overlay_mk"..data.mark..".png", -- z+ back
			"powerbanks_base.png^powerbanks_overlay_mk"..data.mark..".png" -- z- front
		},
		groups = {oddly_breakable_by_hand = 1, not_in_creative_inventory = 1},
		is_ground_content = false,
		drop = {},

		can_dig = function(pos, digger)
			if not digger then return end

			-- check if the digger is the owner
			local meta = minetest.get_meta(pos)
			if not is_owner(pos, digger) then
				minetest.chat_send_player(digger:get_player_name(), "Powerbank is owned by "..meta:get_string("owner"))
				return false
			end

			-- check if inventory is empty
			local node_inv = meta:get_inventory()
			if not node_inv:is_empty("main") then
				minetest.chat_send_player(digger:get_player_name(), "Powerbank cannot be removed because it is not empty")
				return false
			end

			return true
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

		after_place_node = function(pos, placer, itemstack, pointed_thing)
			local node_meta = minetest.get_meta(pos)
			local itemstack_meta = minetest.deserialize(itemstack:get_metadata()) or {}

			if not itemstack_meta.charge then
				itemstack_meta.charge = 0
			end

			-- set node metadata
			node_meta:get_inventory():set_size("main", data.charging_slots)
			node_meta:set_string("formspec", formspec)
			node_meta:set_string("owner", placer:get_player_name())
			node_meta:set_int("charge", itemstack_meta.charge)

			update_infotext(pos, false)
			update_formspec(pos, itemstack_meta.charge)
		end,

		on_metadata_inventory_put = function(pos, listname, index, stack, player)
			local timer = minetest.get_node_timer(pos)
			if not timer:is_started() then
				timer:start(charge_time) -- start charging item immediately
			end
		end,

		on_timer = function(pos, elapsed)
		local steps = math.floor((elapsed / charge_time) + 0.5)
			return do_charging(pos, steps * data.charge_step)
		end,

		after_dig_node = function(pos, node, metadata, player)
			-- create item to give player
			local item = create_itemstack({charge = metadata.fields.charge}, false)

			-- give the item, or drop if inventory is full
			local player_inv = player:get_inventory()
			if player_inv:room_for_item("main", item) then
				player_inv:add_item("main", item)
			else
				minetest.add_item(pos, item)
			end
		end
	})

	minetest.register_tool("powerbanks:powerbank_mk"..data.mark, {
		description = "Powerbank Mk"..data.mark,
		inventory_image = minetest.inventorycube(
			"powerbanks_base.png",
			"powerbanks_base.png^powerbanks_overlay_mk"..data.mark..".png",
			"powerbanks_base.png^powerbanks_overlay_mk"..data.mark..".png"
		),
		stack_max = 1,
		wear_represents = "technic_RE_charge",
		on_refill = technic.refill_RE_charge,

		on_place = function(itemstack, placer, pointed_thing)
			-- create fake itemstack of node to place
			local item_meta = minetest.deserialize(itemstack:get_metadata()) or {}
			local node_itemstack = create_itemstack(item_meta, true)

			-- place node like player
			local _, placed = minetest.item_place(node_itemstack, placer, pointed_thing)

			-- remove powerbank from inventory if placed
			if placed then
				itemstack:clear()
			end

			return itemstack
		end
	})

	technic.register_power_tool("powerbanks:powerbank_mk"..data.mark, data.max_charge)

	minetest.register_craft({
		output = "powerbanks:powerbank_mk"..data.mark,
		recipe = {
			{"technic:battery", "technic:battery", "technic:battery"},
			{"technic:stainless_steel_ingot", data.craft_base, "technic:stainless_steel_ingot"},
			{"", data.craft_crystal, ""},
		}
	})
end

register_powerbank({ -- Powerbank Mk1
	mark = 1,
	max_charge = 300000,
	charge_step = 3000,
	charging_slots = 1,
	craft_base = "technic:machine_casing",
	craft_crystal = "technic:red_energy_crystal",
})

register_powerbank({ -- Powerbank Mk2
	mark = 2,
	max_charge = 600000,
	charge_step = 6000,
	charging_slots = 2,
	craft_base = "powerbanks:powerbank_mk1",
	craft_crystal = "technic:green_energy_crystal"
})

register_powerbank({ -- Powerbank Mk3
	mark = 3,
	max_charge = 1200000,
	charge_step = 12000,
	charging_slots = 3,
	craft_base = "powerbanks:powerbank_mk2",
	craft_crystal = "technic:blue_energy_crystal"
})
