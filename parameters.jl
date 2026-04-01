# This file defines the parameters used in the model, and the function to load them from input files.

function load_params(sets)
    (; T, TYPE, FEEDSTOCK, NON_CO2_EL, INTERMEDIATE, HEAT_FUELS,
        BIO_FUEL, FUEL, CO2, EL, MODES, VEHICLES, SHIPS, TRUCKS,
        PIPELINE_CO2, CO2_VEH, BIO_VEH, MEOH_VEH,
        NODES, HUBS, HARBORS, NONHARBORS,
        TECH, BOILERS, PYRA, PTH, ELGEN, WIND, PV,
        NON_RES, NON_BIO_FEED, ELECTROLYSIS,
        TECH_PROP, NODE_PROP, MODE_PROP, VRE_PROP) = sets

    # PARAMETERS TO ADJUST FOR SCENARIO RUNS
    vre_rate = 1 # share of vre potential available for use
    gf_available = false # whether or not gasification is available
    pyr_available = false # whether or not pyrolysis is available
    fossil_CO2_available = false # whether or not fossil CO2 is available to be captured and used for RFNBO
    pulp_mill_CO2_available = true # whether or not pulp mill CO2 is available to be captured

    TT = 10 # timestep length in years

    # Parameter(timestep)
    beccs_target = [0.0, 1.8, 10.0]        # MtCO2/a
    meoh_demand  = [0.0, 15.0, 50.0]       # TWh/a
    CO2_price    = [100.0, 200.0, 450.0]   # €/tCO2 fossil

    CO2_storage_cost = 50.0  # €/tCO2 stored

    # GWh feedstock import (corresponding to import share of feedstock use, currently (approx 30%)
    non_bound_feed = Dict{Symbol,Float64}()
    for fs in FEEDSTOCK
        non_bound_feed[fs] = 0.0
    end
    non_bound_feed[:waste] = 5538.0
    non_bound_feed[:rt] = 2032.0

    current_dir = @__DIR__
    input_dir = joinpath(current_dir, "input")

    tech_prop_df = load_wide_param_2d(input_dir,"tech_prop.xlsx";
                                    index_col=:tech, prop_col=:tech_prop)
    mode_prop_df = load_wide_param_2d(input_dir, "mode_props.xlsx";
                                    index_col=:modes, prop_col=:mode_prop)
    node_prop_df = load_wide_param_2d(input_dir, "node_prop.xlsx";
                                    index_col=:nodes, prop_col=:node_prop)
    yield_df = load_wide_param_2d(input_dir, "yield.xlsx";
                                    index_col=:type, prop_col=:tech)
    dist_ship_df = load_wide_param_2d(input_dir, "dist_ship.xlsx";
                                    index_col=:nodes, prop_col=:nodes2)
    feed_supply_df = load_wide_param_2d(input_dir, "feed_supply.xlsx";
                                    index_col=:hubs, prop_col=:type)
    feed_cost_df = load_wide_param_2d(input_dir, "feed_cost.xlsx";
                                    index_col=:nodes, prop_col=:type)
    vre_pot_df = load_wide_param_2d(input_dir, "vre_pot.xlsx";
                                    index_col=:hubs, prop_col=:vre_prop)
  

    ir = 0.05  # discount rate for annuity factor
    annuity_tech = Dict{Symbol,Float64}()
    for tech in TECH
        life = tech_prop_df[(tech, :life)]
        if life > 0
            annuity_tech[tech] = ir / (1 - (1 + ir)^(-life))
        end
    end
    annuity_mode = Dict{Symbol,Float64}()
    for mode in MODES
        life = mode_prop_df[(mode, :life)]
        if life > 0
            annuity_mode[mode] = ir / (1 - (1 + ir)^(-life))
        end
    end

    # calculate t trip for all node-node and vehicle combinations
    t_trip = Dict{Tuple{Symbol,Symbol,Symbol},Float64}()
    dist_veh = Dict{Tuple{Symbol,Symbol},Float64}()
    for n1 in NODES, n2 in NODES, v in VEHICLES
        if v in SHIPS
            dist = get(dist_ship_df, (n1, n2), 0.0)
        else
            lat1 = node_prop_df[(n1, :lat)]
            lon1 = node_prop_df[(n1, :long)]
            lat2 = node_prop_df[(n2, :lat)]
            lon2 = node_prop_df[(n2, :long)]
            # Haversine formula
            dlat = lat2 - lat1
            dlon = lon2 - lon1
            a = sin(dlat/2)^2 + cos(lat1) * cos(lat2) * sin(dlon/2)^2
            c = 2 * atan(sqrt(a), sqrt(1-a))
            dist = c * 6371  # Earth's radius in km
            dist_veh[(n1,n2)] = dist
        end
        winding = mode_prop_df[(v, :winding)]
        speed = mode_prop_df[(v, :speed)]
        t_load = mode_prop_df[(v, :t_load)]
        t_unload = mode_prop_df[(v, :t_unload)]
        trip_time = dist * winding * 2 / speed + t_load + t_unload
        t_trip[(n1, n2, v)] = trip_time
    end 
    # Example:
    # t_trip[(:hub1, :hub2, :ship10)] gives the trip time for ship10 between hub1 and hub2      
 

    if fossil_CO2_available == false
        for n in NODES
            feed_supply_df[(n, :co2_fossil)] = 0.0
        end
    end

    if pulp_mill_CO2_available == false
        for n in NODES
            feed_supply_df[(n, :co2_bio)] = 0.0
        end
    end


    heat_demand = Dict{Symbol,Float64}()
    for (k, v) in node_prop_df
        (node, prop) = k
        if prop == :heat_demand
            heat_demand[node] = v
        end
    end

    exist_cap = Dict{Tuple{Symbol,Symbol,Int},Float64}()
    for (k, v) in node_prop_df   
        (node, prop) = k
        for tech in TECH, t in T
        exist_cap[(node,tech,t)] = 0.0
        end 
        if prop == :mw_bio
            exist_cap[(node, :chp_bio, 1)] = v / 1000.0
        elseif prop == :mw_waste
            exist_cap[(node, :chp_waste, 1)] = v / 1000.0
        end
    end

    import_limit = Dict{Tuple{Symbol,Symbol},Float64}()
    for n in NODES, f in FEEDSTOCK
        import_limit[(n,f)] = 10000.0
    end
    for n in NODES
        import_limit[(n,:nh3)] = 0.0
        import_limit[(n,:h2)] = 0.0
    end

    vre_potential = Dict{Tuple{Symbol,Symbol},Float64}()
    vre_cf = Dict{Tuple{Symbol,Symbol},Float64}()   
    for (k, v) in vre_pot_df
        (node, prop) = k
        if prop == :cap_won
            vre_potential[(node, :won)] = v
        elseif prop == :cap_woff
            vre_potential[(node, :woff)] = v
        elseif prop == :cap_pvplant
            vre_potential[(node, :pvplant)] = v
        elseif prop == :cap_pvroof
            vre_potential[(node, :pvroof)] = v
        elseif prop == :cf_won
            vre_cf[(node, :won)] = v
        elseif prop == :cf_woff
            vre_cf[(node, :woff)] = v
        elseif prop == :cf_pvplant
            vre_cf[(node, :pvplant)] = v
        elseif prop == :cf_pvroof
            vre_cf[(node, :pvroof)] = v
        end
    end

    params = (; 
        beccs_target, meoh_demand, CO2_price,
        tech_prop=tech_prop_df, tech_yield=yield_df, mode_prop=mode_prop_df, 
        dist=dist_veh, t_trip, node_prop=node_prop_df, feed_supply=feed_supply_df, 
        feed_cost=feed_cost_df, vre_pot=vre_pot_df, vre_cf, vre_potential,
        heat_demand, 
        exist_cap, import_limit, ir, 
        non_bound_feed, vre_rate, TT, CO2_storage_cost,
        annuity_mode=annuity_mode, annuity_tech=annuity_tech, gf_available=gf_available, pyr_available=pyr_available,
        fossil_CO2_available=fossil_CO2_available, pulp_mill_CO2_available=pulp_mill_CO2_available)

    return params
end
