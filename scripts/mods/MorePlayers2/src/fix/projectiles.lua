-- luacheck: globals get_mod Unit Vector3 Actor DamageUtils Managers ScriptUnit
-- luacheck: globals DefaultPowerLevel NetworkLookup DamageProfileTemplates
-- luacheck: globals ActionUtils Quaternion AiUtils StatusUtils AttackTemplates
-- luacheck: globals ProjectileImpactDataIndex NetworkConstants PlayerProjectileUnitExtension
-- luacheck: globals EffectHelper BoostCurves DamageOutput
local mod = get_mod("MorePlayers2")

-- WOW
-- Some big functions that need very targetted fixes: checking `hit_zone`
-- exists before indexing it. I have no idea _why_ hit_zone doesn't exist
-- sometimes with more players. But it does and this dumb null check stops
-- it from crashing. No one has complained about this being a bug yet so
-- I think it's safe to ignore.

local INDEX_POSITION = 1
local INDEX_NORMAL = 3
local INDEX_ACTOR = 4
local HIT_UNITS = {}
local HIT_DATA = {}
local unit_get_data = Unit.get_data
local unit_alive = Unit.alive
local unit_actor = Unit.actor
local actor_unit = Actor.unit
local actor_node = Actor.node
mod:hook_origin(DamageUtils, "process_projectile_hit", function (world, damage_source, owner_unit, is_server, raycast_result, current_action, direction, check_buffs, target, ignore_list, is_critical_strike, power_level, override_damage_profile, target_number)
  table.clear(HIT_UNITS)
  table.clear(HIT_DATA)

  local hit_units = HIT_UNITS
  local hit_data = HIT_DATA
  local attack_direction = direction
  local owner_player = owner_unit and Managers.player:owner(owner_unit)
  local damage_source_id = NetworkLookup.damage_sources[damage_source]
  local check_backstab = false
  local difficulty_settings = Managers.state.difficulty:get_difficulty_settings()
  local owner_buff_extension = ScriptUnit.has_extension(owner_unit, "buff_system")
  local amount_of_mass_hit = 0
  local num_penetrations = 0
  local predicted_damage, shield_blocked = nil
  power_level = power_level or DefaultPowerLevel
  local damage_profile_name = override_damage_profile or current_action.damage_profile or "default"
  local damage_profile_id = NetworkLookup.damage_profiles[damage_profile_name]
  local damage_profile = DamageProfileTemplates[damage_profile_name]
  local difficulty_level = Managers.state.difficulty:get_difficulty()
  local cleave_power_level = ActionUtils.scale_power_levels(power_level, "cleave", owner_unit, difficulty_level)
  local max_targets_attack, max_targets_impact = ActionUtils.get_max_targets(damage_profile, cleave_power_level)

  if owner_buff_extension and (not override_damage_profile or not override_damage_profile.no_procs) then
    owner_buff_extension:trigger_procs("on_ranged_hit")
  end

  local _, ranged_boost_curve_multiplier = ActionUtils.get_ranged_boost(owner_unit)
  local max_targets = (max_targets_impact < max_targets_attack and max_targets_attack) or max_targets_impact
  local owner_is_bot = owner_player and owner_player.bot_player
  local is_husk = (owner_is_bot and true) or false
  local hit_effect = current_action.hit_effect
  local critical_hit_effect = current_action.critical_hit_effect
  local num_hits = #raycast_result
  hit_data.hits = num_penetrations
  local friendly_fire_disabled = damage_profile.no_friendly_fire
  local forced_friendly_fire = damage_profile.always_hurt_players
  local difficulty_rank = Managers.state.difficulty:get_difficulty_rank()
  local allow_friendly_fire = forced_friendly_fire or (not friendly_fire_disabled and DamageUtils.allow_friendly_fire_ranged(difficulty_settings, owner_player))
  local side_manager = Managers.state.side
  local player_manager = Managers.player

  for i = 1, num_hits, 1 do
    repeat
      local hit = raycast_result[i]
      local hit_position = hit[INDEX_POSITION]
      local hit_normal = hit[INDEX_NORMAL]
      local hit_actor = hit[INDEX_ACTOR]
      local hit_valid_target = hit_actor ~= nil
      local hit_unit = (hit_valid_target and actor_unit(hit_actor)) or nil

      if not unit_alive(hit_unit) or Unit.is_frozen(hit_unit) then
        hit_valid_target = false
        hit_unit = nil
      else
        hit_unit, hit_actor = ActionUtils.redirect_shield_hit(hit_unit, hit_actor)
      end

      local attack_hit_self = hit_unit == owner_unit

      if attack_hit_self or not hit_valid_target then
        break
      end

      local target_settings = (damage_profile.targets and damage_profile.targets[num_penetrations + 1]) or damage_profile.default_target
      local hit_rotation = Quaternion.look(hit_normal)
      local is_target = hit_unit == target or target == nil
      local breed = AiUtils.unit_breed(hit_unit)
      local hit_zone_name = nil

      if breed then
        local node = actor_node(hit_actor)
        local hit_zone = breed.hit_zones_lookup[node]
        -- MODIFIED. Check if hit_zone exists before indexing it
        if hit_zone then
          hit_zone_name = hit_zone.name

          if ignore_list and ignore_list[hit_unit] and hit_zone_name ~= "afro" then
            return hit_data
          end
        end
      end

      local is_player = player_manager:is_player_unit(hit_unit)
      local is_character = breed or is_player
      local block_processing = false

      if is_character and owner_player then
        local side = side_manager.side_by_unit[hit_unit]
        local owner_side = side_manager.side_by_unit[owner_unit]

        if side and owner_side and side.side_id == owner_side.side_id then
          block_processing = not allow_friendly_fire
        end
      end

      if not is_character then
        amount_of_mass_hit = DamageUtils._projectile_hit_object(current_action, owner_unit, owner_player, owner_buff_extension, target_settings, hit_unit, hit_actor, hit_position, hit_rotation, hit_normal, is_husk, breed, is_server, check_buffs, check_backstab, is_critical_strike, difficulty_rank, power_level, ranged_boost_curve_multiplier, damage_profile, damage_source, critical_hit_effect, world, hit_effect, attack_direction, damage_source_id, damage_profile_id, max_targets, num_penetrations, amount_of_mass_hit)

        if hit_data.stop then
          hit_data.hit_unit = hit_unit
          hit_data.hit_actor = hit_actor
          hit_data.hit_position = hit_position
          hit_data.hit_direction = attack_direction

          return hit_data
        end
      elseif not hit_units[hit_unit] and is_target and not block_processing then
        amount_of_mass_hit, num_penetrations, predicted_damage, shield_blocked = DamageUtils._projectile_hit_character(current_action, owner_unit, owner_player, owner_buff_extension, target_settings, hit_unit, hit_actor, hit_position, hit_rotation, hit_normal, is_husk, breed, is_server, check_buffs, is_critical_strike, difficulty_rank, power_level, ranged_boost_curve_multiplier, damage_profile, damage_source, critical_hit_effect, world, hit_effect, attack_direction, damage_source_id, damage_profile_id, max_targets, num_penetrations, amount_of_mass_hit, target_number)

        if hit_data.stop then
          hit_data.hit_unit = hit_unit
          hit_data.hit_actor = hit_actor
          hit_data.hit_position = hit_position
          hit_data.hit_direction = attack_direction
          hit_data.predicted_damage = predicted_damage
          hit_data.shield_blocked = shield_blocked
          hit_data.hit_player = is_player

          return hit_data
        end
      end
    until true
  end

  return hit_data
end)

