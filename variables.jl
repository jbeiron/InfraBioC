# This file defines the decision variables used in the model, and the function to create them in the JuMP model.

using JuMP
function create_variables!(model, sets, params)
    (; T, TYPE, FEEDSTOCK, NON_CO2_EL, INTERMEDIATE, HEAT_FUELS,
    BIO_FUEL, FUEL, CO2, EL, MODES, VEHICLES, SHIPS, TRUCKS,
    PIPELINE_CO2, CO2_VEH, BIO_VEH, MEOH_VEH,
    NODES, HUBS, HARBORS, NONHARBORS,
    TECH, BOILERS, PYRA, PTH, ELGEN, WIND, PV,
    NON_RES, NON_BIO_FEED, ELECTROLYSIS,
    TECH_PROP, NODE_PROP, MODE_PROP, VRE_PROP) = sets
    (; beccs_target, meoh_demand, CO2_price,
    tech_prop, tech_yield, mode_prop, dist, t_trip, node_prop, 
    feed_supply, feed_cost, vre_pot, heat_demand, exist_cap, ir, import_limit,
    non_bound_feed, vre_rate, TT, CO2_storage_cost,
    vre_cf, vre_potential,
    annuity_mode, annuity_tech, gf_available, pyr_available,
    fossil_CO2_available, pulp_mill_CO2_available) = params

    ARCS = [(n,n2) for n in NODES, n2 in NODES if n != n2 && dist[(n,n2)] > 0]
    #FLOW_TYPES = FEEDSTOCK ∪ INTERMEDIATE

    # positive variables
    @variable(model,vnewcap[NODES, TECH, T] >= 0)    # new installed capacity of technology at node in year t (GW)
    @variable(model,vinstalled[NODES, TECH, T] >= 0)  # installed capacity of technology at node in year t (GW)
    @variable(model,vuse[NODES, TYPE, TECH, T] >= 0)  # use of feedstock at node in year t (GWh)
    @variable(model,vgen[NODES, TYPE, T] >= 0)       # generation of energy carrier at node in year t (GWh or ktCO2)
    @variable(model,vco2_comb[NODES, CO2, T] >= 0)   # CO2 emissions from combustion at node in year t (ktCO2)
    @variable(model,vco2_captured[NODES, CO2, T] >= 0) # ktCO2  # CO2 captured at node in year t (ktCO2)
    @variable(model,vco2_emitted[NODES, CO2, T] >= 0) # ktCO2  # CO2 emitted at node in year t (ktCO2)
    @variable(model,vtransp[NODES, NODES, TYPE, MODES, T] >= 0)  # transport of energy carrier from node to node2 by mode in year t (GWh or ktCO2)
    @variable(model,vimport[NODES, TYPE, T] >= 0)    # import of energy carrier to node in year t (GWh)
    @variable(model,v_vehicles[NODES, NODES, TYPE, VEHICLES, T] >= 0)  # vehicle capacity for transport from node to node2 by mode in year t (GW)
    @variable(model,v_newvehicles[NODES, NODES, TYPE, VEHICLES, T] >= 0)  # new vehicle capacity for transport from node to node2 by mode in year t (GW)


    # variables that can be positive or negative
    @variable(model, vtotcost)    # total cost (G€)
    @variable(model, vannual_cost[T])   # annual cost in year t (G€)

    # integer variables
    @variable(model, v_num_ships[NODES,NODES,TYPE,SHIPS,T] >= 0, Int)  # number of ships for transport from node to node2 by mode in year t

    # binary variables
    @variable(model, v_pyr_nodes[NODES,T], Bin) # 1 if pyrolysis plant is built at node in year t, 0 otherwise

    # variable bounds

    # Gasifier technology availability
    if gf_available == false
        for n in NODES, te in TECH, t in T
            if te == :gf
                set_upper_bound(vinstalled[n, te, t], 0.0)
            end
        end
    end

    # pyrolysis availability
    if pyr_available == false
        for n in NODES, te in TECH, t in T
            if te in PYRA
                set_upper_bound(vinstalled[n, te, t], 0.0)
                fix(v_pyr_nodes[n, t], 0.0; force=true)
            end
        end
    end

    # no PtH in T = 1
    for n in NODES, te in PTH
        set_upper_bound(vinstalled[n, te, 1], 0.0)
    end

    # limit pyr_B capacity expansion over time
    for n in NODES
        set_upper_bound(vinstalled[n, :pyr_b, 1], 0.0)
        set_upper_bound(vinstalled[n, :pyr_b, 2], 0.3)
    end

    # transport to/from storage
    storage_node = :storage
    for n in NODES, ty in TYPE, m in MODES, t in T
        if n != storage_node
            set_upper_bound(vtransp[n, storage_node, ty, m, t], 0.0)
        end
        if n != storage_node
            set_upper_bound(vtransp[storage_node, n, ty, m, t], 0.0)
        end
    end

    # ship transport only between HARBORS
    for a in NONHARBORS, b in NODES, ty in TYPE, sh in SHIPS, t in T
        set_upper_bound(vtransp[a, b, ty, sh, t], 0.0)
    end
    for a in NODES, b in NONHARBORS, ty in TYPE, sh in SHIPS, t in T
        set_upper_bound(vtransp[a, b, ty, sh, t], 0.0)
    end
    for a in HARBORS, b in HARBORS, ty in TYPE, sh in SHIPS, t in T
        set_upper_bound(vtransp[a, b, ty, sh, t], 100000.0)
    end

    # truck, pipeline within same subset
    for a in HUBS, b in HUBS, ty in TYPE, trk in TRUCKS, t in T
        set_upper_bound(vtransp[a, b, ty, trk, t], 100000.0)
    end

    for a in HUBS, b in HUBS, c in CO2, t in T
        set_upper_bound(vtransp[a, b, c, :pipeline_on, t], 100000.0)
    end

    # pipeline_H2, only for H2
    for n in NODES, n2 in NODES, ty in TYPE, t in T
        set_upper_bound(vtransp[n, n2, ty, :pipeline_h2, t], 0.0)
    end
    for n in NODES, n2 in NODES, t in T
        set_upper_bound(vtransp[n, n2, :h2, :pipeline_h2, t], 100000.0)
    end

    # CO2 to storage only via pipeline or ship
    for h in HARBORS, c in CO2, sh in SHIPS, t in T
        set_upper_bound(vtransp[h, :storage, c, sh, t], 100000.0)
    end
    for h in HARBORS, c in CO2, t in T
        #set_upper_bound(vtransp[h, :storage, c, :pipeline_off, t], 100000.0)
        set_upper_bound(vtransp[h, :storage, c, :pipeline_off, t], 0.0)
    end

    # no trucks to Gotland, hub 24 (an island)
    for n in NODES, ty in TYPE, trk in TRUCKS, t in T
        set_upper_bound(vtransp[n, :hub24, ty, trk, t], 0.0)
        set_upper_bound(vtransp[:hub24, n, ty, trk, t], 0.0)
    end

    # no transport of pyoil, needs to be upgraded first 
    for n in NODES, n2 in NODES, m in MODES, t in T
        set_upper_bound(vtransp[n, n2, :pyoil, m, t], 0.0)
    end

    # no MeOH transport out from hub 19 (refineries)
    for n in NODES, m in MODES, t in T
        set_upper_bound(vtransp[:hub19, n, :meoh, m, t], 0.0)
    end

    for ty in TYPE, m in MODES, t in T
        set_upper_bound(vtransp[:storage, :storage, ty, m, t], 0.0)
    end

    # Default: 0 for all vehicle types (adjusted for specific types below)
    for n in NODES, n2 in NODES, ty in TYPE, veh in VEHICLES, t in T
        set_upper_bound(v_newvehicles[n,n2,ty,veh,t], 0.0)
    end

    # Allow certain categories up to 100 vehicles per route (upper bound can be adjusted as needed)
    for n in NODES, n2 in NODES, c in CO2, veh in CO2_VEH, t in T
        set_upper_bound(v_newvehicles[n,n2,c,veh,t], 100.0)
    end
    for n in NODES, n2 in NODES, fu in FUEL, veh in BIO_VEH, t in T
        set_upper_bound(v_newvehicles[n,n2,fu,veh,t], 100.0)
    end
    for n in NODES, n2 in NODES, veh in MEOH_VEH, t in T
        set_upper_bound(v_newvehicles[n,n2,:meoh,         veh,t], 100.0)
        set_upper_bound(v_newvehicles[n,n2,:pyoil,        veh,t], 0.0)
        set_upper_bound(v_newvehicles[n,n2,:pyoil_upgrade,veh,t], 100.0)
        set_upper_bound(v_newvehicles[n,n2,:nh3,          veh,t], 100.0)
    end

    # bounds for v_num_ships
    for n in NODES, n2 in NODES, ty in TYPE, sh in SHIPS, t in T
        set_upper_bound(v_num_ships[n,n2,ty,sh,t], 50.0)
    end
    for a in NONHARBORS, b in NODES, ty in TYPE, sh in SHIPS, t in T
        set_upper_bound(v_num_ships[a,b,ty,sh,t], 0.0)
    end
    for a in NODES, b in NONHARBORS, ty in TYPE, sh in SHIPS, t in T
        set_upper_bound(v_num_ships[a,b,ty,sh,t], 0.0)
    end

    # import and use/generation
    # vimport default 0
    for n in NODES, ty in TYPE, t in T
        set_upper_bound(vimport[n, ty, t], 0.0)
    end

    # harbors: feedstock import with limits
    for h in HARBORS, fs in FEEDSTOCK, t in T
        set_upper_bound(vimport[h, fs, t], non_bound_feed[fs])
    end
    for h in HARBORS, t in T
        set_upper_bound(vimport[h, :nh3, t], import_limit[(h, :nh3)])
        set_upper_bound(vimport[h, :h2,  t], import_limit[(h, :h2)])
    end

    # vuse on storage site = 0
    for ty in TYPE, te in TECH, t in T
        set_upper_bound(vuse[:storage, ty, te, t], 0.0)
    end

    # vgen: no generation of fuel and NH3, can only use feedstock resources
    for n in NODES, fu in FUEL, t in T
        set_upper_bound(vgen[n, fu, t], 0.0)
    end
    for n in NODES, t in T
        set_upper_bound(vgen[n, :nh3, t], 0.0)
    end

    # vuse: waste restrictions
    for n in NODES, te in TECH, t in T
        set_upper_bound(vuse[n, :waste, te, t], 0.0)
    end
    for n in NODES, te in PYRA, t in T
        set_upper_bound(vuse[n, :waste, te, t], 0.0)
        set_upper_bound(vuse[n, :rt,    te, t], 0.0)
    end
    for n in NODES, te in BOILERS, t in T
        set_upper_bound(vuse[n, :waste, te, t], 100000.0)
    end
    for n in NODES, t in T
        set_upper_bound(vuse[n, :waste, :gf, t], 100000.0)
        set_upper_bound(vuse[n, :waste, :chp_bio, t], 0.0)
        set_upper_bound(vuse[n, :waste, :hob_bio, t], 0.0)
    end

    # CO2_capture technology cannot use non_co2_el feedstocks
    for n in NODES, ty in NON_CO2_EL, t in T
        set_upper_bound(vuse[n, ty, :co2_capture, t], 0.0)
    end

    # non_bio_feed technologies cannot use fuels
    for n in NODES, fu in FUEL, te in NON_BIO_FEED, t in T
        set_upper_bound(vuse[n, fu, te, t], 0.0)
    end

    # PtH cannot use PV electricity (low correlation between PV generation and heat demand)
    for n in NODES, te in PTH, t in T
        set_upper_bound(vuse[n, :el_pvplant, te, t], 0.0)
        set_upper_bound(vuse[n, :el_pvroof,  te, t], 0.0)
    end

    # vgen fixed to 0 for co2 types, co2 can only be captured from combustion or direct air capture, not generated
     for n in NODES, c in CO2, t in T
         set_upper_bound(vgen[n, c, t], 0.0)
     end
    for n in NODES, c in CO2, t in T
        fix(vgen[n, c, t], 0.0; force=true)
    end

    # RFNBO conditions - fossil CO2 from industries not OK for CCU methanol after 2040
    for n in NODES
        set_upper_bound(vuse[n, :co2_fossil, :synthesis, 3], 0.0)
    end


    vars = (; vnewcap, vinstalled, vuse, vgen, vco2_comb, vco2_captured, vco2_emitted,
            vtransp, vimport, v_vehicles, v_newvehicles,
            vtotcost, vannual_cost, v_num_ships, v_pyr_nodes)

    return vars
end

