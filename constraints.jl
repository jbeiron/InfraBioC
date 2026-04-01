# This file contains the objective function and constraints of the model. 
# The constraints are added to the model in the function add_constraints!, which is called from run.jl. 
# The objective function is defined in set_objective!, which is also called from run.jl.

function set_objective!(model,sets,params,vars)
    @objective(model, Min, vars.vtotcost)
    return nothing
end
    

function add_constraints!(model, sets, params, vars)
    (; T, TYPE, FEEDSTOCK, NON_CO2_EL, INTERMEDIATE, HEAT_FUELS,
    BIO_FUEL, FUEL, CO2, EL, MODES, VEHICLES, SHIPS, TRUCKS,
    PIPELINE_CO2, CO2_VEH, BIO_VEH, MEOH_VEH,
    NODES, HUBS, HARBORS, NONHARBORS,
    TECH, BOILERS, PYRA, PTH, ELGEN, WIND, PV,
    NON_RES, NON_BIO_FEED, ELECTROLYSIS,
    TECH_PROP, NODE_PROP, MODE_PROP, VRE_PROP) = sets
    (; beccs_target, meoh_demand, CO2_price, 
    tech_prop, tech_yield, mode_prop, dist, t_trip, node_prop, 
    feed_supply, feed_cost, vre_pot, vre_cf, vre_potential,
    heat_demand, exist_cap, import_limit,
    non_bound_feed, vre_rate, TT, CO2_storage_cost, ir,
    annuity_mode, annuity_tech, gf_available, pyr_available,
    fossil_CO2_available, pulp_mill_CO2_available) = params

    (; vnewcap, vinstalled, vuse, vgen, vco2_comb, vco2_captured, vco2_emitted,
    vtransp, vimport, v_vehicles, v_newvehicles,
    vtotcost, vannual_cost, v_num_ships, v_pyr_nodes) = vars

    # Objective function: minimize total discounted cost in G€ over model horizon
    @constraint(model, total_cost, 
        vtotcost >= sum(
            TT * (vannual_cost[t] / 1000) / (1 + ir)^((t - 1) * TT)
            for t in T
        )
    )

    # calculate annual cost, M€
    @constraint(model, annual_cost[t in T],
        vannual_cost[t] >=
        # paying annualized investment costs for ALL tech and vehicles, not only new ones each timestep.
        # investment and OM cost for new production facilities (tech)
        sum(
            (vinstalled[n, tech, t] - exist_cap[n, tech, t]) * tech_prop[(tech, :c_inv)] * annuity_tech[tech]
            + vinstalled[n, tech, t] * tech_prop[(tech, :c_om_fix)]
            + sum(vuse[n, type, tech, t] * tech_prop[(tech, :c_om_var)] for type in TYPE) / 1000
            for n in NODES, tech in TECH
        )
        # feedstock costs, regional and imported. vuse includes both regional and imported.
        + sum(
            vuse[n, fuel, tech, t] * feed_cost[(n, fuel)] / 1000
            for n in NODES, fuel in FUEL, tech in TECH
        )
        + sum(
            (vimport[n, :h2, t] * feed_cost[(n, :h2)] 
            + vimport[n, :nh3, t] * feed_cost[(n, :nh3)]) / 1000
            for n in NODES
        ) 
        # transport costs between nodes
        # trucks
        + sum(
            v_vehicles[n, n2, type, m, t] * mode_prop[(m, :c_inv)] * annuity_mode[m]
            + v_vehicles[n, n2, type, m, t] * (mode_prop[(m, :c_inv)] * mode_prop[(m, :c_om)]
                        + mode_prop[(m, :c_salary)] * mode_prop[(m, :num_driver)])
            + vtransp[n, n2, type, m, t] * (1 / mode_prop[(m, :size)]) * dist[(n, n2)]
                * mode_prop[(m, :winding)] * 2 * mode_prop[(m, :fuel_cons)] * mode_prop[(m, :c_fuel)] / 1_000_000
            for n in NODES, n2 in NODES, type in TYPE, m in TRUCKS
        )
        # Ships
        + sum(
                v_vehicles[n, n2, type, m, t] * mode_prop[(m, :c_inv)]*annuity_mode[m]
                + v_vehicles[n,n2,type,m,t]* mode_prop[(m, :c_inv)]*mode_prop[(m, :c_om)]
                + vtransp[n,n2,type,m,t] * (1/mode_prop[(m, :size)]) * (
                    mode_prop[(m, :c_harbor)] 
                    + mode_prop[(m, :fuel_cons)]*(1/1_000_000)* mode_prop[(m, :c_fuel)]* 
                    (t_trip[(n, n2, m)]
                    + (mode_prop[(m,:t_load)] + mode_prop[(m, :t_unload)]) * mode_prop[(m, :fuel_cons_still)])
                    )
                for n in NODES, n2 in NODES,
                    type in TYPE,
                    m in SHIPS
            )
        # Pipelines
        + sum(
                vtransp[n, n2, type, m, t] * dist[(n, n2)] * mode_prop[(m, :winding)] *
                    (mode_prop[(m, :c_inv)] * annuity_mode[m]
                        + mode_prop[(m, :c_om)])
                for n in NODES, n2 in NODES,
                    type in TYPE,
                    m in PIPELINE_CO2
            )
        # unit for H2 pipeline capacity is GW, therefore divide GWh (vtransp) with operational time of pipeline to get GW.
        + sum(  
                vtransp[n, n2, type, :pipeline_h2, t] * (1 / mode_prop[(:pipeline_h2, :t_op)]) * dist[(n, n2)] * mode_prop[(:pipeline_h2, :winding)] *
                    (mode_prop[(:pipeline_h2, :c_inv)] * annuity_mode[:pipeline_h2]
                        + mode_prop[(:pipeline_h2, :c_om)])
                for n in NODES, n2 in NODES,
                    type in TYPE
            )   
        # Cost of emitting fossil co2 kton
        + sum(
                (vco2_comb[n, :co2_fossil, t] + feed_supply[(n, :co2_fossil)]
                - sum(vtransp[n, :storage, :co2_fossil, m, t] for m in MODES)
                + sum(vtransp[:storage, n, :co2_fossil, m, t] for m in MODES)
                - vuse[n, :co2_fossil, :synthesis, t])*CO2_price[t] / 1000
                for n in HUBS
            ) 

        # cost of CO2 storage á 50 €/t
        + sum(
        vtransp[n, :storage, co2, m, t] * CO2_storage_cost / 1000
        for n in HUBS, co2 in CO2, m in MODES
        )
            
    )

    # BECCS target constraint
    @constraint(model, beccs[t in T],
        (sum(vtransp[n, :storage, :co2_bio, m, t] for n in HUBS, m in MODES) 
        - sum(vtransp[:storage, n, :co2_bio, m, t] for n in HUBS, m in MODES)
        )/ 1000
        >= beccs_target[t]
    )

    # methanol demand at hub19 (refineries)
    @constraint(model, methanol[t in T],
        (
            # meoh net inflow to hub19
            sum(vtransp[n, :hub19, :meoh, m, t] for n in NODES, m in MODES)
        - sum(vtransp[:hub19, n, :meoh, m, t] for n in NODES, m in MODES)

            # production in hub19
        + vgen[:hub19, :meoh, t]
        + vgen[:hub19, :pyoil_upgrade, t]

            # pyoil_upgrade net inflow to hub19
        + sum(vtransp[n, :hub19, :pyoil_upgrade, m, t] for n in NODES, m in MODES)
        - sum(vtransp[:hub19, n, :pyoil_upgrade, m, t] for n in NODES, m in MODES)
        ) / 1000
        >= meoh_demand[t]
    )

    # Heat demand constraint at each hub
    @constraint(model, heat_production[h in HUBS, t in T],
        vgen[h, :heat, t] >= heat_demand[h] + vuse[h, :heat, :dac, t]
    )

    # transport constraints

    # * Calculate how many new vehicles that should be invested in, given vtransp 
    @constraint(model, new_vehicles[n in NODES, n2 in NODES, type in NON_CO2_EL, m in TRUCKS, t in T],
        v_vehicles[n, n2, type, m, t] >=
            vtransp[n, n2, type, m, t] * t_trip[(n, n2, m)] * (1 / mode_prop[(m, :size)]) * (1 / mode_prop[(m, :t_op)])
    )

    # special equation for transport of CO2 - so that fossil and biogenic CO2 can be transported together in the same ship (ship for co2_bio)
    # look at transport variable to see which type of CO2 is shipped from where
    @constraint(model, new_co2_vehicles[n in NODES, n2 in NODES, m in TRUCKS, t in T],
        v_vehicles[n, n2, :co2_bio, m, t] >=
            sum(
                vtransp[n, n2, co2, m, t]
                for co2 in CO2
            ) * t_trip[(n, n2, m)] * (1 / mode_prop[(m, :size)]) * (1 / mode_prop[(m, :t_op)])
    )

    # Vehicle stock balance, add new investments in vehicles to pool, subtract end-of-life vehicles
    # Help function: number of time steps until end-of-life for a vehicle
    life_steps(veh) = Int(round(mode_prop[(veh, :life)] / TT))  # requires an integer

    @constraint(model, vehicle_stock[n in NODES, n2 in NODES, ty in TYPE, veh in VEHICLES, t in T],
        v_vehicles[n,n2,ty,veh,t] ==
            # previous stock (0 if t is the first period)
            (t == first(T) ? 0.0 : v_vehicles[n,n2,ty,veh,t-1])
            # end-of-life (0 if t - life_steps is before first period)
        - (t - life_steps(veh) < first(T) ? 0.0 : v_newvehicles[n,n2,ty,veh,t - life_steps(veh)])
            # new investment this period
        + v_newvehicles[n,n2,ty,veh,t]
    )

    # Require the number of ships to be integer
    @constraint(model, integer_ships[n in NODES, n2 in NODES, ty in TYPE, m in SHIPS, t in T],
        v_vehicles[n,n2,ty,m,t] >=
            v_num_ships[n,n2,ty,m,t] 
    )


    @constraint(model, number_ships[n in NODES, n2 in NODES, ty in TYPE, m in SHIPS, t in T],
        v_num_ships[n,n2,ty,m,t] >=
            vtransp[n,n2,ty,m,t] * t_trip[(n, n2, m)] * (1 / mode_prop[(m, :size)]) * (1 / mode_prop[(m, :t_op)])
    )

    @constraint(model, number_co2_ships[n in NODES, n2 in NODES, m in SHIPS, t in T],
        v_num_ships[n,n2,:co2_bio,m,t] >=
            sum(
                vtransp[n, n2, co2, m, t]
                for co2 in CO2
            ) * t_trip[(n, n2, m)] * (1 / mode_prop[(m, :size)]) * (1 / mode_prop[(m, :t_op)])
    )

    # Mass balances of feedstock and products
    # Use of feedstock is limited by supply (regional), import to region, export from region (to other regions) and import from other regions
    # and generation of feedstock (H2, syngas, co2). Unit: fuels: GWh_fuel, co2: ktons, per year
    # Electricity is handled separately in equation further down
    @constraint(model, mass_balance_node[n in NODES, fc in NON_CO2_EL, t in T],
        sum(vuse[n, fc, tech, t] for tech in TECH)
        <=
        feed_supply[(n, fc)]
        + vimport[n, fc, t]
        - sum(vtransp[n, n2, fc, m, t] for n2 in NODES, m in MODES)
        + sum(vtransp[n2, n, fc, m, t] for n2 in NODES, m in MODES)
        + vgen[n, fc, t]
    )

    @constraint(model, co2_balance[n in NODES, co2 in CO2, t in T],
        vuse[n, co2, :synthesis, t]
        <=
        vco2_captured[n, co2, t]
        + vuse[n, :heat, :dac, t] * tech_yield[(co2, :dac)]
        - sum(vtransp[n, n2, co2, m, t] for n2 in NODES, m in MODES)
        + sum(vtransp[n2, n, co2, m, t] for n2 in NODES, m in MODES)
    )

    @constraint(model, import_max[f in FEEDSTOCK, t in T],
        sum(
            vimport[n, f, t] for n in NODES)
        <= 
        non_bound_feed[f]
    )

    # Hydrogen
    # Local generation of H2 is given by electrolyser production and ammonia cracker. Import is considered in above balance.
    # Units: convert from GWh NH3/el to GWh H2 using yield factor
    @constraint(model, H2_production[n in NODES, t in T],
        vgen[n, :h2, t]
        <=
        vuse[n, :el_won, :electrolysis_won, t] * tech_yield[(:el_won, :electrolysis_won)]
        + vuse[n, :el_woff, :electrolysis_woff, t] * tech_yield[(:el_woff, :electrolysis_woff)]
        + vuse[n, :el_pvplant, :electrolysis_pvplant, t] * tech_yield[(:el_pvplant, :electrolysis_pvplant)]
        + vuse[n, :el_pvroof, :electrolysis_pvroof, t] * tech_yield[(:el_pvroof, :electrolysis_pvroof)]
        + vuse[n, :nh3, :ammonia_crack, t] * tech_yield[(:nh3, :ammonia_crack)]
        + vimport[n, :h2, t]
    )

    # Demand for hydrogen in synthesis process is given by how much syngas and co2 that is converted
    # NOTE syngas does not require extra/external H2 (assumption!), the CO2 from gasifier is added to vco2_captured, if captured. 
    # Unit: vgen: GWh H2. vuse: use yield factor/h2_demand to make units work, ktonCO2 to GWh H2. Need: 4.54 GWh H2 / kton CO2 converted!
    # Adding a synthesis energy efficiency of 75% (also included for syngas to synthesis in yield prop)
    @constraint(model, H2_use[n in NODES, t in T],
        vgen[n, :h2, t]
        >=
        sum(
            vuse[n, co2, :synthesis, t] * (4.54 / 0.75)
            for co2 in CO2
        )
        + vgen[n, :pyoil_upgrade, t] * 0.18
    )

    # CO2 capture
    # Generation of CO2 (other than supply available from pulp mills) is given by combustion of fuels in boilers
    # Use yield factor to convert vuse [GWh fuel] to ktonCO2
    # CO2 yields from gasifier: for bio_fuel: 0.195 kton CO2/GWh fuel gasified, 0.302 kton CO2/GWh waste gasified.
    @constraint(model, co2_fossil_generation[n in NODES, t in T],
        vco2_comb[n, :co2_fossil, t]
        ==
        sum(
            vuse[n, :waste, tech, t] * tech_yield[(:waste, tech)] * (1 - tech_prop[(tech, :em_factor)])
            for tech in BOILERS
        )
        + vuse[n, :waste, :gf, t] * 0.302 * (1 - tech_prop[(:chp_waste, :em_factor)])
    )

    # Accounting for biogenic share of CO2, see notes for previous equation
    # CO2 from pyrolysis assumed to come from combustion of byproduct gases and biochar
    @constraint(model, co2_bio_generation[n in NODES, t in T],
        vco2_comb[n, :co2_bio, t]
        ==
        sum(
            vuse[n, fuel, tech, t] * tech_yield[(fuel, tech)] * tech_prop[(tech, :em_factor)]
            for fuel in BIO_FUEL, tech in BOILERS
        )
        + sum(
            vuse[n, :waste, tech, t] * tech_yield[(:waste, tech)] * tech_prop[(tech, :em_factor)]
            for tech in BOILERS
        )
        + sum(
            vuse[n, fuel, :gf, t] * 0.195
            for fuel in BIO_FUEL
        )
        + vuse[n, :waste, :gf, t] * 0.302 * tech_prop[(:chp_waste, :em_factor)]
        + sum(
            vuse[n, fuel, tech, t] * 0.14
            for fuel in BIO_FUEL, tech in PYRA
        )
    )

    # CO2 from combustion is only available for synthesis if carbon capture tech is installed. I.e. assume that new boilers do not have capture by default.
    # Note assumes same cost data for capture from boilers and gasifiers
    # Unit: ktCO2 captured 
    @constraint(model, co2_capture[n in NODES, t in T],
        sum(
            vco2_captured[n, co2, t]
            for co2 in CO2
        )
        <=
        vinstalled[n, :co2_capture, t] * 8000
    )

    # Limit CO2 available for use by capture rate. NOTE assumes same capture rate for boilers and gasifiers and industries!
    # Unit ktonCO2
    @constraint(model, co2_capture_balance[n in NODES, co2 in CO2, t in T],
        vco2_captured[n, co2, t]
        <=
        (vco2_comb[n, co2, t] + feed_supply[(n, co2)]) * tech_yield[(co2, :co2_capture)]
    )

    @constraint(model, co2_emitted[n in HUBS, co2 in CO2, t in T],
        vco2_emitted[n,co2,t] ==
                    feed_supply[(n,co2)] + vco2_comb[n, co2, t]
                    - vco2_captured[n, co2, t]
    )

    # synthesis
    # Syngas availability as feedstock is given by amount of waste/bio gasified
    # yield to convert from GWh feed to GWh syngas
    @constraint(model, syngas_balance[n in NODES, t in T],
        vgen[n, :syngas, t]
        ==
        sum(
            vuse[n, bio_fuel, :gf, t] * tech_yield[(bio_fuel, :gf)]
            for bio_fuel in BIO_FUEL
        )
        + vuse[n, :waste, :gf, t] * tech_yield[(:waste, :gf)]
    )

    # Production of methanol in region is given by amount of co/co2 sent to synthesis
    # Unit: tonCO2 to GWh methanol, GWh syngas to GWh methanol
    @constraint(model, methanol_balance[n in NODES, t in T],
        vgen[n, :meoh, t]
        <=
        vuse[n, :syngas, :synthesis, t] * tech_yield[(:syngas, :synthesis)]
        + sum(
            vuse[n, co2, :synthesis, t] * tech_yield[(co2, :synthesis)]
            for co2 in CO2
        )
    )

    # ---- PYROLYSIS -----------------------------------------------------------------------------
    # Pyrolysis of biomass residues to bio-oil, GWh
    @constraint(model, pyrolysis_balance[n in NODES, t in T],
        vgen[n, :pyoil, t]
        ==
        sum(
            vuse[n, bio_fuel, tech, t] * tech_yield[(bio_fuel, tech)]
            for bio_fuel in BIO_FUEL, tech in PYRA
        )
    )

    # Upgrading of fast pyrolysis oil in a b-plant to feed to refinery, GWh
    @constraint(model, pyB_balance[n in NODES, t in T],
        vgen[n, :pyoil_upgrade, t]
        ==
        vuse[n, :pyoil, :pyr_b, t] * tech_yield[(:pyoil, :pyr_b)]
    )

    # equation to force binary variable to be 1 if there is a pyrolysis plant in the node
    @constraint(model, pyrolysis_capacity[n in NODES, t in T],
        vgen[n, :pyoil, t] <= v_pyr_nodes[n, t] * 10000
    )

    # Not realistic to build more than 2 plants (one per node) by 2035-ish
    @constraint(model, py_plants,
        sum(
            v_pyr_nodes[n, 2]
            for n in NODES
        ) <= 2
    )

    # ---- HEAT --------------------------------------------------------------------------------------
    # Generation of heat for DH and DAC, from boilers or power-to-heat + electrolysers
    @constraint(model, heat_supply[n in NODES, t in T],
        vgen[n, :heat, t] 
        <=
        sum(
            vuse[n, bio_fuel, tech, t] * tech_prop[(tech, :n_heat)]
            for bio_fuel in BIO_FUEL, tech in BOILERS
        )
        + sum(
            vuse[n, :waste, tech, t] * tech_prop[(tech, :n_heat)]
            for tech in BOILERS
        )
        + sum(
            vuse[n, el, pth, t] * tech_prop[(pth, :n_heat)]
            for el in EL, pth in PTH
        )
    )

    # NEW INVESTMENTS IN TECHNOLOGIES AND CAPACITY LIMITS
    # ------------------------------------------------------------------
    # Limit use of feedstock by installed capacity (new and existing).
    # Unit vuse = GWh/y feedstock. vinstalled = GW feedstock. Convert GWh to GW using full load hours (flh). 
    @constraint(model, capacity_inv[n in NODES, non_res in NON_RES, t in T],
        sum(vuse[n, type, non_res, t] for type in TYPE)
        <=
        (vinstalled[n, non_res, t] + exist_cap[n, non_res, t]) * tech_prop[(non_res, :flh)]
    )
    @constraint(model, synthesis_capacity[n in NODES, t in T],
        sum(
            vuse[n, co2, :synthesis, t] * 5.54
            for co2 in CO2
        )
        <=
        vinstalled[n, :synthesis, t] * tech_prop[(:synthesis, :flh)]
    )

    # constraints for using renewable energy and capacity factors
    # Limit use of VRE for electrolysis by installed capacity and capacity factor of VRE (variable renewable electricity generation)
    @constraint(model, [n in NODES, t in T],
        vuse[n, :el_won, :electrolysis_won, t]
        <=
        vinstalled[n, :electrolysis_won, t] * tech_prop[(:electrolysis_won, :flh)] * vre_pot[(n, :cf_won)]
    )   
    @constraint(model, [n in NODES, t in T],
        vuse[n, :el_woff, :electrolysis_woff, t]
        <=
        vinstalled[n, :electrolysis_woff, t] * tech_prop[(:electrolysis_woff, :flh)] * vre_pot[(n, :cf_woff)]
    )
    @constraint(model, [n in NODES, t in T],
        vuse[n, :el_pvplant, :electrolysis_pvplant, t]
        <=
        vinstalled[n, :electrolysis_pvplant, t] * tech_prop[(:electrolysis_pvplant, :flh)] * vre_pot[(n, :cf_pvplant)]
    )
    @constraint(model, [n in NODES, t in T],
        vuse[n, :el_pvroof, :electrolysis_pvroof, t]
        <=
        vinstalled[n, :electrolysis_pvroof, t] * tech_prop[(:electrolysis_pvroof, :flh)] * vre_pot[(n, :cf_pvroof)]
    )

    # Limit total use of VRE for electrolysis and power-to-heat by installed VRE capacity and capacity factor of VRE
    @constraint(model, [n in NODES, t in T],
        vuse[n, :el_won, :electrolysis_won, t] + sum(vuse[n, :el_won, pth, t] for pth in PTH)
        <=
        vinstalled[n, :won, t] * 8760 * vre_pot[(n, :cf_won)]
    )
    @constraint(model, [n in NODES, t in T],
        vuse[n, :el_woff, :electrolysis_woff, t] + sum(vuse[n, :el_woff, pth, t] for pth in PTH)
        <=
        vinstalled[n, :woff, t] * 8760 * vre_pot[(n, :cf_woff)]
    )
    @constraint(model, [n in NODES, t in T],
        vuse[n, :el_pvplant, :electrolysis_pvplant, t]
        <=
        vinstalled[n, :pvplant, t] * 8760 * vre_pot[(n, :cf_pvplant)]
    )
    @constraint(model, [n in NODES, t in T],
        vuse[n, :el_pvroof, :electrolysis_pvroof, t]
        <=
        vinstalled[n, :pvroof, t] * 8760 * vre_pot[(n, :cf_pvroof)]
    )

    # connect vgen variable to vinstalled capacity of VRE tech
    @constraint(model, [n in NODES, t in T],
        sum(
            vgen[n, el, t]
            for el in EL
        )
        <=
        vinstalled[n, :won, t] * vre_pot[(n, :cf_won)] * 8760
        + vinstalled[n, :woff, t] * vre_pot[(n, :cf_woff)] * 8760
        + vinstalled[n, :pvplant, t] * vre_pot[(n, :cf_pvplant)] * 8760
        + vinstalled[n, :pvroof, t] * vre_pot[(n, :cf_pvroof)] * 8760
        + sum(
            vuse[n, fuel, tech, t] * tech_prop[(tech, :n_el)]
            for fuel in FUEL, tech in BOILERS
        )
    )

    # separate constraints for each VRE technology capacity installations
    @constraint(model, [n in NODES, t in T],
        vgen[n, :el_won, t]
        <=
        vinstalled[n, :won, t] * vre_pot[(n, :cf_won)] * 8760
    )
    @constraint(model, [n in NODES, t in T],
        vgen[n, :el_woff, t]
        <=
        vinstalled[n, :woff, t] * vre_pot[(n, :cf_woff)] * 8760
    )
    @constraint(model, [n in NODES, t in T],
        vgen[n, :el_pvplant, t]
        <=
        vinstalled[n, :pvplant, t] * vre_pot[(n, :cf_pvplant)] * 8760
    )
    @constraint(model, [n in NODES, t in T],
        vgen[n, :el_pvroof, t]
        <=
        vinstalled[n, :pvroof, t] * vre_pot[(n, :cf_pvroof)] * 8760
    )


    # Installed capacity balance. Add new investments and existing capacity, remove end-of-life. 
    life_steps_2(tech) = Int(round(tech_prop[(tech, :life)] / TT))  # requires an integer
    @constraint(model, [n in NODES, tech in TECH, t in T],
        vinstalled[n, tech, t] ==
            # previous stock (0 if t is first period)
            (t == first(T) ? 0.0 : vinstalled[n, tech, t-1])
            # end-of-life removal (0 if t - life_steps is before the first period)
        - (t - life_steps_2(tech) < first(T) ? 0.0 : vnewcap[n, tech, t - life_steps_2(tech)])
            # new investment in the current period
        + vnewcap[n, tech, t]
    )

    # Limit use of electricity by renewable electricity generation, minus electricity from CHP plants
    # Electricity to run DAC included, yield factor converts from GWh heat to GWh el required
    # add electricity demand for sawmill drying process if sawdust, bark etc is used for biocrude instead of heating
    # electricity demand for drying = 0.105 GWh el/GWh sawdust
    @constraint(model, [n in NODES, t in T],
        sum(
            vuse[n, el, tech, t]
        + vuse[n, :heat, :dac, t] * tech_yield[(el, :dac)] 
        for el in EL, tech in TECH
        )
        + (
            sum(
                vuse[n, :sawdust, tech, t]
                for tech in PYRA
            )
            + vuse[n, :sawdust, :gf, t]
        ) * 0.105
        <=
        sum(
            vgen[n, el, t]
            for el in EL
        )
    )

    # Limit installed renewable generation by area potentials. per wind/PV type and region
    @constraint(model, [n in NODES, t in T],
        vinstalled[n, :won, t] <= vre_pot[(n, :cap_won)] * vre_rate
    )
    @constraint(model, [n in NODES, t in T],
        vinstalled[n, :woff, t] <= vre_pot[(n, :cap_woff)] * vre_rate
    )
    @constraint(model, [n in NODES, t in T],
        vinstalled[n, :pvplant, t] <= vre_pot[(n, :cap_pvplant)] * vre_rate
    )
    @constraint(model, [n in NODES, t in T],
        vinstalled[n, :pvroof, t] <= vre_pot[(n, :cap_pvroof)] * vre_rate
    )

    # RFNBO constraint for electrolysis powered by VRE
    @constraint(model, rfnbo[n in NODES, t in T],
        sum(
            vuse[n, el, tech, t]
            for el in EL, tech in ELECTROLYSIS
        )
        <=
        sum(
            vinstalled[n, elgen, t] * vre_cf[(n,elgen)] * 8760
            for elgen in ELGEN
        )
    )

    return (; total_cost, annual_cost, beccs, methanol, 
            heat_production, new_vehicles, new_co2_vehicles,
            vehicle_stock, integer_ships, number_ships, number_co2_ships,
            mass_balance_node, co2_balance, import_max,
            H2_production, H2_use, 
            co2_fossil_generation, co2_bio_generation, co2_emitted,
            co2_capture, co2_capture_balance, 
            syngas_balance, methanol_balance, pyrolysis_balance,
            pyB_balance, pyrolysis_capacity, py_plants,
            heat_supply, capacity_inv, synthesis_capacity,
            rfnbo)
end