mod:hook_origin(DamageUtils, "_projectile_hit_character", function (current_action, owner_unit, owner_player, owner_buff_extension, target_settings, hit_unit, hit_actor, hit_position, hit_rotation, hit_normal, is_husk, breed, is_server, check_buffs, is_critical_strike, difficulty_rank, power_level, ranged_boost_curve_multiplier, damage_profile, damage_source, critical_hit_effect, world, hit_effect, attack_direction, damage_source_id, damage_profile_id, max_targets, current_num_penetrations, current_amount_of_mass_hit, target_number)
  local hit_units = HIT_UNITS
  local hit_data = HIT_DATA
  local network_manager = Managers.state.network
  local attacker_unit_id, attacker_is_level_unit = network_manager:game_object_or_level_id(owner_unit)
  local hit_unit_id, _ = network_manager:game_object_or_level_id(hit_unit)
  local hit_zone_name = "torso"
  local predicted_damage = 0
  local shield_blocked = false
  local num_penetrations = current_num_penetrations
  local amount_of_mass_hit = current_amount_of_mass_hit

  if breed then
    local node = actor_node(hit_actor)
    local hit_zone = breed.hit_zones_lookup[node]
    -- MODIFIED: Check for hit_zone before indexing it
    if hit_zone then
      hit_zone_name = hit_zone.name

      if hit_zone_name ~= "afro" then
        shield_blocked = AiUtils.attack_is_shield_blocked(hit_unit, owner_unit) and not current_action.ignore_shield_hit

        if shield_blocked then
          hit_data.blocked_by_unit = hit_unit
        end
      end
    end
  end

  if current_action.hit_zone_override and hit_zone_name ~= "afro" then
    hit_zone_name = current_action.hit_zone_override
  end

  if breed and hit_zone_name == "head" and owner_player and not shield_blocked then
    local first_person_extension = ScriptUnit.extension(owner_unit, "first_person_system")
    local _, procced = owner_buff_extension:apply_buffs_to_value(0, "coop_stamina")

    if procced and AiUtils.unit_alive(hit_unit) then
      local headshot_coop_stamina_fatigue_type = breed.headshot_coop_stamina_fatigue_type or "headshot_clan_rat"
      local fatigue_type_id = NetworkLookup.fatigue_types[headshot_coop_stamina_fatigue_type]

      if is_server then
        network_manager.network_transmit:send_rpc_clients("rpc_replenish_fatigue_other_players", fatigue_type_id)
      else
        network_manager.network_transmit:send_rpc_server("rpc_replenish_fatigue_other_players", fatigue_type_id)
      end

      StatusUtils.replenish_stamina_local_players(owner_unit, headshot_coop_stamina_fatigue_type)
      first_person_extension:play_hud_sound_event("hud_player_buff_headshot", nil, false)
    end

    if not current_action.no_headshot_sound and AiUtils.unit_alive(hit_unit) then
      first_person_extension:play_hud_sound_event("Play_hud_headshot", nil, false)
    end
  end

  local hit_unit_player = Managers.player:owner(hit_unit)

  if hit_zone_name == "afro" then
    if breed.is_ai then
      local attacker_is_player = Managers.player:owner(owner_unit)

      if attacker_is_player then
        if is_server then
          if ScriptUnit.has_extension(hit_unit, "ai_system") then
            AiUtils.alert_unit_of_enemy(hit_unit, owner_unit)
          end
        else
          network_manager.network_transmit:send_rpc_server("rpc_alert_enemy", hit_unit_id, attacker_unit_id)
        end
      end
    end
  elseif hit_unit_player and hit_actor == unit_actor(hit_unit, "c_afro") then
    local afro_hit_sound = current_action.afro_hit_sound

    if afro_hit_sound and not hit_unit_player.bot_player and Managers.state.network:game() then
      local sound_id = NetworkLookup.sound_events[afro_hit_sound]

      network_manager.network_transmit:send_rpc("rpc_play_first_person_sound", hit_unit_player.peer_id, hit_unit_id, sound_id, hit_position)
    end
  else
    hit_units[hit_unit] = true
    local hit_zone_id = NetworkLookup.hit_zones[hit_zone_name]
    local attack_template_name = target_settings.attack_template
    local attack_template = AttackTemplates[attack_template_name]

    if owner_player and breed and check_buffs and not shield_blocked then
      local send_to_server = true
      local buff_type = DamageUtils.get_item_buff_type(damage_source)
      local buffs_checked = DamageUtils.buff_on_attack(owner_unit, hit_unit, "instant_projectile", is_critical_strike, hit_zone_name, target_number or num_penetrations + 1, send_to_server, buff_type)
      hit_data.buffs_checked = hit_data.buffs_checked or buffs_checked
    end

    local target_health_extension = ScriptUnit.extension(hit_unit, "health_system")

    if breed and target_health_extension:is_alive() then
      local action_mass_override = current_action.hit_mass_count

      if action_mass_override and action_mass_override[breed.name] then
        local mass_cost = current_action.hit_mass_count[breed.name]
        amount_of_mass_hit = amount_of_mass_hit + (mass_cost or 1)
      else
        amount_of_mass_hit = amount_of_mass_hit + ((shield_blocked and ((breed.hit_mass_counts_block and breed.hit_mass_counts_block[difficulty_rank]) or breed.hit_mass_count_block)) or (breed.hit_mass_counts and breed.hit_mass_counts[difficulty_rank]) or breed.hit_mass_count or 1)
      end
    end

    local actual_target_index = math.ceil(amount_of_mass_hit)
    local damage_sound = attack_template.sound_type
    predicted_damage = DamageUtils.calculate_damage(DamageOutput, hit_unit, owner_unit, hit_zone_name, power_level, BoostCurves[target_settings.boost_curve_type], ranged_boost_curve_multiplier, is_critical_strike, damage_profile, actual_target_index, nil, damage_source)
    local no_damage = predicted_damage <= 0

    if breed and not breed.is_hero then
      local enemy_type = breed.name

      if is_critical_strike and critical_hit_effect then
        EffectHelper.play_skinned_surface_material_effects(critical_hit_effect, world, hit_unit, hit_position, hit_rotation, hit_normal, is_husk, enemy_type, damage_sound, no_damage, hit_zone_name, shield_blocked)
      else
        EffectHelper.play_skinned_surface_material_effects(hit_effect, world, hit_unit, hit_position, hit_rotation, hit_normal, is_husk, enemy_type, damage_sound, no_damage, hit_zone_name, shield_blocked)
      end

      if Managers.state.network:game() then
        if is_critical_strike and critical_hit_effect then
          EffectHelper.remote_play_skinned_surface_material_effects(critical_hit_effect, world, hit_position, hit_rotation, hit_normal, enemy_type, damage_sound, no_damage, hit_zone_name, is_server)
        else
          EffectHelper.remote_play_skinned_surface_material_effects(hit_effect, world, hit_position, hit_rotation, hit_normal, enemy_type, damage_sound, no_damage, hit_zone_name, is_server)
        end
      end
    elseif hit_unit_player and breed.is_hero and current_action.player_push_velocity then
      local hit_unit_buff_extension = ScriptUnit.has_extension(hit_unit, "buff_system")
      local no_ranged_knockback = hit_unit_buff_extension and hit_unit_buff_extension:has_buff_perk("no_ranged_knockback")

      if not no_ranged_knockback then
        local status_extension = ScriptUnit.extension(hit_unit, "status_system")

        if not status_extension:is_disabled() then
          local max_impact_push_speed = current_action.max_impact_push_speed
          local locomotion = ScriptUnit.extension(hit_unit, "locomotion_system")

          locomotion:add_external_velocity(current_action.player_push_velocity:unbox(), max_impact_push_speed)
        end
      end
    end

    local deal_damage = true
    local owner_unit_alive = unit_alive(owner_unit)

    if owner_unit_alive and hit_unit_player then
      local ranged_block = DamageUtils.check_ranged_block(owner_unit, hit_unit, attack_direction, "blocked_ranged")
      deal_damage = not ranged_block
      shield_blocked = ranged_block
    end

    if deal_damage then
      local weapon_system = Managers.state.entity:system("weapon_system")

      weapon_system:send_rpc_attack_hit(damage_source_id, attacker_unit_id, hit_unit_id, hit_zone_id, hit_position, attack_direction, damage_profile_id, "power_level", power_level, "hit_target_index", actual_target_index, "blocking", shield_blocked, "shield_break_procced", false, "boost_curve_multiplier", ranged_boost_curve_multiplier, "is_critical_strike", is_critical_strike, "attacker_is_level_unit", attacker_is_level_unit)
      EffectHelper.player_critical_hit(world, is_critical_strike, owner_unit, hit_unit, hit_position)

      if not owner_player and owner_unit_alive and hit_unit_player and hit_unit_player.bot_player then
        local bot_ai_extension = ScriptUnit.extension(hit_unit, "ai_system")

        bot_ai_extension:hit_by_projectile(owner_unit)
      end
    end

    local dummy_unit_armor = unit_get_data(hit_unit, "armor")
    local target_unit_armor, _, target_unit_primary_armor, _ = ActionUtils.get_target_armor(hit_zone_name, breed, dummy_unit_armor)

    if no_damage or shield_blocked or target_unit_primary_armor == 6 or target_unit_armor == 2 then
      max_targets = num_penetrations
    else
      num_penetrations = num_penetrations + 1
    end

    if max_targets <= amount_of_mass_hit then
      hit_data.stop = true
      hit_data.hits = num_penetrations
    end
  end

  return amount_of_mass_hit, num_penetrations, predicted_damage, shield_blocked
end)

local best_hit_units = {}
mod:hook_origin(PlayerProjectileUnitExtension, "handle_impacts", function (self, impacts, num_impacts)
  table.clear(best_hit_units)

  local unit = self._projectile_unit
  local owner_unit = self._owner_unit
  local is_server = self._is_server
  local UNIT_INDEX = ProjectileImpactDataIndex.UNIT
  local POSITION_INDEX = ProjectileImpactDataIndex.POSITION
  local DIRECTION_INDEX = ProjectileImpactDataIndex.DIRECTION
  local NORMAL_INDEX = ProjectileImpactDataIndex.NORMAL
  local ACTOR_INDEX = ProjectileImpactDataIndex.ACTOR_INDEX
  local hit_units = self._hit_units
  local hit_afro_units = self._hit_afro_units
  local impact_data = self._impact_data
  local network_manager = Managers.state.network
  local network_transmit = network_manager.network_transmit
  local unit_id = network_manager:unit_game_object_id(unit)
  local pos_min = NetworkConstants.position.min
  local pos_max = NetworkConstants.position.max

  for i = 1, num_impacts / ProjectileImpactDataIndex.STRIDE, 1 do
    local j = (i - 1) * ProjectileImpactDataIndex.STRIDE
    local hit_position = impacts[j + POSITION_INDEX]:unbox()
    local hit_unit = impacts[j + UNIT_INDEX]
    local actor_index = impacts[j + ACTOR_INDEX]
    local hit_actor = Unit.actor(hit_unit, actor_index)
    local breed = AiUtils.unit_breed(hit_unit)

    if breed then
      local node = Actor.node(hit_actor)
      local hit_zone = breed.hit_zones_lookup[node]

      -- MODIFIED. Check we have hit_zone before indexing it
      if hit_zone then
        if hit_zone and hit_zone.name ~= "afro" then
          local potential_hit_zone = best_hit_units[hit_unit]

          if not potential_hit_zone or (potential_hit_zone and hit_zone.prio < potential_hit_zone.prio) then
            best_hit_units[hit_unit] = hit_zone
          end
        elseif not hit_afro_units[hit_unit] and hit_zone and hit_zone.name == "afro" then
          self:_alert_enemy(hit_unit, owner_unit)

          hit_afro_units[hit_unit] = true
        end
      end
    end
  end

  for i = 1, num_impacts / ProjectileImpactDataIndex.STRIDE, 1 do
    repeat
      if self._stop_impacts then
        return
      end

      local j = (i - 1) * ProjectileImpactDataIndex.STRIDE
      local hit_unit = impacts[j + UNIT_INDEX]
      local hit_position = impacts[j + POSITION_INDEX]:unbox()
      local hit_direction = impacts[j + DIRECTION_INDEX]:unbox()
      local hit_normal = impacts[j + NORMAL_INDEX]:unbox()
      local actor_index = impacts[j + ACTOR_INDEX]
      local hit_actor = Unit.actor(hit_unit, actor_index)
      local valid_position = self:validate_position(hit_position, pos_min, pos_max)

      if not valid_position then
        self:stop()
      end

      hit_unit, hit_actor = ActionUtils.redirect_shield_hit(hit_unit, hit_actor)
      local hit_self = hit_unit == owner_unit

      if not hit_self and valid_position and not hit_units[hit_unit] then
        local hud_extension = ScriptUnit.has_extension(owner_unit, "hud_system")

        if hud_extension then
          hud_extension.show_critical_indication = false
        end

        local breed = AiUtils.unit_breed(hit_unit)

        if breed then
          local best_hit_zone = best_hit_units[hit_unit]

          if best_hit_zone then
            local node = Actor.node(hit_actor)
            local hit_zone = breed.hit_zones_lookup[node]

            if hit_zone.name == best_hit_zone.name then
              hit_units[hit_unit] = true
            else
              break
            end
          else
            break
          end
        else
          hit_units[hit_unit] = true
        end

        local level_index, is_level_unit = network_manager:game_object_or_level_id(hit_unit)

        if is_server then
          if is_level_unit then
            network_transmit:send_rpc_clients("rpc_player_projectile_impact_level", unit_id, level_index, hit_position, hit_direction, hit_normal, actor_index)
          elseif level_index then
            network_transmit:send_rpc_clients("rpc_player_projectile_impact_dynamic", unit_id, level_index, hit_position, hit_direction, hit_normal, actor_index)
          end
        elseif is_level_unit then
          network_transmit:send_rpc_server("rpc_player_projectile_impact_level", unit_id, level_index, hit_position, hit_direction, hit_normal, actor_index)
        elseif level_index then
          network_transmit:send_rpc_server("rpc_player_projectile_impact_dynamic", unit_id, level_index, hit_position, hit_direction, hit_normal, actor_index)
        end

        local side_manager = Managers.state.side
        local is_enemy = side_manager:is_enemy(owner_unit, hit_unit)
        local has_ranged_boost, ranged_boost_curve_multiplier = ActionUtils.get_ranged_boost(owner_unit)

        if breed then
          if is_enemy then
            self:hit_enemy(impact_data, hit_unit, hit_position, hit_direction, hit_normal, hit_actor, breed, has_ranged_boost, ranged_boost_curve_multiplier)

            local buff_extension = ScriptUnit.has_extension(owner_unit, "buff_system")

            if buff_extension then
              buff_extension:trigger_procs("on_ranged_hit")
            end
          elseif breed.is_player then
            self:hit_player(impact_data, hit_unit, hit_position, hit_direction, hit_normal, hit_actor, has_ranged_boost, ranged_boost_curve_multiplier)
          end
        elseif is_level_unit or Unit.get_data(hit_unit, "is_dummy") then
          self:hit_level_unit(impact_data, hit_unit, hit_position, hit_direction, hit_normal, hit_actor, level_index, has_ranged_boost, ranged_boost_curve_multiplier)
        elseif not is_level_unit then
          self:hit_non_level_unit(impact_data, hit_unit, hit_position, hit_direction, hit_normal, hit_actor, has_ranged_boost, ranged_boost_curve_multiplier)
        end
      end
    until true
  end
end)
